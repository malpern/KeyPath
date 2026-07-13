#!/usr/bin/env python3
import importlib.machinery
import importlib.util
import pathlib
import unittest


SCRIPT = pathlib.Path(__file__).resolve().parents[1] / "update-issue-dashboard"
LAB_DIR = SCRIPT.parent
REPO_ROOT = LAB_DIR.parents[1]
loader = importlib.machinery.SourceFileLoader("update_issue_dashboard", str(SCRIPT))
spec = importlib.util.spec_from_loader(loader.name, loader)
module = importlib.util.module_from_spec(spec)
loader.exec_module(module)


def issue(number: int, *labels: str) -> dict:
    return {"number": number, "labels": [{"name": label} for label in labels]}


class IssueDashboardTests(unittest.TestCase):
    def test_active_and_next_override_general_labels(self) -> None:
        self.assertEqual(module.issue_status(issue(748, "tech-debt")), "active")
        self.assertEqual(module.issue_status(issue(848, "testing", "agent-ok")), "next")

    def test_upstream_release_wait_is_human_gated(self) -> None:
        self.assertEqual(module.issue_status(issue(982, "bug-risk", "human-in-loop")), "human")

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

    def test_issue_type_uses_stable_label_precedence(self) -> None:
        self.assertEqual(module.issue_type(issue(1, "bug-risk", "upstream")), "bug")
        self.assertEqual(module.issue_type(issue(2, "testing", "tech-debt")), "testing")
        self.assertEqual(module.issue_type(issue(3, "refactor", "enhancement")), "debt")
        self.assertEqual(module.issue_type(issue(4, "Feature", "upstream")), "feature")
        self.assertEqual(module.issue_type(issue(5, "research", "devux")), "upstream")
        self.assertEqual(module.issue_type(issue(6, "documentation")), "docs")

    def test_card_navigation_contract_is_generated_safely(self) -> None:
        fragment = (REPO_ROOT / "docs/testing/keypath-github-issues-dashboard.fragment.html").read_text()
        tab_renderer = (LAB_DIR / "add-dashboard-tabs.py").read_text()
        self.assertIn("button.setAttribute('aria-pressed','false')", fragment)
        self.assertIn("button.addEventListener('dblclick'", fragment)
        self.assertIn("keypath-issue-navigation", fragment)
        self.assertIn("event.source!==dashboardFrame.contentWindow", tab_renderer)
        self.assertIn(r"github\\.com\\/malpern\\/KeyPath\\/issues", tab_renderer)

    def test_description_excerpt_is_plain_bounded_text(self) -> None:
        body = "## Context\n\n**Important** `detail` " + ("word " * 80)
        excerpt = module.description_excerpt(body)
        self.assertTrue(excerpt.startswith("Context Important detail"))
        self.assertLessEqual(len(excerpt), 261)
        self.assertTrue(excerpt.endswith("…"))
        self.assertNotIn("**", excerpt)

    def test_type_highlight_can_be_persistently_toggled(self) -> None:
        fragment = (REPO_ROOT / "docs/testing/keypath-github-issues-dashboard.fragment.html").read_text()
        self.assertIn("selectedType === filter.dataset.type ? undefined", fragment)
        self.assertIn("candidate.setAttribute('aria-pressed'", fragment)
        self.assertIn("showType(selectedType)", fragment)
        self.assertNotIn('.issue::before { content:"";', fragment)


if __name__ == "__main__":
    unittest.main()
