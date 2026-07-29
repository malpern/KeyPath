#!/usr/bin/env python3

import importlib.machinery
import importlib.util
import pathlib
import subprocess
import unittest
from unittest import mock


ROOT = pathlib.Path(__file__).resolve().parents[3]
SCRIPT = ROOT / "Scripts/lab/physical-hid-shift-matrix"
LOADER = importlib.machinery.SourceFileLoader("physical_hid_shift_matrix", str(SCRIPT))
SPEC = importlib.util.spec_from_loader(LOADER.name, LOADER)
assert SPEC and SPEC.loader
MODULE = importlib.util.module_from_spec(SPEC)
SPEC.loader.exec_module(MODULE)


class ShiftMatrixTests(unittest.TestCase):
    def artifact(self, expected="A!", received="a1", focused=True):
        return {
            "runID": "case",
            "status": "failed",
            "modifierTiming": {"shiftLeadMs": 0, "keyHoldMs": 8, "shiftReleaseLagMs": 0},
            "fixture": {"lateReports": 0, "maximumLatenessUs": 0},
            "fixtureTrace": [{"sequence": 1}, {"sequence": 2}],
            "capture": {
                "expected": expected, "received": received, "focused": focused,
                "pressedKeyCodes": [], "activeModifiers": 0,
            },
        }

    def test_analysis_counts_shift_demotions(self):
        case = MODULE.analyze_artifact(self.artifact())
        self.assertEqual(case["wrongCharacters"], 2)
        self.assertEqual(case["shiftDemotions"], 2)
        self.assertEqual(case["fixtureTraceReports"], 2)

    def test_classification_finds_timing_sensitive_exact_case(self):
        baseline = MODULE.analyze_artifact(self.artifact())
        improved_artifact = self.artifact(expected="A!", received="A!")
        improved_artifact["modifierTiming"]["shiftLeadMs"] = 4
        improved = MODULE.analyze_artifact(improved_artifact)
        self.assertEqual(MODULE.classify([baseline, improved]), "modifier-timing-sensitive")

    def test_classification_fails_closed_on_focus_loss(self):
        invalid = MODULE.analyze_artifact(self.artifact(focused=False))
        self.assertEqual(MODULE.classify([invalid]), "harness-invalid")

    def test_ready_jig_is_reused_without_focus_or_reopen(self):
        responses = [subprocess.CompletedProcess([], 0, stdout="{}", stderr="")]
        with mock.patch.object(MODULE.subprocess, "run", side_effect=responses) as run:
            ready, _ = MODULE.ensure_jig_running()
        self.assertTrue(ready)
        self.assertEqual(len(run.call_args_list), 1)
        self.assertEqual(run.call_args_list[0].args[0][-1], "status")

    def test_missing_jig_is_opened(self):
        responses = [
            subprocess.CompletedProcess([], 2, stdout="", stderr="not running"),
            subprocess.CompletedProcess([], 0, stdout='{"snapshot":{"focused":true}}', stderr=""),
        ]
        with mock.patch.object(MODULE.subprocess, "run", side_effect=responses) as run:
            ready, _ = MODULE.ensure_jig_running()
        self.assertTrue(ready)
        self.assertEqual(run.call_args_list[1].args[0][-1], "open")

    def test_readiness_wait_does_not_request_focus(self):
        response = subprocess.CompletedProcess(
            [], 0, stdout='{"systemReadiness":{"canProceed":true,"detail":"stable"}}', stderr=""
        )
        with mock.patch.object(MODULE.subprocess, "run", return_value=response) as run:
            ready, detail = MODULE.wait_for_jig_readiness(0)
        self.assertTrue(ready)
        self.assertEqual(detail, "stable")
        self.assertEqual(run.call_args.args[0][-1], "status")

    def test_readiness_wait_times_out_closed(self):
        response = subprocess.CompletedProcess(
            [], 0,
            stdout='{"systemReadiness":{"canProceed":false,"detail":"memory pressure"}}',
            stderr="",
        )
        with mock.patch.object(MODULE.subprocess, "run", return_value=response):
            ready, detail = MODULE.wait_for_jig_readiness(0)
        self.assertFalse(ready)
        self.assertEqual(detail, "memory pressure")


if __name__ == "__main__":
    unittest.main()
