"""Signature inspection must not substitute for integrity verification."""
import os
from pathlib import Path
import plistlib
import shutil
import subprocess
import tempfile
import unittest
ROOT = Path(__file__).resolve().parents[2]
class SignatureIntegrityTests(unittest.TestCase):
    def helper(self, target, env=None):
        return subprocess.run(["bash", "-c", 'source "$1"; kp_verify_signature "$2"',
            "test", str(ROOT / "Scripts/lib/signing.sh"), str(target)],
            env=env, capture_output=True, text=True)
    def test_helper_verifies_and_propagates_failure(self):
        with tempfile.TemporaryDirectory() as tmp:
            stub = Path(tmp) / "codesign"
            stub.write_text('#!/bin/sh\nprintf "%s\\n" "$@" > "$ARG_LOG"\ncase " $* " in *" --verify "*) exit 19;; esac\n')
            stub.chmod(0o755)
            log = Path(tmp) / "args"
            result = self.helper("example.app", dict(os.environ, KP_VERIFY_CMD=str(stub), ARG_LOG=str(log)))
            self.assertEqual(result.returncode, 19)
            args = log.read_text().splitlines()
            for flag in ["--verify", "--deep", "--strict"]:
                self.assertIn(flag, args)
    def test_identity_checks_component_integrity_before_metadata(self):
        source = (ROOT / "Scripts/verify-identity-contract.sh").read_text()
        function = source.split("expect_codesign_identity() {", 1)[1].split("\nexpect_no_forbidden_payloads()", 1)[0]
        script = """failures=0
fail() { failures=$((failures+1)); }
pass() { :; }
codesign() { case " $* " in *" --verify "*) return 19;; esac
printf '%s\\n' 'Identifier=id' 'Authority=authority' 'TeamIdentifier=team' 'CodeDirectory flags=0x10000(runtime)' 'designated => requirement'
}
DEVELOPER_ID_AUTHORITY=authority
TEAM_ID=team
expect_codesign_identity() {""" + function + """
expect_codesign_identity '/app/Contents/Library/KeyPath/bridge.dylib' id requirement bridge
[ "$failures" -gt 0 ]
"""
        result = subprocess.run(["bash", "-c", script], capture_output=True, text=True)
        self.assertEqual(result.returncode, 0, result.stderr)
    @unittest.skipUnless(os.uname().sysname == "Darwin", "requires macOS codesign")
    def test_real_tampered_bundle_is_rejected(self):
        with tempfile.TemporaryDirectory() as tmp:
            app = Path(tmp) / "Fixture.app"
            (app / "Contents/MacOS").mkdir(parents=True)
            shutil.copy("/usr/bin/true", app / "Contents/MacOS/Fixture")
            info = app / "Contents/Info.plist"
            info.write_bytes(plistlib.dumps({"CFBundleIdentifier": "com.keypath.signature-test", "CFBundleExecutable": "Fixture", "CFBundlePackageType": "APPL"}))
            subprocess.run(["codesign", "--force", "--sign", "-", str(app)], check=True, capture_output=True)
            self.assertEqual(self.helper(app).returncode, 0)
            info.write_bytes(info.read_bytes() + b"\n")
            self.assertNotEqual(self.helper(app).returncode, 0, "metadata display accepted a tampered signed bundle")
if __name__ == "__main__":
    unittest.main()
