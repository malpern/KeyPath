#!/usr/bin/env python3
import os
import pathlib
import subprocess
import tempfile
import unittest


TOOL = pathlib.Path(__file__).resolve().parents[1] / "macos-26-selector-scenario"


class ScenarioTests(unittest.TestCase):
    def setUp(self):
        self.tmp = tempfile.TemporaryDirectory()
        self.root = pathlib.Path(self.tmp.name)
        self.output = self.root / "out"
        self.calls = self.root / "calls"
        self.bin = self.root / "bin"
        self.bin.mkdir()
        for name in ("open", "osascript", "sleep"):
            path = self.bin / name
            path.write_text(f'#!/bin/sh\nprintf "%s\\n" "{name} $*" >> "$CALLS"\n')
            path.chmod(0o755)
        self.peekaboo = self.bin / "peekaboo"
        self.peekaboo.write_text(
            '#!/bin/sh\nout=\nwhile [ $# -gt 0 ]; do [ "$1" = --output ] && out=$2; shift; done\n'
            'printf \'%s\\n\' \'{"identifier":"com.apple.settings.accessibility","label":"Allow the applications below to control your computer.","row":"Peekaboo Lab Host"}\' > "$out"\n'
        )
        self.peekaboo.chmod(0o755)
        self.driver = self.bin / "driver"
        self.driver.write_text('#!/bin/sh\nprintf "%s\\n" "driver $*" >> "$CALLS"\n')
        self.driver.chmod(0o755)

    def tearDown(self):
        self.tmp.cleanup()

    def test_prepares_accessibility_pane_and_uses_macos26_contract(self):
        env = os.environ | {
            "CALLS": str(self.calls),
            "KEYPATH_SELECTOR_DRIVER": str(self.driver),
            "KEYPATH_SELECTOR_PEEKABOO": str(self.peekaboo),
            "KEYPATH_SELECTOR_OPEN": str(self.bin / "open"),
            "KEYPATH_SELECTOR_OSASCRIPT": str(self.bin / "osascript"),
            "KEYPATH_SELECTOR_SLEEP": str(self.bin / "sleep"),
        }
        result = subprocess.run([str(TOOL), "--output", str(self.output)], env=env, text=True, capture_output=True)
        self.assertEqual(result.returncode, 0, result.stderr)
        calls = self.calls.read_text()
        self.assertIn("Privacy_Accessibility", calls)
        self.assertIn("--expect com.apple.settings.accessibility", calls)
        self.assertIn("--expect Allow the applications below to control your computer.", calls)
        self.assertIn("--expect Peekaboo Lab Host", calls)
        self.assertTrue((self.output / "accessibility-readiness.json").exists())


if __name__ == "__main__":
    unittest.main()
