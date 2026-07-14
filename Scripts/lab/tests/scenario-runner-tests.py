#!/usr/bin/env python3
import json
import os
import pathlib
import signal
import subprocess
import sys
import tempfile
import time
import unittest


RUNNER = pathlib.Path(__file__).resolve().parents[1] / "scenario-runner"


class ScenarioRunnerTests(unittest.TestCase):
    def setUp(self) -> None:
        self.temporary = tempfile.TemporaryDirectory()
        self.root = pathlib.Path(self.temporary.name)
        self.plan = self.root / "plan.json"
        self.state = self.root / "state.json"
        self.result = self.root / "result.json"

    def tearDown(self) -> None:
        self.temporary.cleanup()

    def command(self, code: str) -> list[str]:
        return [sys.executable, "-c", code]

    def write_plan(self, steps: list[dict]) -> None:
        self.plan.write_text(json.dumps({"schemaVersion": 1, "scenario": "resume-test", "steps": steps}))

    def invoke(self, check: bool = True) -> subprocess.CompletedProcess[str]:
        return subprocess.run(
            [str(RUNNER), "--plan", str(self.plan), "--state", str(self.state), "--result", str(self.result)],
            capture_output=True, text=True, check=check,
        )

    def test_resume_accepts_postcondition_without_replaying_interrupted_action(self) -> None:
        effect = self.root / "effect"
        started = self.root / "started"
        self.write_plan([{
            "id": "install", "verify": self.command(f"import pathlib, sys; sys.exit(not pathlib.Path({str(effect)!r}).exists())"),
            "action": self.command(f"import pathlib, time; pathlib.Path({str(effect)!r}).touch(); pathlib.Path({str(started)!r}).touch(); time.sleep(30)"),
        }])
        process = subprocess.Popen(
            [str(RUNNER), "--plan", str(self.plan), "--state", str(self.state), "--result", str(self.result)],
            start_new_session=True,
        )
        for _ in range(100):
            if started.exists():
                break
            time.sleep(0.02)
        self.assertTrue(started.exists(), "action did not begin")
        os.killpg(process.pid, signal.SIGTERM)
        process.wait(timeout=5)

        resumed = self.invoke(check=False)
        self.assertEqual(resumed.returncode, 0, resumed.stderr)
        state = json.loads(self.state.read_text())
        self.assertEqual(state["status"], "passed")
        self.assertEqual(state["steps"][0]["attempts"], 1)

    def test_unverified_interrupted_mutation_blocks_without_replay(self) -> None:
        count = self.root / "action-count"
        started = self.root / "started"
        self.write_plan([{
            "id": "repair", "verify": self.command("import sys; sys.exit(1)"),
            "action": self.command(
                f"import pathlib, time; p=pathlib.Path({str(count)!r}); p.write_text(str(int(p.read_text()) + 1) if p.exists() else '1'); pathlib.Path({str(started)!r}).touch(); time.sleep(30)"
            ),
        }])
        process = subprocess.Popen(
            [str(RUNNER), "--plan", str(self.plan), "--state", str(self.state), "--result", str(self.result)],
            start_new_session=True,
        )
        for _ in range(100):
            if started.exists():
                break
            time.sleep(0.02)
        self.assertTrue(started.exists(), "action did not begin")
        os.killpg(process.pid, signal.SIGTERM)
        process.wait(timeout=5)

        resumed = self.invoke(check=False)
        self.assertEqual(resumed.returncode, 3)
        self.assertEqual(count.read_text(), "1")
        state = json.loads(self.state.read_text())
        self.assertEqual(state["status"], "blocked")
        result = json.loads(self.result.read_text())
        self.assertEqual(result["failure"]["classification"], "harness-transport-failure")

    def test_completed_checkpoint_is_not_replayed(self) -> None:
        first = self.root / "first"
        second = self.root / "second"
        self.write_plan([
            {
                "id": "first", "verify": self.command(f"import pathlib, sys; sys.exit(not pathlib.Path({str(first)!r}).exists())"),
                "action": self.command(f"import pathlib; pathlib.Path({str(first)!r}).touch()"),
            },
            {
                "id": "second", "verify": self.command(f"import pathlib, sys; sys.exit(not pathlib.Path({str(second)!r}).exists())"),
                "action": self.command(f"import pathlib; pathlib.Path({str(second)!r}).touch()"),
            },
        ])
        self.invoke()
        self.assertEqual(self.invoke(check=False).returncode, 3)
        self.assertTrue(first.exists())
        self.assertTrue(second.exists())

    def test_plan_digest_change_is_rejected(self) -> None:
        target = self.root / "target"
        self.write_plan([{
            "id": "install", "verify": self.command(f"import pathlib, sys; sys.exit(not pathlib.Path({str(target)!r}).exists())"),
            "action": self.command(f"import pathlib; pathlib.Path({str(target)!r}).touch()"),
        }])
        self.invoke()
        plan = json.loads(self.plan.read_text())
        plan["steps"][0]["id"] = "install-changed"
        self.plan.write_text(json.dumps(plan))
        changed = self.invoke(check=False)
        self.assertEqual(changed.returncode, 2)
        self.assertIn("plan changed", changed.stderr)

    def test_successful_action_without_postcondition_is_product_failure(self) -> None:
        self.write_plan([{
            "id": "verify-runtime", "verify": self.command("import sys; sys.exit(1)"),
            "action": self.command("pass"),
        }])
        run = self.invoke(check=False)
        self.assertEqual(run.returncode, 1)
        result = json.loads(self.result.read_text())
        self.assertEqual(result["failure"]["classification"], "keypath-product-failure")

    def test_verified_recovery_allows_an_interrupted_step_to_restart(self) -> None:
        count = self.root / "action-count"
        started = self.root / "started"
        recovered = self.root / "recovered"
        effect = self.root / "effect"
        action = (
            f"import pathlib, time; p=pathlib.Path({str(count)!r}); n=int(p.read_text()) + 1 if p.exists() else 1; "
            f"p.write_text(str(n)); pathlib.Path({str(started)!r}).touch(); "
            f"time.sleep(30) if n == 1 else None; pathlib.Path({str(effect)!r}).touch()"
        )
        self.write_plan([{
            "id": "repair", "verify": self.command(f"import pathlib, sys; sys.exit(not pathlib.Path({str(effect)!r}).exists())"),
            "action": self.command(action),
            "recovery": self.command(f"import pathlib; pathlib.Path({str(recovered)!r}).touch()"),
            "recoveryVerify": self.command(f"import pathlib, sys; sys.exit(not pathlib.Path({str(recovered)!r}).exists())"),
        }])
        process = subprocess.Popen(
            [str(RUNNER), "--plan", str(self.plan), "--state", str(self.state), "--result", str(self.result)],
            start_new_session=True,
        )
        for _ in range(100):
            if started.exists():
                break
            time.sleep(0.02)
        self.assertTrue(started.exists(), "action did not begin")
        os.killpg(process.pid, signal.SIGTERM)
        process.wait(timeout=5)

        resumed = self.invoke(check=False)
        self.assertEqual(resumed.returncode, 0, resumed.stderr)
        self.assertTrue(recovered.exists())
        self.assertEqual(count.read_text(), "2")


if __name__ == "__main__":
    unittest.main()
