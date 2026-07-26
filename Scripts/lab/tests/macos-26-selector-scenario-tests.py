#!/usr/bin/env python3
import json
import os
import pathlib
import subprocess
import tempfile
import unittest


TOOL = pathlib.Path(__file__).resolve().parents[1] / "macos-26-selector-scenario"
DRIVER = pathlib.Path(__file__).resolve().parents[1] / "macos-26-selector-driver"


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
            'printf \'%s\\n\' \'{"identifier":"com.apple.Accessibility-Settings.extension","label":"Allow the applications below to control your computer.","row":"peekaboo_Title"}\' > "$out"\n'
        )
        self.peekaboo.chmod(0o755)
        self.driver = self.bin / "driver"
        self.driver.write_text('#!/bin/sh\nprintf "%s\\n" "driver $*" >> "$CALLS"\n')
        self.driver.chmod(0o755)
        self.sw_vers = self.bin / "sw_vers"
        self.sw_vers.write_text('#!/bin/sh\n[ "$1" = -productVersion ] && echo 26.5.2 || echo "ProductName: macOS"\n')
        self.sw_vers.chmod(0o755)

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
        self.assertIn("--expect-any com.apple.settings.accessibility|com.apple.Accessibility-Settings.extension", calls)
        self.assertIn("--expect Allow the applications below to control your computer.", calls)
        self.assertIn("--expect-any Peekaboo Lab Host|peekaboo_Title", calls)
        self.assertTrue((self.output / "accessibility-readiness.json").exists())

    def test_driver_accepts_observed_semantic_selector_variants(self):
        env = os.environ | {
            "PATH": f"{self.bin}:{os.environ['PATH']}",
            "KEYPATH_SELECTOR_PEEKABOO": str(self.peekaboo),
            "KEYPATH_SELECTOR_RESULT": "/usr/bin/true",
        }
        result = subprocess.run([
            str(DRIVER), "--output", str(self.output),
            "--expect-any", "com.apple.settings.accessibility|com.apple.Accessibility-Settings.extension",
            "--expect", "Allow the applications below to control your computer.",
            "--expect-any", "Peekaboo Lab Host|peekaboo_Title",
        ], env=env, text=True, capture_output=True)

        self.assertEqual(result.returncode, 0, result.stderr)
        contract = json.loads((self.output / "selector-contract.json").read_text())
        self.assertEqual(contract["expectedAny"][0][1], "com.apple.Accessibility-Settings.extension")
        self.assertEqual(contract["expectedAny"][1][1], "peekaboo_Title")


if __name__ == "__main__":
    unittest.main()
