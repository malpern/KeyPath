#!/usr/bin/env python3

import json
import os
import pathlib
import subprocess
import tempfile
import textwrap
import unittest


ROOT = pathlib.Path(__file__).resolve().parents[3]
RUNNER = ROOT / "Scripts/lab/scenario-matrix-runner"


class MatrixRunnerTests(unittest.TestCase):
    def setUp(self) -> None:
        self.temporary = tempfile.TemporaryDirectory()
        self.directory = pathlib.Path(self.temporary.name)
        self.installer = self.directory / "KeyPath.zip"
        self.installer.write_bytes(b"candidate")
        self.log = self.directory / "lab.log"
        self.lab = self.directory / "keypath-lab"
        self.lab.write_text(textwrap.dedent(f"""\
            #!/bin/zsh
            print -r -- "$*" >> {str(self.log)!r}
            case "$1" in
              create) print 'lease_id\tcbx_test_lease'; print 'manifest\t/tmp/manifest' ;;
              status) print 'status\tready' ;;
              *) print 'ok\t'$1 ;;
            esac
        """))
        self.lab.chmod(0o755)
        self.dashboard_log = self.directory / "dashboard.log"
        self.dashboard = self.directory / "dashboard-updater"
        self.dashboard.write_text(textwrap.dedent(f"""\
            #!/bin/zsh
            print -r -- "$*" >> {str(self.dashboard_log)!r}
        """))
        self.dashboard.chmod(0o755)

    def tearDown(self) -> None:
        self.temporary.cleanup()

    def plan(self, steps: list[str], *, job_id: str = "vm-job") -> pathlib.Path:
        path = self.directory / f"{job_id}.json"
        path.write_text(json.dumps({
            "schemaVersion": 1,
            "cadence": "weekly",
            "summary": {"eligiblePairs": 10},
            "jobs": [{
                "id": job_id, "title": "VM job", "provider": "tart", "macOS": 15,
                "lane": "managed-functional", "automation": "operator", "ttlMinutes": 120,
                "steps": steps, "finalizer": "destroy-owned-lease",
                "factors": {"platform": "macos15", "lane": "managed", "family": "install", "boundary": "fresh", "evidence": "runtime"},
            }],
            "waves": [[job_id]],
            "excluded": [],
        }))
        return path

    def run_runner(self, plan: pathlib.Path, *extra: str) -> subprocess.CompletedProcess[str]:
        return subprocess.run([
            str(RUNNER), "--plan", str(plan), "--state", str(self.directory / "state.json"),
            "--artifacts", str(self.directory / "artifacts"), "--commit", "a" * 40,
            "--installer", str(self.installer), "--lab", str(self.lab), "--repo", str(ROOT),
            "--dashboard-updater", str(self.dashboard), "--dashboard-state", str(self.directory / "dashboard-state.json"),
            *extra,
        ], text=True, capture_output=True)

    def test_executes_steps_updates_dashboard_and_destroys_owned_lease(self) -> None:
        result = self.run_runner(self.plan(["create-fresh-lease", "install-exact-artifact", "artifact-capture"]))
        self.assertEqual(result.returncode, 0, result.stderr)
        state = json.loads((self.directory / "state.json").read_text())
        self.assertEqual(state["status"], "passed")
        self.assertEqual(state["jobs"][0]["status"], "passed")
        self.assertEqual(state["jobs"][0]["cleanupStatus"], "passed")
        lab_log = self.log.read_text()
        self.assertIn("create --macos 15", lab_log)
        self.assertIn("install-runtime cbx_test_lease", lab_log)
        self.assertIn("scenario cbx_test_lease artifact-capture", lab_log)
        self.assertIn("artifacts cbx_test_lease --output", lab_log)
        self.assertIn("destroy cbx_test_lease", lab_log)
        dashboard = self.dashboard_log.read_text()
        self.assertIn("initialize --plan", dashboard)
        self.assertIn("--status running", dashboard)
        self.assertIn("--status passed", dashboard)

    def test_human_checkpoint_waits_without_cleanup_then_resumes(self) -> None:
        plan = self.plan(["create-fresh-lease", "operator-visible-action", "artifact-capture"])
        first = self.run_runner(plan)
        self.assertEqual(first.returncode, 4, first.stderr)
        state = json.loads((self.directory / "state.json").read_text())
        self.assertEqual(state["status"], "waiting")
        self.assertEqual(state["jobs"][0]["waitingCheckpoint"], "vm-job:operator-visible-action")
        self.assertNotIn("destroy", self.log.read_text())

        second = self.run_runner(plan, "--ack-checkpoint", "vm-job:operator-visible-action")
        self.assertEqual(second.returncode, 0, second.stderr)
        state = json.loads((self.directory / "state.json").read_text())
        self.assertEqual(state["jobs"][0]["status"], "passed")
        self.assertIn("destroy cbx_test_lease", self.log.read_text())

    def test_managed_macos15_drives_input_monitoring_then_verifies_runtime(self) -> None:
        marker = self.directory / "approval-requested"
        self.lab.write_text(textwrap.dedent(f"""\
            #!/bin/zsh
            print -r -- "$*" >> {str(self.log)!r}
            case "$1" in
              create) print 'lease_id\tcbx_test_lease'; print 'manifest\t/tmp/manifest' ;;
              status) print 'status\tready' ;;
              install-runtime)
                if [[ ! -f {str(marker)!r} ]]; then
                  touch {str(marker)!r}
                  print 'install_runtime\twaiting'
                  print 'user_action_required\tApprove KeyPath'
                  exit 4
                fi
                print 'install_runtime\tpassed'
                ;;
              *) print 'ok\t'$1 ;;
            esac
        """))
        self.lab.chmod(0o755)
        plan = self.plan(["create-fresh-lease", "install-exact-artifact", "artifact-capture"])

        first = self.run_runner(plan)
        self.assertEqual(first.returncode, 0, first.stderr)
        state = json.loads((self.directory / "state.json").read_text())
        self.assertEqual(state["jobs"][0]["status"], "passed")
        self.assertEqual(state["jobs"][0]["steps"][1]["status"], "passed")
        self.assertEqual(self.log.read_text().count("install-runtime cbx_test_lease"), 2)
        self.assertIn("approve-input-monitoring cbx_test_lease", self.log.read_text())
        self.assertIn("destroy cbx_test_lease", self.log.read_text())

    def test_failed_automatic_input_monitoring_falls_back_to_retained_checkpoint(self) -> None:
        self.lab.write_text(textwrap.dedent(f"""\
            #!/bin/zsh
            print -r -- "$*" >> {str(self.log)!r}
            case "$1" in
              create) print 'lease_id\tcbx_test_lease'; print 'manifest\t/tmp/manifest' ;;
              status) print 'status\tready' ;;
              install-runtime) print 'install_runtime\twaiting'; exit 4 ;;
              approve-input-monitoring) print 'target occluded' >&2; exit 1 ;;
              *) print 'ok\t'$1 ;;
            esac
        """))
        self.lab.chmod(0o755)
        result = self.run_runner(self.plan(["create-fresh-lease", "install-exact-artifact"]))
        self.assertEqual(result.returncode, 4, result.stderr)
        state = json.loads((self.directory / "state.json").read_text())
        self.assertEqual(state["status"], "waiting")
        self.assertEqual(state["jobs"][0]["steps"][1]["status"], "waiting")
        self.assertNotIn("destroy", self.log.read_text())

    def test_refuses_checkpoint_preapproval(self) -> None:
        result = self.run_runner(self.plan(["create-fresh-lease", "operator-visible-action"]),
                          "--ack-checkpoint", "vm-job:operator-visible-action")
        self.assertEqual(result.returncode, 2)
        self.assertIn("not currently waiting", result.stderr)
        self.assertFalse(self.log.exists())

    def test_recovers_created_lease_but_blocks_other_uncertain_mutations(self) -> None:
        plan = self.plan(["create-fresh-lease", "install-exact-artifact"])
        initial = self.run_runner(plan)
        self.assertEqual(initial.returncode, 0, initial.stderr)

        state_path = self.directory / "state.json"
        state = json.loads(state_path.read_text())
        state["status"] = "running"
        state["jobs"][0]["status"] = "running"
        state["jobs"][0]["cleanupStatus"] = "pending"
        state["jobs"][0]["leaseId"] = "cbx_test_lease"
        state["jobs"][0]["steps"][1]["status"] = "running"
        state_path.write_text(json.dumps(state))
        resumed = self.run_runner(plan)
        self.assertEqual(resumed.returncode, 1)
        state = json.loads(state_path.read_text())
        self.assertEqual(state["jobs"][0]["status"], "blocked")
        self.assertIn("refusing to repeat", state["jobs"][0]["blocker"])

    def test_failed_create_adopts_controller_lease_and_cleans_it_up(self) -> None:
        self.lab.write_text(textwrap.dedent(f"""\
            #!/bin/zsh
            print -r -- "$*" >> {str(self.log)!r}
            case "$1" in
              create)
                print 'provisioning provider=tart lease=cbx_failed_create slug=test'
                exit 1
                ;;
              status) print 'status\tmanaged-policy-failed' ;;
              *) print 'ok\t'$1 ;;
            esac
        """))
        self.lab.chmod(0o755)

        result = self.run_runner(self.plan(["create-fresh-lease"]))
        self.assertEqual(result.returncode, 1, result.stderr)
        state = json.loads((self.directory / "state.json").read_text())
        self.assertEqual(state["jobs"][0]["leaseId"], "cbx_failed_create")
        self.assertEqual(state["jobs"][0]["status"], "failed")
        self.assertEqual(state["jobs"][0]["cleanupStatus"], "passed")
        lab_log = self.log.read_text()
        self.assertIn("artifacts cbx_failed_create", lab_log)
        self.assertIn("destroy cbx_failed_create", lab_log)

    def test_rejects_changed_installer_on_resume(self) -> None:
        plan = self.plan(["create-fresh-lease"])
        first = self.run_runner(plan)
        self.assertEqual(first.returncode, 0, first.stderr)
        self.installer.write_bytes(b"different")
        second = self.run_runner(plan)
        self.assertEqual(second.returncode, 2)
        self.assertIn("installer changed", second.stderr)


if __name__ == "__main__":
    unittest.main()
