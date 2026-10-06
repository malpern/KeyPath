"""Read-only guest extension after restart/caps definitions, excluding their entrypoints.
Arguments: BOOT CUTOFF BINDING_JSON. No recovery, mutation, signals or dispatch.
"""

def marker_owner(owner):
    require(type(owner) is dict and set(owner) == {'uid', 'parentPID', 'workerPID',
        'nonce', 'generation', 'bootSessionUUID'} and type(owner['uid']) is int
        and owner['uid'] == 502, 'marker owner refused')
    require(all(type(owner[k]) is int and 0 < owner[k] < 2**31
                for k in ('parentPID', 'workerPID'))
            and owner['parentPID'] != owner['workerPID'], 'marker PID refused')
    for key in ('nonce', 'generation'):
        require(type(owner[key]) is str and re.fullmatch(r'[A-Za-z0-9_-]{1,128}', owner[key]),
                'marker token refused')
    require(type(owner['bootSessionUUID']) is str, 'marker boot refused')
    uuid.UUID(owner['bootSessionUUID'])
    return owner


def marker_pair():
    before = JOURNAL.lstat()
    require(JOURNAL.resolve() == JOURNAL and stat.S_ISDIR(before.st_mode)
            and before.st_uid == 502 and stat.S_IMODE(before.st_mode) == 0o700,
            'journal directory refused')
    names = set(os.listdir(JOURNAL))
    intent_name, marker_name = 'caps-mapping-intent.json', 'caps-mapping-mutation-in-flight.json'
    require({intent_name, marker_name} <= names
            and names <= {intent_name, marker_name, 'caps-mapping.lock'}, 'journal names refused')
    identity = lambda s: (s.st_dev, s.st_ino, s.st_mode, s.st_uid, s.st_gid,
                          s.st_nlink, s.st_size, s.st_mtime_ns, s.st_ctime_ns)
    metadata = {}
    for name in names:
        path = JOURNAL / name
        s = path.lstat()
        require(path.resolve() == path and stat.S_ISREG(s.st_mode) and s.st_uid == 502
                and s.st_nlink == 1 and stat.S_IMODE(s.st_mode) == 0o600
                and 0 <= s.st_size <= 65536, 'journal file identity refused')
        metadata[name] = identity(s)
    intent_raw, marker_raw = read(JOURNAL / intent_name, 65536), read(JOURNAL / marker_name, 65536)
    record = json.loads(intent_raw, object_pairs_hook=unique)
    marker = json.loads(marker_raw, object_pairs_hook=unique)
    require(type(record) is dict, 'journal object required')
    require(set(record) == {'version', 'device', 'owner', 'effectiveConfigSHA256',
                            'original', 'applied'} and type(record['version']) is int
            and record['version'] == 1, 'journal fields refused')
    # Swift Codable omits nil optional SerialNumber; normalize only that field.
    record['device'] = device(dict(record['device'], serialNumber=record['device'].get('serialNumber')))
    owner = record['owner']
    require(type(owner) is dict and set(owner) == {'uid', 'parentPID', 'workerPID',
            'nonce', 'generation', 'bootSessionUUID'} and type(owner['uid']) is int
            and owner['uid'] == 502, 'journal owner refused')
    require(all(type(owner[k]) is int and 0 < owner[k] < 2**31
                for k in ('parentPID', 'workerPID'))
            and owner['parentPID'] != owner['workerPID'], 'journal PID refused')
    for key in ('nonce', 'generation'):
        require(type(owner[key]) is str and re.fullmatch(r'[A-Za-z0-9_-]{1,128}', owner[key]),
                'journal token refused')
    require(type(owner['bootSessionUUID']) is str, 'journal boot refused')
    uuid.UUID(owner['bootSessionUUID'])
    require(command(['/usr/sbin/sysctl', '-n', 'kern.bootsessionuuid']).strip()
            == owner['bootSessionUUID'], 'journal boot changed')
    require(record['effectiveConfigSHA256'] == hashlib.sha256(CAPS).hexdigest(),
            'journal config changed')
    validate_mappings(record['original'])
    validate_mappings(record['applied'])
    require(all(row['HIDKeyboardModifierMappingSrc'] not in (CAPS_USAGE, F18_USAGE)
                and row['HIDKeyboardModifierMappingDst'] != F18_USAGE
                for row in record['original'])
            and record['applied'] == record['original'] + [{
                'HIDKeyboardModifierMappingSrc': CAPS_USAGE,
                'HIDKeyboardModifierMappingDst': F18_USAGE}], 'journal mapping refused')
    require(marker_owner(marker) == record['owner'], 'marker does not match retained owner')
    require(read(JOURNAL / intent_name, 65536) == intent_raw
            and read(JOURNAL / marker_name, 65536) == marker_raw
            and set(os.listdir(JOURNAL)) == names
            and identity(JOURNAL.lstat()) == identity(before)
            and all(identity((JOURNAL / name).lstat()) == metadata[name] for name in names),
            'retained artifacts changed during read')
    return record, marker, intent_raw, marker_raw


def identity_log_tail():
    path=HOME/'Library/Logs/KeyPath/keypath-debug.log'
    if not os.path.lexists(path):return dict(absent=True)
    require(path.resolve()==path,'log symlink refused')
    fd=os.open(path,os.O_RDONLY|os.O_NOFOLLOW|os.O_NONBLOCK)
    try:
        before=os.fstat(fd)
        require(stat.S_ISREG(before.st_mode) and before.st_uid==502 and before.st_nlink==1
                and not before.st_mode & 0o002 and 0<=before.st_size<=100000000,'log metadata refused')
        os.lseek(fd,max(0,before.st_size-16384),os.SEEK_SET)
        raw=os.read(fd,16384)
        after=os.fstat(fd);current=path.lstat()
        identity=lambda x:(x.st_dev,x.st_ino,x.st_uid,x.st_mode,x.st_nlink)
        require(identity(before)==identity(after)==identity(current),'log replaced during read')
        return dict(path=str(path),observedMode=oct(stat.S_IMODE(before.st_mode)),sizeBefore=before.st_size,sizeAfter=after.st_size,
                    tail=raw.decode('utf-8',errors='replace'),maximumTailBytes=16384)
    finally:os.close(fd)


def admit_replacement_parent(owner, runtime, global_pids, replacement_pid, main_executable):
    """Admit only one explicitly bound normal parent after both recorded PIDs exit."""
    require(type(replacement_pid) is int and replacement_pid > 0
            and replacement_pid < 2**31
            and replacement_pid not in (owner['parentPID'], owner['workerPID']),
            'replacement parent PID refused')
    require(replacement_pid in global_pids, 'bound replacement parent not globally live')
    require(owner['parentPID'] not in global_pids
            and owner['workerPID'] not in global_pids,
            'recorded owner parent/worker still live or PID reused')
    require(type(runtime) is dict and set(runtime) == {'parents', 'workers', 'target'}
            and runtime['workers'] == [] and runtime['target'] is None,
            'replacement runtime must have no worker or target')
    parents = runtime['parents']
    require(type(parents) is list and len(parents) == 1,
            'exactly one replacement parent required')
    parent = parents[0]
    require(type(parent) is dict and parent.get('pid') == replacement_pid
            and type(parent.get('uid')) is int and parent['uid'] == 502
            and parent.get('executable') == main_executable
            and parent.get('arguments') == [main_executable],
            'replacement parent identity refused')
    return parent


def marker_observe(b):
    global DATA
    old_scope = {'lease', 'providerUUID', 'account', 'home', 'uid', 'bootEpoch',
                 'hardCutoffEpoch', 'selectedDevice', 'expectedIntentSHA256', 'expectedMarkerSHA256'}
    replacement_scope = old_scope | {'replacementParentPID'}
    require(type(b) is dict and set(b) in (old_scope, replacement_scope),
        'exact marker observation scope required')
    require(type(b['lease']) is str and re.fullmatch(r'cbx_[0-9a-f]{12}', b['lease']), 'lease scope refused')
    uuid.UUID(b['providerUUID'])
    require(type(b['uid']) is int and b['uid'] == 502 and b['home'] == str(HOME)
            and b['account'] == HOME.name and type(b['bootEpoch']) is int and b['bootEpoch'] == BOOT
            and type(b['hardCutoffEpoch']) is int and b['hardCutoffEpoch'] == CUTOFF,
            'fresh scope identity refused')
    for key in ('expectedIntentSHA256', 'expectedMarkerSHA256'):
        require(b[key] is None or (type(b[key]) is str and re.fullmatch(r'[0-9a-f]{64}', b[key])),
                'expected artifact digest refused')
    replacement_pid = b.get('replacementParentPID')
    if 'replacementParentPID' in b:
        require(type(replacement_pid) is int and replacement_pid > 0
                and b['expectedIntentSHA256'] is not None
                and b['expectedMarkerSHA256'] is not None,
                'replacement requires bound parent PID and retained digests')
    DATA = device(b['selectedDevice'])
    guard()
    require(read(PROFILE) == CAPS, 'managed Caps profile changed')
    selected = selected_device()
    record, marker, intent_raw, marker_raw = marker_pair()
    require(record['device'] == selected, 'retained intent selection changed')
    runtime = inspect()
    require(not runtime['workers'] and runtime['target'] is None, 'live worker/target refused')
    # Check recorded PIDs globally, not merely named product rows: PID reuse refuses.
    raw = command(['/bin/ps', '-axo', 'pid='])
    require(len(raw.encode()) <= 1048576 and all(line.strip().isdigit() for line in raw.splitlines()),
            'global PID scan refused')
    pids = {int(line.strip()) for line in raw.splitlines()}
    owner = record['owner']
    if 'replacementParentPID' in b:
        admit_replacement_parent(owner, runtime, pids, replacement_pid, str(MAIN))
    else:
        require(not runtime['parents'] or [p['pid'] for p in runtime['parents']] == [owner['parentPID']],
                'foreign replacement parent refused')
        require(owner['workerPID'] not in pids, 'recorded worker PID still live')
        require((owner['parentPID'] in pids) == bool(runtime['parents']), 'recorded parent PID reused')
    current = mapping(selected)
    require(current['mappings'] == record['applied'], 'current mapping is not retained applied mapping')
    intent_sha, marker_sha = hashlib.sha256(intent_raw).hexdigest(), hashlib.sha256(marker_raw).hexdigest()
    for key, digest in (('expectedIntentSHA256', intent_sha), ('expectedMarkerSHA256', marker_sha)):
        require(b[key] is None or b[key] == digest, 'retained artifact digest changed')
    log = identity_log_tail()
    require(selected_device() == selected and mapping(selected)['mappings'] == current['mappings'],
            'selected mapping changed during observation')
    again = marker_pair()
    require(again == (record, marker, intent_raw, marker_raw) and inspect() == runtime,
            'artifacts/runtime changed during observation')
    result = dict(readOnly=True, observed=True, observedAt=time.time(), scope=b, selectedDevice=selected,
        currentMapping=current, matchesApplied=True, journal=record, mutationMarker=marker,
        journalRawJSON=intent_raw.decode(), journalRawSHA256=intent_sha,
        markerRawJSON=marker_raw.decode(), markerRawSHA256=marker_sha,
        recordedWorkerPIDAbsent=True, parentOwnershipVerified=True, runtime=runtime, log=log)
    encoded = json.dumps(result, sort_keys=True)
    require(len(encoded.encode()) <= 262144, 'observation exceeds output bound')
    return encoded


if __name__ == '__main__':
    try:
        require(len(sys.argv) == 4, 'expected BOOT CUTOFF BINDING_JSON')
        BOOT, CUTOFF = int(sys.argv[1]), int(sys.argv[2])
        require(BOOT > 0 and time.time() < CUTOFF, 'invocation refused')
        b = json.loads(sys.argv[3], object_pairs_hook=unique)
        print(marker_observe(b), flush=True)
    except Exception as error:
        print(json.dumps(dict(readOnly=True, observed=False, errorType=type(error).__name__, error=str(error))), flush=True)
        sys.exit(79)
