#!/usr/bin/env python3
import json
import pathlib
import subprocess
import tempfile
import unittest


UPDATER = pathlib.Path(__file__).resolve().parents[1] / "update-progress-dashboard"


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


if __name__ == "__main__":
    unittest.main()
