@testable import KeyPathAppKit
import KeyPathWizardCore
@preconcurrency import XCTest

final class WizardNavigationHeuristicsTests: XCTestCase {
    func testNavigatesToSummaryWhenHealthyAndNotAlreadyThere() {
        let result = shouldNavigateToSummary(
            currentPage: .service,
            state: .active,
            issues: []
        )
        XCTAssertTrue(result)
    }

    func testDoesNotNavigateWhenIssuesPresent() {
        let issue = WizardIssue(
            identifier: .component(.kanataBinaryMissing),
            severity: .critical,
            category: .installation,
            title: "Kanata binary missing",
            description: "",
            autoFixAction: .installBundledKanata,
            userAction: nil
        )

        let result = shouldNavigateToSummary(
            currentPage: .service,
            state: .active,
            issues: [issue]
        )
        XCTAssertFalse(result)
    }

    func testDoesNotNavigateWhenNotActive() {
        let result = shouldNavigateToSummary(
            currentPage: .service,
            state: .serviceNotRunning,
            issues: []
        )
        XCTAssertFalse(result)
    }

    func testDoesNotNavigateWhenAlreadyOnSummary() {
        let result = shouldNavigateToSummary(
            currentPage: .summary,
            state: .active,
            issues: []
        )
        XCTAssertFalse(result)
    }
}
