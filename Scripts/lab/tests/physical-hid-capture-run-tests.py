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
SHOWROOM_TEXT = ROOT / "Scripts/lab/tests/fixtures/showroom-demo.txt"

READY_PREFLIGHT = {
    "canProceed": True,
    "state": "ready",
    "detail": "Resources stable",
    "suggestions": [],
}

BUSY_PREFLIGHT = {
    "canProceed": False,
    "state": "waiting",
    "detail": "CPU 93% (limit 80%)",
    "suggestions": ["Pause builds or VMs."],
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
        "status", "load-script", "arm", "start", "abort", "trace", "trace-all", "present",
    }
    return "fixture", next(value for value in command[1:] if value in fixture_actions)


class PhysicalHIDCaptureRunTests(unittest.TestCase):
    def setUp(self) -> None:
        self.runner = load_runner()

    def test_showroom_payload_is_short_fixed_and_return_terminated(self) -> None:
        self.assertEqual(SHOWROOM_TEXT.read_bytes(), b"KeyPath demo OK\n")

    def test_presentation_brand_defaults_to_keypath_and_accepts_bear(self) -> None:
        required = ["--run-id", "brand-test", "--text", str(RUNNER)]
        self.assertEqual(self.runner.parser().parse_args(required).brand, "keypath")
        self.assertEqual(
            self.runner.parser().parse_args([*required, "--brand", "bear"]).brand,
            "bear",
        )

    @staticmethod
    def compile_script(command: list[str], environment: dict[str, str]) -> None:
        del environment
        output = pathlib.Path(command[command.index("--output") + 1])
        output.write_text("KPHID1 test-run 2 1 100000 00000000\n0 0 4 0 0 0 0 0\n50000 0 0 0 0 0 0 0\n")

    def test_demo_mode_records_busy_preflight_then_runs_with_explicit_bypass(self) -> None:
        calls: list[tuple[str, str]] = []
        fixture_status_calls = 0
        capture_status_calls = 0
        capture_arm_command: list[str] | None = None
        presentation_commands: list[list[str]] = []

        def fake_run_json(command, environment, allowed_returncodes=(0,)):
            del environment, allowed_returncodes
            nonlocal fixture_status_calls, capture_status_calls, capture_arm_command
            target, operation = action(command)
            calls.append((target, operation))
            if (target, operation) == ("fixture", "present"):
                presentation_commands.append(command)
            if (target, operation) == ("fixture", "trace-all"):
                return TRACE_BATCH[1:]
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
                    "systemReadiness": BUSY_PREFLIGHT,
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
                "--demo-mode",
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
            self.assertIn("--demo-mode", capture_arm_command)
            self.assertNotIn("--instruction", capture_arm_command)
            self.assertEqual(capture_arm_command[capture_arm_command.index("--timeout-ms") + 1], "90000")
            self.assertEqual(len(presentation_commands), 2)
            self.assertTrue(all(
                command[command.index("--brand") + 1] == "keypath"
                for command in presentation_commands
            ))
            artifact = json.loads(output_path.read_text())
            self.assertEqual(artifact["admissionMode"], "demo-bypass")
            self.assertEqual(artifact["presentationBrand"], "keypath")
            self.assertFalse(artifact["control"]["capturePreflight"]["systemReadiness"]["canProceed"])
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
        self.assertEqual(artifact["admissionMode"], "strict")
        self.assertEqual(artifact["failure"]["classification"], "host-resource-admission")
        self.assertNotIn(("fixture", "load-script"), calls)
        self.assertNotIn(("fixture", "arm"), calls)

    def test_swift_compile_load_starts_after_confirmed_fixture_schedule_and_is_recorded(self) -> None:
        timeline: list[tuple[str, str]] = []
        fixture_status_calls = 0
        capture_status_calls = 0

        def snapshot():
            return {
                "state": "passed", "received": "a", "focused": True,
                "pressedKeyCodes": [], "activeModifiers": 0, "issues": [],
                "events": [{}, {}],
            }

        def fake_run_json(command, environment, allowed_returncodes=(0,)):
            del environment, allowed_returncodes
            nonlocal fixture_status_calls, capture_status_calls
            target, operation = action(command)
            timeline.append((target, operation))
            if (target, operation) == ("fixture", "trace-all"):
                return TRACE_BATCH[1:]
            if (target, operation) == ("fixture", "status"):
                fixture_status_calls += 1
                if fixture_status_calls == 1:
                    return {"address": "10.0.0.47", "state": "idle"}
                return {
                    "state": "complete", "reportsSubmitted": 2,
                    "transfersCompleted": 2, "lateReports": 0,
                    "maximumLatenessUs": 0,
                }
            if (target, operation) == ("capture", "status"):
                capture_status_calls += 1
                if capture_status_calls == 1:
                    return {
                        "ok": True, "snapshot": {"state": "idle"},
                        "systemReadiness": READY_PREFLIGHT,
                    }
                return {"ok": True, "snapshot": snapshot()}
            if (target, operation) == ("capture", "wait"):
                return {"snapshot": snapshot()}
            return {"ok": True}

        class FakeSwiftCompileLoad:
            def start(self):
                timeline.append(("load", "swift-start"))

            def stop(self):
                timeline.append(("load", "swift-stop"))
                return {"enabled": True, "sourceBytes": 12345, "durationMs": 500}

        with tempfile.TemporaryDirectory() as directory:
            input_path = pathlib.Path(directory) / "input.txt"
            output_path = pathlib.Path(directory) / "result.json"
            input_path.write_text("a")
            arguments = [
                str(RUNNER), "--run-id", "swift-load-run", "--text", str(input_path),
                "--fixture-host", "fixture.local", "--swift-compile-load",
                "--output", str(output_path),
            ]
            with mock.patch.object(self.runner, "load_fixture_token", return_value="token"), \
                 mock.patch.object(self.runner, "run_json", side_effect=fake_run_json), \
                 mock.patch.object(self.runner, "run_checked", side_effect=self.compile_script), \
                 mock.patch.object(self.runner, "ControlledSwiftCompileLoad", FakeSwiftCompileLoad), \
                 mock.patch.object(self.runner.sys, "argv", arguments), \
                 contextlib.redirect_stdout(io.StringIO()):
                self.assertEqual(self.runner.main(), 0)

            artifact = json.loads(output_path.read_text())

        self.assertLess(timeline.index(("capture", "arm")), timeline.index(("load", "swift-start")))
        self.assertLess(timeline.index(("fixture", "start")), timeline.index(("load", "swift-start")))
        self.assertEqual(artifact["swiftCompileLoad"]["sourceBytes"], 12345)
        self.assertEqual(artifact["scheduling"]["effectiveDelayMs"], 10000)
        self.assertTrue(artifact["scheduling"]["loadStartedAfterStartConfirmation"])
        self.assertEqual(timeline.count(("load", "swift-stop")), 1)

    def test_swift_compile_cleanup_does_not_signal_an_exited_process_group(self) -> None:
        load = self.runner.ControlledSwiftCompileLoad()
        process = mock.Mock(pid=4242)
        process.poll.return_value = 1
        load.process = process

        with mock.patch.object(self.runner.os, "killpg") as kill_group:
            result = load.stop()

        kill_group.assert_not_called()
        process.terminate.assert_not_called()
        process.kill.assert_not_called()
        self.assertEqual(result["returnCode"], 1)
        self.assertIsNone(load.process)

    def test_swift_compile_load_uses_the_selected_macos_sdk(self) -> None:
        load = self.runner.ControlledSwiftCompileLoad()
        compiler = "/Toolchains/Test/usr/bin/swiftc"
        sdk = "/Platforms/Test/MacOSX.sdk"
        process = mock.Mock(pid=4242)
        process.poll.return_value = None
        lookups = [
            mock.Mock(stdout=f"{compiler}\n"),
            mock.Mock(stdout=f"{sdk}\n"),
        ]

        with mock.patch.object(self.runner.subprocess, "run", side_effect=lookups), \
             mock.patch.object(self.runner.subprocess, "Popen", return_value=process) as popen, \
             mock.patch.object(self.runner.time, "sleep"):
            load.start()

        command = popen.call_args.args[0]
        self.assertEqual(command[0:2], ["/bin/bash", "-c"])
        self.assertEqual(command[4:6], [compiler, sdk])
        self.assertIn('-sdk "$2"', command[2])
        self.assertEqual(load.sdk, sdk)
        load.process = None
        load.temporary.cleanup()
        load.temporary = None

    def test_trace_collection_allows_the_firmware_wifi_recovery_window(self) -> None:
        errors: list[dict] = []
        with mock.patch.object(self.runner, "run_json", return_value=TRACE_BATCH[1:]) as request:
            trace = self.runner.fetch_fixture_trace("10.0.0.47", {}, errors)

        self.assertEqual(trace, TRACE_BATCH[1:])
        command = request.call_args.args[0]
        self.assertIn("trace-all", command)
        self.assertIn("60", command)

    def test_fixture_discovery_allows_the_firmware_wifi_recovery_window(self) -> None:
        errors: list[dict] = []
        response = {"address": "10.0.0.47", "state": "idle"}
        with mock.patch.object(
            self.runner, "run_fixture_json_with_retry", return_value=response
        ) as request:
            host, status = self.runner.resolve_fixture_host("fixture.local", {}, errors)

        self.assertEqual(host, "10.0.0.47")
        self.assertIs(status, response)
        self.assertEqual(request.call_args.kwargs["retry_seconds"], 60)
        self.assertIs(request.call_args.kwargs["errors"], errors)

    def test_lost_arm_response_is_confirmed_from_fixture_status(self) -> None:
        errors: list[dict] = []
        responses = [
            RuntimeError("arm response timed out"),
            {"state": "armed", "runId": "case"},
        ]
        with mock.patch.object(self.runner, "run_json", side_effect=responses):
            result = self.runner.run_fixture_state_change_with_confirmation(
                "10.0.0.47", "arm", "case", expected_states={"armed"},
                environment={}, retry_seconds=1, errors=errors,
            )

        self.assertTrue(result["confirmedByStatus"])
        self.assertEqual(result["status"]["state"], "armed")
        self.assertEqual(errors[0]["action"], "arm")

    def test_lost_load_response_is_confirmed_without_passing_run_id_to_command(self) -> None:
        errors: list[dict] = []
        responses = [
            RuntimeError("load response timed out"),
            {"state": "loaded", "runId": "case"},
        ]
        with mock.patch.object(self.runner, "run_json", side_effect=responses) as request:
            result = self.runner.run_fixture_state_change_with_confirmation(
                "10.0.0.47", "load-script", "case", "/tmp/script.txt",
                include_run_id_argument=False, expected_states={"loaded"},
                environment={}, retry_seconds=1, errors=errors,
            )

        self.assertTrue(result["confirmedByStatus"])
        load_command = request.call_args_list[0].args[0]
        self.assertIn("load-script", load_command)
        self.assertIn("/tmp/script.txt", load_command)
        self.assertNotIn("case", load_command)

    def test_lost_abort_response_confirms_global_safe_state(self) -> None:
        errors: list[dict] = []
        responses = [
            RuntimeError("abort response timed out"),
            {"state": "aborted", "runId": "stale-case"},
        ]
        with mock.patch.object(self.runner, "run_json", side_effect=responses) as request:
            result = self.runner.run_fixture_state_change_with_confirmation(
                "10.0.0.47", "abort", "new-case",
                include_run_id_argument=False, expected_states={"aborted"},
                environment={}, retry_seconds=1, errors=errors,
                require_run_id_match=False,
            )

        self.assertTrue(result["confirmedByStatus"])
        abort_command = request.call_args_list[0].args[0]
        self.assertIn("abort", abort_command)
        self.assertNotIn("new-case", abort_command)

    def test_state_confirmation_rejects_a_different_run_id(self) -> None:
        errors: list[dict] = []
        responses = [
            RuntimeError("start response timed out"),
            {"state": "running", "runId": "other-case"},
        ]
        with mock.patch.object(self.runner, "run_json", side_effect=responses), \
             mock.patch.object(self.runner.time, "monotonic", side_effect=[0.0, 2.0]):
            with self.assertRaisesRegex(RuntimeError, "fixture start unavailable"):
                self.runner.run_fixture_state_change_with_confirmation(
                    "10.0.0.47", "start", "case", "--delay-ms", "800",
                    expected_states={"running", "complete"}, environment={},
                    retry_seconds=1, errors=errors,
                )

    def test_swift_compile_cleanup_falls_back_when_group_signal_is_denied(self) -> None:
        load = self.runner.ControlledSwiftCompileLoad()
        process = mock.Mock(pid=4242)
        process.poll.side_effect = [None, None]
        process.wait.return_value = -15
        load.process = process

        with mock.patch.object(
            self.runner.os, "killpg", side_effect=PermissionError
        ) as kill_group:
            result = load.stop()

        kill_group.assert_called_once_with(4242, self.runner.signal.SIGTERM)
        process.terminate.assert_called_once_with()
        self.assertEqual(result["returnCode"], -15)
        self.assertIsNone(load.process)

    def test_failed_capture_waits_for_fixture_and_persists_complete_evidence(self) -> None:
        fixture_status_calls = 0
        capture_status_calls = 0

        def fake_run_json(command, environment, allowed_returncodes=(0,)):
            del environment, allowed_returncodes
            nonlocal fixture_status_calls, capture_status_calls
            target, operation = action(command)
            if (target, operation) == ("fixture", "trace-all"):
                return TRACE_BATCH[1:]
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
            if (target, operation) == ("fixture", "trace-all"):
                return TRACE_BATCH[1:]
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
            if (target, operation) == ("fixture", "trace-all"):
                return TRACE_BATCH[1:]
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
            if (target, operation) == ("fixture", "trace-all"):
                return TRACE_BATCH[1:]
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
