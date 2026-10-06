"""Trial-only extension injected after the unchanged restart_guest.py definitions.

No HID writes, signal/quit path, recovery, or marker deletion is added here.
Device-bearing actions take one DeviceIdentity JSON from fresh event-service
enumeration; they independently re-enumerate before using the selection.
"""
CAPS = b'(defcfg)\n(defsrc caps q)\n(deflayer base (tap-hold 200 200 esc lctl) a)\n'
JOURNAL = PROFILE.parent / '.session-caps-mapping'
DEVICE_ENV = 'KEYPATH_EXPERIMENTAL_MANAGED_CAPS_DEVICE'
RESERVE_ENV = 'KEYPATH_EXPERIMENTAL_MANAGED_CAPS_RESERVE_F18'
CAPS_USAGE, F18_USAGE = 0x700000039, 0x70000006D
restart_main = main


def device(value):
    require(type(value) is dict and set(value) == {
        'registryEntryID', 'vendorID', 'productID', 'serialNumber', 'locationID'},
        'exact device fields required')
    require(value['vendorID'] == 51966 and type(value['vendorID']) is int
            and value['productID'] == 16400 and type(value['productID']) is int
            and (value['serialNumber'] is None
                 or (type(value['serialNumber']) is str
                     and value['serialNumber'] == '2884855553BC'))
            and type(value['registryEntryID']) is int
            and 0 < value['registryEntryID'] < 2**64
            and type(value['locationID']) is int and 0 < value['locationID'] < 2**32,
            'fixture event-service identity refused')
    return value


def selected_device():
    selected = device(DATA)
    raw = command(['/usr/bin/hidutil', 'list', '--ndjson', '--matching', 'keyboard'], 2)
    require(len(raw.encode()) <= 65536, 'enumeration too large')
    found = []
    for line in raw.splitlines():
        if not line.strip():
            continue
        row = json.loads(line, object_pairs_hook=unique)
        require(type(row) is dict and row.get('type') in ('device', 'service'),
                'enumeration row refused')
        if row['type'] == 'device':
            continue
        for key, maximum in (('PrimaryUsagePage', 65535), ('PrimaryUsage', 65535)):
            require(type(row.get(key)) is int and 0 <= row[key] <= maximum,
                    'enumeration usage refused')
        if (row['PrimaryUsagePage'], row['PrimaryUsage']) != (1, 6):
            continue
        require(type(row.get('LocationID')) is int and 0 <= row['LocationID'] < 2**32,
                'enumeration location refused')
        if row.get('Transport') == 'AppleVirtualPlatformHIDBridge' and row['LocationID'] == 0:
            continue
        require(row.get('IOClass') == 'AppleUserHIDEventService', 'event service required')
        # A nil policy serial is valid only when this event service omits the
        # property. The independent attachment proof binds the ESP32 serial.
        require('SerialNumber' not in row
                or (type(row['SerialNumber']) is str
                    and row['SerialNumber'] == '2884855553BC'),
                'event-service serial property refused')
        found.append(device(dict(registryEntryID=row.get('IORegistryEntryID'),
                                 vendorID=row.get('VendorID'), productID=row.get('ProductID'),
                                 serialNumber=row.get('SerialNumber'), locationID=row['LocationID'])))
    require(found == [selected], 'fresh enumeration changed or ambiguous')
    return selected


def mapping(selected):
    selector = dict(VendorID=selected['vendorID'], ProductID=selected['productID'],
                    PrimaryUsagePage=1, PrimaryUsage=6, LocationID=selected['locationID'])
    if selected['serialNumber'] is not None:
        selector['IOPropertyMatch'] = dict(SerialNumber=selected['serialNumber'])
    raw = command(['/usr/bin/hidutil', 'property', '--matching',
                   json.dumps(selector, sort_keys=True, separators=(',', ':')),
                   '--get', 'UserKeyMapping'], 2)
    require(len(raw.encode()) <= 65536, 'property too large')
    head = re.fullmatch(r'\s*RegistryID\s+Key\s+Value\s+([0-9a-fA-F]+)\s+'
                        r'UserKeyMapping\s*\((.*)\)\s*', raw, re.S)
    require(head and int(head[1], 16) == selected['registryEntryID'],
            'selected property identity refused')
    body = head[2].strip()
    if body == 'null' or body == '':
        return dict(device=selected, mappings=[], raw=raw)
    keys = r'HIDKeyboardModifierMapping(?:Src|Dst)'
    row_pattern = r'\{\s*(' + keys + r')\s*=\s*([0-9]+)\s*;\s*(' + keys + r')\s*=\s*([0-9]+)\s*;\s*\}'
    require(re.fullmatch(row_pattern + r'(?:\s*,\s*' + row_pattern + r')*', body),
            'property grammar refused')
    rows = []
    for match in re.finditer(row_pattern, body):
        require(match[1] != match[3], 'duplicate mapping key')
        rows.append({match[1]: int(match[2]), match[3]: int(match[4])})
    validate_mappings(rows)
    return dict(device=selected, mappings=rows, raw=raw)


def validate_mappings(rows):
    require(type(rows) is list and len(rows) <= 1024, 'mapping array refused')
    sources = []
    for row in rows:
        require(type(row) is dict and set(row) == {
            'HIDKeyboardModifierMappingSrc', 'HIDKeyboardModifierMappingDst'}, 'mapping fields refused')
        for value in row.values():
            require(type(value) is int and 1 <= value >> 32 <= 65535
                    and 1 <= value & 0xFFFFFFFF <= 65535, 'mapping usage refused')
        sources.append(row['HIDKeyboardModifierMappingSrc'])
    require(len(sources) == len(set(sources)), 'duplicate mapping source')


def journal():
    if not os.path.lexists(JOURNAL):
        return None
    before = JOURNAL.lstat()
    require(JOURNAL.resolve() == JOURNAL and stat.S_ISDIR(before.st_mode)
            and before.st_uid == 502 and stat.S_IMODE(before.st_mode) == 0o700,
            'journal directory refused')
    names = set(os.listdir(JOURNAL))
    require(names <= {'caps-mapping.lock', 'caps-mapping-intent.json'},
            'unknown/in-flight journal marker; preserve all state')
    for name in names:
        path = JOURNAL / name
        s = path.lstat()
        require(path.resolve() == path and stat.S_ISREG(s.st_mode) and s.st_uid == 502
                and s.st_nlink == 1 and stat.S_IMODE(s.st_mode) == 0o600
                and 0 <= s.st_size <= 65536, 'journal file identity refused')
    record = obj(JOURNAL / 'caps-mapping-intent.json') if 'caps-mapping-intent.json' in names else None
    identity = lambda s: (s.st_dev, s.st_ino, s.st_mode, s.st_uid, s.st_gid,
                          s.st_nlink, s.st_size, s.st_mtime_ns, s.st_ctime_ns)
    require(set(os.listdir(JOURNAL)) == names and identity(JOURNAL.lstat()) == identity(before),
            'journal directory changed during read')
    if record is not None:
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
    return record


def env_values():
    return {key: command(['/bin/launchctl', 'getenv', key]).rstrip('\n')
            for key in (DEVICE_ENV, RESERVE_ENV)}


def stopped():
    require(not processes() and not os.path.lexists(REPORT),
            'requires product/target/report absent')
    require(journal() is None, 'pending journal; preserve all state')
    require(hashlib.sha256(read(BACKUP)).hexdigest() == ORIGINAL_SHA,
            'original backup changed')


def main():
    guard()
    require(ACTION in ('profile', 'launch', 'observe', 'inspect', 'cleanup', 'restore',
                       'target', 'retire-target'), 'Caps action refused')
    if ACTION in ('target', 'retire-target'):
        return restart_main()
    if ACTION == 'inspect':
        require(not DATA, 'unexpected inspect arguments')
        return inspect()
    if ACTION in ('profile', 'restore'):
        require(not DATA, 'unexpected profile arguments')
        stopped()
        require(all(not value for value in env_values().values()), 'DEBUG environment still set')
        expected, replacement = (FIXED, CAPS) if ACTION == 'profile' else (CAPS, FIXED)
        require(read(PROFILE) == expected, 'profile binding changed')
        guard()
        stopped()
        write_existing(PROFILE, replacement)
        return dict(profilePrepared=ACTION == 'profile', fixedRestored=ACTION == 'restore',
                    profileSHA256=hashlib.sha256(read(PROFILE)).hexdigest())
    selected = selected_device()
    encoded = json.dumps(selected, sort_keys=True, separators=(',', ':'))
    if ACTION == 'observe':
        record = journal()
        snapshot = mapping(selected)
        state = inspect()  # retains the original <3s report freshness rule
        if record is not None:
            require(record['device'] == selected, 'journal selection changed')
            if state['workers']:
                require(len(state['parents']) == 1 and len(state['workers']) == 1,
                        'journal runtime ownership ambiguous')
                worker = state['workers'][0]
                require(record['owner']['parentPID'] == state['parents'][0]['pid']
                        and record['owner']['workerPID'] == worker['pid']
                        and record['owner']['nonce'] == worker['report']['nonce']
                        and record['owner']['generation'] == worker['report'].get('managedCapsGeneration'),
                        'journal runtime ownership changed')
        return dict(runtime=state, selectedMapping=snapshot, journal=record,
                    matchesApplied=record is not None and snapshot['mappings'] == record['applied'],
                    matchesOriginal=record is not None and snapshot['mappings'] == record['original'],
                    debugEnvironment=env_values())
    stopped()
    require(read(PROFILE) == CAPS, 'Caps profile required')
    values = env_values()
    if ACTION == 'launch':
        require(all(not value for value in values.values()), 'existing DEBUG environment refused')
        snapshot = mapping(selected)
        require(all(row['HIDKeyboardModifierMappingSrc'] not in (CAPS_USAGE, F18_USAGE)
                    and row['HIDKeyboardModifierMappingDst'] != F18_USAGE
                    for row in snapshot['mappings']), 'pre-existing Caps/F18 mapping refused')
        guard()
        stopped()
        selected_device()
        command(['/bin/launchctl', 'setenv', DEVICE_ENV, encoded])
        command(['/bin/launchctl', 'setenv', RESERVE_ENV, '1'])
        require(env_values() == {DEVICE_ENV: encoded, RESERVE_ENV: '1'}, 'DEBUG environment verification failed')
        command(['/usr/bin/open', '-n', str(APP)])
        return dict(launchRequested=True, selectedDevice=selected, originalMapping=snapshot['mappings'])
    require(values[DEVICE_ENV] in ('', encoded) and values[RESERVE_ENV] in ('', '1'),
            'foreign DEBUG environment; preserve state')
    guard()
    stopped()
    for key in (DEVICE_ENV, RESERVE_ENV):
        command(['/bin/launchctl', 'unsetenv', key])
    require(all(not value for value in env_values().values()), 'environment cleanup verification failed')
    return dict(environmentCleared=True)


if __name__ == '__main__':
    try:
        require(len(sys.argv) in (4, 5), 'expected BOOT CUTOFF ACTION optional device/target JSON')
        BOOT, CUTOFF, ACTION = int(sys.argv[1]), int(sys.argv[2]), sys.argv[3]
        DATA = json.loads(sys.argv[4], object_pairs_hook=unique) if len(sys.argv) == 5 else {}
        require(type(DATA) is dict and BOOT > 0 and time.time() < CUTOFF, 'invocation refused')
        print(json.dumps(main(), sort_keys=True))
    except Exception as error:
        print(json.dumps(dict(ok=False, errorType=type(error).__name__, error=str(error))))
        sys.exit(79)
