"""Worker-only startup observation derived from pinned d290 snapshot. No target read/adoption."""
import base64,json,pathlib,re,shlex,time,uuid
class Refusal(RuntimeError):pass
def require(value,reason):
    if not value:raise Refusal(reason)

def worker_snapshot(self):
    old = None
    """One guarded read returns owned processes, reports and exit proof.

    Shell records are individually base64 encoded; no guest Python or
    transcribed JSON is required. Process tables bracket the read so a
    partial or changing generation is refused, not accidentally combined.
    """
    self.observation_scope()
    q = shlex.quote
    commands = [
        'set -e; set -o pipefail',
        'd8emit() { printf "D8\\t%s\\t" "$1"; /usr/bin/base64 | /usr/bin/tr -d "\\n"; printf "\\n"; }',
        'd8processes() { local d8selected d8pid d8uid d8comm d8args; '
        + 'd8selected=$(/bin/ps -ww -axo pid=,uid=,comm= | /usr/bin/awk -v exe='
        + q(self.exe) + ' \'$3 == exe\') || return $?; '
        + 'while read -r d8pid d8uid d8comm; do '
        + 'test -n "$d8pid" || continue; '
        + 'd8args=$(/bin/ps -ww -p "$d8pid" -o args=) || return $?; '
        + 'test -n "$d8args" || return 79; '
        + 'printf "%s %s %s %s\\n" "$d8pid" "$d8uid" "$d8comm" "$d8args"; '
        + 'done <<< "$d8selected"; }',
        'd8before=$(d8processes) || exit $?',
        '{ /usr/bin/id -un ' + str(self.uid) + '; /usr/bin/id -u ' + q(self.account)
        + '; /usr/bin/dscl . -read /Users/' + q(self.account) + ' NFSHomeDirectory | /usr/bin/cut -d " " -f 2-'
        + '; /usr/bin/stat -f %Su /dev/console; /usr/bin/stat -f %u /dev/console'
        + "; /usr/sbin/sysctl -n kern.boottime | /usr/bin/sed -E 's/^.*sec = ([0-9]+),.*$/\\1/'; } | d8emit identity",
        'printf %s "$d8before" | d8emit processes',
        'printf %s "$$" | d8emit observerPID',
        "/bin/ps -axo pid= | /usr/bin/awk '$1 ~ /^[0-9]+$/ && $1 > 0 {print $1}' | d8emit pids",
        '/usr/bin/shasum -a 256 ' + q(self.exe) + ' | d8emit binaryHash',
    ]
    # Discover only bounded owned report paths. A foreign worker causes a
    # refusal before its file can be read. Host repeats the argument checks.
    commands += [
        '''while read -r d8pid d8uid d8comm d8args; do
 test -z "$d8pid" && continue
 case " $d8args " in *" --session-runtime "*)
 d8path=$(printf '%s\\n' "$d8args" | /usr/bin/awk '{for(i=1;i<NF;i++)if($i=="--session-report")print $(i+1)}')
 d8nonce=$(printf '%s\\n' "$d8args" | /usr/bin/awk '{for(i=1;i<NF;i++)if($i=="--session-nonce")print $(i+1)}')
 d8owner=$(printf '%s\\n' "$d8args" | /usr/bin/awk '{for(i=1;i<NF;i++)if($i=="--session-owner")print $(i+1)}')
 test "$d8owner" = ''' + shlex.quote(str(self.parent)) + '''
 test "$d8uid" = ''' + str(self.uid) + '''
 [[ "$d8nonce" =~ ^[0-9a-fA-F-]{36}$ ]]
 [[ "$d8path" =~ ^/var/folders/[A-Za-z0-9_/-]+/T/keypath-session-$d8nonce/report.json$ ]]
 test ! -L "$d8path"
 test "$(/usr/bin/stat -f %u "$d8path")" = ''' + str(self.uid) + '''
 /bin/cat "$d8path" | d8emit "report-$d8pid"
 ;; esac
 done <<< "$d8before"''',
    ]
    if old:
        commands += ['test ! -L ' + q(old['reportPath']),
                     'test "$(/usr/bin/stat -f %u ' + q(old['reportPath']) + ')" = ' + str(self.uid),
                     '/bin/cat ' + q(old['reportPath']) + ' | d8emit oldReport']
    commands += ['d8after=$(d8processes) || exit $?', 'test "$d8before" = "$d8after"',
                 'if ! ( ' + self.guest_identity.guard() + ' ); then exit 79; fi',
                 'printf D8_COMPLETE | d8emit complete']
    expression = ('true; if ! ( ' + self.guest_identity.guard() + ' ); then exit 79; fi; { '
                  + '\n'.join(commands) + '\n}')
    output = self.pilot.observe(self.lease, 'guest-root', '--', '/bin/zsh', '-lc', expression)
    fields = {}
    for line in output.splitlines():
        parts = line.split('\t')
        require(len(parts) == 3 and parts[0] == 'D8' and parts[1] not in fields,
                'incomplete or ambiguous batch receipt')
        try:
            fields[parts[1]] = base64.b64decode(parts[2], validate=True).decode('utf-8')
        except (ValueError, UnicodeError):
            raise Refusal('malformed batch receipt') from None
    expected = {'identity', 'processes', 'pids', 'observerPID', 'binaryHash', 'complete'}
    if old:
        expected.add('oldReport')
    require(fields.get('complete') == 'D8_COMPLETE' and expected <= fields.keys(),
            'incomplete batch receipt')
    actual_identity = fields['identity'].splitlines()
    require(len(actual_identity) == 6 and actual_identity[:5]
            == [self.account, str(self.uid), self.home, self.account, str(self.uid)]
            and actual_identity[5].isdigit()
            and (self.guest_identity.boot_epoch is None
                 or int(actual_identity[5]) == self.guest_identity.boot_epoch),
            'batched account/home/console/boot identity changed')
    require(fields['binaryHash'].split()[0] == self.binary_sha, 'owned executable hash changed')
    def process(row):
        values = row.strip().split(maxsplit=3)
        require(len(values) == 4 and values[0].isdigit() and values[1].isdigit(),
                'malformed process observation')
        return dict(pid=int(values[0]), uid=int(values[1]), executable=values[2],
                    arguments=shlex.split(values[3]), rawArguments=values[3], binarySHA256=self.binary_sha)
    processes = [process(row) for row in fields['processes'].splitlines()]
    require(len({p['pid'] for p in processes}) == len(processes), 'duplicate process receipt')
    parent = [p for p in processes if p['pid'] == self.parent]
    if self.parent:
        require(len(parent) == 1 and parent[0]['uid'] == self.uid
                and parent[0]['arguments'] == self.parent_args, 'owned parent identity changed')
    live = []
    for item in processes:
        require(item['executable'] == self.exe and item['uid'] == self.uid, 'foreign process')
        args = item['arguments']
        if item['pid'] == self.parent:
            continue
        require('--session-runtime' in args and args.count('--session-owner') == 1
                and args[args.index('--session-owner') + 1] == str(self.parent), 'foreign worker')
        require(args.count('--session-report') == args.count('--session-nonce') == 1,
                'ambiguous worker report arguments')
        path, nonce = args[args.index('--session-report') + 1], args[args.index('--session-nonce') + 1]
        uuid.UUID(nonce)
        require(re.fullmatch(r'/var/folders/[A-Za-z0-9_/-]+/T/keypath-session-'
                             + re.escape(nonce) + r'/report.json', path), 'unsafe worker report path')
        item.update(reportPath=path, nonce=nonce)
        known = self.generations.get(item['pid'])
        require(known is None or all(item[k] == known[k] for k in ('uid', 'nonce', 'arguments', 'reportPath')),
                'owned worker process identity changed')
        label = 'report-' + str(item['pid'])
        require(label in fields, 'incomplete worker batch receipt')
        expected.add(label)
        report = json.loads(fields[label])
        require(tuple(report.get(k) for k in ('pid', 'uid', 'nonce'))
                == tuple(item[k] for k in ('pid', 'uid', 'nonce')), 'report ownership mismatch')
        self.generations[item['pid']] = item
        live.append((item, report))
    require(len(live) <= 1 and set(fields) == expected, 'unexpected or ambiguous batch records')
    pids = fields['pids'].split()
    observer = fields['observerPID'].strip()
    positive_pid = lambda value: re.fullmatch(r'[1-9][0-9]*', value) is not None
    require(bool(pids) and all(positive_pid(p) for p in pids) and len(pids) == len(set(pids))
            and positive_pid(observer) and observer in pids
            and all(str(item['pid']) in pids for item in processes), 'incomplete or malformed exit observation')
    result = dict(worker=live[0] if live else None,
                  observerPID=int(observer), pidScan=[int(p) for p in pids],
                  processes=processes, oldExited=old is not None and str(old['pid']) not in pids,
                  observedAt=time.time(), identity=dict(account=self.account, uid=self.uid, home=self.home,
                  providerUUID=self.guest_identity.provider_uuid, bootEpoch=int(actual_identity[5]),
                  consoleAccount=actual_identity[3], consoleUID=int(actual_identity[4])))
    if old:
        result['oldReport'] = json.loads(fields['oldReport'])
        require(not any(p['pid'] == old['pid'] and p['arguments'] != old['arguments'] for p in processes),
                'old worker PID reused')
    return result
