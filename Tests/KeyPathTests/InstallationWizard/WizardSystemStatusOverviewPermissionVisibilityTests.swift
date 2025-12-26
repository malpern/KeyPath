@testable import KeyPathAppKit
import KeyPathWizardCore
@preconcurrency import XCTest

@MainActor
final class WizardSystemStatusOverviewPermissionVisibilityTests: XCTestCase {
    func testNotVerifiedKanataPermissionShowsWarningInStatusRow() {
        let warningIssue = WizardIssue(
            identifier: .permission(.kanataInputMonitoring),
            severity: .warning,
            category: .permissions,
            title: "Kanata Input Monitoring Permission",
            description: "Not verified (grant Full Disk Access to verify).",
            autoFixAction: nil,
            userAction: "Grant Full Disk Access to verify (optional)"
        )

        let nav: [WizardPage] = []
        let visible = 0
        let overview = WizardSystemStatusOverview(
            systemState: .serviceNotRunning,
            issues: [warningIssue],
            stateInterpreter: WizardStateInterpreter(),
            onNavigateToPage: nil,
            kanataIsRunning: false,
            showAllItems: true,
            navSequence: .constant(nav),
            visibleIssueCount: .constant(visible)
        )

        let items = overview.statusItems
        let input = items.first(where: { $0.id == "input-monitoring" })
        XCTAssertNotNil(input, "Expected an Input Monitoring status row")
        XCTAssertEqual(input?.status, .warning, "Not verified permission should display as warning")
        XCTAssertTrue(
            (input?.relatedIssues.contains { $0.identifier == .permission(.kanataInputMonitoring) } ?? false),
            "Input Monitoring row should include the underlying warning issue"
        )
    }
}

