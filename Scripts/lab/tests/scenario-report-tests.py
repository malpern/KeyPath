#!/usr/bin/env python3
import json
import pathlib
import subprocess
import tempfile
import unittest


TOOL = pathlib.Path(__file__).resolve().parents[1] / "scenario-report"


class ScenarioReportTests(unittest.TestCase):
    def setUp(self) -> None:
        self.temporary = tempfile.TemporaryDirectory()
        self.root = pathlib.Path(self.temporary.name) / "artifacts"
        self.root.mkdir()
        self.output = pathlib.Path(self.temporary.name) / "report.json"

    def tearDown(self) -> None:
        self.temporary.cleanup()

    def write_result(self, directory: str, result: dict) -> pathlib.Path:
        target = self.root / directory
        target.mkdir(parents=True)
        path = target / "result.json"
        path.write_text(json.dumps(result))
        return path

    def invoke(self, check: bool = True) -> subprocess.CompletedProcess[str]:
        return subprocess.run(
            [str(TOOL), "--input", str(self.root), "--output", str(self.output)],
            capture_output=True, text=True, check=check,
        )

    def test_aggregates_results_and_sanitized_evidence_links(self) -> None:
        passed = {
            "schemaVersion": 1, "scenario": "clean-install", "status": "passed",
            "summary": "Install reached its postcondition.", "evidence": ["inspect.json"],
        }
        failed = {
            "schemaVersion": 1, "scenario": "repair", "status": "failed",
            "summary": "Runtime postcondition was absent.", "evidence": ["logs/tcp.json"],
            "failure": {"classification": "keypath-product-failure", "step": "verify", "message": "raw detail omitted"},
        }
        self.write_result("b", failed)
        self.write_result("a", passed)
        (self.root / "a/inspect.json").write_text("{}")
        (self.root / "b/logs").mkdir()
        (self.root / "b/logs/tcp.json").write_text("{}")

        self.invoke()
        report = json.loads(self.output.read_text())
        self.assertEqual(report["summary"]["total"], 2)
        self.assertEqual(report["summary"]["statuses"], {"passed": 1, "failed": 1, "blocked": 0})
        self.assertEqual(report["summary"]["failureClassifications"], {"keypath-product-failure": 1})
        self.assertEqual([entry["scenario"] for entry in report["results"]], ["clean-install", "repair"])
        self.assertEqual(report["results"][0]["evidence"], [{"path": "a/inspect.json", "exists": True}])
        self.assertNotIn("message", report["results"][1]["failure"])

    def test_reports_missing_relative_evidence_without_inventing_success(self) -> None:
        self.write_result("run", {
            "schemaVersion": 1, "scenario": "selector", "status": "passed",
            "summary": "Selector resolved.", "evidence": ["snapshot.json"],
        })
        self.invoke()
        report = json.loads(self.output.read_text())
        self.assertEqual(report["results"][0]["evidence"], [{"path": "run/snapshot.json", "exists": False}])

    def test_rejects_evidence_path_traversal(self) -> None:
        self.write_result("run", {
            "schemaVersion": 1, "scenario": "selector", "status": "passed",
            "summary": "Unsafe fixture.", "evidence": ["../secret.txt"],
        })
        result = self.invoke(check=False)
        self.assertEqual(result.returncode, 2)
        self.assertIn("artifact-relative", result.stderr)
        self.assertFalse(self.output.exists())

    def test_rejects_unclassified_non_passing_result(self) -> None:
        self.write_result("run", {
            "schemaVersion": 1, "scenario": "selector", "status": "blocked",
            "summary": "Missing prerequisite.", "evidence": [],
        })
        result = self.invoke(check=False)
        self.assertEqual(result.returncode, 2)
        self.assertIn("no classified failure", result.stderr)

    def test_rejects_result_symlink(self) -> None:
        outside = pathlib.Path(self.temporary.name) / "outside.json"
        outside.write_text(json.dumps({
            "schemaVersion": 1, "scenario": "outside", "status": "passed",
            "summary": "Outside artifact.", "evidence": [],
        }))
        run = self.root / "run"
        run.mkdir()
        (run / "result.json").symlink_to(outside)
        result = self.invoke(check=False)
        self.assertEqual(result.returncode, 2)
        self.assertIn("must not be a symlink", result.stderr)


if __name__ == "__main__":
    unittest.main()
