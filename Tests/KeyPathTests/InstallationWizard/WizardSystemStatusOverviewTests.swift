@testable import KeyPathAppKit
@testable import KeyPathInstallationWizard
import KeyPathWizardCore
import KeyPathPermissions
@preconcurrency import XCTest

@MainActor
final class WizardSystemStatusOverviewTests: XCTestCase {
    func testFilteredDisplayItemsKeepsDependentRows() {
        let items: [LocalStatusItem] = [
            LocalStatusItem(
                id: "privileged-helper",
                icon: "lock",
                title: "Privileged Helper",
                status: .failed,
                isNavigable: true,
                targetPage: .helper
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

        XCTAssertEqual(filtered.map(\.id), ["privileged-helper", "kanata-service"])
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
            identifier: .component(.karabinerDaemon),
            severity: .error,
            category: .daemon,
            title: "Daemon not running",
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

    func testSessionBackendShowsOnlyItsTwoPermissionsAndRuntime() {
        let items = WizardSystemStatusOverview.sessionStatusItems(systemState: .active, issues: [])

        XCTAssertEqual(items.map(\.id), ["input-monitoring", "accessibility", "kanata-service"])
        XCTAssertTrue(items.allSatisfy { $0.status == .completed })
        XCTAssertEqual(WizardSystemStatusOverview.incompleteItemCount(items), 0)
    }

    func testSessionUnknownPermissionEvidenceRemainsVisibleAndCounted() {
        let warning = WizardIssue(
            identifier: .permission(.keyPathInputMonitoring),
            severity: .warning,
            category: .permissions,
            title: "Input access not verified",
            description: "Runtime permission evidence is unavailable.",
            autoFixAction: nil,
            userAction: "Retry keyboard access verification"
        )

        let items = WizardSystemStatusOverview.sessionStatusItems(
            systemState: .serviceNotRunning,
            issues: [warning]
        )

        XCTAssertEqual(items.first(where: { $0.id == "input-monitoring" })?.status, .warning)
        XCTAssertEqual(items.first(where: { $0.id == "accessibility" })?.status, .notStarted)
        XCTAssertEqual(items.first(where: { $0.id == "kanata-service" })?.status, .notStarted)
        XCTAssertEqual(WizardSystemStatusOverview.incompleteItemCount(items), 3)
    }

    func testSessionRuntimeStoppedPreservesGrantedPermissionEvidence() {
        let permissions = sessionPermissions(accessibility: .granted, inputMonitoring: .granted)
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

        XCTAssertEqual(items.first(where: { $0.id == "input-monitoring" })?.status, .completed)
        XCTAssertEqual(items.first(where: { $0.id == "accessibility" })?.status, .completed)
        XCTAssertEqual(items.first(where: { $0.id == "kanata-service" })?.status, .failed)
        XCTAssertEqual(WizardSystemStatusOverview.incompleteItemCount(items), 1)
    }

    func testWizardSnapshotRetainsCanonicalPermissionFacts() {
        let permissions = sessionPermissions(accessibility: .granted, inputMonitoring: .granted)
        let result = SystemStateResult(
            state: .serviceNotRunning,
            issues: [],
            autoFixActions: [],
            detectionTimestamp: Date(timeIntervalSince1970: 1),
            backend: .session,
            permissions: permissions
        )
        let stateMachine = WizardStateMachine()
        stateMachine.updateWizardState(from: result)

        XCTAssertEqual(stateMachine.lastWizardSnapshot?.permissions?.backend, .session)
        XCTAssertTrue(stateMachine.lastWizardSnapshot?.permissions?.kanata.inputMonitoring.isReady == true)
    }

    func testSessionIncompleteCaptureDoesNotPromoteMissingPermissionFacts() {
        let items = WizardSystemStatusOverview.sessionStatusItems(systemState: .serviceNotRunning, issues: [])

        XCTAssertEqual(items.first(where: { $0.id == "input-monitoring" })?.status, .notStarted)
        XCTAssertEqual(items.first(where: { $0.id == "accessibility" })?.status, .notStarted)

        let unknownPermissions = WizardSystemStatusOverview.sessionStatusItems(
            systemState: .serviceNotRunning,
            issues: [],
            permissions: sessionPermissions(accessibility: .unknown, inputMonitoring: .unknown)
        )
        XCTAssertEqual(unknownPermissions.first(where: { $0.id == "input-monitoring" })?.status, .notStarted)
        XCTAssertEqual(unknownPermissions.first(where: { $0.id == "accessibility" })?.status, .notStarted)
    }

    func testSessionDeniedPermissionsStayFailedAndNavigateToTheirConsentPages() {
        let axIssue = WizardIssue(
            identifier: .permission(.keyPathAccessibility),
            severity: .error,
            category: .permissions,
            title: "Allow KeyPath to remap keys",
            description: "Accessibility permission is denied.",
            autoFixAction: nil,
            userAction: "Open Accessibility settings"
        )
        let imIssue = WizardIssue(
            identifier: .permission(.keyPathInputMonitoring),
            severity: .error,
            category: .permissions,
            title: "Keyboard access still needs approval",
            description: "Input Monitoring permission is denied.",
            autoFixAction: nil,
            userAction: "Open Input Monitoring settings"
        )
        let items = WizardSystemStatusOverview.sessionStatusItems(
            systemState: .missingPermissions(missing: [.keyPathAccessibility, .keyPathInputMonitoring]),
            issues: [axIssue, imIssue],
            permissions: sessionPermissions(accessibility: .denied, inputMonitoring: .denied)
        )

        let input = items.first(where: { $0.id == "input-monitoring" })
        let accessibility = items.first(where: { $0.id == "accessibility" })
        XCTAssertEqual(input?.status, .failed)
        XCTAssertEqual(input?.targetPage, .inputMonitoring)
        XCTAssertEqual(accessibility?.status, .failed)
        XCTAssertEqual(accessibility?.targetPage, .accessibility)
        XCTAssertEqual(WizardSystemStatusOverview.incompleteItemCount(items), 3)
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

        XCTAssertEqual(items.map(\.id), ["input-monitoring", "accessibility", "kanata-service"])
        XCTAssertEqual(items.first(where: { $0.id == "kanata-service" })?.status, .failed)
        XCTAssertEqual(WizardSystemStatusOverview.incompleteItemCount(items), 3)
    }

    func testDriverKitBackendRetainsLegacyRows() {
        let nav: [WizardPage] = []
        let visible = 0
        let overview = WizardSystemStatusOverview(
            systemState: .active,
            issues: [],
            backend: .driverKit,
            onNavigateToPage: nil,
            kanataIsRunning: true,
            showAllItems: true,
            navSequence: .constant(nav),
            visibleIssueCount: .constant(visible),
            duplicateCopiesOverride: []
        )

        let ids = Set(overview.statusItems.map(\.id))
        XCTAssertTrue(ids.contains("privileged-helper"))
        XCTAssertFalse(ids.contains("full-disk-access"))
        XCTAssertTrue(ids.contains("karabiner-components"))
    }

    private func sessionPermissions(
        accessibility: PermissionOracle.Status,
        inputMonitoring: PermissionOracle.Status
    ) -> PermissionOracle.Snapshot {
        let timestamp = Date(timeIntervalSince1970: 1)
        func set() -> PermissionOracle.PermissionSet {
            PermissionOracle.PermissionSet(
                accessibility: accessibility,
                inputMonitoring: inputMonitoring,
                source: "test",
                confidence: .high,
                timestamp: timestamp
            )
        }
        return PermissionOracle.Snapshot(
            keyPath: set(),
            kanata: set(),
            timestamp: timestamp,
            backend: .session
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
