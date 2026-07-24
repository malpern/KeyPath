#!/usr/bin/env python3
import html
import json
import pathlib
import re
import subprocess
import tempfile
import unittest


LAB_DIR = pathlib.Path(__file__).resolve().parents[1]
REPO_ROOT = LAB_DIR.parents[1]
UPDATER = LAB_DIR / "update-lab-dashboard"
LAB_DASHBOARD = REPO_ROOT / "docs/testing/keypath-lab-state-dashboard.html"


class LabDashboardTests(unittest.TestCase):
    def setUp(self) -> None:
        self.temporary = tempfile.TemporaryDirectory()
        self.state = pathlib.Path(self.temporary.name) / "lab-state.json"

    def tearDown(self) -> None:
        self.temporary.cleanup()

    def update(self, *arguments: str) -> dict:
        subprocess.run(
            [str(UPDATER), "--state", str(self.state), *arguments],
            check=True,
            capture_output=True,
            text=True,
        )
        return json.loads(self.state.read_text())

    def test_run_stage_and_human_handoff_are_recorded(self) -> None:
        state = self.update(
            "--run-id",
            "create-test",
            "--title",
            "Create macOS 15 lease",
            "--status",
            "waiting",
            "--stage",
            "assign",
            "--stage-label",
            "Assign keyboard",
            "--stage-status",
            "waiting",
            "--detail",
            "Choose Kinesis mWave.",
            "--next",
            "Use the Accessory Access menu.",
            "--requires-human",
            "true",
            "--event-tone",
            "waiting",
        )
        self.assertEqual(state["run"]["id"], "create-test")
        self.assertEqual(state["run"]["currentStage"], "assign")
        self.assertTrue(state["run"]["requiresHuman"])
        self.assertEqual(state["run"]["stages"][0]["status"], "waiting")
        self.assertEqual(state["events"][0]["tone"], "waiting")

    def test_snapshot_merge_preserves_run_and_events(self) -> None:
        self.update(
            "--run-id",
            "run-1",
            "--title",
            "Existing run",
            "--stage",
            "boot",
            "--stage-status",
            "active",
        )
        snapshot = pathlib.Path(self.temporary.name) / "snapshot.json"
        snapshot.write_text(
            json.dumps(
                {
                    "host": {
                        "name": "KeyPath lab mini",
                        "connectivity": "online",
                        "console": "unlocked",
                        "keyboard": {"name": "Kinesis mWave", "state": "connected-to-host"},
                    },
                    "leases": [{"id": "cbx_test", "status": "ready"}],
                    "resources": [
                        {
                            "kind": "vm",
                            "id": "vm-test",
                            "state": "ready",
                            "detail": "macOS 15",
                        }
                    ],
                }
            )
        )
        state = self.update("--snapshot", str(snapshot))
        self.assertEqual(state["run"]["id"], "run-1")
        self.assertEqual(state["events"][0]["stage"], "boot")
        self.assertEqual(state["host"]["console"], "unlocked")
        self.assertEqual(state["leases"][0]["id"], "cbx_test")
        self.assertEqual(state["resources"][0]["id"], "vm-test")

    def test_resource_updates_are_upserted(self) -> None:
        self.update("--resource", "vm|vm-test|booting|Waiting for IP")
        state = self.update("--resource", "vm|vm-test|ready|Guest verified")
        self.assertEqual(len(state["resources"]), 1)
        self.assertEqual(state["resources"][0]["state"], "ready")
        self.assertEqual(state["resources"][0]["detail"], "Guest verified")

    def test_all_dashboards_include_three_tab_navigation(self) -> None:
        for filename in (
            "keypath-test-automation-progress.html",
            "keypath-github-issues-dashboard.html",
            "keypath-lab-state-dashboard.html",
        ):
            document = (REPO_ROOT / "docs/testing" / filename).read_text()
            self.assertIn(">Automation lab</a>", document)
            self.assertIn(">GitHub issues</a>", document)
            self.assertIn(">Lab state</a>", document)

    def test_lab_dashboard_embedded_script_parses(self) -> None:
        source = LAB_DASHBOARD.read_text()
        srcdoc = re.search(r'srcdoc="(.*?)">\s*</iframe>', source, re.DOTALL)
        self.assertIsNotNone(srcdoc)
        decoded = html.unescape(srcdoc.group(1))
        scripts = re.findall(r"<script(?:\s[^>]*)?>(.*?)</script>", decoded, re.DOTALL)
        dashboard_script = next(script for script in scripts if "const defaultStages" in script)
        result = subprocess.run(
            ["node", "-e", "new Function(process.argv[1])", dashboard_script],
            capture_output=True,
            text=True,
        )
        self.assertEqual(result.returncode, 0, result.stderr)
        self.assertIn("keypath-lab-state.json", dashboard_script)
        self.assertIn("host.console==='locked'", dashboard_script)

    def test_server_routes_and_refreshes_lab_state(self) -> None:
        server = (LAB_DIR / "progress-dashboard-server.py").read_text()
        self.assertIn('"/docs/testing/keypath-lab-state.json"', server)
        self.assertIn("target=refresh_lab", server)
        self.assertIn('"lab-state"', server)

    def test_console_lock_string_is_parsed_by_value(self) -> None:
        remote = (LAB_DIR / "remote.sh").read_text()
        self.assertIn('r\'"IOConsoleLocked"\\s*=\\s*(Yes|No)\'', remote)
        self.assertIn('console_match.group(1) == "Yes"', remote)


if __name__ == "__main__":
    unittest.main()
