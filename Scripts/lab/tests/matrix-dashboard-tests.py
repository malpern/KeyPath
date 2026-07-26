#!/usr/bin/env python3

import html
import json
import pathlib
import re
import subprocess
import tempfile
import unittest


LAB_DIR = pathlib.Path(__file__).resolve().parents[1]
ROOT = LAB_DIR.parents[1]
UPDATER = LAB_DIR / "update-matrix-dashboard"
MATRIX_PAGE = ROOT / "docs/testing/keypath-matrix-dashboard.html"
class MatrixDashboardTests(unittest.TestCase):
    def setUp(self) -> None:
        self.temporary = tempfile.TemporaryDirectory()
        self.root = pathlib.Path(self.temporary.name)
        self.state = self.root / "matrix.json"
        def case(case_id: str, provider: str, platform: str, steps: list[str]) -> dict:
            return {
                "id": case_id, "title": case_id.replace("-", " ").title(),
                "provider": provider, "macOS": int(platform) if platform else None,
                "automation": "unattended" if provider == "local" else "operator",
                "estimatedMinutes": 5, "steps": steps,
                "factors": {
                    "platform": platform or "local", "lane": "managed" if platform else "none",
                    "family": case_id, "boundary": "fresh", "evidence": "report",
                },
            }
        selected = [
            case("local-contracts", "local", "", ["run-lab-contract-tests"]),
            case("macos15-clean-install", "tart", "15", ["create-fresh-lease", "install-exact-artifact"]),
            case("macos26-upgrade", "parallels", "26", ["create-fresh-lease-with-fixture", "install-fixture"]),
        ]
        self.plan = self.root / "plan.json"
        self.plan.write_text(json.dumps({
            "schemaVersion": 1,
            "cadence": "weekly",
            "summary": {"eligiblePairs": 30},
            "waves": [[case["id"] for case in selected]],
            "jobs": selected,
            "excluded": [],
        }))

    def tearDown(self) -> None:
        self.temporary.cleanup()

    def update(self, *arguments: str) -> dict:
        subprocess.run(
            [str(UPDATER), "--state", str(self.state), *arguments],
            check=True, capture_output=True, text=True,
        )
        return json.loads(self.state.read_text())

    def test_initialize_is_explicitly_idle(self) -> None:
        state = self.update("initialize", "--plan", str(self.plan), "--campaign-id", "campaign-test")
        self.assertEqual(state["campaign"]["status"], "idle")
        self.assertEqual(state["campaign"]["completedJobs"], 0)
        self.assertEqual(state["campaign"]["pairsCovered"], 0)
        self.assertTrue(all(job["status"] == "queued" for job in state["jobs"]))

    def test_live_job_update_recomputes_wave_and_pair_progress(self) -> None:
        self.update("initialize", "--plan", str(self.plan), "--campaign-id", "campaign-test")
        state = self.update(
            "job", "--id", "local-contracts", "--status", "running", "--progress", "34",
            "--step", "run-lab-contract-tests", "--step-status", "running",
            "--message", "Contract tests are running.", "--event-title", "Local contracts started",
        )
        self.assertEqual(state["waves"][0]["status"], "running")
        self.assertEqual(state["jobs"][0]["currentStep"], "Run lab contracts")
        state = self.update(
            "job", "--id", "local-contracts", "--status", "passed", "--progress", "100",
            "--step", "run-lab-contract-tests", "--step-status", "passed",
        )
        self.assertEqual(state["campaign"]["completedJobs"], 1)
        self.assertEqual(state["campaign"]["pairsCovered"], 10)

    def test_duplicate_catalog_steps_receive_stable_ids(self) -> None:
        case = {
            "id": "macos15-uninstall-reinstall", "title": "Uninstall and reinstall",
            "provider": "tart", "macOS": 15, "automation": "operator", "estimatedMinutes": 5,
            "steps": ["create-fresh-lease", "install-exact-artifact", "uninstall", "install-exact-artifact", "reinstall"],
            "factors": {"platform": "macos15", "lane": "managed", "family": "lifecycle", "boundary": "uninstall", "evidence": "runtime"},
        }
        self.plan.write_text(json.dumps({
            "schemaVersion": 1, "cadence": "weekly", "summary": {"eligiblePairs": 10},
            "waves": [[case["id"]]], "jobs": [case], "excluded": [],
        }))
        state = self.update("initialize", "--plan", str(self.plan), "--campaign-id", "campaign-test")
        ids = [step["id"] for step in state["jobs"][0]["steps"]]
        self.assertIn("install-exact-artifact", ids)
        self.assertIn("install-exact-artifact-2", ids)

    def test_rendered_script_parses_and_polls_live_state(self) -> None:
        source = MATRIX_PAGE.read_text()
        srcdoc = re.search(r'srcdoc="(.*?)">\s*</iframe>', source, re.DOTALL)
        self.assertIsNotNone(srcdoc)
        decoded = html.unescape(srcdoc.group(1))
        scripts = re.findall(r"<script(?:\s[^>]*)?>(.*?)</script>", decoded, re.DOTALL)
        dashboard = next(script for script in scripts if "keypath-matrix-state.json" in script)
        result = subprocess.run(["node", "-e", "new Function(process.argv[1])", dashboard], capture_output=True, text=True)
        self.assertEqual(result.returncode, 0, result.stderr)
        self.assertIn("setInterval(refresh,1000)", dashboard)
        self.assertNotIn("innerHTML", dashboard)

    def test_server_exposes_matrix_runtime_state(self) -> None:
        server = (LAB_DIR / "progress-dashboard-server.py").read_text()
        self.assertIn('"/docs/testing/keypath-matrix-state.json"', server)
        self.assertIn("matrix_seed", server)


if __name__ == "__main__":
    unittest.main()
