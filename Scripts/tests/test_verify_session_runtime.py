"""Synthetic installed-session QA fixtures; never launch/stop an app or post input."""
import hashlib
import io
import importlib.util
import json
import os
from pathlib import Path
import subprocess
import tempfile
import time
import unittest
from unittest.mock import patch, MagicMock

ROOT = Path(__file__).resolve().parents[2]
HELPER = ROOT / 'Scripts/verify-session-runtime.py'
SPEC = importlib.util.spec_from_file_location('verify_session_runtime', HELPER)
runtime = importlib.util.module_from_spec(SPEC)
SPEC.loader.exec_module(runtime)
NONCE = '12345678-1234-1234-1234-123456789abc'


class SessionVerificationTests(unittest.TestCase):
    def setUp(self):
        self.temporary = tempfile.TemporaryDirectory()
        self.addCleanup(self.temporary.cleanup)
        self.base = Path(self.temporary.name)
        self.executable = str(self.base / 'KeyPath App.app/Contents/MacOS/KeyPath')
        self.uid = os.getuid()
        self.directory = self.base / ('keypath-session-' + NONCE)
        self.directory.mkdir(mode=0o700)
        self.path = self.directory / 'report.json'
        self.parent = (self.uid, self.executable, (self.executable, '--headless'))
        self.worker = (self.uid, self.executable, (self.executable, '--session-runtime',
                       '--session-owner', '100', '--session-report', str(self.path),
                       '--session-nonce', NONCE, '--session-port', '37001',
                       '--session-config', str(self.base / 'Config With Spaces.kbd')))
        self.processes = {100: self.parent, 101: self.worker}
        self.report = dict(nonce=NONCE, pid=101, uid=self.uid, state='running',
                           accessibility=True, effectiveInputAccess=True, tapActive=True,
                           tcpPort=37001, inputCount=0, outputCount=0,
                           timestamp=time.time() - runtime.SWIFT_REFERENCE_DATE, heldOutputUsages=[])
        self.write()

    def write(self):
        self.path.write_text(json.dumps(self.report))
        self.path.chmod(0o600)

    def verify(self, listener='p101\nn127.0.0.1:37001\n', identity=None, connect=None):
        with patch.object(runtime, 'discover', return_value=self.processes), \
             patch.object(runtime, 'process_identity', side_effect=identity or [self.parent, self.worker]), \
             patch.object(runtime.subprocess, 'check_output', return_value=listener) as probe, \
             patch.object(runtime.socket, 'create_connection', side_effect=connect) as tcp:
            tcp.return_value = MagicMock()
            result = runtime.verify(self.executable, self.uid, 37001)
            self.assertIn('-i4TCP:37001', probe.call_args.args[0])
            tcp.assert_called_once_with(('127.0.0.1', 37001), timeout=0.3)
            return result

    def test_exact_session_ready_with_spaces_in_paths(self):
        self.assertEqual(self.verify(), (100, 101))

    def test_absent_ambiguous_foreign_and_capability_processes_refused(self):
        cases = [dict(), {100: self.parent}, {101: self.worker},
                 {100: self.parent, 102: self.parent, 101: self.worker},
                 {100: self.parent, 101: self.worker, 102: self.worker},
                 {100: self.parent, 101: (self.uid, '/Other.app/Contents/MacOS/KeyPath', self.worker[2])},
                 {100: self.parent, 101: (self.uid + 1, self.executable, self.worker[2])},
                 {100: self.parent, 101: (self.uid, self.executable, self.worker[2] + ('--session-capabilities',))}]
        for processes in cases:
            with self.subTest(processes=processes), self.assertRaises(ValueError):
                runtime.owned_launch(processes, self.executable, self.uid, 37001)

    def test_launch_owner_nonce_port_and_report_binding(self):
        for old, new in [('100', '999'), (NONCE, 'not-a-uuid'), ('37001', '37002'),
                         (str(self.path), str(self.base / 'report.json'))]:
            args = tuple(new if value == old else value for value in self.worker[2])
            with self.subTest(value=old), self.assertRaises(ValueError):
                runtime.owned_launch({100: self.parent, 101: (self.uid, self.executable, args)},
                                     self.executable, self.uid, 37001)
        for extra in [('--session-owner', '100'), ('--session-nonce', NONCE), ('--session-runtime',)]:
            with self.subTest(extra=extra), self.assertRaises(ValueError):
                runtime.owned_launch({100: self.parent, 101: (self.uid, self.executable, self.worker[2] + extra)},
                                     self.executable, self.uid, 37001)

    def test_stale_failed_false_or_malformed_report_refused(self):
        cases = [('nonce', 'another-nonce'), ('pid', 999), ('uid', self.uid + 1),
                 ('pid', True), ('tcpPort', 37002), ('state', 'secureInput'),
                 ('state', 'starting'), ('state', 'failed'), ('tapActive', False),
                 ('tapActive', 1), ('accessibility', False), ('effectiveInputAccess', False),
                 ('failure', 'failure'), ('inputCount', -1), ('outputCount', True),
                 ('heldOutputUsages', [False]), ('timestamp', float('nan')),
                 ('timestamp', float('inf')), ('timestamp', 'today'),
                 ('timestamp', self.report['timestamp'] - 3),
                 ('timestamp', self.report['timestamp'] + 2)]
        for key, value in cases:
            report = dict(self.report, **{key: value})
            with self.subTest(key=key, value=value), self.assertRaises(ValueError):
                runtime.validate_report(report, NONCE, 101, self.uid, 37001, time.time())
        for key in self.report:
            report = dict(self.report)
            del report[key]
            with self.subTest(missing=key), self.assertRaises(ValueError):
                runtime.validate_report(report, NONCE, 101, self.uid, 37001, time.time())

    def test_canonical_report_age_boundaries(self):
        now = time.time()
        for age in (-1, 0, 2):
            runtime.validate_report(dict(self.report, timestamp=now - runtime.SWIFT_REFERENCE_DATE - age),
                                    NONCE, 101, self.uid, 37001, now)

    def test_report_numeric_widths_and_non_root_ownership(self):
        for key, overflow in [('pid', 2**31), ('uid', 2**32), ('tcpPort', 65536),
                              ('inputCount', 2**64), ('outputCount', 2**64),
                              ('heldOutputUsages', [2**32])]:
            values = dict(self.report, **{key: overflow})
            with self.subTest(key=key), self.assertRaises(ValueError):
                runtime.validate_report(values, NONCE, values['pid'], values['uid'], values['tcpPort'], time.time())
        with self.assertRaises(ValueError):
            runtime.owned_launch({100: (0, self.executable, self.parent[2]),
                                 101: (0, self.executable, self.worker[2])}, self.executable, 0, 37001)

    def test_main_fails_without_evidence_or_invalid_timeout_and_prints_no_success(self):
        for failure in (ValueError('no owned session'), OSError('process query refused')):
            out, err = io.StringIO(), io.StringIO()
            with patch.object(runtime.sys, 'argv', ['verify-session-runtime.py', '--timeout', '0']), \
                 patch.object(runtime.sys, 'platform', 'darwin'), \
                 patch.object(runtime, 'verify', side_effect=failure), \
                 patch.object(runtime.sys, 'stdout', out), patch.object(runtime.sys, 'stderr', err):
                self.assertEqual(runtime.main(), 1)
            self.assertEqual(out.getvalue(), '')
            self.assertIn('verification failed', err.getvalue())
        with patch.object(runtime.sys, 'argv', ['verify-session-runtime.py', '--timeout', 'nan']), \
             patch.object(runtime.sys, 'platform', 'darwin'), self.assertRaises(ValueError):
            runtime.main()

    def test_unsafe_report_metadata_symlinks_and_oversize_refused(self):
        self.directory.chmod(0o755)
        with self.assertRaises(ValueError):
            runtime.read_report(self.path, self.uid)
        self.directory.chmod(0o700)
        self.path.chmod(0o644)
        with self.assertRaises(ValueError):
            runtime.read_report(self.path, self.uid)
        self.path.chmod(0o600)
        with self.assertRaises(ValueError):
            runtime.read_report(self.path, self.uid + 1)
        os.link(self.path, self.directory / 'hardlink')
        with self.assertRaises(ValueError):
            runtime.read_report(self.path, self.uid)
        (self.directory / 'hardlink').unlink()
        saved = self.directory / 'saved'
        self.path.rename(saved)
        self.path.symlink_to(saved)
        with self.assertRaises(OSError):
            runtime.read_report(self.path, self.uid)
        self.path.unlink()
        saved.rename(self.path)
        self.path.unlink()
        os.mkfifo(self.path, 0o600)
        with self.assertRaises(ValueError):
            runtime.read_report(self.path, self.uid)
        self.path.unlink()
        self.write()
        self.path.write_bytes(b'x' * 16385)
        with self.assertRaises(ValueError):
            runtime.read_report(self.path, self.uid)
        self.path.write_text('{"nonce":"x","nonce":"y"}')
        with self.assertRaises(ValueError):
            runtime.read_report(self.path, self.uid)
        saved_directory = self.base / 'saved-directory'
        self.directory.rename(saved_directory)
        self.directory.symlink_to(saved_directory, target_is_directory=True)
        with self.assertRaises(OSError):
            runtime.read_report(self.path, self.uid)

    def test_foreign_listener_dead_tcp_or_changed_process_refused(self):
        for listener in ('p999\nn127.0.0.1:37001\n', 'p101\nn192.168.1.2:37001\n', 'p101\nn*:37001\n', ''):
            with self.subTest(listener=listener), self.assertRaises(ValueError):
                self.verify(listener=listener)
        with self.assertRaises(OSError):
            self.verify(connect=ConnectionRefusedError())
        with self.assertRaises(ValueError):
            self.verify(identity=[self.parent, (self.uid, self.executable, ('replaced',))])
        with self.assertRaises(ProcessLookupError):
            self.verify(identity=[self.parent, ProcessLookupError()])

    def test_report_rechecked_after_tcp(self):
        def change_report(*args, **kwargs):
            self.report['state'] = 'stopped'
            self.write()
            return MagicMock()
        with self.assertRaises(ValueError):
            self.verify(connect=change_report)

    def test_shell_retains_trust_and_delegates_runtime_failures(self):
        app = self.base / 'KeyPath App.app'
        for bundle in ('KeyPath_KeyPath.bundle', 'KeyPath_KeyPathAppKit.bundle',
                       'KeyPath_KeyPathInstallationWizard.bundle'):
            (app / 'Contents/Resources' / bundle).mkdir(parents=True)
        (app / 'Contents/Resources/KeyPath_KeyPathAppKit.bundle/default.metallib').write_bytes(b'fixture-metallib')
        sparkle = app / 'Contents/Frameworks/Sparkle.framework/Versions/B/Sparkle'
        sparkle.parent.mkdir(parents=True)
        sparkle.touch()
        cli = app / 'Contents/MacOS/keypath-cli'
        cli.parent.mkdir(parents=True)
        cli.write_text('#!/bin/bash\necho fixture-cli-version\n')
        cli.chmod(0o755)
        for component in ('Contents/MacOS/KeyPath',
                          'Contents/Library/KeyPath/libkeypath_kanata_host_bridge.dylib',
                          'Contents/Library/KeyPath/kanata-simulator',
                          'Contents/Library/KeyPath/Kanata Engine.app/Contents/MacOS/kanata',
                          'Contents/PlugIns/Insights.bundle/Contents/MacOS/libKeyPathInsights'):
            binary = app / component
            binary.parent.mkdir(parents=True, exist_ok=True)
            binary.touch()
        tools = self.base / 'tools'
        tools.mkdir()
        log = self.base / 'trust-calls'
        for name, body in {'lipo': 'echo "${FIXTURE_ARCHITECTURES-arm64}"',
                           'otool': 'echo "@executable_path/../Frameworks"',
                           'codesign': 'echo "Identifier=com.keypath.KeyPath.CLI" >&2',
                           'spctl': ':', 'xcrun': ':',
                           'python-fixture': 'test "$1" = "$EXPECTED_HELPER" || exit 9\n'
                           'test "$(/usr/bin/shasum -a 256 "$1" | /usr/bin/awk \'{print $1}\')" = "$EXPECTED_HELPER_SHA" || exit 9\n'
                           'exit "${FIXTURE_RUNTIME_EXIT:-0}"'}.items():
            tool = tools / name
            tool.write_text('#!/bin/bash\necho "' + name + ' $*" >> "$TRUST_LOG"\n'
                            'if [[ "${FAIL_TOOL:-}" == "' + name + '" ]]; then exit 1; fi\n' + body + '\n')
            tool.chmod(0o755)
        environment = dict(os.environ, APP_PATH=str(app), PATH=str(tools) + ':' + os.environ['PATH'],
                           KEYPATH_VERIFY_PYTHON=str(tools / 'python-fixture'), EXPECTED_HELPER=str(HELPER),
                           EXPECTED_HELPER_SHA=hashlib.sha256(HELPER.read_bytes()).hexdigest(),
                           TRUST_LOG=str(log), CHECK_RUNTIME='1', REQUIRE_NOTARIZED='1', REQUIRE_STAPLED='1')
        script = ROOT / 'Scripts/verify-installed-app.sh'
        for architectures in ('x86_64', 'x86_64 arm64', ''):
            result = subprocess.run(['/bin/bash', str(script)],
                                    env=dict(environment, FIXTURE_ARCHITECTURES=architectures),
                                    capture_output=True, text=True)
            self.assertNotEqual(result.returncode, 0)
            self.assertIn('requires Apple Silicon only', result.stderr)
            self.assertNotIn('codesign', log.read_text())
            log.unlink()
        for code in ('0', '1'):
            result = subprocess.run(['/bin/bash', str(script)], env=dict(environment, FIXTURE_RUNTIME_EXIT=code),
                                    capture_output=True, text=True)
            self.assertEqual(result.returncode, int(code), result.stderr)
            calls = log.read_text()
            self.assertIn('codesign --verify --strict --verbose=2', calls)
            self.assertIn('spctl -a -vvv -t install', calls)
            self.assertIn('xcrun stapler validate', calls)
            self.assertIn('--app ' + str(app) + ' --port 37001 --timeout 20', calls)
            self.assertNotIn('launchctl', calls)
            log.unlink()
        result = subprocess.run(['/bin/bash', str(script)], env=dict(environment, CHECK_RUNTIME='0', FIXTURE_RUNTIME_EXIT='1'),
                                capture_output=True, text=True)
        self.assertEqual(result.returncode, 0, result.stderr)
        self.assertIn('trust checks', result.stdout)
        self.assertNotIn('python-fixture', log.read_text())
        log.unlink()
        for failed_tool in ('codesign', 'spctl', 'xcrun'):
            result = subprocess.run(['/bin/bash', str(script)], env=dict(environment, FAIL_TOOL=failed_tool),
                                    capture_output=True, text=True)
            self.assertNotEqual(result.returncode, 0)
            self.assertNotIn('python-fixture', log.read_text())
            log.unlink()
        result = subprocess.run(['/bin/bash', str(script)],
                                env=dict(environment, KEYPATH_VERIFY_PYTHON=str(tools / 'missing-python')),
                                capture_output=True, text=True)
        self.assertNotEqual(result.returncode, 0)
        self.assertIn('Python 3 is required', result.stderr)
        self.assertNotIn('runtime verification.', result.stdout)

        flat = app / 'Contents/Resources/KeyPath_KeyPathAppKit.bundle/default.metallib'
        native = flat.parent / 'Contents/Resources/default.metallib'
        native.parent.mkdir(parents=True)
        layouts = [('flat', b'compiled-fixture', None, True),
                   ('native', None, b'compiled-fixture', True),
                   ('native_with_empty_flat', b'', b'compiled-fixture', True),
                   ('missing', None, None, False),
                   ('empty_flat', b'', None, False),
                   ('empty_native', None, b'', False)]
        for name, flat_bytes, native_bytes, accepted in layouts:
            with self.subTest(metal_layout=name):
                flat.unlink(missing_ok=True)
                native.unlink(missing_ok=True)
                log.unlink(missing_ok=True)
                if flat_bytes is not None:
                    flat.write_bytes(flat_bytes)
                if native_bytes is not None:
                    native.write_bytes(native_bytes)
                result = subprocess.run(['/bin/bash', str(script)],
                                        env=dict(environment, CHECK_RUNTIME='0'),
                                        capture_output=True, text=True)
                self.assertEqual(result.returncode, 0 if accepted else 1, result.stderr)
                if accepted:
                    self.assertIn('codesign --verify --strict', log.read_text())
                else:
                    self.assertIn('Metal library is missing or empty', result.stderr)
                    self.assertFalse(log.exists(), 'missing resource must fail before trust tools')

    def test_release_doctor_uses_same_helper_and_keeps_trust_preflight(self):
        doctor = (ROOT / 'Scripts/release-doctor.sh').read_text()
        section = doctor.split('print_section "Installed Runtime"')[1].split('print_section "Background Watchers"')[0]
        self.assertIn('"$SCRIPT_DIR/verify-session-runtime.py"', section)
        self.assertIn('--timeout 0', section)
        self.assertNotIn('launchctl', section)
        self.assertIn('kp_notary_resolve_auth', doctor)
        self.assertIn('verify-release-signing-contract.sh', doctor)


if __name__ == '__main__':
    unittest.main()
