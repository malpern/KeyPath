#!/usr/bin/env python3
"""Contract tests for the strict repeat/duplicate physical-HID matrix."""

from __future__ import annotations

import importlib.machinery
import importlib.util
import json
import pathlib
import subprocess
import tempfile
import unittest
from unittest import mock


ROOT = pathlib.Path(__file__).resolve().parents[3]
SCRIPT = ROOT / "Scripts/lab/physical-hid-repeat-matrix"
LOADER = importlib.machinery.SourceFileLoader("physical_hid_repeat_matrix", str(SCRIPT))
SPEC = importlib.util.spec_from_loader(LOADER.name, LOADER)
assert SPEC and SPEC.loader
MODULE = importlib.util.module_from_spec(SPEC)
SPEC.loader.exec_module(MODULE)


def artifact(expected: str, received: str, *, focused: bool = True) -> dict:
    return {
        "runID": "case",
        "status": "passed" if expected == received else "failed",
        "admissionMode": "strict",
        "fixture": {"state": "complete", "lateReports": 0, "maximumLatenessUs": 0},
        "capture": {
            "expected": expected,
            "received": received,
            "focused": focused,
            "pressedKeyCodes": [],
            "activeModifiers": 0,
            "duplicateDownEvents": 0,
            "repeatEvents": 0,
            "unmatchedUpEvents": 0,
        },
    }


class PhysicalHIDRepeatMatrixTests(unittest.TestCase):
    def test_case_run_ids_fit_firmware_limit_and_keep_profile_identity(self) -> None:
        prefix = "repeat-matrix-with-an-extremely-long-human-readable-campaign-name"
        identifiers = {
            MODULE.case_run_id(prefix, "alternating", 5, workers, swift)
            for workers, swift in ((0, False), (2, False), (0, True), (2, True))
        }
        self.assertEqual(len(identifiers), 4)
        self.assertTrue(all(len(identifier) <= 48 for identifier in identifiers))

    def test_campaign_requires_explicit_exclusive_desktop_confirmation(self) -> None:
        with mock.patch.object(MODULE.sys, "argv", [str(SCRIPT)]):
            self.assertEqual(MODULE.main(), 2)

    def test_analysis_distinguishes_additions_deletions_and_substitutions(self) -> None:
        added = MODULE.analyze_artifact(artifact("abcd", "abbcd"))
        deleted = MODULE.analyze_artifact(artifact("abcd", "acd"))
        substituted = MODULE.analyze_artifact(artifact("abcd", "abXd"))

        self.assertEqual(added["addedCharacters"], 1)
        self.assertEqual(deleted["deletedCharacters"], 1)
        self.assertEqual(substituted["substitutedCharacters"], 1)

    def test_classification_calls_added_output_a_repeated_input_observation(self) -> None:
        case = MODULE.analyze_artifact(artifact("abcd", "abbcd"))
        self.assertEqual(MODULE.classify([case]), "repeated-input-observed")

    def test_classification_fails_closed_when_focus_is_lost(self) -> None:
        case = MODULE.analyze_artifact(artifact("abcd", "abcd", focused=False))
        self.assertEqual(MODULE.classify([case]), "harness-invalid")

    def test_campaign_uses_strict_runner_and_load_budget_only_for_loaded_case(self) -> None:
        commands: list[list[str]] = []

        def fake_run(command, text=True, capture_output=True):
            del text, capture_output
            commands.append(command)
            if command[-1] == "status":
                return subprocess.CompletedProcess(
                    command, 0,
                    stdout=json.dumps({
                        "systemReadiness": {"canProceed": True, "detail": "stable"}
                    }),
                    stderr="",
                )
            output = pathlib.Path(command[command.index("--output") + 1])
            corpus = pathlib.Path(command[command.index("--text") + 1]).read_text()
            repeat = int(command[command.index("--repeat") + 1])
            output.write_text(json.dumps(artifact(corpus * repeat, corpus * repeat)))
            return subprocess.CompletedProcess(command, 0, stdout="{}", stderr="")

        with tempfile.TemporaryDirectory() as directory:
            root = pathlib.Path(directory)
            corpus = root / "corpus.txt"
            corpus.write_text("aaaa")
            output = root / "output"
            arguments = [
                str(SCRIPT), "--run-id-prefix", "test", "--interval-values", "10",
                "--cpu-worker-values", "0,2", "--hold-ms", "2", "--repeat", "1",
                "--readiness-timeout-seconds", "0", "--output-directory", str(output),
                "--exclusive-desktop-confirmed",
            ]
            with mock.patch.object(MODULE, "DEFAULT_CORPORA", [("single", corpus)]), \
                 mock.patch.object(MODULE, "ensure_jig_running", return_value=(True, "ready")), \
                 mock.patch.object(MODULE.subprocess, "run", side_effect=fake_run), \
                 mock.patch.object(MODULE.sys, "argv", arguments):
                self.assertEqual(MODULE.main(), 0)

            runner_commands = [command for command in commands if "--output" in command]
            self.assertEqual(len(runner_commands), 4)
            calm = next(command for command in runner_commands if (
                command[command.index("--cpu-load-workers") + 1] == "0" and
                "--swift-compile-load" not in command
            ))
            loaded = next(command for command in runner_commands if (
                command[command.index("--cpu-load-workers") + 1] == "2" and
                "--swift-compile-load" not in command
            ))
            swift = next(command for command in runner_commands if (
                command[command.index("--cpu-load-workers") + 1] == "0" and
                "--swift-compile-load" in command
            ))
            self.assertNotIn("--demo-mode", calm)
            self.assertNotIn("--max-late-reports", calm)
            self.assertIn("--max-late-reports", loaded)
            self.assertEqual(loaded[loaded.index("--max-late-reports") + 1], "5")
            self.assertIn("--max-late-reports", swift)
            summary = json.loads((output / "summary.json").read_text())
            self.assertEqual(summary["classification"], "exact-output-observed")
            self.assertEqual(summary["completedCases"], 4)


if __name__ == "__main__":
    unittest.main()
