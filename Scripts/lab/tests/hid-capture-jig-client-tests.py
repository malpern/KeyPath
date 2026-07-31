#!/usr/bin/env python3
from __future__ import annotations

import json
import os
import pathlib
import subprocess
import tempfile
import threading
import time
import unittest


ROOT = pathlib.Path(__file__).resolve().parents[2]
CLIENT = ROOT / "lab/hid-capture-jig-client"


class FakeJig:
    def __init__(self, directory: pathlib.Path):
        self.directory = directory
        self.commands: list[dict[str, object]] = []
        self.stop = False
        self.thread = threading.Thread(target=self.run, daemon=True)

    def __enter__(self):
        self.thread.start()
        return self

    def __exit__(self, *_):
        self.stop = True
        self.thread.join(timeout=1)

    def run(self):
        last_id = None
        while not self.stop:
            try:
                command = json.loads((self.directory / "command.json").read_text())
            except (FileNotFoundError, json.JSONDecodeError):
                time.sleep(0.005)
                continue
            if command["id"] == last_id:
                time.sleep(0.005)
                continue
            last_id = command["id"]
            self.commands.append(command)
            snapshot = {
                "state": "armed" if command["action"] == "arm" else "idle",
                "expected": command.get("expected", ""),
                "received": "",
            }
            response = {
                "id": command["id"], "ok": True, "message": "fake response",
                "processID": 42, "snapshot": snapshot,
            }
            temporary = self.directory / ".response.tmp"
            temporary.write_text(json.dumps(response))
            os.replace(temporary, self.directory / "response.json")


class HIDCaptureJigClientTests(unittest.TestCase):
    def run_client(self, directory: pathlib.Path, *arguments: str, timeout: str = "1"):
        environment = os.environ.copy()
        environment["KEYPATH_CAPTURE_JIG_STATE_DIR"] = str(directory)
        environment["KEYPATH_CAPTURE_JIG_COMMAND_TIMEOUT"] = timeout
        return subprocess.run(
            [str(CLIENT), *arguments], text=True, capture_output=True,
            env=environment, timeout=5,
        )

    def test_arm_transports_expected_text_by_file(self):
        with tempfile.TemporaryDirectory() as temporary:
            directory = pathlib.Path(temporary)
            expected = directory / "expected.txt"
            expected.write_text("q becomes w")
            with FakeJig(directory) as jig:
                result = self.run_client(
                    directory, "arm", "--run-id", "physical-1", "--expected", str(expected),
                    "--timeout-ms", "7000", "--settle-ms", "300",
                    "--demo-mode",
                    "--instruction", "UNPLUG USB-C NOW",
                )
            self.assertEqual(result.returncode, 0, result.stderr)
            response = json.loads(result.stdout)
            self.assertEqual(response["snapshot"]["expected"], "q becomes w")
            self.assertEqual(jig.commands[0]["runID"], "physical-1")
            self.assertEqual(jig.commands[0]["timeoutMs"], 7000)
            self.assertEqual(jig.commands[0]["settleMs"], 300)
            self.assertEqual(jig.commands[0]["instruction"], "UNPLUG USB-C NOW")
            self.assertTrue(jig.commands[0]["demoMode"])

    def test_focus_uses_a_distinct_control_action(self):
        with tempfile.TemporaryDirectory() as temporary:
            directory = pathlib.Path(temporary)
            with FakeJig(directory) as jig:
                result = self.run_client(directory, "focus")
            self.assertEqual(result.returncode, 0, result.stderr)
            self.assertEqual(jig.commands[0]["action"], "focus")

    def test_bear_monitor_transports_schedule_without_claiming_capture(self):
        with tempfile.TemporaryDirectory() as temporary:
            directory = pathlib.Path(temporary)
            scheduled = directory / "scheduled.txt"
            scheduled.write_text("teh teh \n")
            with FakeJig(directory) as jig:
                begin = self.run_client(
                    directory, "bear-begin", "--run-id", "typover-1",
                    "--case-index", "2", "--case-count", "4",
                    "--interval-ms", "60", "--word-count", "2",
                    "--scheduled-text", str(scheduled), "--start-delay-ms", "1500",
                    "--bear-focused",
                )
                update = self.run_client(
                    directory, "bear-update", "--phase", "safeMisses",
                    "--corrected-words", "1", "--missed-words", "1",
                    "--message", "one safe miss", "--bear-focused",
                )
            self.assertEqual(begin.returncode, 0, begin.stderr)
            self.assertEqual(update.returncode, 0, update.stderr)
            self.assertEqual(jig.commands[0]["action"], "bear-monitor-begin")
            self.assertEqual(jig.commands[0]["scheduledText"], "teh teh \n")
            self.assertEqual(jig.commands[0]["intervalMs"], 60)
            self.assertEqual(jig.commands[1]["action"], "bear-monitor-update")
            self.assertEqual(jig.commands[1]["phase"], "safeMisses")
            self.assertEqual(jig.commands[1]["correctedWords"], 1)

    def test_missing_app_fails_with_actionable_message(self):
        with tempfile.TemporaryDirectory() as temporary:
            result = self.run_client(pathlib.Path(temporary), "status", timeout="0.1")
        self.assertEqual(result.returncode, 2)
        self.assertIn("hid-capture-jig-tool open", result.stderr)

    def test_missing_expected_file_is_rejected_before_command(self):
        with tempfile.TemporaryDirectory() as temporary:
            directory = pathlib.Path(temporary)
            result = self.run_client(
                directory, "arm", "--run-id", "missing", "--expected", str(directory / "none"),
            )
        self.assertEqual(result.returncode, 2)
        self.assertIn("does not exist", result.stderr)
        self.assertFalse((directory / "command.json").exists())


if __name__ == "__main__":
    unittest.main()
