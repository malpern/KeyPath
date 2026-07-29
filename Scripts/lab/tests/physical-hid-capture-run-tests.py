#!/usr/bin/env python3
"""Contract tests for the combined physical HID capture runner."""

from __future__ import annotations

import contextlib
import importlib.machinery
import importlib.util
import io
import json
import pathlib
import tempfile
import unittest
from unittest import mock


ROOT = pathlib.Path(__file__).resolve().parents[3]
RUNNER = ROOT / "Scripts/lab/physical-hid-capture-run"

READY_PREFLIGHT = {
    "canProceed": True,
    "state": "ready",
    "detail": "Resources stable",
    "suggestions": [],
}

TRACE_BATCH = [
    {"runId": "test-run", "from": 0, "available": 2},
    {"sequence": 1, "modifiers": 0, "keys": [4, 0, 0, 0, 0, 0]},
    {"sequence": 2, "modifiers": 0, "keys": [0, 0, 0, 0, 0, 0]},
]


def load_runner():
    loader = importlib.machinery.SourceFileLoader("physical_hid_capture_run", str(RUNNER))
    spec = importlib.util.spec_from_loader(loader.name, loader)
    assert spec is not None
    module = importlib.util.module_from_spec(spec)
    loader.exec_module(module)
    return module


def action(command: list[str]) -> tuple[str, str]:
    if "hid-capture-jig-client" in command[0]:
        return "capture", command[1]
    fixture_actions = {
        "status", "load-script", "arm", "start", "abort", "trace", "present",
    }
    return "fixture", next(value for value in command[1:] if value in fixture_actions)


class PhysicalHIDCaptureRunTests(unittest.TestCase):
    def setUp(self) -> None:
        self.runner = load_runner()

    @staticmethod
    def compile_script(command: list[str], environment: dict[str, str]) -> None:
        del environment
        output = pathlib.Path(command[command.index("--output") + 1])
        output.write_text("KPHID1 test-run 2 1 100000 00000000\n0 0 4 0 0 0 0 0\n50000 0 0 0 0 0 0 0\n")

    def test_capture_preflight_happens_before_fixture_mutation(self) -> None:
        calls: list[tuple[str, str]] = []
        fixture_status_calls = 0
        capture_status_calls = 0
        capture_arm_command: list[str] | None = None

        def fake_run_json(command, environment, allowed_returncodes=(0,)):
            del environment, allowed_returncodes
            nonlocal fixture_status_calls, capture_status_calls, capture_arm_command
            target, operation = action(command)
            calls.append((target, operation))
            if (target, operation) == ("fixture", "trace"):
                return TRACE_BATCH
            if (target, operation) == ("fixture", "status"):
                fixture_status_calls += 1
                if fixture_status_calls == 1:
                    return {"address": "10.0.0.47", "state": "idle"}
                if fixture_status_calls == 2:
                    raise RuntimeError("transient fixture status timeout")
                return {
                    "state": "complete", "reportsSubmitted": 2,
                    "lateReports": 1, "maximumLatenessUs": 2_000,
                }
            if (target, operation) == ("capture", "status"):
                capture_status_calls += 1
                if capture_status_calls > 1:
                    return {"ok": True, "snapshot": {
                        "state": "passed", "received": "a", "pressedKeyCodes": [],
                        "activeModifiers": 0, "issues": [], "events": [{}, {}],
                    }}
                return {
                    "ok": True, "snapshot": {"state": "idle"},
                    "systemReadiness": READY_PREFLIGHT,
                }
            if (target, operation) == ("capture", "arm"):
                capture_arm_command = command
                return {"ok": True}
            if (target, operation) == ("capture", "wait"):
                return {"snapshot": {
                    "state": "passed", "received": "a", "pressedKeyCodes": [],
                    "issues": [], "events": [{}, {}],
                }}
            return {"ok": True}

        with tempfile.TemporaryDirectory() as directory:
            input_path = pathlib.Path(directory) / "input.txt"
            output_path = pathlib.Path(directory) / "result.json"
            input_path.write_text("a")
            arguments = [
                str(RUNNER), "--run-id", "test-run", "--text", str(input_path),
                "--fixture-host", "fixture.local", "--output", str(output_path),
                "--max-late-reports", "2", "--max-lateness-us", "3000",
            ]
            with mock.patch.object(self.runner, "load_fixture_token", return_value="token"), \
                 mock.patch.object(self.runner, "run_json", side_effect=fake_run_json), \
                 mock.patch.object(self.runner, "run_checked", side_effect=self.compile_script), \
                 mock.patch.object(self.runner.sys, "argv", arguments), \
                 contextlib.redirect_stdout(io.StringIO()):
                self.assertEqual(self.runner.main(), 0)

            self.assertLess(calls.index(("capture", "status")), calls.index(("fixture", "load-script")))
            self.assertEqual(
                calls.index(("capture", "focus")) + 1,
                calls.index(("capture", "arm")),
            )
            self.assertIsNotNone(capture_arm_command)
            assert capture_arm_command is not None
            self.assertNotIn("--instruction", capture_arm_command)
            self.assertEqual(capture_arm_command[capture_arm_command.index("--timeout-ms") + 1], "15000")
            artifact = json.loads(output_path.read_text())
            self.assertEqual(artifact["control"]["capturePreflight"]["snapshot"]["state"], "idle")
            self.assertTrue(artifact["checks"]["latenessWithinBudget"])
            self.assertEqual(artifact["timingBudget"]["maxLateReports"], 2)
            self.assertTrue(artifact["controlPlane"]["degraded"])
            self.assertIn("status timeout", artifact["controlPlane"]["errors"][0]["error"])

    def test_busy_capture_preflight_stops_before_fixture_mutation(self) -> None:
        calls: list[tuple[str, str]] = []

        def fake_run_json(command, environment, allowed_returncodes=(0,)):
            del environment, allowed_returncodes
            target, operation = action(command)
            calls.append((target, operation))
            if (target, operation) == ("fixture", "status"):
                return {"address": "10.0.0.47", "state": "idle"}
            if (target, operation) == ("capture", "status"):
                return {
                    "ok": True,
                    "snapshot": {"state": "idle"},
                    "systemReadiness": {
                        "canProceed": False,
                        "detail": "CPU 93% (limit 80%)",
                        "suggestions": ["Pause builds or VMs."],
                    },
                }
            raise AssertionError(f"unexpected mutation: {target} {operation}")

        with tempfile.TemporaryDirectory() as directory:
            input_path = pathlib.Path(directory) / "input.txt"
            output_path = pathlib.Path(directory) / "result.json"
            input_path.write_text("a")
            arguments = [
                str(RUNNER), "--run-id", "busy-run", "--text", str(input_path),
                "--fixture-host", "fixture.local", "--output", str(output_path),
            ]
            error = io.StringIO()
            with mock.patch.object(self.runner, "load_fixture_token", return_value="token"), \
                 mock.patch.object(self.runner, "run_json", side_effect=fake_run_json), \
                 mock.patch.object(self.runner.sys, "argv", arguments), \
                contextlib.redirect_stderr(error):
                self.assertEqual(self.runner.main(), 2)

            artifact = json.loads(output_path.read_text())

        self.assertIn("CPU 93%", error.getvalue())
        self.assertIn("Pause builds or VMs", error.getvalue())
        self.assertEqual(artifact["failure"]["classification"], "host-resource-admission")
        self.assertNotIn(("fixture", "load-script"), calls)
        self.assertNotIn(("fixture", "arm"), calls)

    def test_failed_capture_waits_for_fixture_and_persists_complete_evidence(self) -> None:
        fixture_status_calls = 0
        capture_status_calls = 0

        def fake_run_json(command, environment, allowed_returncodes=(0,)):
            del environment, allowed_returncodes
            nonlocal fixture_status_calls, capture_status_calls
            target, operation = action(command)
            if (target, operation) == ("fixture", "trace"):
                return TRACE_BATCH
            if (target, operation) == ("fixture", "status"):
                fixture_status_calls += 1
                if fixture_status_calls == 1:
                    return {"address": "10.0.0.47", "state": "idle"}
                if fixture_status_calls == 2:
                    return {"state": "running", "reportsSubmitted": 1}
                return {
                    "state": "complete", "reportsSubmitted": 2,
                    "lateReports": 0, "maximumLatenessUs": 0,
                }
            if (target, operation) == ("capture", "status"):
                capture_status_calls += 1
                if capture_status_calls == 1:
                    return {
                        "ok": True, "snapshot": {"state": "idle"},
                        "systemReadiness": READY_PREFLIGHT,
                    }
                return {"ok": True, "snapshot": {
                    "state": "failed", "received": "ab", "pressedKeyCodes": [],
                    "activeModifiers": 0, "issues": ["mismatch"],
                    "events": [{}, {}, {}, {}],
                }}
            if (target, operation) == ("capture", "wait"):
                return {"snapshot": {
                    "state": "failed", "received": "a", "pressedKeyCodes": [],
                    "activeModifiers": 0, "issues": ["mismatch"], "events": [{}, {}],
                }}
            return {"ok": True}

        with tempfile.TemporaryDirectory() as directory:
            input_path = pathlib.Path(directory) / "input.txt"
            output_path = pathlib.Path(directory) / "result.json"
            input_path.write_text("aa")
            arguments = [
                str(RUNNER), "--run-id", "complete-failure", "--text", str(input_path),
                "--fixture-host", "fixture.local", "--output", str(output_path),
            ]
            with mock.patch.object(self.runner, "load_fixture_token", return_value="token"), \
                 mock.patch.object(self.runner, "run_json", side_effect=fake_run_json), \
                 mock.patch.object(self.runner, "run_checked", side_effect=self.compile_script), \
                 mock.patch.object(self.runner.time, "sleep"), \
                 mock.patch.object(self.runner.sys, "argv", arguments), \
                 contextlib.redirect_stdout(io.StringIO()):
                self.assertEqual(self.runner.main(), 1)

            artifact = json.loads(output_path.read_text())
            self.assertEqual(artifact["fixture"]["state"], "complete")
            self.assertEqual(artifact["fixture"]["reportsSubmitted"], 2)
            self.assertEqual(artifact["capture"]["received"], "ab")
            self.assertEqual(len(artifact["capture"]["events"]), 4)
            self.assertEqual(
                artifact["control"]["captureInitialTerminal"]["snapshot"]["received"], "a"
            )
            self.assertTrue(artifact["checks"]["fixtureCompleted"])
            self.assertTrue(artifact["checks"]["allReportsSubmitted"])

    def test_capture_arm_failure_aborts_mutated_fixture(self) -> None:
        calls: list[tuple[str, str]] = []

        def fake_run_json(command, environment, allowed_returncodes=(0,)):
            del environment, allowed_returncodes
            target, operation = action(command)
            calls.append((target, operation))
            if (target, operation) == ("fixture", "status"):
                return {"address": "10.0.0.47", "state": "idle"}
            if (target, operation) == ("capture", "status"):
                return {
                    "ok": True, "snapshot": {"state": "idle"},
                    "systemReadiness": READY_PREFLIGHT,
                }
            if (target, operation) == ("capture", "arm"):
                raise RuntimeError("capture app exited")
            return {"ok": True}

        with tempfile.TemporaryDirectory() as directory:
            input_path = pathlib.Path(directory) / "input.txt"
            output_path = pathlib.Path(directory) / "result.json"
            input_path.write_text("a")
            arguments = [
                str(RUNNER), "--run-id", "test-run", "--text", str(input_path),
                "--fixture-host", "fixture.local", "--output", str(output_path),
            ]
            error = io.StringIO()
            with mock.patch.object(self.runner, "load_fixture_token", return_value="token"), \
                 mock.patch.object(self.runner, "run_json", side_effect=fake_run_json), \
                 mock.patch.object(self.runner, "run_checked", side_effect=self.compile_script), \
                 mock.patch.object(self.runner.sys, "argv", arguments), \
                 contextlib.redirect_stderr(error):
                self.assertEqual(self.runner.main(), 2)

            artifact = json.loads(output_path.read_text())
        self.assertIn(("fixture", "abort"), calls)
        self.assertIn("fixture aborted with all-keys-released queued", artifact["cleanup"])
        self.assertIn("capture-oracle", error.getvalue())

    def test_abort_mode_verifies_released_prefix(self) -> None:
        calls: list[tuple[str, str]] = []
        fixture_status_calls = 0

        def fake_run_json(command, environment, allowed_returncodes=(0,)):
            del environment, allowed_returncodes
            nonlocal fixture_status_calls
            target, operation = action(command)
            calls.append((target, operation))
            if (target, operation) == ("fixture", "trace"):
                return TRACE_BATCH
            if (target, operation) == ("fixture", "status"):
                fixture_status_calls += 1
                if fixture_status_calls == 1:
                    return {"address": "10.0.0.47", "state": "idle"}
                return {
                    "state": "aborted", "reportsSubmitted": 1,
                    "transfersCompleted": 2, "lateReports": 0,
                    "maximumLatenessUs": 0,
                }
            if (target, operation) == ("capture", "status"):
                return {
                    "ok": True, "snapshot": {"state": "idle"},
                    "systemReadiness": READY_PREFLIGHT,
                }
            if (target, operation) == ("capture", "finalize"):
                return {"snapshot": {
                    "state": "failed", "received": "a", "pressedKeyCodes": [],
                    "activeModifiers": 0, "duplicateDownEvents": 0,
                    "repeatEvents": 0, "unmatchedUpEvents": 0,
                    "issues": ["received output differs from expected output"],
                    "events": [{}, {}],
                }}
            return {"ok": True}

        with tempfile.TemporaryDirectory() as directory:
            input_path = pathlib.Path(directory) / "input.txt"
            output_path = pathlib.Path(directory) / "result.json"
            input_path.write_text("aa")
            arguments = [
                str(RUNNER), "--run-id", "abort-run", "--text", str(input_path),
                "--fixture-host", "fixture.local", "--abort-after-ms", "10",
                "--output", str(output_path),
            ]
            with mock.patch.object(self.runner, "load_fixture_token", return_value="token"), \
                 mock.patch.object(self.runner, "run_json", side_effect=fake_run_json), \
                 mock.patch.object(self.runner, "run_checked", side_effect=self.compile_script), \
                 mock.patch.object(self.runner.time, "sleep"), \
                 mock.patch.object(self.runner.sys, "argv", arguments), \
                 contextlib.redirect_stdout(io.StringIO()):
                self.assertEqual(self.runner.main(), 0)

            artifact = json.loads(output_path.read_text())
            self.assertEqual(artifact["status"], "passed")
            self.assertTrue(all(artifact["checks"].values()))
            self.assertIn(("fixture", "abort"), calls)
            self.assertIn(("capture", "finalize"), calls)

    def test_late_report_allowance_requires_a_lateness_ceiling(self) -> None:
        with tempfile.TemporaryDirectory() as directory:
            arguments = [
                str(RUNNER), "--run-id", "invalid-budget", "--text", str(RUNNER),
                "--max-late-reports", "1", "--output",
                str(pathlib.Path(directory) / "result.json"),
            ]
            error = io.StringIO()
            with mock.patch.object(self.runner.sys, "argv", arguments), \
                 contextlib.redirect_stderr(error), contextlib.redirect_stdout(io.StringIO()):
                self.assertEqual(self.runner.main(), 2)
        self.assertIn("--max-lateness-us is required", error.getvalue())

    def test_external_abort_mode_waits_for_physical_abort(self) -> None:
        fixture_status_calls = 0

        def fake_run_json(command, environment, allowed_returncodes=(0,)):
            del environment, allowed_returncodes
            nonlocal fixture_status_calls
            target, operation = action(command)
            if (target, operation) == ("fixture", "trace"):
                return TRACE_BATCH
            if (target, operation) == ("fixture", "status"):
                fixture_status_calls += 1
                if fixture_status_calls == 1:
                    return {"address": "10.0.0.47", "state": "idle"}
                return {"state": "aborted", "reportsSubmitted": 1, "transfersCompleted": 2}
            if (target, operation) == ("capture", "status"):
                return {
                    "ok": True, "snapshot": {"state": "idle"},
                    "systemReadiness": READY_PREFLIGHT,
                }
            if (target, operation) == ("capture", "finalize"):
                return {"snapshot": {
                    "state": "failed", "received": "a", "pressedKeyCodes": [],
                    "activeModifiers": 0, "duplicateDownEvents": 0,
                    "repeatEvents": 0, "unmatchedUpEvents": 0, "issues": [], "events": [],
                }}
            if (target, operation) == ("capture", "arm"):
                self.assertEqual(
                    command[command.index("--instruction") + 1],
                    "PRESS BOOT OR TAP THE SCREEN NOW TO ABORT THE ACTIVE TEST",
                )
            return {"ok": True}

        self._run_interruption_case(
            fake_run_json, ["--expect-external-abort-ms", "100"], "external-abort"
        )

    def test_usb_cycle_mode_waits_for_release_after_remount(self) -> None:
        fixture_status_calls = 0

        def fake_run_json(command, environment, allowed_returncodes=(0,)):
            del environment, allowed_returncodes
            nonlocal fixture_status_calls
            target, operation = action(command)
            if (target, operation) == ("fixture", "trace"):
                return TRACE_BATCH
            if (target, operation) == ("fixture", "status"):
                fixture_status_calls += 1
                if fixture_status_calls == 1:
                    return {"address": "10.0.0.47", "state": "idle"}
                if fixture_status_calls == 2:
                    return {
                        "state": "error", "usbMounted": False,
                        "reportsSubmitted": 1, "transfersCompleted": 1,
                    }
                return {
                    "state": "error", "usbMounted": True,
                    "reportsSubmitted": 1, "transfersCompleted": 2,
                }
            if (target, operation) == ("capture", "status"):
                return {
                    "ok": True, "snapshot": {"state": "idle"},
                    "systemReadiness": READY_PREFLIGHT,
                }
            if (target, operation) == ("capture", "finalize"):
                return {"snapshot": {
                    "state": "failed", "received": "a", "pressedKeyCodes": [],
                    "activeModifiers": 0, "duplicateDownEvents": 0,
                    "repeatEvents": 0, "unmatchedUpEvents": 0, "issues": [], "events": [],
                }}
            if (target, operation) == ("capture", "arm"):
                self.assertEqual(
                    command[command.index("--instruction") + 1],
                    "UNPLUG USB-C NOW · WAIT 2 SECONDS · RECONNECT THE SAME CABLE",
                )
            return {"ok": True}

        self._run_interruption_case(
            fake_run_json, ["--expect-usb-cycle-ms", "100"], "usb-cycle"
        )

    def _run_interruption_case(self, fake_run_json, mode_arguments, expected_mode) -> None:
        with tempfile.TemporaryDirectory() as directory:
            input_path = pathlib.Path(directory) / "input.txt"
            output_path = pathlib.Path(directory) / "result.json"
            input_path.write_text("aa")
            arguments = [
                str(RUNNER), "--run-id", "manual-run", "--text", str(input_path),
                "--fixture-host", "fixture.local", "--output", str(output_path),
                *mode_arguments,
            ]
            with mock.patch.object(self.runner, "load_fixture_token", return_value="token"), \
                 mock.patch.object(self.runner, "run_json", side_effect=fake_run_json), \
                 mock.patch.object(self.runner, "run_checked", side_effect=self.compile_script), \
                 mock.patch.object(self.runner.time, "sleep"), \
                 mock.patch.object(self.runner.sys, "argv", arguments), \
                 contextlib.redirect_stdout(io.StringIO()):
                self.assertEqual(self.runner.main(), 0)
            artifact = json.loads(output_path.read_text())
            self.assertEqual(artifact["status"], "passed")
            self.assertEqual(artifact["interruptionMode"], expected_mode)
            self.assertTrue(all(artifact["checks"].values()))


if __name__ == "__main__":
    unittest.main()
