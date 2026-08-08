#!/usr/bin/env python3
import json
import os
import pathlib
import subprocess
import tempfile
import unittest

TOOL = pathlib.Path(__file__).resolve().parents[1] / "macos-27-selector-driver"


class DriverTests(unittest.TestCase):
    def setUp(self):
        self.tmp = tempfile.TemporaryDirectory()
        self.root = pathlib.Path(self.tmp.name)
        self.bin = self.root / "bin"
        self.bin.mkdir()
        self.output = self.root / "out"
        (self.bin / "sw_vers").write_text(
            '#!/bin/sh\nversion=${MACOS_TEST_VERSION:-27.0}\n'
            'if [ "$1" = -productVersion ]; then echo "$version"; '
            'elif [ "$1" = -buildVersion ]; then echo 26A5378j; '
            'else echo "ProductVersion: $version"; echo "BuildVersion: 26A5378j"; fi\n'
        )
        (self.bin / "sw_vers").chmod(0o755)
        self.peekaboo = self.root / "peekaboo-ui"
        self.peekaboo.write_text(
            '#!/bin/sh\n'
            'if [ "$1" = preflight ]; then\n'
            '  if [ -n "${PEEKABOO_TEST_PREFLIGHT:-}" ]; then printf \'%s\\n\' "$PEEKABOO_TEST_PREFLIGHT"; '
            '  else printf \'%s\\n\' \'{"data":{"permissions":[{"name":"Screen Recording","isRequired":true,"isGranted":true},{"name":"Accessibility","isRequired":true,"isGranted":true}]}}\'; fi\n'
            '  exit 0\n'
            'fi\n'
            'out=\nwhile [ $# -gt 0 ]; do [ "$1" = --output ] && out=$2; shift; done\n'
            'printf \'{"data":{"ui_elements":[{"identifier":"Privacy_Accessibility","label":"Accessibility"}]}}\' > "$out"\n'
        )
        self.peekaboo.chmod(0o755)
        self.result = self.root / "scenario-result"
        self.result.write_text((TOOL.parent / "scenario-result").read_text())
        self.result.chmod(0o755)

    def tearDown(self):
        self.tmp.cleanup()

    def call(self, *extra, version="27.0", preflight=None):
        env = os.environ | {
            "PATH": str(self.bin) + ":" + os.environ["PATH"],
            "MACOS_TEST_VERSION": version,
            "KEYPATH_SELECTOR_PEEKABOO": str(self.peekaboo),
            "KEYPATH_SELECTOR_RESULT": str(self.result),
        }
        if preflight is not None:
            env["PEEKABOO_TEST_PREFLIGHT"] = json.dumps(preflight, separators=(",", ":"))
        return subprocess.run(
            [str(TOOL), "--output", str(self.output), *extra],
            env=env,
            text=True,
            capture_output=True,
        )

    def test_accepts_fresh_macos_27_selector_evidence(self):
        result = self.call("--expect", "Privacy_Accessibility", "--expect", "Accessibility")
        self.assertEqual(result.returncode, 0, result.stderr)
        contract = json.loads((self.output / "selector-contract.json").read_text())
        self.assertEqual(contract["macOSMajor"], 27)
        self.assertEqual(contract["macOSBuild"], "26A5378j")

    def test_requires_at_least_one_selector(self):
        result = self.call()
        self.assertEqual(result.returncode, 2)

    def test_rejects_another_macos_version_without_preflight(self):
        result = self.call("--expect", "Accessibility", version="26.6")
        self.assertEqual(result.returncode, 4)
        self.assertEqual(json.loads((self.output / "result.json").read_text())["failure"]["classification"], "unsupported-os-selector")
        self.assertFalse((self.output / "peekaboo-preflight.json").exists())

    def test_missing_permission_is_environment_precondition_failure(self):
        result = self.call("--expect", "Accessibility", preflight={
            "data": {"permissions": [
                {"name": "Screen Recording", "isRequired": True, "isGranted": False}
            ]}
        })
        self.assertEqual(result.returncode, 4)
        outcome = json.loads((self.output / "result.json").read_text())
        self.assertEqual(outcome["failure"]["classification"], "environment-precondition-failure")
        self.assertIn("Screen Recording", outcome["failure"]["message"])

    def test_missing_selector_is_explicitly_unsupported(self):
        result = self.call("--expect", "Missing Control")
        self.assertEqual(result.returncode, 4)
        outcome = json.loads((self.output / "result.json").read_text())
        self.assertEqual(outcome["failure"]["classification"], "unsupported-os-selector")


if __name__ == "__main__":
    unittest.main()
