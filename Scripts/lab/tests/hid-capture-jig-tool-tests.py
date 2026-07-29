#!/usr/bin/env python3
"""Contract tests for the HID Capture Jig launcher."""

from __future__ import annotations

import os
import pathlib
import subprocess
import tempfile
import textwrap
import unittest


ROOT = pathlib.Path(__file__).resolve().parents[3]
TOOL = ROOT / "Scripts/lab/hid-capture-jig-tool"


class HIDCaptureJigToolTests(unittest.TestCase):
    def setUp(self) -> None:
        self.temporary = tempfile.TemporaryDirectory()
        self.directory = pathlib.Path(self.temporary.name)
        self.fake_bin = self.directory / "bin"
        self.fake_bin.mkdir()
        self.state = self.directory / "running"
        self.log = self.directory / "calls.log"
        self.app = self.directory / "KeyPath HID Capture Jig.app"
        binary = self.app / "Contents/MacOS/HIDCaptureJig"
        binary.parent.mkdir(parents=True)
        binary.write_text("current jig binary\n")
        binary.chmod(0o755)
        self.state.write_text("old process\n")

        self.build_app = self.directory / "build-app"
        self._write_executable(self.build_app, "#!/bin/bash\nexit 0\n")
        self.client = self.directory / "client"
        self._write_executable(self.client, textwrap.dedent(f"""\
            #!/bin/bash
            set -eu
            printf 'client %s\\n' "$*" >> {str(self.log)!r}
            case "$1" in
                quit) rm -f {str(self.state)!r}; printf '{{"ok":true}}\\n' ;;
                status)
                    [[ -f {str(self.state)!r} ]] || exit 2
                    printf '{{"ok":true,"snapshot":{{"state":"idle"}}}}\\n'
                    ;;
                focus) printf '{{"ok":true}}\\n' ;;
                *) printf '{{"ok":true}}\\n' ;;
            esac
        """))
        self.runner = self.directory / "runner"
        self._write_executable(self.runner, textwrap.dedent(f"""\
            #!/bin/bash
            printf 'runner %s\\n' "$*" >> {str(self.log)!r}
            printf '{{"status":"passed"}}\\n'
        """))
        self._write_executable(self.fake_bin / "pgrep", textwrap.dedent(f"""\
            #!/bin/bash
            [[ -f {str(self.state)!r} ]]
        """))
        self._write_executable(self.fake_bin / "open", textwrap.dedent(f"""\
            #!/bin/bash
            printf 'open %s\\n' "$*" >> {str(self.log)!r}
            printf 'new process\\n' > {str(self.state)!r}
        """))

        self.environment = os.environ.copy()
        self.environment.update({
            "HOME": str(self.directory),
            "PATH": f"{self.fake_bin}:{self.environment['PATH']}",
            "KEYPATH_CAPTURE_JIG_APP": str(self.app),
            "KEYPATH_CAPTURE_JIG_BUILD_APP": str(self.build_app),
            "KEYPATH_CAPTURE_JIG_CLIENT": str(self.client),
            "KEYPATH_PHYSICAL_HID_RUNNER": str(self.runner),
        })

    def tearDown(self) -> None:
        self.temporary.cleanup()

    @staticmethod
    def _write_executable(path: pathlib.Path, contents: str) -> None:
        path.write_text(contents)
        path.chmod(0o755)

    def run_tool(self, command: str) -> subprocess.CompletedProcess[str]:
        return subprocess.run(
            [str(TOOL), command], text=True, capture_output=True, env=self.environment
        )

    def test_showroom_restarts_a_healthy_but_potentially_stale_process(self) -> None:
        result = self.run_tool("showroom")

        self.assertEqual(result.returncode, 0, result.stderr)
        calls = self.log.read_text().splitlines()
        self.assertIn("client quit", calls)
        self.assertTrue(any(call.startswith("open ") for call in calls))
        self.assertFalse(any(call == "client focus" for call in calls))
        runner_call = next(call for call in calls if call.startswith("runner "))
        self.assertIn("--demo-mode", runner_call)
        self.assertIn("--repeat 14", runner_call)
        self.assertIn("--cycle-gap-ms 469", runner_call)
        self.assertLess(calls.index("client quit"), next(
            index for index, call in enumerate(calls) if call.startswith("open ")
        ))


if __name__ == "__main__":
    unittest.main()
