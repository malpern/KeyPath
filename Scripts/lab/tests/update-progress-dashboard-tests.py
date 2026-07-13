#!/usr/bin/env python3
import html
import json
import pathlib
import re
import subprocess
import tempfile
import unittest


UPDATER = pathlib.Path(__file__).resolve().parents[1] / "update-progress-dashboard"
REPO_ROOT = UPDATER.parents[2]
DASHBOARD = REPO_ROOT / "docs/testing/keypath-test-automation-progress.html"


class UpdateProgressDashboardTests(unittest.TestCase):
    def setUp(self) -> None:
        self.temporary = tempfile.TemporaryDirectory()
        self.state = pathlib.Path(self.temporary.name) / "state.json"
        self.state.write_text('{"activeWork": {}, "workingBlocks": [], "statuses": {}, "updates": []}\n')

    def tearDown(self) -> None:
        self.temporary.cleanup()

    def run_updater(self, *arguments: str, check: bool = True) -> subprocess.CompletedProcess[str]:
        return subprocess.run(
            [str(UPDATER), "--state", str(self.state), "--block", "P01", "--title", "Test", "--message", "Test", *arguments],
            check=check,
            capture_output=True,
            text=True,
        )

    def test_records_and_preserves_blocker_metadata(self) -> None:
        self.run_updater(
            "--progress", "40",
            "--next-task", "Prove input|active|25",
            "--blocker", "Synthetic input is not trusted",
            "--core-capability",
            "--unlocks", "Scenario matrix",
        )
        work = json.loads(self.state.read_text())["activeWork"]["P01"]
        self.assertEqual(work["nextTasks"], [{"label": "Prove input", "status": "active", "progress": 25}])
        self.assertEqual(work["blocker"], "Synthetic input is not trusted")
        self.assertTrue(work["coreCapability"])
        self.assertEqual(work["unlocks"], ["Scenario matrix"])

        self.run_updater("--progress", "50")
        preserved = json.loads(self.state.read_text())["activeWork"]["P01"]
        self.assertEqual(preserved["nextTasks"], work["nextTasks"])
        self.assertEqual(preserved["blocker"], work["blocker"])
        self.assertEqual(preserved["unlocks"], work["unlocks"])

    def test_rejects_invalid_task_status(self) -> None:
        result = self.run_updater("--next-task", "Bad task|unknown|10", check=False)
        self.assertNotEqual(result.returncode, 0)
        self.assertIn("STATUS queued, active, done, or blocked", result.stderr)

    def test_finish_marks_block_proven_and_stops_pulsing(self) -> None:
        self.run_updater("--progress", "80")
        self.run_updater("--finish")
        state = json.loads(self.state.read_text())
        self.assertEqual(state["statuses"]["P01"], "proven")
        self.assertNotIn("P01", state["activeWork"])
        self.assertNotIn("P01", state["workingBlocks"])

    def test_embedded_dashboard_script_parses_after_srcdoc_decoding(self) -> None:
        source = DASHBOARD.read_text()
        srcdoc = re.search(r'srcdoc="(.*?)">\s*</iframe>', source, re.DOTALL)
        self.assertIsNotNone(srcdoc)
        decoded = html.unescape(srcdoc.group(1))
        scripts = re.findall(r"<script(?:\s[^>]*)?>(.*?)</script>", decoded, re.DOTALL)
        dashboard_script = next(script for script in scripts if "const items = [" in script)
        result = subprocess.run(
            ["node", "-e", "new Function(process.argv[1])", dashboard_script],
            capture_output=True,
            text=True,
        )
        self.assertEqual(result.returncode, 0, result.stderr)
        self.assertIn("window.parent.location.href", dashboard_script)


if __name__ == "__main__":
    unittest.main()
