@testable import KeyPathAppKit
@preconcurrency import XCTest

@MainActor
final class WizardSummaryPageTests: XCTestCase {
    func testIssueCountPrefersVisibleCount() {
        // Visible list shows 1 item, aggregate detects 2 (hidden by dependency filter)
        let count = WizardSummaryPage.computeIssueCount(visibleCount: 1, failedCount: 2)
        XCTAssertEqual(count, 1, "Header should reflect the visible issues, not hidden ones")
    }

    func testIssueCountFallsBackToFailedWhenVisibleEmpty() {
        // No visible items (e.g., before list renders), fall back to aggregate
        let count = WizardSummaryPage.computeIssueCount(visibleCount: 0, failedCount: 3)
        XCTAssertEqual(count, 3, "When nothing is visible yet, use the aggregate count")
    }

    func testIssueCountZeroWhenNoIssues() {
        let count = WizardSummaryPage.computeIssueCount(visibleCount: 0, failedCount: 0)
        XCTAssertEqual(count, 0)
    }
}
