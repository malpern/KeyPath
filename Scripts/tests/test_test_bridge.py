import pathlib
import subprocess
import tempfile
import unittest

ROOT = pathlib.Path(__file__).resolve().parents[2]
HELPER = ROOT / 'Scripts/lib/test-bridge.sh'

class TestBridgeHarnessTests(unittest.TestCase):
    def run_case(self, explicit=None, fail=False):
        with tempfile.TemporaryDirectory() as directory:
            root = pathlib.Path(directory)
            (root / 'Scripts').mkdir()
            builder = root / 'Scripts/build-kanata-host-bridge.sh'
            builder.write_text('#!/bin/bash\n' + ('exit 17\n' if fail else
                'mkdir -p build/kanata-host-bridge\nprintf fixture > build/kanata-host-bridge/libkeypath_kanata_host_bridge.dylib\n'))
            builder.chmod(0o755)
            env = {'PATH': '/usr/bin:/bin'}
            if explicit is not None:
                env['KEYPATH_SESSION_TEST_BRIDGE_PATH'] = explicit
            result = subprocess.run(['bash', '-c', 'source "$1" && keypath_prepare_test_bridge "$2" && test -f "$KEYPATH_SESSION_TEST_BRIDGE_PATH"', '--', str(HELPER), str(root)], cwd=root, env=env, capture_output=True, text=True)
            return result

    def test_default_builds_and_exports_real_local_fixture(self):
        result = self.run_case()
        self.assertEqual(result.returncode, 0, result.stderr)

    def test_build_failure_cannot_become_a_skipped_or_passing_test(self):
        self.assertNotEqual(self.run_case(fail=True).returncode, 0)

    def test_explicit_missing_bridge_fails_instead_of_falling_back(self):
        self.assertNotEqual(self.run_case(explicit='/missing/bridge.dylib').returncode, 0)

    def test_explicit_fixture_does_not_rebuild(self):
        with tempfile.NamedTemporaryFile() as bridge:
            result = self.run_case(explicit=bridge.name, fail=True)
            self.assertEqual(result.returncode, 0, result.stderr)

if __name__ == '__main__':
    unittest.main()
