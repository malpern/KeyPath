"""Read-only admission of a real, current parent startup completion log."""
import datetime
import json
import math
import re
import shlex
import uuid


class NotReady(RuntimeError):
    pass


def normalize_worker_args(value):
    """ps emits one LF; the known provider may add one more. Nothing else."""
    if not isinstance(value, str) or not value or '\r' in value or '\0' in value:
        raise ValueError('invalid process argument observation')
    trailing = len(value) - len(value.rstrip('\n'))
    if trailing > 2:
        raise ValueError('unexpected process argument separator')
    canonical = value[:-trailing] if trailing else value
    if not canonical or '\n' in canonical:
        raise ValueError('process argument observation contains extra rows')
    return canonical


def process_binding(parent, worker, nonce, path, worker_args, executable):
    if type(parent) is not int or type(worker) is not int or min(parent, worker) <= 0 or parent == worker:
        raise ValueError('invalid parent/worker PID tuple')
    if str(uuid.UUID(nonce)).upper() != nonce.upper():
        raise ValueError('invalid worker nonce')
    if not re.fullmatch(r'/var/folders/[A-Za-z0-9_/-]+/T/keypath-session-' + re.escape(nonce) + r'/report\.json', path):
        raise ValueError('invalid owned report path')
    args = shlex.split(worker_args)
    if not args or args[0] != executable or args.count('--session-runtime') != 1:
        raise ValueError('worker executable/mode mismatch')
    for flag, expected in [('--session-owner', str(parent)), ('--session-nonce', nonce), ('--session-report', path)]:
        if args.count(flag) != 1 or args.index(flag) + 1 >= len(args) or args[args.index(flag) + 1] != expected:
            raise ValueError('worker launch tuple mismatch')


def log_command(identity, parent, worker, nonce, path, worker_args, marker):
    executable = identity.app + '/Contents/MacOS/KeyPath'
    # Shell command substitution removes ps's LF framing. Compare like with
    # like, retaining all argument text rather than quoting raw transport LFs.
    worker_args = normalize_worker_args(worker_args)
    process_binding(parent, worker, nonce, path, worker_args, executable)
    if not re.fullmatch(r'KEYPATH_READY_READ_[a-f0-9]{32}', marker):
        raise ValueError('invalid read completion marker')
    log = identity.home + '/Library/Logs/KeyPath/keypath-debug.log'
    q = shlex.quote
    ready_filter = q('index($0, "Session runtime ready (") {print}')
    # An intermediate failed command in an AND-list is exempt from set -e.
    # Explicitly refuse the whole identity chain before any log/process read.
    checks = ['if ! ( ' + identity.guard() + ' ); then exit 79; fi']
    for pid, args in [(parent, executable + ' --headless'), (worker, worker_args)]:
        checks += [f'test "$(/bin/ps -p {pid} -o uid= | /usr/bin/tr -d " ")" = {identity.uid}',
                   f'test "$(/bin/ps -p {pid} -o comm=)" = {q(executable)}',
                   f'test "$(/bin/ps -p {pid} -o args=)" = {q(args)}']
    checks += [f'test -f {q(log)}', f'test ! -L {q(log)}',
               f'test "$(/usr/bin/stat -f %u {q(log)})" = {identity.uid}',
               f'test "$(/usr/bin/stat -f %l {q(log)})" = 1',
               f'test -f {q(path)}', f'test ! -L {q(path)}',
               f'test "$(/usr/bin/stat -f %u {q(path)})" = {identity.uid}',
               f'test "$(/usr/bin/stat -f %l {q(path)})" = 1',
               f'test "$(/usr/bin/stat -f %Lp {q(path)})" = 600',
               f'test "$(/usr/bin/stat -f %z {q(path)})" -le 16384']
    return ('true; set -euo pipefail; ' + '; '.join(checks)
            + '; printf "KEYPATH_PARENT_LOG_V1 %s %s\\n" "$(/bin/date +%s)" "$(/bin/date +%z)"; '
            + f'/usr/bin/tail -c 65536 {q(log)} | /usr/bin/awk {ready_filter} | /usr/bin/tail -n 128; '
            + f'printf "\\n%s\\n" {q(marker + "_WORKER_REPORT")}; /usr/bin/head -c 16385 {q(path)}; '
            + f'printf "\\n%s\\n" {q(marker)}')


def split_observation(output, marker):
    separator = '\n' + marker + '_WORKER_REPORT\n'
    ending = '\n' + marker + '\n'
    # The known provider separator may add exactly one final LF. Do not strip
    # arbitrary whitespace or accept additional noise after completion.
    if output.endswith(ending + '\n'):
        output = output[:-1]
    if output.count(separator) != 1 or not output.endswith(ending) or len(output.encode()) > 83000:
        raise NotReady('complete bounded log/report observation unavailable')
    log, raw = output[:-len(ending)].split(separator)
    if len(raw.encode()) > 16384:
        raise NotReady('oversized worker report')
    def unique(pairs):
        result = {}
        for key, value in pairs:
            if key in result:
                raise ValueError('duplicate worker report key')
            result[key] = value
        return result
    try:
        report = json.loads(raw, object_pairs_hook=unique)
    except (ValueError, TypeError):
        raise NotReady('malformed current worker report') from None
    if not isinstance(report, dict):
        raise NotReady('worker report must be an object')
    return log + '\n' + marker + '\n', report


def admit(output, marker, parent, worker, nonce, uid, report, launched_at, now):
    """Only log evidence may admit; a healthy child alone never does."""
    lines = output.splitlines()
    if not lines or lines[-1] != marker or lines.count(marker) != 1:
        raise NotReady('complete owned parent log read unavailable')
    header = re.fullmatch(r'KEYPATH_PARENT_LOG_V1 ([0-9]+) ([+-])([0-9]{2})([0-9]{2})', lines[0])
    if not header or len(output.encode()) > 66000 or len(lines[1:-1]) > 129:
        raise NotReady('malformed bounded parent log observation')
    observed = int(header[1])
    if not all(type(t) in (int, float) and math.isfinite(t) for t in [launched_at, now]):
        raise NotReady('invalid campaign clock')
    if abs(now - observed) >= 3 or not launched_at <= now:
        raise NotReady('stale parent log observation')
    hours, minutes = int(header[3]), int(header[4])
    if hours > 23 or minutes > 59:
        raise NotReady('invalid guest timezone observation')
    offset = (hours * 60 + minutes) * (1 if header[2] == '+' else -1)
    zone = datetime.timezone(datetime.timedelta(minutes=offset))
    if (type(report.get('pid')) is not int or report.get('pid') != worker
            or type(report.get('uid')) is not int or report.get('uid') != uid or report.get('nonce') != nonce):
        raise RuntimeError('worker identity mismatch')
    if (report.get('state') != 'running' or report.get('tapActive') is not True
            or type(report.get('timestamp')) not in (int, float)
            or not 0 <= now - (report['timestamp'] + 978307200) < 3):
        raise NotReady('current running worker report required')
    pattern = re.compile(r'^\[([0-9]{4}-[0-9]{2}-[0-9]{2} [0-9]{2}:[0-9]{2}:[0-9]{2}\.[0-9]{3})\] '
                         r'\[INFO\] \[[^\]\r\n]+\] Session runtime ready \([^\r\n]+\) '
                         r'parentPID=([1-9][0-9]*) workerPID=([1-9][0-9]*) nonce=([A-Fa-f0-9-]{36})$')
    for line in reversed(lines[1:-1]):
        match = pattern.fullmatch(line)
        if not match or (int(match[2]), int(match[3]), match[4]) != (parent, worker, nonce):
            continue
        try:
            ready_at = datetime.datetime.strptime(match[1], '%Y-%m-%d %H:%M:%S.%f').replace(tzinfo=zone).timestamp()
        except ValueError:
            continue
        if launched_at - 1 <= ready_at <= observed + 1:
            return {'parentPID': parent, 'workerPID': worker, 'nonce': nonce,
                    'readyAt': ready_at, 'observedAt': observed, 'workerReportTimestamp': report['timestamp'],
                    'source': 'actual-parent-startup-log'}
    raise NotReady('matching current parent startup completion not observed')
