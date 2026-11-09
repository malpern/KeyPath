@testable import KeyPathAppKit
@testable import KeyPathInstallationWizard
import KeyPathPermissions
import KeyPathWizardCore
@preconcurrency import XCTest

@MainActor
final class WizardSystemStatusOverviewTests: XCTestCase {
    func testFilteredDisplayItemsKeepsDependentRows() {
        let items: [LocalStatusItem] = [
            LocalStatusItem(
                id: "accessibility",
                icon: "accessibility",
                title: "Accessibility",
                status: .failed,
                isNavigable: true,
                targetPage: .accessibility
            ),
            LocalStatusItem(
                id: "kanata-service",
                icon: "antenna.radiowaves.left.and.right",
                title: "Background Services",
                status: .failed,
                isNavigable: true,
                targetPage: .service
            )
        ]

        let filtered = filteredDisplayItems(items, showAllItems: false)

        XCTAssertEqual(filtered.map(\.id), ["accessibility", "kanata-service"])
        XCTAssertEqual(filtered.count, 2, "Dependent rows should remain visible in filtered view")
    }

    func testServiceStatusStaysCompletedWhenKanataRunning() {
        let nav: [WizardPage] = []
        let visible = 0
        let overview = WizardSystemStatusOverview(
            systemState: .active,
            issues: [],
            onNavigateToPage: nil,
            kanataIsRunning: true,
            showAllItems: true,
            navSequence: .constant(nav),
            visibleIssueCount: .constant(visible)
        )

        XCTAssertEqual(overview.getServiceStatus(), .completed)
    }

    func testServiceStatusIgnoresStaleDaemonIssueWhenRunning() {
        let staleIssue = WizardIssue(
            identifier: .component(.keyPathRuntime),
            severity: .error,
            category: .daemon,
            title: "KeyPath Runtime Not Running",
            description: "",
            autoFixAction: nil,
            userAction: ""
        )

        let nav: [WizardPage] = []
        let visible = 0
        let overview = WizardSystemStatusOverview(
            systemState: .active,
            issues: [staleIssue],
            onNavigateToPage: nil,
            kanataIsRunning: true,
            showAllItems: true,
            navSequence: .constant(nav),
            visibleIssueCount: .constant(visible)
        )

        // Even with a stale daemon issue, running kanata should keep service status completed
        XCTAssertEqual(overview.getServiceStatus(), .completed)
    }

    func testSessionBackendShowsOnlyItsPermissionAndRuntime() {
        let items = WizardSystemStatusOverview.sessionStatusItems(systemState: .active, issues: [])

        XCTAssertEqual(items.map(\.id), ["accessibility", "kanata-service"])
        XCTAssertTrue(items.allSatisfy { $0.status == .completed })
        XCTAssertEqual(WizardSystemStatusOverview.incompleteItemCount(items), 0)
    }

    func testSessionUnknownPermissionEvidenceRemainsVisibleAndCounted() {
        let warning = WizardIssue(
            identifier: .permission(.runtimeKeyAccess),
            severity: .warning,
            category: .permissions,
            title: "Keyboard access not verified",
            description: "Runtime permission evidence is unavailable.",
            autoFixAction: nil,
            userAction: "Retry keyboard access verification"
        )

        let items = WizardSystemStatusOverview.sessionStatusItems(
            systemState: .serviceNotRunning,
            issues: [warning]
        )

        XCTAssertEqual(items.first(where: { $0.id == "accessibility" })?.status, .warning)
        XCTAssertEqual(items.first(where: { $0.id == "kanata-service" })?.status, .notStarted)
        XCTAssertEqual(WizardSystemStatusOverview.incompleteItemCount(items), 2)
    }

    func testSessionRuntimeStoppedPreservesGrantedPermissionEvidence() {
        let permissions = sessionPermissions(accessibility: .granted, runtimeKeyAccess: .granted)
        let runtimeIssue = WizardIssue(
            identifier: .daemon,
            severity: .error,
            category: .daemon,
            title: "Start driverless remapping",
            description: "The session keyboard runtime is stopped or not ready.",
            autoFixAction: nil,
            userAction: "Start the keyboard service"
        )

        let items = WizardSystemStatusOverview.sessionStatusItems(
            systemState: .serviceNotRunning,
            issues: [runtimeIssue],
            permissions: permissions
        )

        XCTAssertEqual(items.first(where: { $0.id == "accessibility" })?.status, .completed)
        XCTAssertEqual(items.first(where: { $0.id == "kanata-service" })?.status, .failed)
        XCTAssertEqual(WizardSystemStatusOverview.incompleteItemCount(items), 1)
    }

    func testWizardSnapshotRetainsCanonicalPermissionFacts() {
        let permissions = sessionPermissions(accessibility: .granted, runtimeKeyAccess: .granted)
        let result = SystemStateResult(
            state: .serviceNotRunning,
            issues: [],
            autoFixActions: [],
            detectionTimestamp: Date(timeIntervalSince1970: 1),
            permissions: permissions
        )
        let stateMachine = WizardStateMachine()
        stateMachine.updateWizardState(from: result)

        XCTAssertTrue(stateMachine.lastWizardSnapshot?.permissions?.accessibility.isReady == true)
        XCTAssertTrue(stateMachine.lastWizardSnapshot?.permissions?.runtimeKeyAccess.status.isReady == true)
    }

    func testSessionIncompleteCaptureDoesNotPromoteMissingPermissionFacts() {
        let items = WizardSystemStatusOverview.sessionStatusItems(systemState: .serviceNotRunning, issues: [])
        XCTAssertEqual(items.first(where: { $0.id == "accessibility" })?.status, .notStarted)

        let unknownPermissions = WizardSystemStatusOverview.sessionStatusItems(
            systemState: .serviceNotRunning,
            issues: [],
            permissions: sessionPermissions(accessibility: .unknown, runtimeKeyAccess: .unknown)
        )
        XCTAssertEqual(unknownPermissions.first(where: { $0.id == "accessibility" })?.status, .notStarted)

        let unreportedRuntime = WizardSystemStatusOverview.sessionStatusItems(
            systemState: .serviceNotRunning,
            issues: [],
            permissions: sessionPermissions(accessibility: .granted, runtimeKeyAccess: .unknown)
        )
        XCTAssertEqual(unreportedRuntime.first(where: { $0.id == "accessibility" })?.status, .notStarted)
    }

    func testSessionDeniedPermissionsStayFailedAndNavigateToTheAccessibilityPage() {
        let axIssue = WizardIssue(
            identifier: .permission(.keyPathAccessibility),
            severity: .error,
            category: .permissions,
            title: "Allow KeyPath to remap keys",
            description: "Accessibility permission is denied.",
            autoFixAction: nil,
            userAction: "Open Accessibility settings"
        )
        let runtimeIssue = WizardIssue(
            identifier: .permission(.runtimeKeyAccess),
            severity: .error,
            category: .permissions,
            title: "Keyboard access still needs approval",
            description: "Quit and reopen KeyPath.",
            autoFixAction: nil,
            userAction: "Quit and reopen KeyPath"
        )
        let items = WizardSystemStatusOverview.sessionStatusItems(
            systemState: .missingPermissions(missing: [.keyPathAccessibility, .runtimeKeyAccess]),
            issues: [axIssue, runtimeIssue],
            permissions: sessionPermissions(accessibility: .denied, runtimeKeyAccess: .denied)
        )

        let accessibility = items.first(where: { $0.id == "accessibility" })
        XCTAssertEqual(accessibility?.status, .failed)
        XCTAssertEqual(accessibility?.targetPage, .accessibility)
        XCTAssertEqual(accessibility?.relatedIssues.count, 2)
        XCTAssertEqual(WizardSystemStatusOverview.incompleteItemCount(items), 2)
    }

    func testSessionRuntimeFailureIsCountedWithoutLegacyPrerequisites() {
        let runtimeIssue = WizardIssue(
            identifier: .daemon,
            severity: .error,
            category: .daemon,
            title: "Runtime stopped",
            description: "The session runtime is not ready.",
            autoFixAction: nil,
            userAction: "Start the keyboard service"
        )

        let items = WizardSystemStatusOverview.sessionStatusItems(
            systemState: .serviceNotRunning,
            issues: [runtimeIssue]
        )

        XCTAssertEqual(items.map(\.id), ["accessibility", "kanata-service"])
        XCTAssertEqual(items.first(where: { $0.id == "kanata-service" })?.status, .failed)
        XCTAssertEqual(WizardSystemStatusOverview.incompleteItemCount(items), 2)
    }

    func testOverviewShowsOnlySessionRows() {
        let nav: [WizardPage] = []
        let visible = 0
        let overview = WizardSystemStatusOverview(
            systemState: .active,
            issues: [],
            onNavigateToPage: nil,
            kanataIsRunning: true,
            showAllItems: true,
            navSequence: .constant(nav),
            visibleIssueCount: .constant(visible)
        )

        XCTAssertEqual(
            overview.statusItems.map(\.id),
            ["accessibility", "kanata-service"],
            "Only the permission and the runtime are shown"
        )
    }

    private func sessionPermissions(
        accessibility: PermissionOracle.Status,
        runtimeKeyAccess: PermissionOracle.Status
    ) -> PermissionOracle.Snapshot {
        .fixture(
            accessibility: accessibility, runtimeKeyAccess: runtimeKeyAccess,
            timestamp: Date(timeIntervalSince1970: 1)
        )
    }
}

/// Local stand-in for filteredDisplayItems logic (mirrors production behavior).
private struct LocalStatusItem {
    let id: String
    let icon: String
    let title: String
    let status: InstallationStatus
    let isNavigable: Bool
    let targetPage: WizardPage
}

private func filteredDisplayItems(_ items: [LocalStatusItem], showAllItems: Bool)
    -> [LocalStatusItem]
{
    if showAllItems { return items }
    return items.filter { $0.status != .completed }
}
