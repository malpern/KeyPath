@testable import KeyPathAppKit
@testable import KeyPathInstallationWizard
import KeyPathWizardCore
@preconcurrency import XCTest

@MainActor
final class WizardSystemStatusOverviewPermissionVisibilityTests: XCTestCase {
    func testRuntimePermissionWarningAppearsAsWarning() {
        let warningIssue = WizardIssue(
            identifier: .permission(.runtimeKeyAccess),
            severity: .warning,
            category: .permissions,
            title: "Keyboard access not verified",
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
        XCTAssertFalse(items.contains { $0.id == "input-monitoring" })
        let accessibility = items.first(where: { $0.id == "accessibility" })
        XCTAssertNotNil(accessibility, "Expected the permission status row")
        XCTAssertEqual(accessibility?.status, .warning, "A runtime permission warning should surface as a warning, not completed")
        XCTAssertTrue(
            (accessibility?.relatedIssues.contains { $0.identifier == .permission(.runtimeKeyAccess) } ?? false),
            "The permission row should include the underlying warning issue"
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
        let permissionItems = overview.statusItems.filter { $0.id == "accessibility" }
        XCTAssertEqual(permissionItems.count, 1)
        XCTAssertTrue(permissionItems.allSatisfy { $0.status == .notStarted })
    }
}
