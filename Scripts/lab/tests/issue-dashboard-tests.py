#!/usr/bin/env python3
import importlib.machinery
import importlib.util
import pathlib
import unittest


SCRIPT = pathlib.Path(__file__).resolve().parents[1] / "update-issue-dashboard"
loader = importlib.machinery.SourceFileLoader("update_issue_dashboard", str(SCRIPT))
spec = importlib.util.spec_from_loader(loader.name, loader)
module = importlib.util.module_from_spec(spec)
loader.exec_module(module)


def issue(number: int, *labels: str) -> dict:
    return {"number": number, "labels": [{"name": label} for label in labels]}


class IssueDashboardTests(unittest.TestCase):
    def test_active_and_next_override_general_labels(self) -> None:
        self.assertEqual(module.issue_status(issue(982, "bug-risk", "agent-ok")), "active")
        self.assertEqual(module.issue_status(issue(748, "tech-debt")), "next")

    def test_explicitly_deferred_issues_are_human_gated(self) -> None:
        for number in (172, 740, 747, 919):
            with self.subTest(number=number):
                self.assertEqual(module.issue_status(issue(number, "agent-ok")), "human")

    def test_features_do_not_enter_agent_bug_queue(self) -> None:
        self.assertEqual(module.issue_status(issue(870, "Feature", "agent-ok")), "feature")

    def test_reliability_and_test_debt_enter_agent_queue(self) -> None:
        self.assertEqual(module.issue_status(issue(1, "bug")), "queued")
        self.assertEqual(module.issue_status(issue(2, "testing")), "queued")
        self.assertEqual(module.issue_status(issue(3, "tech-debt")), "queued")

    def test_issue_limit_is_explicit(self) -> None:
        self.assertEqual(module.ISSUE_LIMIT, 200)


if __name__ == "__main__":
    unittest.main()
