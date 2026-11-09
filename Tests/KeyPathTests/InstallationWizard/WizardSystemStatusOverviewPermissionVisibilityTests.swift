@testable import KeyPathAppKit
@testable import KeyPathInstallationWizard
import KeyPathWizardCore
@preconcurrency import XCTest

@MainActor
final class WizardSystemStatusOverviewPermissionVisibilityTests: XCTestCase {
    func testKanataPermissionWarningAppearsAsWarning() {
        let warningIssue = WizardIssue(
            identifier: .permission(.kanataInputMonitoring),
            severity: .warning,
            category: .permissions,
            title: "Kanata Input Monitoring Permission",
            description: "Permission not verified.",
            autoFixAction: nil,
            userAction: "Check the matching System Settings privacy pane."
        )

        let nav: [WizardPage] = []
        let visible = 0
        let overview = WizardSystemStatusOverview(
            systemState: .serviceNotRunning,
            issues: [warningIssue],
            onNavigateToPage: nil,
            kanataIsRunning: false,
            showAllItems: true,
            navSequence: .constant(nav),
            visibleIssueCount: .constant(visible)
        )

        let items = overview.statusItems
        XCTAssertFalse(items.contains { $0.id == "full-disk-access" || $0.title == "Enhanced Diagnostics" })
        XCTAssertFalse(WizardPage.allCases.contains { $0.rawValue == "Full Disk Access" })
        let input = items.first(where: { $0.id == "input-monitoring" })
        XCTAssertNotNil(input, "Expected an Input Monitoring status row")
        XCTAssertEqual(input?.status, .warning, "Kanata permission warning should surface as a warning, not completed")
        XCTAssertTrue(
            (input?.relatedIssues.contains { $0.identifier == .permission(.kanataInputMonitoring) } ?? false),
            "Input Monitoring row should include the underlying warning issue"
        )
    }

    func testAbsentPermissionEvidenceDoesNotShowCompletedRows() {
        let overview = WizardSystemStatusOverview(
            systemState: .serviceNotRunning,
            issues: [],
            onNavigateToPage: nil,
            kanataIsRunning: false,
            showAllItems: true,
            navSequence: .constant([]),
            visibleIssueCount: .constant(0)
        )
        let permissionItems = overview.statusItems.filter {
            $0.id == "input-monitoring" || $0.id == "accessibility"
        }
        XCTAssertEqual(permissionItems.count, 2)
        XCTAssertTrue(permissionItems.allSatisfy { $0.status == .notStarted })
    }
}
