#!/usr/bin/env python3
"""Read-only installed-session QA; mirrors SessionRuntimeReport.isCurrent/readiness.

The CLI cannot read the UI coordinator's retained session. Bind the signed app's
exact process paths and raw worker launch arguments instead. NSWorkspace workers
have launchd as their OS parent, so --session-owner is the lifecycle owner.
"""
import argparse
import ctypes
import json
import math
import os
from pathlib import Path
import socket
import stat
import struct
import subprocess
import sys
import time
import uuid

SWIFT_REFERENCE_DATE = 978307200


def require(condition, message):
    if not condition:
        raise ValueError(message)


def process_identity(pid):
    """Return (uid, executable, argv) without parsing whitespace in ps args."""
    lib = ctypes.CDLL('/usr/lib/libSystem.B.dylib', use_errno=True)
    path = ctypes.create_string_buffer(4096)
    require(lib.proc_pidpath(pid, path, len(path)) > 0, 'process executable unavailable')
    mib = (ctypes.c_int * 3)(1, 49, pid)  # CTL_KERN, KERN_PROCARGS2
    size = ctypes.c_size_t(1024 * 1024)
    buffer = ctypes.create_string_buffer(size.value)
    require(lib.sysctl(mib, 3, buffer, ctypes.byref(size), None, 0) == 0,
            'process launch arguments unavailable')
    raw = buffer.raw[:size.value]
    require(len(raw) >= 4, 'process launch arguments truncated')
    argc = struct.unpack_from('i', raw)[0]
    require(0 < argc < 1024, 'invalid process argument count')
    end = raw.index(b'\0', 4) + 1  # skip executable path and padding
    while end < len(raw) and raw[end] == 0:
        end += 1
    arguments = raw[end:].split(b'\0')[:argc]
    require(len(arguments) == argc, 'process launch arguments truncated')
    uid = int(subprocess.check_output(['/bin/ps', '-p', str(pid), '-o', 'uid='],
                                      timeout=2).strip())
    return uid, os.fsdecode(path.value), tuple(os.fsdecode(value) for value in arguments)


def discover(executable, uid):
    rows = subprocess.check_output(['/bin/ps', '-axo', 'pid=,uid=,comm='],
                                   text=True, timeout=3).splitlines()
    processes = {}
    for row in rows:
        fields = row.split(maxsplit=2)
        if len(fields) == 3 and int(fields[1]) == uid and fields[2] == executable:
            pid = int(fields[0])
            processes[pid] = process_identity(pid)
    return processes


def owned_launch(processes, executable, uid, port):
    parents = [(pid, identity) for pid, identity in processes.items()
               if identity[:2] == (uid, executable)
               and not any(flag in identity[2] for flag in ('--session-runtime', '--session-capabilities'))]
    require(len(parents) == 1, 'expected exactly one installed KeyPath session parent')
    parent_pid, parent = parents[0]
    workers = [(pid, identity) for pid, identity in processes.items()
               if identity[:2] == (uid, executable) and '--session-runtime' in identity[2]]
    require(len(workers) == 1, 'expected exactly one installed KeyPath session worker')
    worker_pid, worker = workers[0]
    args = worker[2]
    require('--session-capabilities' not in args and args.count('--session-runtime') == 1,
            'worker is not a runtime-only launch')

    def argument(flag):
        require(args.count(flag) == 1, 'missing or duplicate worker ' + flag)
        index = args.index(flag)
        require(index + 1 < len(args), 'missing worker argument value')
        return args[index + 1]

    require(argument('--session-owner') == str(parent_pid), 'worker belongs to another parent')
    require(argument('--session-port') == str(port), 'worker TCP port mismatch')
    require(bool(argument('--session-config')), 'worker config path unavailable')
    nonce = argument('--session-nonce')
    require(str(uuid.UUID(nonce)).lower() == nonce.lower(), 'invalid session nonce')
    report = Path(argument('--session-report'))
    require(report.is_absolute() and report.name == 'report.json'
            and report.parent.name == 'keypath-session-' + nonce,
            'report path does not belong to this launch')
    require(0 < uid <= 2**32 - 1 and 0 < parent_pid <= 2**31 - 1
            and 0 < worker_pid <= 2**31 - 1 and parent_pid != worker_pid,
            'invalid session process ownership')
    return parent_pid, parent, worker_pid, worker, nonce, report


def read_report(path, uid):
    # Open directory and file without following symlinks. Compare the directory
    # path afterward so replacement during the read cannot attest another report.
    directory_fd = os.open(path.parent, os.O_RDONLY | os.O_DIRECTORY | os.O_NOFOLLOW)
    try:
        directory = os.fstat(directory_fd)
        require(stat.S_ISDIR(directory.st_mode) and directory.st_uid == uid
                and stat.S_IMODE(directory.st_mode) == 0o700, 'report directory is not private and owned')
        report_fd = os.open(path.name, os.O_RDONLY | os.O_NOFOLLOW | os.O_NONBLOCK, dir_fd=directory_fd)
        with os.fdopen(report_fd, 'rb') as source:
            metadata = os.fstat(source.fileno())
            require(stat.S_ISREG(metadata.st_mode) and metadata.st_uid == uid
                    and stat.S_IMODE(metadata.st_mode) == 0o600 and metadata.st_nlink == 1,
                    'report file is not private and owned')
            data = source.read(16385)
            require(len(data) <= 16384, 'report exceeds canonical size limit')
            after = os.fstat(source.fileno())
            require((after.st_size, after.st_mtime_ns, after.st_ctime_ns)
                    == (metadata.st_size, metadata.st_mtime_ns, metadata.st_ctime_ns),
                    'report changed during read')
        current = os.stat(path.parent, follow_symlinks=False)
        require((current.st_dev, current.st_ino) == (directory.st_dev, directory.st_ino),
                'report directory changed during read')
        require(current.st_uid == uid and stat.S_IMODE(current.st_mode) == 0o700,
                'report directory permissions changed during read')
        return json.loads(data, object_pairs_hook=unique_fields)
    finally:
        os.close(directory_fd)


def unique_fields(pairs):
    fields = {}
    for key, value in pairs:
        require(key not in fields, 'duplicate report field')
        fields[key] = value
    return fields


def validate_report(report, nonce, pid, uid, port, now):
    require(isinstance(report, dict), 'report is not an object')
    require(report.get('nonce') == nonce, 'report nonce mismatch')
    for key, expected, limit in [('pid', pid, 2**31 - 1), ('uid', uid, 2**32 - 1), ('tcpPort', port, 65535)]:
        require(type(report.get(key)) is int and 0 < report[key] <= limit
                and report[key] == expected, 'report ' + key + ' mismatch')
    require(report.get('state') == 'running', 'session is not running')
    for key in ('accessibility', 'effectiveInputAccess', 'tapActive'):
        require(report.get(key) is True, 'session capability/tap is not ready: ' + key)
    require(report.get('failure') is None, 'session reports a failure')
    for key in ('inputCount', 'outputCount'):
        require(type(report.get(key)) is int and 0 <= report[key] <= 2**64 - 1,
                'invalid report counter')
    held = report.get('heldOutputUsages')
    require(isinstance(held, list) and all(type(value) is int and 0 <= value <= 2**32 - 1 for value in held),
            'invalid held-output ledger')
    timestamp = report.get('timestamp')
    require(type(timestamp) in (int, float) and math.isfinite(timestamp), 'invalid report timestamp')
    age = now - (timestamp + SWIFT_REFERENCE_DATE)
    require(-1 <= age <= 2, 'report is stale or future-dated')


def verify(executable, uid, port):
    launch = owned_launch(discover(executable, uid), executable, uid, port)
    parent_pid, parent, worker_pid, worker, nonce, report_path = launch
    validate_report(read_report(report_path, uid), nonce, worker_pid, uid, port, time.time())
    # A connect alone could pass against a foreign or legacy listener.
    listeners = subprocess.check_output(['/usr/sbin/lsof', '-nP', '-a', '-p', str(worker_pid),
                                          '-i4TCP:' + str(port), '-sTCP:LISTEN', '-Fpn'],
                                         text=True, timeout=2).splitlines()
    require('p' + str(worker_pid) in listeners and 'n127.0.0.1:' + str(port) in listeners,
            'loopback TCP listener is not owned by the session worker')
    with socket.create_connection(('127.0.0.1', port), timeout=0.3):
        pass
    require(process_identity(parent_pid) == parent and process_identity(worker_pid) == worker,
            'session processes changed during verification')
    validate_report(read_report(report_path, uid), nonce, worker_pid, uid, port, time.time())
    return parent_pid, worker_pid


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--app', default='/Applications/KeyPath.app')
    parser.add_argument('--port', type=int, default=37001)
    parser.add_argument('--timeout', type=float, default=20)
    args = parser.parse_args()
    require(sys.platform == 'darwin', 'session verification requires macOS')
    require(0 < args.port <= 65535 and math.isfinite(args.timeout) and 0 <= args.timeout <= 300,
            'invalid TCP port or timeout')
    executable = str(Path(args.app).resolve() / 'Contents/MacOS/KeyPath')
    deadline = time.monotonic() + args.timeout
    while True:
        try:
            parent, worker = verify(executable, os.getuid(), args.port)
            print('✅ Owned driverless session ready: parentPID=%d workerPID=%d TCP=127.0.0.1:%d'
                  % (parent, worker, args.port))
            return 0
        except (ValueError, OSError, subprocess.SubprocessError) as error:
            if time.monotonic() >= deadline:
                print('❌ Driverless session verification failed: ' + str(error), file=sys.stderr)
                return 1
            time.sleep(0.2)


if __name__ == '__main__':
    try:
        sys.exit(main())
    except (ValueError, OSError) as error:
        print('❌ ' + str(error), file=sys.stderr)
        sys.exit(1)
