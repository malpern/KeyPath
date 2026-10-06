#!/usr/bin/env python3
"""Bounded UID502 restart acceptance helper; no fixture or quit dispatch."""
import hashlib
import json
import math
import os
import pathlib
import re
import shlex
import signal
import stat
import subprocess
import sys
import time
import uuid

HOME = pathlib.Path('/Users/keypathqa_438d6abc')
APP = HOME / 'Applications/KeyPath.app'
MAIN = APP / 'Contents/MacOS/KeyPath'
TARGET_APP = HOME / 'Applications/VM Lab Rig Target.app'
TARGET = TARGET_APP / 'Contents/MacOS/RigTarget'
REPORT = HOME / 'rig-target.json'
PROFILE = HOME / '.config/keypath/keypath.kbd'
BACKUP = HOME / '.config/keypath/keypath.kbd.caps-runtime-01-backup'
MAIN_SIZE = 108172800
MAIN_SHA = 'c002059128421e90a5e9592441c1ee6b77fce255617ae2512c3e721343a64996'
TARGET_SHA = '5fb5e05e8f26954f1b4121cdb949f689cff9db325795ce51167a3f998044ced3'
ORIGINAL_SHA = '65c2992efffb755776d346af60aa291250f6b3d9a143dbb3070450578154d573'
FIXED = b'(defcfg)\n(defsrc q a bspc)\n;; KP:BEGIN simple_mods id=protocol-fixture version=1\n(deflayermap (base)\n  q a\n)\n;; KP:END id=protocol-fixture\n'

def require(value, reason):
    if not value:
        raise RuntimeError(reason)

def command(args, timeout=8):
    require(time.time() < CUTOFF, 'cutoff reached')
    result = subprocess.run(args, stdin=subprocess.DEVNULL, capture_output=True,
                            timeout=min(timeout, max(.1, CUTOFF-time.time())), check=True)
    require(time.time() < CUTOFF, 'command crossed cutoff')
    return result.stdout.decode('utf-8')

def read(path, limit=262144):
    path = pathlib.Path(path)
    # macOS's system /var alias is expected; other symlinks remain refused.
    if str(path).startswith('/var/folders/'):
        path = pathlib.Path('/private' + str(path))
    require(path.resolve() == path, 'symlink path refused')
    fd = os.open(path, os.O_RDONLY | os.O_NOFOLLOW | os.O_NONBLOCK)
    try:
        before = os.fstat(fd)
        require(stat.S_ISREG(before.st_mode) and before.st_uid == 502
                and before.st_nlink == 1 and not before.st_mode & 0o022
                and 0 < before.st_size <= limit, 'file identity refused')
        raw = os.read(fd, limit+1)
        signature = lambda s: (s.st_dev, s.st_ino, s.st_size, s.st_mtime_ns,
                               s.st_ctime_ns, s.st_mode, s.st_uid, s.st_nlink)
        require(len(raw) == before.st_size
                and signature(before) == signature(os.fstat(fd))
                == signature(path.lstat()), 'file changed during read')
        return raw
    finally:
        os.close(fd)

def unique(pairs):
    result = {}
    for k, v in pairs:
        require(k not in result, 'duplicate JSON key')
        result[k] = v
    return result

def obj(path):
    value = json.loads(read(path), object_pairs_hook=unique)
    require(type(value) is dict, 'JSON object required')
    return value

def guard():
    require(os.getuid() == 502 and os.environ.get('HOME') == str(HOME)
            and os.stat('/dev/console').st_uid == 502 and time.time() < CUTOFF,
            'account/console/cutoff refused')
    boot = command(['/usr/sbin/sysctl', '-n', 'kern.boottime'])
    match = re.search(r'sec = ([0-9]+),', boot)
    require(match and int(match[1]) == BOOT, 'boot changed')
    require(MAIN.stat().st_size == MAIN_SIZE, 'main executable size mismatch')
    for path, digest in ((MAIN, MAIN_SHA), (TARGET, TARGET_SHA)):
        require(hashlib.sha256(read(path, 120000000)).hexdigest() == digest,
                'executable hash mismatch')
        command(['/usr/bin/codesign', '--verify', '--deep', '--strict',
                 '-R=anchor apple generic and certificate leaf[subject.OU] = "X2RKZ5TG99"',
                 str(path.parents[2])], 20)

def processes():
    raw = command(['/bin/ps', '-ww', '-axo', 'pid=,uid=,comm='])
    require(len(raw) < 1048576, 'process scan too large')
    rows = []
    for line in raw.splitlines():
        parts = line.split(maxsplit=2)
        require(len(parts) == 3 and parts[0].isdigit()
                and re.fullmatch(r'-?[0-9]+', parts[1]) is not None,
                'process scan malformed')
        if pathlib.PurePosixPath(parts[2]).name in ('KeyPath', 'RigTarget'):
            require(int(parts[1]) == 502 and parts[2] in (str(MAIN), str(TARGET)),
                    'foreign product/target process')
            rows.append(dict(pid=int(parts[0]), uid=502, executable=parts[2]))
    return rows

def arguments(pid):
    return shlex.split(command(['/bin/ps', '-ww', '-p', str(pid), '-o', 'args=']).strip())

def target_arguments_match(pid):
    # ps renders an unquoted executable path. Spaces inside the app name are
    # part of that path, rather than argument separators.
    return command(['/bin/ps', '-ww', '-p', str(pid), '-o', 'args=']).strip() == str(TARGET)

def target_state(expected=None, fresh=True):
    t = obj(REPORT)
    require(type(t.get('pid')) is int and t['pid'] > 0 and t.get('uid') == 502
            and type(t.get('nonce')) is str, 'target identity refused')
    uuid.UUID(t['nonce'])
    if expected is not None:
        require(set(expected) == {'pid', 'nonce'} and all(t[k] == expected[k] for k in expected),
                'target binding changed')
    require([r for r in processes() if r['executable'] == str(TARGET)] ==
            [dict(pid=t['pid'], uid=502, executable=str(TARGET))]
            and target_arguments_match(t['pid']), 'target process changed')
    stamp = t.get('observedAt')
    require(type(stamp) in (int, float) and math.isfinite(stamp)
            and (not fresh or 0 <= time.time()-stamp < 3), 'target report stale')
    channel = HOME / ('rig-target-control-' + str(t['pid']) + '-' + t['nonce'])
    s = channel.lstat()
    require(channel.resolve() == channel and stat.S_ISDIR(s.st_mode)
            and s.st_uid == 502 and stat.S_IMODE(s.st_mode) == 0o700
            and t.get('commandPath') == str(channel/'command.json'), 'target channel refused')
    return t

def inspect():
    rows = processes()
    parents, workers = [], []
    for row in rows:
        if row['executable'] != str(MAIN):
            continue
        args = arguments(row['pid'])
        row['arguments'] = args
        if '--session-runtime' not in args:
            require(args == [str(MAIN)], 'ordinary parent arguments refused')
            parents.append(row)
            continue
        for flag in ('--session-nonce', '--session-report', '--session-owner'):
            require(args.count(flag) == 1 and args.index(flag)+1 < len(args),
                    'worker arguments refused')
        nonce = args[args.index('--session-nonce')+1]
        uuid.UUID(nonce)
        path = args[args.index('--session-report')+1]
        require(re.fullmatch(r'/var/folders/[A-Za-z0-9_/-]+/T/keypath-session-'
                             + re.escape(nonce) + r'/report.json', path), 'worker report path refused')
        report = obj(path)
        require(report.get('pid') == row['pid'] and report.get('uid') == 502
                and report.get('nonce') == nonce, 'worker report identity refused')
        stamp = report.get('timestamp')
        require(type(stamp) in (int, float) and math.isfinite(stamp)
                and 0 <= time.time()-(stamp+978307200) < 3, 'worker report stale')
        row.update(report=report, reportPath=path,
                   ownerPID=int(args[args.index('--session-owner')+1]))
        workers.append(row)
    require(len(parents) <= 1 and all(any(p['pid'] == w['ownerPID'] for p in parents)
                                    for w in workers), 'parent/worker ownership refused')
    return dict(parents=parents, workers=workers,
                target=target_state() if any(r['executable'] == str(TARGET) for r in rows) else None)

def write_existing(path, raw):
    fd = os.open(path, os.O_WRONLY | os.O_NOFOLLOW | os.O_NONBLOCK)
    try:
        s = os.fstat(fd)
        require(stat.S_ISREG(s.st_mode) and s.st_uid == 502 and s.st_nlink == 1
                and not s.st_mode & 0o022, 'write identity refused')
        os.ftruncate(fd, 0)
        require(os.write(fd, raw) == len(raw), 'short write')
        os.fsync(fd)
    finally:
        os.close(fd)
    require(read(path) == raw, 'write verification failed')

def main():
    guard()
    require(ACTION in ('inspect', 'initialize', 'profile', 'launch', 'target', 'retire-target', 'restore'),
            'action refused')
    require(not DATA or ACTION == 'retire-target', 'unexpected action arguments')
    if ACTION == 'inspect':
        return inspect()
    if ACTION == 'initialize':
        require(not processes() and not os.path.lexists(PROFILE) and not os.path.lexists(BACKUP), 'first launch requires pristine stopped product')
        command(['/usr/bin/open', '-n', str(APP)])
        return dict(firstLaunchRequested=True)
    if ACTION == 'profile':
        require(not processes(), 'profile requires product and target absent')
        require(PROFILE.is_file(), 'normal first launch must create profile before preparation')
        raw = read(PROFILE)
        require(hashlib.sha256(raw).hexdigest() == ORIGINAL_SHA, 'original profile changed')
        guard()
        fd = os.open(BACKUP, os.O_WRONLY | os.O_CREAT | os.O_EXCL | os.O_NOFOLLOW, 0o600)
        try:
            require(os.write(fd, raw) == len(raw), 'backup short write')
            os.fsync(fd)
        finally:
            os.close(fd)
        require(read(BACKUP) == raw, 'backup verification failed')
        guard()
        write_existing(PROFILE, FIXED)
        return dict(profilePrepared=True, backup=str(BACKUP))
    if ACTION == 'launch':
        require(not any(r['executable'] == str(MAIN) for r in processes()), 'product already running')
        require(read(PROFILE) == FIXED and hashlib.sha256(read(BACKUP)).hexdigest() == ORIGINAL_SHA,
                'prepared profile required')
        guard()
        command(['/usr/bin/open', '-n', str(APP)])
        return dict(launchRequested=True)
    if ACTION == 'target':
        current = inspect()
        require(len(current['parents']) == 1 and len(current['workers']) == 1
                and current['workers'][0]['report'].get('state') == 'running'
                and current['workers'][0]['report'].get('tapActive') is True
                and current['workers'][0]['report'].get('heldOutputUsages') == [],
                'ready all-up parent/worker required')
        require(not any(r['executable'] == str(TARGET) for r in processes())
                and not os.path.lexists(REPORT), 'target/report already exists')
        guard()
        requested = time.time()
        command(['/usr/bin/open', '-n', str(TARGET_APP)])
        end = min(time.monotonic()+8, time.monotonic()+max(0, CUTOFF-time.time()))
        while time.monotonic() < end:
            if REPORT.exists():
                t = target_state()
                require(t['observedAt'] >= requested, 'old target report')
                return dict(target=t, launchRequestedAt=requested)
            time.sleep(.1)
        raise RuntimeError('target launch did not report')
    if ACTION == 'retire-target':
        t = target_state(DATA)
        require(t.get('held') == [] and t.get('modifiers') == 0, 'held target refused')
        guard()
        t = target_state(DATA)
        require(t.get('held') == [] and t.get('modifiers') == 0, 'held target refused')
        os.kill(t['pid'], signal.SIGTERM)
        end = time.monotonic()+5
        while any(r['executable'] == str(TARGET) for r in processes()):
            require(time.monotonic() < end, 'target failed to exit; no retry')
            time.sleep(.1)
        final = obj(REPORT)
        require(all(final.get(k) == t[k] for k in ('pid', 'uid', 'nonce'))
                and final.get('held') == [] and final.get('modifiers') == 0,
                'retired report changed')
        guard()
        require(not any(r['executable'] == str(TARGET) for r in processes()), 'target remains')
        REPORT.unlink()
        return dict(targetRetired=True, pid=t['pid'], nonce=t['nonce'])
    require(not processes() and not os.path.lexists(REPORT), 'restore requires product/target/report absent')
    raw = read(BACKUP)
    require(hashlib.sha256(raw).hexdigest() == ORIGINAL_SHA and read(PROFILE) == FIXED,
            'restore profile binding refused')
    guard()
    write_existing(PROFILE, raw)
    BACKUP.unlink()
    return dict(profileRestored=True, profileSHA256=hashlib.sha256(read(PROFILE)).hexdigest())

if __name__ == '__main__':
    try:
        require(len(sys.argv) in (4, 5), 'expected BOOT CUTOFF ACTION optional JSON')
        BOOT, CUTOFF, ACTION = int(sys.argv[1]), int(sys.argv[2]), sys.argv[3]
        DATA = json.loads(sys.argv[4], object_pairs_hook=unique) if len(sys.argv) == 5 else {}
        require(type(DATA) is dict and BOOT > 0 and time.time() < CUTOFF, 'invocation refused')
        print(json.dumps(main(), sort_keys=True))
    except Exception as error:
        print(json.dumps(dict(ok=False, errorType=type(error).__name__, error=str(error))))
        sys.exit(79)
