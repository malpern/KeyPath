#!/usr/bin/env python3
import json
import os
import pathlib
import subprocess
import tempfile
import unittest


TOOL = pathlib.Path(__file__).resolve().parents[1] / "physical-remap-session"


class PhysicalSessionTests(unittest.TestCase):
    def setUp(self):
        self.tmp = tempfile.TemporaryDirectory()
        self.root = pathlib.Path(self.tmp.name)
        self.bin = self.root / "bin"
        self.bin.mkdir()
        self.output = self.root / "out"
        self.make("sw_vers", '#!/bin/sh\n[ "$1" = -productVersion ] && { echo 15.7.7; exit; }; echo 15.7.7\n')
        self.make("ioreg", '#!/bin/sh\necho \'"Product" = "M-VAVE SMK-25"\'\necho \'"SerialNumber" = "do-not-retain"\'\n')
        self.make("ready", '#!/bin/sh\necho runtime_state=ready\n')
        self.make("keypath-cli", '#!/bin/sh\necho \'{"ok":true,"output":"w"}\'\n')
        self.make("open", '#!/bin/sh\nexit 0\n')
        self.make("osascript", '#!/bin/sh\ncase "$*" in *"get text"*) printf "%s\\n" "${TEXTEDIT_VALUE:-w}";; esac\n')
        self.make("peekaboo", '#!/bin/sh\nexit 0\n')
        self.make("peekaboo-ui", '''#!/bin/sh
command=$1; shift
out=
app=
while [ $# -gt 0 ]; do
  [ "$1" = --output ] && out=$2
  [ "$1" = --app ] && app=$2
  shift
done
if [ "$command" = screenshot ]; then printf png > "$out"; exit 0; fi
if [ "$app" = KeyPath ]; then
  printf '%s\n' '{"data":{"ui_elements":[{"identifier":"keyboard-overlay"},{"identifier":"keycap-code-12","value":"pressed"}]}}' > "$out"
else
  printf '%s\n' '{"data":{"ui_elements":[{"label":"TextEdit"}]}}' > "$out"
fi
''')
        result = self.bin / "scenario-result"
        result.write_text((TOOL.parent / "scenario-result").read_text())
        result.chmod(0o755)

    def make(self, name: str, body: str) -> None:
        path = self.bin / name
        path.write_text(body)
        path.chmod(0o755)

    def tearDown(self):
        self.tmp.cleanup()

    def env(self, **extra):
        values = os.environ | {
            "KEYPATH_PHYSICAL_RESULT": str(self.bin / "scenario-result"),
            "KEYPATH_PHYSICAL_ASSERT_READY": str(self.bin / "ready"),
            "KEYPATH_PHYSICAL_PEEKABOO_UI": str(self.bin / "peekaboo-ui"),
            "KEYPATH_PHYSICAL_PEEKABOO": str(self.bin / "peekaboo"),
            "KEYPATH_PHYSICAL_INSTALLED_CLI": str(self.bin / "keypath-cli"),
            "KEYPATH_PHYSICAL_SW_VERS": str(self.bin / "sw_vers"),
            "KEYPATH_PHYSICAL_IOREG": str(self.bin / "ioreg"),
            "KEYPATH_PHYSICAL_OPEN": str(self.bin / "open"),
            "KEYPATH_PHYSICAL_OSASCRIPT": str(self.bin / "osascript"),
            "KEYPATH_PHYSICAL_SLEEP_SCALE": "0",
        }
        values.update(extra)
        return values

    def call(self, *args, env=None):
        return subprocess.run([str(TOOL), *args], env=env or self.env(), text=True, capture_output=True)

    def test_one_physical_event_proves_output_overlay_and_timing(self):
        prepared = self.call("prepare", "--output", str(self.output), "--device-match", "M-VAVE")
        self.assertEqual(prepared.returncode, 0, prepared.stderr)
        observed = self.call("observe", "--output", str(self.output), "--timeout-seconds", "1")
        self.assertEqual(observed.returncode, 0, observed.stderr)
        for block in ("P02", "P03", "P04"):
            result = json.loads((self.output / block / "result.json").read_text())
            self.assertEqual(result["status"], "passed", block)
        self.assertNotIn("do-not-retain", (self.output / "prepare" / "hid-inventory.txt").read_text())
        timing = json.loads((self.output / "P04" / "timing.json").read_text())
        self.assertIn("launchToOutputMilliseconds", timing)

    def test_missing_named_guest_hid_blocks_before_arming(self):
        prepared = self.call("prepare", "--output", str(self.output), "--device-match", "Kinesis")
        self.assertEqual(prepared.returncode, 4)
        result = json.loads((self.output / "prepare" / "result.json").read_text())
        self.assertEqual(result["failure"]["step"], "physical-hid-admission")

    def test_literal_q_is_a_product_failure_and_cannot_prove_timing(self):
        self.assertEqual(self.call("prepare", "--output", str(self.output), "--device-match", "M-VAVE").returncode, 0)
        observed = self.call("observe", "--output", str(self.output), "--timeout-seconds", "1", env=self.env(TEXTEDIT_VALUE="q"))
        self.assertEqual(observed.returncode, 1)
        p02 = json.loads((self.output / "P02" / "result.json").read_text())
        p03 = json.loads((self.output / "P03" / "result.json").read_text())
        p04 = json.loads((self.output / "P04" / "result.json").read_text())
        self.assertEqual(p02["failure"]["classification"], "keypath-product-failure")
        self.assertEqual(p03["status"], "passed")
        self.assertEqual(p04["status"], "blocked")


if __name__ == "__main__":
    unittest.main()
