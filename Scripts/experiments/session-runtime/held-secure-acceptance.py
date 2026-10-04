#!/usr/bin/env python3
"""Review-gated D8 campaign. Import is inert; only main performs guest operations."""
import argparse
import base64
import hashlib
import importlib.util
import json
import os
import sys
import pathlib
import re
import shlex
import time
import uuid
import zlib

from held_secure_predicates import (TargetHistory, Refusal, applied, control_down,
                                   control_released, exact_trace, no_resurrection,
                                   physical_hold, require, worker, StoppedWorkerEvidence)

ROOT = pathlib.Path(__file__).resolve().parents[3]
IDENTITY_MODULE = pathlib.Path('/private/tmp/keypath-guest-identity/Scripts/experiments/session-runtime/guest-identity.py')
RIG_ROOTS = ('/private/tmp/vm-lab-hid-rig', '/private/tmp/vm-lab-guest-identity')
PARENT_READINESS_SHA256 = '69e69782c338a36768233fddcdadac54ea2b908a25d39ec84b9b4bcd6ee19f6b'
_READINESS_MODULE = None
GUEST_PYTHON = '/Library/Frameworks/Python.framework/Versions/3.13/bin/python3.13'
CONFIG = '(defcfg)\n(defsrc q a)\n(deflayer base (tap-hold 200 200 q lctl) a)\n'


def load_module(path, name):
    spec = importlib.util.spec_from_file_location(name, path)
    require(spec is not None and spec.loader is not None, 'dependency module unavailable')
    module = importlib.util.module_from_spec(spec)
    sys.modules[name] = module  # dataclasses with postponed annotations resolve this entry
    spec.loader.exec_module(module)
    return module


def readiness_module():
    global _READINESS_MODULE
    path = pathlib.Path(__file__).with_name('parent_readiness.py')
    require(hashlib.sha256(path.read_bytes()).hexdigest() == PARENT_READINESS_SHA256,
            'reviewed parent readiness source changed')
    if _READINESS_MODULE is None:
        _READINESS_MODULE = load_module(path, 'held_parent_readiness')
    return _READINESS_MODULE


class Guest:
    def __init__(self, lease, pilot, binary_sha, target_sha, identity):
        self.lease, self.pilot = lease, pilot
        self.binary_sha, self.target_sha = binary_sha, target_sha
        self.guest_identity = identity
        self.account, self.uid, self.home = identity.account, identity.uid, identity.home
        self.app = identity.app
        self.exe = self.app + "/Contents/MacOS/KeyPath"
        require(not any(c.isspace() for c in self.exe), 'unsupported spaced KeyPath discovery path')
        self.profile = self.home + "/.config/keypath/keypath.kbd"
        self.parent = None
        self.generations = {}
        self.backup = self.profile + '.held-secure-' + uuid.uuid4().hex
        self.backed_up = False
        self.parent_args = None
        self.target_identity = None
        self.parent_launch_requested_at = None

    def check_account(self):
        return self.guest_identity.verify(self.pilot, self.lease)

    def run(self, command):
        self.check_account()
        # prlctl drops/mangles the first shell command; retain its established
        # no-op prefix, while leaving guard/mutation failure as the final status.
        return self.pilot.lab(self.lease, 'guest-root', '--', '/bin/zsh', '-lc',
                              'true; ' + self.guest_identity.guard() + ' && { ' + command + '; }')

    def observation_scope(self):
        """The shared receipt/provider checks, without a second guest round trip."""
        shared = load_module(IDENTITY_MODULE, 'held_batch_guest_identity')
        identity = self.guest_identity
        require(identity.lease is None or identity.lease == self.lease, 'identity lease changed')
        if identity.receipt_path:
            raw = shared.read_private_receipt(pathlib.Path(identity.receipt_path))
            require(hashlib.sha256(raw).hexdigest() == identity.receipt_sha256,
                    'frozen identity receipt changed')
        if identity.provider_uuid is not None:
            shared.verify_provider(self.pilot.lab(self.lease, 'status'), self.lease,
                                   identity.provider_uuid, time.time())

    def snapshot(self, old=None):
        """One guarded read returns target, owned processes, reports and exit proof.

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
            '/bin/cat ' + q(self.home + '/rig-target.json') + ' | d8emit target',
            '/usr/bin/shasum -a 256 ' + q(self.exe) + ' | d8emit binaryHash',
        ]
        target_fields = (('pid', 'targetPID', 'pid'), ('uid', 'targetUID', 'uid'),
                         ('comm', 'targetExecutable', 'executable'), ('args', 'targetArguments', 'rawArguments'))
        if self.target_identity:
            for option, label, _ in target_fields:
                variable = 'd8target' + option
                commands += [variable + '=$(/bin/ps -ww -p ' + str(self.target_identity['pid']) + ' -o ' + option + '=)',
                             'printf %s "$' + variable + '" | d8emit ' + label]
            commands += ['/usr/bin/shasum -a 256 ' + q(self.target_identity['executable']) + ' | d8emit targetHash']
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
        if self.target_identity:
            for option, _, _ in target_fields:
                commands += ['test "$d8target' + option + '" = "$(/bin/ps -ww -p '
                             + str(self.target_identity['pid']) + ' -o ' + option + '=)"']
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
        expected = {'identity', 'processes', 'pids', 'observerPID', 'target', 'binaryHash', 'complete'}
        if self.target_identity:
            expected.update(label for _, label, _ in target_fields)
            expected.add('targetHash')
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
        if self.target_identity:
            require(all(fields[label].strip() == str(self.target_identity[key])
                        for _, label, key in target_fields)
                    and fields['targetHash'].split()[0] == self.target_sha, 'target process or hash changed')
        pids = fields['pids'].split()
        observer = fields['observerPID'].strip()
        positive_pid = lambda value: re.fullmatch(r'[1-9][0-9]*', value) is not None
        require(bool(pids) and all(positive_pid(p) for p in pids) and len(pids) == len(set(pids))
                and positive_pid(observer) and observer in pids
                and all(str(item['pid']) in pids for item in processes), 'incomplete or malformed exit observation')
        target_receipt = json.loads(fields['target'])
        require(type(target_receipt.get('pid')) is int and target_receipt['pid'] > 0
                and str(target_receipt['pid']) in pids, 'target absent from exit observation')
        if self.target_identity:
            require(tuple(target_receipt.get(k) for k in ('pid', 'uid', 'nonce'))
                    == tuple(self.target_identity[k] for k in ('pid', 'uid', 'nonce')),
                    'target receipt ownership changed')
        result = dict(target=target_receipt, worker=live[0] if live else None,
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

    def target(self):
        return json.loads(self.run('cat ' + shlex.quote(self.home + '/rig-target.json')))

    def processes(self):
        rows = self.run('ps -axo pid=,uid=,comm=').splitlines()
        result = []
        for row in rows:
            fields = row.split(maxsplit=2)
            if len(fields) == 3 and fields[2] == self.exe:
                result.append((int(fields[0]), int(fields[1]),
                               shlex.split(self.run(f'ps -p {int(fields[0])} -o args='))))
        return result

    def identity(self, pid, expected_args):
        self.check_account()
        require(type(pid) is int and pid > 0, 'invalid owned PID')
        result = self.run(f'ps -p {pid} -o uid=,comm=').strip().split(maxsplit=1)
        require(result == [str(self.uid), self.exe], 'owned process executable or UID changed')
        raw_args = self.run(f'ps -p {pid} -o args=').strip()
        args = shlex.split(raw_args)
        require(args == expected_args, 'owned process arguments changed')
        digest = self.run('shasum -a 256 ' + shlex.quote(self.exe)).split()[0]
        require(digest == self.binary_sha, 'owned executable hash changed')
        return {'pid': pid, 'uid': self.uid, 'arguments': args, 'rawArguments': raw_args, 'binarySHA256': digest}

    def alive(self, pid):
        # ps returning no row is an explicit exit observation, not a masked transport failure.
        return bool(self.run(f'ps -axo pid= | awk \'$1 == {pid} {{print $1}}\'').strip())

    def preflight(self, target):
        require(not self.processes(), 'existing KeyPath process; campaign refuses adoption')
        require(self.run('stat -f %Su /dev/console').strip() == self.account, 'wrong owned console')
        self.check_account()
        self.run('codesign --verify --strict ' + shlex.quote(self.app))
        require(self.run('shasum -a 256 ' + shlex.quote(self.exe)).split()[0] == self.binary_sha,
                'frozen parent/worker binary mismatch')
        target_exe = self.run(f'ps -ww -p {target["pid"]} -o comm=').strip()
        require(self.run(f'ps -p {target["pid"]} -o uid=').strip() == str(self.uid), 'target UID mismatch')
        require(self.run('shasum -a 256 ' + shlex.quote(target_exe)).split()[0] == self.target_sha,
                'reviewed target binary mismatch')
        self.target_identity = {'pid': target['pid'], 'uid': self.uid, 'nonce': target['nonce'],
                'rawArguments': self.run(f'ps -ww -p {target["pid"]} -o args=').strip(),
                'executable': target_exe, 'binarySHA256': self.target_sha}
        # Command writes use Python; verify this explicit dependency before input.
        self.run(shlex.quote(GUEST_PYTHON) + ' -I -B -c ' + shlex.quote(
            'import json,os,pathlib,stat,sys,tempfile; assert sys.version_info[:3] == (3,13,16)'))
        return self.target_identity

    def parent_ready(self, identity):
        readiness = readiness_module()
        require(self.parent is not None and self.parent_launch_requested_at is not None,
                'parent launch evidence unavailable')
        self.observation_scope()
        marker = 'KEYPATH_READY_READ_' + uuid.uuid4().hex
        command = readiness.log_command(self.guest_identity, self.parent, identity['pid'],
                                        identity['nonce'], identity['reportPath'],
                                        identity['rawArguments'], marker)
        output = self.pilot.observe(self.lease, 'guest-root', '--', '/bin/zsh', '-lc', command)
        log, current = readiness.split_observation(output, marker)
        evidence = readiness.admit(log, marker, self.parent, identity['pid'], identity['nonce'],
                                   self.uid, current, self.parent_launch_requested_at, time.time())
        return current, evidence

    def start(self):
        self.check_account()
        self.run('test -f ' + shlex.quote(self.profile) + ' && test ! -e ' + shlex.quote(self.backup)
                 + ' && cp -p ' + shlex.quote(self.profile) + ' ' + shlex.quote(self.backup))
        self.backed_up = True
        self.check_account()
        self.parent_launch_requested_at = time.time()
        self.run('printf %s ' + shlex.quote(CONFIG) + ' > ' + shlex.quote(self.profile)
                 + ' && chown ' + shlex.quote(self.account) + ' ' + shlex.quote(self.profile)
                 + ' && launchctl asuser ' + str(self.uid) + ' sudo -H -u ' + shlex.quote(self.account) + ' open -g -n '
                 + shlex.quote(self.app) + ' --args --headless')
        deadline = time.monotonic() + 8
        while time.monotonic() < deadline:
            rows = self.processes()
            parents = [(pid, args) for pid, uid, args in rows
                       if uid == self.uid and '--headless' in args and '--session-runtime' not in args]
            require(len(parents) <= 1, 'ambiguous parent launch')
            if parents:
                self.parent, self.parent_args = parents[0]
                return self.identity(self.parent, self.parent_args)
            time.sleep(.2)
        raise Refusal('parent launch deadline')

    def command(self, before, mode):
        # Trusted owned guest directory; target independently verifies O_NOFOLLOW,
        # owner, links, mode, exact shape and PID/UID/nonce/sequence before applying.
        path = before['commandPath']
        require(re.fullmatch(re.escape(self.home) + r'/rig-target-control-'
                             + str(before['pid']) + '-' + re.escape(before['nonce'])
                             + r'/command.json', path), 'unexpected target command path')
        command = {k: before[k] for k in ('pid', 'uid', 'nonce')}
        command.update(sequence=before['commandSequence'] + 1, mode=mode)
        code = '''import json,os,pathlib,stat,sys,tempfile
assert sys.version_info[:3] == (3,13,16)
p=pathlib.Path(sys.argv[1]); d=p.parent
s=d.lstat()
assert stat.S_ISDIR(s.st_mode) and s.st_uid==int(sys.argv[3]) and stat.S_IMODE(s.st_mode)==0o700
fd,tmp=tempfile.mkstemp(prefix='.held-command-',dir=d)
try:
 os.fchmod(fd,0o600); os.fchown(fd,int(sys.argv[3]),s.st_gid)
 with os.fdopen(fd,'w') as f: f.write(sys.argv[2]); f.flush(); os.fsync(f.fileno())
 os.replace(tmp,p)
finally:
 if os.path.exists(tmp): os.unlink(tmp)
'''
        self.run(shlex.quote(GUEST_PYTHON) + ' -I -B -c ' + shlex.quote(code) + ' ' + shlex.quote(path)
                 + ' ' + shlex.quote(json.dumps(command, separators=(',', ':'))) + ' ' + str(self.uid))
        return command['sequence']

    def cleanup(self):
        errors = []
        # Only owned, fully revalidated processes can receive a signal. No global kill.
        owned = list(self.generations.values())
        if self.parent:
            owned.insert(0, {'pid': self.parent, 'arguments': self.parent_args})
        for identity in owned:
            try:
                if self.alive(identity['pid']):
                    checked = self.identity(identity['pid'], identity['arguments'])
                    pid = identity['pid']
                    self.run(f'test "$(ps -p {pid} -o uid= | tr -d \" \")" = {self.uid}'
                             + f' && test "$(ps -p {pid} -o comm=)" = ' + shlex.quote(self.exe)
                             + f' && test "$(ps -p {pid} -o args=)" = ' + shlex.quote(checked['rawArguments'])
                             + f' && kill -TERM {pid}')
            except Exception as error:
                errors.append(str(error))
        try:
            deadline = time.monotonic() + 5
            while any(self.alive(v['pid']) for v in owned) and time.monotonic() < deadline:
                time.sleep(.2)
            if any(self.alive(v['pid']) for v in owned):
                errors.append('owned process remains after graceful cleanup')
        except Exception as error:
            errors.append('owner exit observation failed: ' + str(error))
        if self.backed_up:
            try:
                self.check_account()
                self.run('cp -p ' + shlex.quote(self.backup) + ' ' + shlex.quote(self.profile)
                         + ' && cmp -s ' + shlex.quote(self.backup) + ' ' + shlex.quote(self.profile))
                # Retain backup as evidence; do not delete the only original on a failed campaign.
            except Exception as error:
                errors.append('bytewise profile restore failed: ' + str(error))
        return {'errors': errors, 'profileBackup': self.backup,
                'profileBytewiseRestored': self.backed_up and not any('restore' in e for e in errors)}


def script(run, timed):
    payload = ''.join(str(at) + ' ' + ' '.join(map(str, row)) + '\n' for at, row in timed)
    duration = timed[-1][0] + 300000
    return f'KPHID1 {run} {len(timed)} 1 {duration} {zlib.crc32(payload.encode()) & 0xffffffff:08x}\n' + payload


class Campaign:
    def __init__(self, guest, client, destination):
        self.guest, self.client, self.destination = guest, client, destination
        self.history = None
        self.active_run = None
        self.receipt_count = 0
        self.last_target_read = 0
        self.record = {'passed': False, 'untested': ['actual OS tap timeout', 'sleep/wake',
                                                  'console departure/return'], 'phases': []}

    def save(self, label, value):
        self.receipt_count += 1
        name = f'{self.receipt_count:04d}-{label}.json'
        with (self.destination / name).open('x') as output:
            json.dump(value, output, indent=2)
            output.write('\n')
        self.record['phases'].append({'label': label, 'receipt': name})
        return name

    def target(self, old=None):
        remaining = .2 - (time.monotonic() - self.last_target_read)
        if remaining > 0:
            time.sleep(remaining)
        batch = self.guest.snapshot(old)
        self.latest = batch
        value = batch['target']
        self.save('phase-observation', batch)
        self.last_target_read = time.monotonic()
        if self.history is None:
            self.history = TargetHistory(value, time.time(), self.guest.uid)
        else:
            self.history.check(value, time.time())
        return value

    def wait(self, label, predicate, seconds=5, old=None):
        deadline = time.monotonic() + seconds
        while time.monotonic() < deadline:
            time.sleep(.2)
            target = self.target(old)  # stale, focus or instance failures are never retried
            require(time.monotonic() < deadline, label + ' observation overran deadline')
            value = predicate(target)
            require(time.monotonic() < deadline, label + ' predicate overran deadline')
            if value is not None:
                self.save(label, value)
                return target, value
        raise Refusal(label + ' deadline')

    def accept_phase(self, phase, value):
        receipt = self.save('accepted-' + phase, value)
        # Persist acceptance before retiring any live ring retention requirement.
        self.history.retire(phase, receipt)
        self.save('retired-' + phase, {'phase': phase, 'acceptedReceipt': receipt})

    def switch(self, mode, old=None):
        before = self.target()
        sequence = self.guest.command(before, mode)
        if old is not None:
            self.terminal = StoppedWorkerEvidence(tuple(old[k] for k in ('pid', 'uid', 'nonce')),
                                                 before['observedAt'])
        self.save('command', {'sequence': sequence, 'mode': mode, 'anchor': before['monotonicAt'],
                              'wallAnchor': before['observedAt']})
        def switched(target):
            if old is not None:
                self.terminal.observe(self.latest['oldReport'], time.time())
            require(target['commandSequence'] <= sequence, 'unexpected target command consumed')
            if target['commandSequence'] == sequence:
                applied(target, mode, sequence)
                return target
            require(target['commandStatus'] in ('applied', 'awaitingCommand'), 'target rejected mode command')
            return None
        after, _ = self.wait('mode-' + mode, switched, old=old)
        return before, after

    def start_input(self, timed, phase=None):
        self.guest.check_account()
        status = self.client.status()
        require(status.get('state') in ('idle', 'complete', 'aborted'), 'foreign fixture campaign')
        run = 'held-secure-' + uuid.uuid4().hex[:16]
        # A lost load response may leave this exact script installed. Preserve
        # ownership before every mutation; cleanup still checks live run identity.
        self.active_run = run
        self.client.load_script(script(run, timed))
        self.client.arm(run)
        self.guest.check_account()
        if phase is not None:
            self.history.begin(phase, self.target())
        self.client.start(run, 500)
        self.save('physical-script', {'runId': run, 'timedReports': timed})
        return run

    def finish_input(self, timed, seconds=50):
        run = self.active_run
        deadline = time.monotonic() + seconds
        while time.monotonic() < deadline:
            status = self.client.status()
            require(time.monotonic() < deadline, 'fixture status overran completion deadline')
            require(status.get('runId') == run, 'fixture ownership changed')
            if status.get('state') == 'complete':
                break
            require(status.get('state') == 'running', 'fixture stopped before all-up')
            # Continue retaining fresh target/focus/journals across the physical hold.
            time.sleep(.2)
            self.target()
        else:
            raise Refusal('fixture completion deadline')
        trace = self.client.trace_all(retry_seconds=0)
        require(time.monotonic() < deadline, 'fixture trace overran completion deadline')
        exact_trace(trace, [row for _, row in timed], status, run)
        self.last_physical_trace = self.save('physical-trace', {'status': status, 'trace': trace})
        self.active_run = None

    def execute(self):
        initial = self.target()
        require(initial['secureTest'] is False and initial['secureInputEnabled'] is False
                and initial['modifiers'] == 0 and initial['combinedSessionControl'] is False
                and initial['held'] == [] and initial['downs'] == initial['ups'] == 0
                and initial['text'] == '' and initial['secureLength'] == 0, 'fresh empty normal target required')
        self.record['targetIdentity'] = self.guest.preflight(initial)
        self.record['usbBefore'] = self.guest.pilot.verify_usb(self.guest.lease)
        self.record['parentIdentity'] = self.guest.start()
        readiness = readiness_module()
        def ready(_):
            found = self.latest['worker']
            if found and found[1].get('state') == 'running':
                try:
                    report, evidence = self.guest.parent_ready(found[0])
                except readiness.NotReady:
                    return None
                worker(report, tuple(found[0][k] for k in ('pid', 'uid', 'nonce')), time.time())
                require(report.get('heldOutputUsages') == [], 'initial worker ledger not empty')
                return {'identity': found[0], 'report': report, 'parentReadiness': evidence}
            return None
        _, old = self.wait('initial-worker', ready, 8)
        timed = [(0, [0, 20, 0, 0, 0, 0, 0]), (45000000, [0] * 7)]
        run = self.start_input(timed, 'held-transition')
        flags = self.history.previous['flagsChangedJournal']
        anchor = flags[-1]['sequence'] if flags else 0
        def held(target):
            found = self.latest['worker']
            require(found is not None and found[0]['pid'] == old['identity']['pid'], 'held worker disappeared')
            ledger = found[1]
            worker(ledger, tuple(old['identity'][k] for k in ('pid', 'uid', 'nonce')), time.time())
            if ledger.get('heldOutputUsages') != [224]:
                return None
            down = control_down(target, ledger, anchor)
            status = self.client.status()
            physical_hold(status, run)
            return {'down': down, 'worker': ledger, 'fixture': status}
        _, hold = self.wait('control-held', held)
        self.history.anchor('held-transition', self.history.previous)
        command_before, secure = self.switch('secure', old['identity'])
        self.history.anchor('held-transition', secure)
        terminal = self.terminal
        def released(target):
            applied(target, 'secure', secure['commandSequence'])
            stopped = terminal.observe(self.latest['oldReport'], time.time())
            if stopped is None or self.latest['oldExited'] is not True:
                return None
            up = control_released(target, stopped, hold['down'], command_before['monotonicAt'], True)
            status = self.client.status()
            physical_hold(status, run)
            return {'up': up, 'worker': stopped, 'oldWorkerExited': True, 'fixture': status}
        _, release = self.wait('control-released-before-q-up', released, old=old['identity'])
        self.history.anchor('held-transition', self.history.previous)
        self.switch('normal')
        def resumed(target):
            found = self.latest['worker']
            if not found or found[1].get('state') != 'running':
                return None
            require(found[0]['pid'] != old['identity']['pid']
                    and found[0]['nonce'] != old['identity']['nonce'], 'worker generation was reused')
            try:
                report, evidence = self.guest.parent_ready(found[0])
            except readiness.NotReady:
                return None
            worker(report, tuple(found[0][k] for k in ('pid', 'uid', 'nonce')), time.time())
            no_resurrection(target, report, release['up']['sequence'])
            physical_hold(self.client.status(), run)
            return {'identity': found[0], 'report': report, 'parentReadiness': evidence}
        _, new = self.wait('resumed-worker', resumed, 8)
        deadline = time.monotonic() + 2
        while time.monotonic() < deadline:
            time.sleep(.2)
            target = self.target()
            found = self.latest['worker']
            require(found is not None and found[0]['pid'] == new['identity']['pid'], 'new worker disappeared')
            ledger = found[1]
            worker(ledger, tuple(new['identity'][k] for k in ('pid', 'uid', 'nonce')), time.time())
            no_resurrection(target, ledger, release['up']['sequence'])
            status = self.client.status()
            physical_hold(status, run)
            self.save('held-no-resurrection', {'worker': ledger, 'fixture': status})
        self.finish_input(timed)
        time.sleep(.3)
        baseline = self.target()
        found = self.latest['worker']
        require(found is not None and found[0]['pid'] == new['identity']['pid'], 'new worker disappeared')
        ledger = found[1]
        worker(ledger, tuple(new['identity'][k] for k in ('pid', 'uid', 'nonce')), time.time())
        no_resurrection(baseline, ledger, release['up']['sequence'])
        require(baseline['held'] == [] and baseline['combinedSessionControl'] is False
                and baseline['modifiers'] == 0, 'physical all-up did not reconcile target')
        self.accept_phase('held-transition', {'target': baseline, 'worker': ledger,
                         'release': release, 'oldTerminalTransition': terminal.accepted,
                         'physicalAllUpVerified': self.active_run is None, 'physicalTraceReceipt': self.last_physical_trace})
        # Fresh tap, modifier hold, then Control+a chord; every sample ends all-up.
        for label, rows in (
            ('tap', [(0, [0, 20, 0, 0, 0, 0, 0]), (80000, [0] * 7)]),
            ('hold', [(0, [0, 20, 0, 0, 0, 0, 0]), (350000, [0] * 7)]),
            ('chord', [(0, [0, 20, 0, 0, 0, 0, 0]), (300000, [0, 20, 4, 0, 0, 0, 0]),
                       (350000, [0, 20, 0, 0, 0, 0, 0]), (400000, [0] * 7)])):
            self.start_input(rows, 'fresh-' + label)
            before = self.history.previous
            self.finish_input(rows, 8)
            time.sleep(.3)
            after = self.target()
            found = self.latest['worker']
            require(found is not None and found[0]['pid'] == new['identity']['pid'], 'new worker disappeared')
            ledger = found[1]
            worker(ledger, tuple(new['identity'][k] for k in ('pid', 'uid', 'nonce')), time.time())
            require(ledger['heldOutputUsages'] == [] and after['held'] == []
                    and after['combinedSessionControl'] is False and after['modifiers'] == 0,
                    'fresh sample output not released')
            require(after['downs'] - before['downs'] == after['ups'] - before['ups']
                    == (0 if label == 'hold' else 1), 'fresh sample keyboard delivery not balanced')
            if label == 'tap':
                require(after['qDowns'] - before['qDowns'] == 1, 'fresh q tap not delivered')
            else:
                recent = [r for r in after['flagsChangedJournal'] if r['monotonicAt'] > before['monotonicAt']
                          and r.get('keyCode') == 59]
                require([r['control'] for r in recent] == [True, False], 'fresh Control hold not balanced')
            if label == 'chord':
                require(after['controlA'] - before['controlA'] == 1, 'fresh Control+a chord missing')
            self.accept_phase('fresh-' + label, {'before': before, 'after': after, 'worker': ledger,
                             'physicalTraceReceipt': self.last_physical_trace})
        # No secret text is collected. This fixed sample occurs only after reconciled all-up.
        self.history.begin('secure-calibration', self.target())
        _, secure = self.switch('secure')
        # Native repeats from the original q hold may have populated this same
        # secure field. Clear that fixed nonsecret input physically after all-up;
        # commands never carry text, and cumulative target counters stay intact.
        clear = [(0, [8, 4, 0, 0, 0, 0, 0]), (80000, [0] * 7),
                 (160000, [0, 42, 0, 0, 0, 0, 0]), (240000, [0] * 7)]
        self.start_input(clear)
        self.finish_input(clear, 8)
        time.sleep(.3)
        cleared = self.target()
        applied(cleared, 'secure', secure['commandSequence'])
        require(cleared['secureLength'] == 0 and cleared['held'] == []
                and cleared['modifiers'] == 0 and cleared['combinedSessionControl'] is False, 'secure field clear did not reconcile all-up')
        keys = [20, 4, 29, 30, 31, 32]  # qaz123
        rows = []
        for index, key in enumerate(keys):
            rows.extend([(index * 120000, [0, key, 0, 0, 0, 0, 0]),
                         (index * 120000 + 40000, [0] * 7)])
        self.start_input(rows)
        self.finish_input(rows, 8)
        time.sleep(.3)
        after = self.target()
        applied(after, 'secure', secure['commandSequence'])
        require(after['secureLength'] == 6 and after['secureSampleMatches'] is True
                and after['held'] == [] and after['modifiers'] == 0
                and after['combinedSessionControl'] is False,
                'fixed nonsecret secure sample did not pass through cleanly')
        # Clear the accepted fixed sample only after its exact terminal all-up.
        self.start_input(clear)
        self.finish_input(clear, 8)
        time.sleep(.3)
        final_clear = self.target()
        applied(final_clear, 'secure', secure['commandSequence'])
        require(final_clear['secureLength'] == 0 and final_clear['held'] == []
                and final_clear['modifiers'] == 0 and final_clear['combinedSessionControl'] is False,
                'accepted secure sample cleanup did not reconcile all-up')
        self.accept_phase('secure-calibration', {'after': after, 'cleared': cleared,
                         'finalClear': final_clear, 'physicalTraceReceipt': self.last_physical_trace,
                         'fixedNonsecretSample': 'qaz123'})
        _, restored = self.switch('normal')
        require(restored['held'] == [] and restored['modifiers'] == 0
                and restored['combinedSessionControl'] is False, 'target cleanup retained output')
        self.save('target-restored-normal', restored)
        self.record['usbAfter'] = self.guest.pilot.verify_usb(self.guest.lease)
        self.record['passed'] = True

    def cleanup(self):
        errors = []
        try:
            status = self.client.status()
            if self.active_run and status.get('runId') == self.active_run:
                if status.get('state') in ('loaded', 'armed', 'running'):
                    self.client.abort()  # only this campaign's exact run; never abort a foreign run
            elif self.active_run:
                errors.append('fixture ownership changed; foreign run was not aborted')
        except Exception as error:
            errors.append(str(error))
        finally:
            try:
                self.client.close()
            except Exception as error:
                errors.append('fixture client close failed: ' + str(error))
        try:
            self.record['ownerCleanup'] = self.guest.cleanup()
            errors.extend(self.record['ownerCleanup']['errors'])
        except Exception as error:
            errors.append(str(error))
        if errors:
            self.record.update(passed=False, cleanupErrors=errors)


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('lease')
    identity_module = load_module(IDENTITY_MODULE, 'held_shared_guest_identity')
    identity_module.add_arguments(parser)
    parser.add_argument('--binary-sha', required=True)
    parser.add_argument('--target-sha', required=True)
    parser.add_argument('--fixture-factory', type=pathlib.Path, required=True,
                        help='Reviewed module create_client(); returns preauthenticated persistent scoped client')
    parser.add_argument('--reviewed-execution', action='store_true',
                        help='Required explicit gate after high review and guest target release')
    args = parser.parse_args()
    identity = identity_module.from_arguments(args)
    require(identity.lease is None or identity.lease == args.lease, 'identity receipt belongs to another lease')
    require(args.reviewed_execution, 'source-only harness requires review and guest-release gate')
    require(re.fullmatch(r'cbx_[0-9a-f]{12}', args.lease), 'invalid owned lease')
    require(all(re.fullmatch(r'[0-9a-f]{64}', v) for v in (args.binary_sha, args.target_sha)),
            'invalid frozen binary hashes')
    destination = ROOT / 'evidence/session-runtime' / ('held-secure-' + uuid.uuid4().hex)
    destination.mkdir(parents=True, exist_ok=False)
    rig_root = os.environ.get('VM_LAB_RIG_ROOT', RIG_ROOTS[0])
    require(rig_root in RIG_ROOTS, 'unreviewed rig root')
    pilot = load_module(pathlib.Path(rig_root) / 'rig/physical-baseline.py', 'held_pilot')
    factory = load_module(args.fixture_factory, 'held_fixture_factory')
    guest = Guest(args.lease, pilot, args.binary_sha, args.target_sha, identity)
    campaign = Campaign(guest, factory.create_client(), destination)
    campaign.record.update(account=identity.account, uid=identity.uid, home=identity.home,
                           identityReceipt=identity.receipt_path, identityReceiptSHA256=identity.receipt_sha256,
                           providerUUID=identity.provider_uuid, bootEpoch=identity.boot_epoch,
                           rigRoot=rig_root, lease=args.lease, binarySHA256=args.binary_sha,
                           targetSHA256=args.target_sha, profile=CONFIG)
    try:
        campaign.execute()
    except Exception as error:
        campaign.record.update(passed=False, error=str(error), failureType=type(error).__name__)
    finally:
        campaign.cleanup()
        with (destination / 'campaign.json').open('x') as output:
            json.dump(campaign.record, output, indent=2)
            output.write('\n')
    print(json.dumps({'passed': campaign.record['passed'], 'evidence': str(destination)}))
    return 0 if campaign.record['passed'] else 79


if __name__ == '__main__':
    raise SystemExit(main())
