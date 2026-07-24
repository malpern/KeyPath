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
    def test_upstream_release_wait_is_human_gated(self) -> None:
        self.assertEqual(module.issue_status(issue(982, "bug-risk", "human-in-loop")), "human")

    def test_on_hold_and_tracking_labels_override_work_type(self) -> None:
        self.assertEqual(module.issue_status(issue(982, "human-in-loop", "on-hold")), "hold")
        self.assertEqual(module.issue_status(issue(604, "testing", "tracking-only")), "deferred")
        self.assertEqual(module.issue_status(issue(865, "enhancement", "tracking-only", "on-hold")), "hold")
        self.assertEqual(module.issue_status(issue(870, "recommended-next", "on-hold")), "hold")

    def test_on_hold_is_a_distinct_visible_dashboard_state(self) -> None:
        fragment = (REPO_ROOT / "docs/testing/keypath-github-issues-dashboard.fragment.html").read_text()
        self.assertIn("data-status=\"hold\"", fragment)
        self.assertIn("id=\"metric-hold\"", fragment)
        self.assertIn("hold:'On hold'", fragment)

    def test_topic_labels_do_not_imply_execution_state(self) -> None:
        self.assertEqual(module.issue_status(issue(912, "wwdc26", "enhancement")), "feature")
        self.assertEqual(module.issue_status(issue(919, "wwdc26", "human-in-loop")), "human")

    def test_features_do_not_enter_agent_bug_queue(self) -> None:
        self.assertEqual(module.issue_status(issue(870, "Feature", "agent-ok")), "feature")

    def test_reliability_and_test_debt_enter_agent_queue(self) -> None:
        self.assertEqual(module.issue_status(issue(1, "bug")), "queued")
        self.assertEqual(module.issue_status(issue(2, "testing")), "queued")
        self.assertEqual(module.issue_status(issue(3, "tech-debt")), "queued")

    def test_recommended_next_overrides_feature_classification(self) -> None:
        self.assertEqual(
            module.issue_status(issue(870, "enhancement", "agent-ok", "recommended-next")),
            "next",
        )

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
