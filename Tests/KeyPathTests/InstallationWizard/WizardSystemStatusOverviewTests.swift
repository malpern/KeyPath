import XCTest
@testable import KeyPathAppKit
import KeyPathWizardCore

@MainActor
final class WizardSystemStatusOverviewTests: XCTestCase {
  func testFilteredDisplayItemsKeepsDependentRows() {
    let items = [
      StatusItemModel(
        id: "privileged-helper",
        icon: "lock",
        title: "Privileged Helper",
        status: .failed,
        isNavigable: true,
        targetPage: .helper
      ),
      StatusItemModel(
        id: "kanata-service",
        icon: "antenna.radiowaves.left.and.right",
        title: "Background Services",
        status: .failed,
        isNavigable: true,
        targetPage: .service
      )
    ]

    let filtered = WizardSystemStatusOverview.filteredDisplayItems(items, showAllItems: false)

    XCTAssertEqual(filtered.map(\.id), ["privileged-helper", "kanata-service"])
    XCTAssertEqual(filtered.count, 2, "Dependent rows should remain visible in filtered view")
  }

  func testServiceStatusStaysCompletedWhenKanataRunning() {
    var nav: [WizardPage] = []
    var visible = 0
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

    var nav: [WizardPage] = []
    var visible = 0
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
