import base64
import hashlib
import io
import os
from pathlib import Path
import re
import shutil
import subprocess
import tarfile
import tempfile
import unittest


ROOT = Path(__file__).resolve().parent
EXPECTED_HELPERS = {
    "fixture-usb": "b4bad3168fdcd687888d4d8d7e374f19dbd78ed32beaa1e64d1000fdeddd713b",
    "desktop-bootstrap": "b1d483fc11e96dd6b17dddbc6044e40d3bbea2261d6a5584f40b58625a02f68b",
    "nameplate-instrumentation": "10686f636c16754f0e0d1ad3f2e8e58e5857f9fa1dd0b0e6a23d838b4e10a668",
    "peekaboo-ui": "1925e1ca8da1eba87caa66350440f668f4cfe10b89e23fa593f3255f842a877b",
    "permission-drag": "62e3bd1ebbd8a391cfde054349688cb52ca77111c34f1090d1a9f46ee6b20ae4",
}


class GuestPayloadTests(unittest.TestCase):
    def _fixture(self, root):
        lab = root / "lab"
        shutil.copytree(ROOT / "bin", lab / "bin")
        shutil.copytree(ROOT / "lib", lab / "lib")
        repo = root / "tenant"
        repo.mkdir()
        (repo / ".vm-lab.tsv").write_text("guest_user\tkeypathqa\n")
        registry = root / "tenants.tsv"
        registry.write_text(f"keypath\t{repo}\n")

        bindir = root / "fake-bin"
        bindir.mkdir()
        capture = root / "captured-payload"
        called = root / "ssh-called"
        ssh = bindir / "ssh"
        ssh.write_text(
            "#!/bin/bash\n"
            "set -eu\n"
            ": > \"$SSH_CALLED_MARKER\"\n"
            "cat > \"$SSH_PAYLOAD_CAPTURE\"\n"
            "printf 'VM_LAB_STATUS_V1 {\\\"state\\\":\\\"inert-stub\\\"}\\n'\n"
        )
        ssh.chmod(0o755)
        env = os.environ.copy()
        env.update(
            {
                "HOME": str(root / "home"),
                "VM_LAB_REGISTRY": str(registry),
                "PATH": f"{bindir}:/usr/bin:/bin",
                "SSH_PAYLOAD_CAPTURE": str(capture),
                "SSH_CALLED_MARKER": str(called),
            }
        )
        Path(env["HOME"]).mkdir()
        return lab, capture, called, env

    def test_actual_cli_assembles_pinned_helpers_then_remote_script(self):
        source = (ROOT / "bin/vm-lab").read_text()
        match = re.search(r"^GUEST_HELPERS=\(([^)]*)\)$", source, re.MULTILINE)
        self.assertIsNotNone(match)
        names = match.group(1).split()
        self.assertEqual(names, ["desktop-bootstrap", "nameplate-instrumentation", "peekaboo-ui", "permission-drag", "fixture-usb"])

        with tempfile.TemporaryDirectory() as directory:
            lab, capture, called, env = self._fixture(Path(directory))
            result = subprocess.run(
                [str(lab / "bin/vm-lab"), "keypath", "list"],
                env=env,
                capture_output=True,
                text=True,
                check=False,
            )
            self.assertEqual(result.returncode, 0, result.stderr)
            self.assertEqual(result.stdout, 'VM_LAB_STATUS_V1 {"state":"inert-stub"}\n')
            self.assertTrue(called.is_file())

            stream = capture.read_bytes()
            frame = re.match(rb"VM_LAB_GUEST_HELPERS_B64='(.*?)'\n", stream, re.DOTALL)
            self.assertIsNotNone(frame)
            archive = base64.b64decode(frame.group(1))
            with tarfile.open(fileobj=io.BytesIO(archive), mode="r:gz") as bundle:
                members = bundle.getmembers()
                member_names = [member.name for member in members]
                self.assertEqual(
                    member_names,
                    [name for helper in names for name in ("._" + helper, helper)],
                )
                for member in members:
                    if member.name.startswith("._"):
                        continue  # Darwin tar carries the host provenance xattr as AppleDouble.
                    data = bundle.extractfile(member).read()
                    self.assertEqual(hashlib.sha256(data).hexdigest(), EXPECTED_HELPERS[member.name])
            remote_script = stream[frame.end():]
            self.assertEqual(remote_script, (lab / "lib/remote.sh").read_bytes())

    def test_missing_helper_refuses_before_the_ssh_dispatch(self):
        with tempfile.TemporaryDirectory() as directory:
            lab, capture, called, env = self._fixture(Path(directory))
            (lab / "lib/peekaboo-ui").unlink()
            result = subprocess.run(
                [str(lab / "bin/vm-lab"), "keypath", "list"],
                env=env,
                capture_output=True,
                text=True,
                check=False,
            )
            self.assertEqual(result.returncode, 1)
            self.assertIn("guest helper is missing from the lab: lib/peekaboo-ui", result.stderr)
            # The shell pipeline starts its SSH side concurrently, but the fake
            # SSH must receive no script bytes; the real remote helper rejects
            # a failed producer before any provider operation.
            self.assertTrue(called.is_file())
            self.assertEqual(capture.read_bytes(), b"")


if __name__ == "__main__":
    unittest.main()
