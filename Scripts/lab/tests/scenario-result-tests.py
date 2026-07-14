#!/usr/bin/env python3
import json
import pathlib
import subprocess
import tempfile
import unittest


TOOL = pathlib.Path(__file__).resolve().parents[1] / "scenario-result"


class ScenarioResultTests(unittest.TestCase):
    def setUp(self) -> None:
        self.temporary = tempfile.TemporaryDirectory()
        self.output = pathlib.Path(self.temporary.name) / "result.json"

    def tearDown(self) -> None:
        self.temporary.cleanup()

    def run_tool(self, *arguments: str, check: bool = True) -> subprocess.CompletedProcess[str]:
        return subprocess.run([str(TOOL), *arguments], check=check, capture_output=True, text=True)

    def test_records_a_product_failure_with_evidence(self) -> None:
        self.run_tool(
            "record", "--output", str(self.output), "--scenario", "repair-reinstall",
            "--status", "failed", "--summary", "Repair reported success without TCP readiness.",
            "--classification", "keypath-product-failure", "--step", "postcondition",
            "--evidence", "system-inspect.json", "--evidence", "tcp-readiness.json",
        )
        result = json.loads(self.output.read_text())
        self.assertEqual(result["failure"]["classification"], "keypath-product-failure")
        self.assertEqual(result["evidence"], ["system-inspect.json", "tcp-readiness.json"])

    def test_selector_self_test_is_never_a_product_failure(self) -> None:
        self.run_tool("selector-self-test", "--output", str(self.output))
        result = json.loads(self.output.read_text())
        self.assertEqual(result["status"], "failed")
        self.assertEqual(result["failure"]["classification"], "harness-selector-failure")

    def test_rejects_unclassified_failure(self) -> None:
        result = self.run_tool(
            "record", "--output", str(self.output), "--scenario", "repair-reinstall",
            "--status", "failed", "--summary", "Unknown failure.", "--step", "repair",
            check=False,
        )
        self.assertNotEqual(result.returncode, 0)
        self.assertIn("requires --classification", result.stderr)


if __name__ == "__main__":
    unittest.main()
