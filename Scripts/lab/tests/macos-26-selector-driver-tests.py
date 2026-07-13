#!/usr/bin/env python3
import json
import os
import pathlib
import subprocess
import tempfile
import unittest

TOOL = pathlib.Path(__file__).resolve().parents[1] / "macos-26-selector-driver"

class DriverTests(unittest.TestCase):
    def setUp(self):
        self.tmp = tempfile.TemporaryDirectory(); self.root = pathlib.Path(self.tmp.name)
        self.bin = self.root / "bin"; self.bin.mkdir(); self.output = self.root / "out"
        (self.bin / "sw_vers").write_text('#!/bin/sh\nversion=${MACOS_TEST_VERSION:-26.0}\nif [ "$1" = -productVersion ]; then echo "$version"; else echo "ProductVersion: $version"; fi\n')
        (self.bin / "sw_vers").chmod(0o755)
        self.peekaboo = self.root / "peekaboo-ui"; self.peekaboo.write_text('#!/bin/sh\nout=\nwhile [ $# -gt 0 ]; do [ "$1" = --output ] && out=$2; shift; done\nprintf \'{"data":{"ui_elements":[{"identifier":"InputMonitoring","label":"KeyPath"}]}}\' > "$out"\n')
        self.peekaboo.chmod(0o755)
        self.result = self.root / "scenario-result"; self.result.write_text((TOOL.parent / "scenario-result").read_text()); self.result.chmod(0o755)

    def tearDown(self): self.tmp.cleanup()

    def call(self, *extra, version="26.0"):
        env = os.environ | {"PATH": str(self.bin) + ":" + os.environ["PATH"], "MACOS_TEST_VERSION": version, "KEYPATH_SELECTOR_PEEKABOO": str(self.peekaboo), "KEYPATH_SELECTOR_RESULT": str(self.result)}
        return subprocess.run([str(TOOL), "--output", str(self.output), *extra], env=env, text=True, capture_output=True)

    def test_accepts_fresh_macos_26_selector_evidence(self):
        result = self.call("--expect", "InputMonitoring", "--expect", "KeyPath")
        self.assertEqual(result.returncode, 0, result.stderr)
        self.assertEqual(json.loads((self.output / "selector-contract.json").read_text())["macOSMajor"], 26)

    def test_rejects_another_macos_version_without_snapshot(self):
        result = self.call("--expect", "KeyPath", version="15.7.7")
        self.assertEqual(result.returncode, 4)
        self.assertEqual(json.loads((self.output / "result.json").read_text())["failure"]["classification"], "unsupported-os-selector")

    def test_missing_selector_is_explicitly_unsupported(self):
        result = self.call("--expect", "Missing Control")
        self.assertEqual(result.returncode, 4)
        outcome = json.loads((self.output / "result.json").read_text())
        self.assertEqual(outcome["failure"]["classification"], "unsupported-os-selector")

if __name__ == "__main__": unittest.main()
