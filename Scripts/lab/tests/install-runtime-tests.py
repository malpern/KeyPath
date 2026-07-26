#!/usr/bin/env python3

import json
import os
import pathlib
import subprocess
import tempfile
import textwrap
import unittest


ROOT = pathlib.Path(__file__).resolve().parents[3]
INSTALL_RUNTIME = ROOT / "Scripts/lab/install-runtime"
PLAN_ID = "11111111-1111-4111-8111-111111111111"
SNAPSHOT_ID = "22222222-2222-4222-8222-222222222222"
RUN_ID = "33333333-3333-4333-8333-333333333333"
INSTALL_PLAN_ID = "44444444-4444-4444-8444-444444444444"
AFTER_ID = "55555555-5555-4555-8555-555555555555"


class InstallRuntimeTests(unittest.TestCase):
    def setUp(self) -> None:
        self.temporary = tempfile.TemporaryDirectory()
        self.directory = pathlib.Path(self.temporary.name)
        self.approved = self.directory / "approved"
        self.install_count = self.directory / "install-count"
        self.cli = self.directory / "keypath-cli"
        self.cli.write_text(textwrap.dedent(f"""\
            #!/bin/zsh
            if [[ "$1 $2" == "system inspect" ]]; then
              operational=false
              [[ -f {str(self.approved)!r} ]] && operational=true
              print '{{"planID":"{PLAN_ID}","snapshotID":"{SNAPSHOT_ID}","isOperational":'$operational'}}'
              exit 0
            fi
            if [[ "$1 $2" == "system install" ]]; then
              count=0
              [[ -f {str(self.install_count)!r} ]] && count=$(cat {str(self.install_count)!r})
              print $((count + 1)) > {str(self.install_count)!r}
              if [[ "${{KEYPATH_TEST_INSTALL_MODE:-waiting}}" == "success" ]]; then
                print '{{"runID":"{RUN_ID}","planID":"{INSTALL_PLAN_ID}","beforeSnapshotID":"{SNAPSHOT_ID}","afterSnapshotID":"{AFTER_ID}","completionState":"completed","userActionRequired":false,"success":true}}'
                exit 0
              fi
              print '{{"runID":"{RUN_ID}","planID":"{INSTALL_PLAN_ID}","beforeSnapshotID":"{SNAPSHOT_ID}","afterSnapshotID":"{AFTER_ID}","completionState":"awaitingApproval","userActionRequired":true,"success":false}}'
              exit 1
            fi
            exit 2
        """))
        self.cli.chmod(0o755)
        self.assert_runtime = self.directory / "assert-runtime"
        self.assert_runtime.write_text(textwrap.dedent(f"""\
            #!/bin/zsh
            [[ -f {str(self.approved)!r} ]] || exit 1
            print 'runtime\tready'
        """))
        self.assert_runtime.chmod(0o755)

    def tearDown(self) -> None:
        self.temporary.cleanup()

    def invoke(self, *, mode: str = "waiting") -> subprocess.CompletedProcess[str]:
        env = {
            **os.environ,
            "KEYPATH_INSTALL_RUNTIME_CLI": str(self.cli),
            "KEYPATH_INSTALL_RUNTIME_ASSERT": str(self.assert_runtime),
            "KEYPATH_TEST_INSTALL_MODE": mode,
        }
        return subprocess.run(
            [str(INSTALL_RUNTIME), "unmanaged-ui"], cwd=self.directory,
            env=env, text=True, capture_output=True,
        )

    def test_waiting_install_is_not_repeated_after_operator_approval(self) -> None:
        first = self.invoke()
        self.assertEqual(first.returncode, 4, first.stderr)
        self.assertIn("install_runtime\twaiting", first.stdout)
        self.assertEqual(self.install_count.read_text().strip(), "1")

        self.approved.touch()
        second = self.invoke()
        self.assertEqual(second.returncode, 0, second.stderr)
        self.assertEqual(self.install_count.read_text().strip(), "1")
        evidence = json.loads((self.directory / ".keypath-lab/scenario-output/install-runtime/assert-state.json").read_text())
        self.assertTrue(evidence["runtimeReady"]["agreement"])
        self.assertEqual(evidence["plan"]["runID"], RUN_ID)

    def test_claimed_success_without_independent_ready_state_is_a_failure(self) -> None:
        result = self.invoke(mode="success")
        self.assertEqual(result.returncode, 1)
        self.assertIn("independent runtime postconditions were absent", result.stderr)
        evidence = json.loads((self.directory / ".keypath-lab/scenario-output/install-runtime/assert-state.json").read_text())
        self.assertFalse(evidence["runtimeReady"]["agreement"])


if __name__ == "__main__":
    unittest.main()
