#!/usr/bin/env python3

import importlib.machinery
import importlib.util
import json
import pathlib
import subprocess
import tempfile
import unittest


ROOT = pathlib.Path(__file__).resolve().parents[3]
SCRIPT = ROOT / "Scripts/lab/scenario-matrix"
CATALOG = ROOT / "Scripts/lab/scenarios/matrix-catalog.json"


loader = importlib.machinery.SourceFileLoader("scenario_matrix", str(SCRIPT))
spec = importlib.util.spec_from_loader(loader.name, loader)
matrix = importlib.util.module_from_spec(spec)
loader.exec_module(matrix)


class ScenarioMatrixTests(unittest.TestCase):
    def run_plan(self, *arguments: str) -> dict:
        result = subprocess.run(
            [str(SCRIPT), *arguments], text=True, capture_output=True, check=True
        )
        return json.loads(result.stdout)

    def test_nightly_is_unattended_and_requires_cleanup(self):
        plan = self.run_plan("--cadence", "nightly")
        self.assertGreaterEqual(plan["summary"]["jobs"], 2)
        self.assertTrue(all(job["automation"] == "unattended" for job in plan["jobs"]))
        self.assertTrue(all(
            job["provider"] == "local" or job["finalizer"] == "destroy-owned-lease"
            for job in plan["jobs"]
        ))
        excluded = {entry["id"] for entry in plan["excluded"]}
        self.assertIn("macos15-clean-install", excluded)
        self.assertIn("macos15-repair", excluded)
        self.assertIn("macos26-selectors", excluded)
        self.assertIn("macos15-cancellation-recovery", excluded)
        self.assertIn("macos15-physical-remap", excluded)

    def test_weekly_plan_covers_every_eligible_pair(self):
        plan = self.run_plan("--cadence", "weekly")
        self.assertTrue(plan["summary"]["pairwiseComplete"])
        self.assertEqual(
            plan["summary"]["pairwisePairsCovered"], plan["summary"]["eligiblePairs"]
        )

    def test_operator_and_physical_cases_require_separate_opt_in(self):
        operator = self.run_plan("--cadence", "weekly", "--include-operator")
        operator_ids = {job["id"] for job in operator["jobs"]}
        self.assertIn("macos15-cancellation-recovery", operator_ids)
        self.assertNotIn("macos15-physical-remap", operator_ids)

        physical = self.run_plan("--cadence", "weekly", "--include-physical")
        physical_ids = {job["id"] for job in physical["jobs"]}
        self.assertIn("macos15-physical-remap", physical_ids)
        self.assertNotIn("macos15-cancellation-recovery", physical_ids)

    def test_ttl_rejects_a_plan_before_any_lease_can_start(self):
        result = subprocess.run(
            [str(SCRIPT), "--cadence", "nightly", "--ttl-minutes", "20"],
            text=True, capture_output=True,
        )
        self.assertEqual(result.returncode, 2)
        self.assertIn("lease TTL 20m is too short", result.stderr)

    def test_shared_identity_cases_are_serialized_even_with_capacity(self):
        cases = [
            {
                "id": "a", "provider": "parallels", "identityScope": "shared",
            },
            {
                "id": "b", "provider": "parallels", "identityScope": "shared",
            },
        ]
        self.assertEqual(matrix.schedule(cases, {"tart": 1, "parallels": 2}), [["a"], ["b"]])

    def test_plan_is_deterministic_except_timestamp(self):
        first = self.run_plan("--cadence", "weekly")
        second = self.run_plan("--cadence", "weekly")
        first.pop("generatedAt")
        second.pop("generatedAt")
        self.assertEqual(first, second)

    def test_invalid_catalog_without_cleanup_fails_closed(self):
        catalog = json.loads(CATALOG.read_text())
        catalog["cases"][1].pop("cleanup")
        with tempfile.TemporaryDirectory() as directory:
            path = pathlib.Path(directory) / "catalog.json"
            path.write_text(json.dumps(catalog))
            result = subprocess.run(
                [str(SCRIPT), "--catalog", str(path), "--cadence", "nightly"],
                text=True, capture_output=True,
            )
        self.assertEqual(result.returncode, 2)
        self.assertIn("require destroy-owned-lease cleanup", result.stderr)


if __name__ == "__main__":
    unittest.main()
