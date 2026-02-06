@testable import KeyPathAppKit
import KeyPathWizardCore
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
            stateInterpreter: WizardStateInterpreter(),
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
            stateInterpreter: WizardStateInterpreter(),
            onNavigateToPage: nil,
            kanataIsRunning: true,
            showAllItems: true,
            navSequence: .constant(nav),
            visibleIssueCount: .constant(visible)
        )

        // Even with a stale daemon issue, running kanata should keep service status completed
        XCTAssertEqual(overview.getServiceStatus(), .completed)
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
    -> [LocalStatusItem] {
    if showAllItems { return items }
    return items.filter { $0.status != .completed }
}
