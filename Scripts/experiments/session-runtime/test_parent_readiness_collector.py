"""Run beside parent_readiness.py; actual generated collector, no guest actions."""
import datetime
import pathlib
import shlex
import subprocess
import tempfile
import types
import unittest
import parent_readiness as readiness


class ReadyCollectorTests(unittest.TestCase):
    def test_generated_collector_retains_ready_before_noise_and_refuses_wrong_tuple(self):
        nonce = '912D0000-0000-4000-8000-000000000000'
        parent, worker, now = 27838, 27947, 1791123600
        stamp = datetime.datetime.fromtimestamp(now - 1, datetime.timezone.utc).strftime('%Y-%m-%d %H:%M:%S.%f')[:-3]
        ready = (f'[{stamp}] [INFO] [KeyPath] Session runtime ready (test) '
                 f'parentPID={parent} workerPID={worker} nonce={nonce}\n')
        identity = types.SimpleNamespace(app='/Users/public/Applications/KeyPath.app',
                                         home='/Users/public', uid=502, guard=lambda: 'true')
        executable = identity.app + '/Contents/MacOS/KeyPath'
        path = f'/var/folders/inert/T/keypath-session-{nonce}/report.json'
        args = (f'{executable} --session-runtime --session-owner {parent} '
                f'--session-nonce {nonce} --session-report {path}')
        marker = 'KEYPATH_READY_READ_' + 'a' * 32
        report = dict(pid=worker, uid=502, nonce=nonce, state='running', tapActive=True,
                      timestamp=now - 978307200)
        command = readiness.log_command(identity, parent, worker, nonce, path, args, marker)
        start = command.index('/usr/bin/tail -c 65536')
        end = command.index('; ', start)
        with tempfile.TemporaryDirectory() as directory:
            log = pathlib.Path(directory) / 'log'
            collector = command[start:end].replace(
                shlex.quote(identity.home + '/Library/Logs/KeyPath/keypath-debug.log'), shlex.quote(str(log)))
            def collect():
                result = subprocess.run(['/bin/zsh', '-c', 'set -euo pipefail; ' + collector],
                                        capture_output=True, text=True, check=True)
                return f'KEYPATH_PARENT_LOG_V1 {now} +0000\n' + result.stdout + '\n' + marker + '\n'
            for count in (167, 187):
                with self.subTest(noise_rows=count):
                    log.write_text('prefix\n' + ready + 'noise row\n' * count)
                    # Demonstrate the old line clipping independently using the same bounded bytes.
                    old = subprocess.run(['/bin/zsh', '-c',
                        '/usr/bin/tail -c 65536 ' + shlex.quote(str(log)) + ' | /usr/bin/tail -n 128'],
                        capture_output=True, text=True, check=True)
                    self.assertNotIn(ready.strip(), old.stdout)
                    observation = collect()
                    evidence = readiness.admit(observation, marker, parent, worker, nonce, 502,
                                               report, now - 2, now)
                    self.assertEqual(evidence['workerPID'], worker)
                    with self.assertRaises(readiness.NotReady):
                        readiness.admit(observation, marker, parent, worker + 1, nonce, 502,
                                        report | dict(pid=worker + 1), now - 2, now)
            # A valid line outside the 65KB tail must remain unavailable.
            log.write_text(ready + ('x' * 200 + '\n') * 400)
            with self.assertRaises(readiness.NotReady):
                readiness.admit(collect(), marker, parent, worker, nonce, 502, report, now - 2, now)


if __name__ == '__main__':
    unittest.main()
