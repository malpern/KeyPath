import KeyPathWizardCore
import XCTest

@testable import KeyPathAppKit

class WizardNavigationEngineTests: XCTestCase {
    var engine: WizardNavigationEngine!

    override func setUp() {
        super.setUp()
        engine = WizardNavigationEngine()
    }

    override func tearDown() {
        engine = nil
        super.tearDown()
    }

    // MARK: - Navigation Priority Tests

    func testNavigationPriorityConflictsFirst() {
        // Given: System has conflicts and other issues
        let conflictIssue = createTestIssue(category: .conflicts, title: "Test Conflict")
        let permissionIssue = createTestIssue(category: .permissions, title: "Test Permission")
        let issues = [conflictIssue, permissionIssue]

        // When: Determining current page
        let page = engine.determineCurrentPage(for: .conflictsDetected(conflicts: []), issues: issues)

        // Then: Should navigate to conflicts first
        XCTAssertEqual(page, .conflicts, "Conflicts should have highest priority")
    }

    func testNavigationPriorityInstallationSecond() {
        // Given: System has component issues but no conflicts
        let componentIssue = createTestIssue(
            category: .installation,
            title: "Kanata Binary Missing",
            identifier: .component(.kanataBinaryMissing)
        )
        let permissionIssue = createTestIssue(category: .permissions, title: "Test Permission")
        let issues = [componentIssue, permissionIssue]

        // When: Determining current page
        let page = engine.determineCurrentPage(for: .missingComponents(missing: []), issues: issues)

        // Then: Should navigate to installation second
        XCTAssertEqual(page, .kanataComponents, "Installation should have second highest priority")
    }

    func testNavigationPriorityInputMonitoringThird() {
        // Given: System has input monitoring issues but no conflicts or installation issues
        let inputMonitoringIssue = createTestIssue(
            category: .permissions,
            title: "Kanata Input Monitoring",
            identifier: .permission(.kanataInputMonitoring)
        )
        let accessibilityIssue = createTestIssue(
            category: .permissions,
            title: "Kanata Accessibility",
            identifier: .permission(.kanataAccessibility)
        )
        let issues = [inputMonitoringIssue, accessibilityIssue]

        // When: Determining current page
        let page = engine.determineCurrentPage(for: .missingPermissions(missing: []), issues: issues)

        // Then: Should navigate to input monitoring before accessibility
        XCTAssertEqual(page, .inputMonitoring, "Input monitoring should come before accessibility")
    }

    func testNavigationPriorityAccessibilityFourth() {
        // Given: System has accessibility issues but no input monitoring issues
        let accessibilityIssue = createTestIssue(
            category: .permissions,
            title: "Kanata Accessibility",
            identifier: .permission(.kanataAccessibility)
        )
        let issues = [accessibilityIssue]

        // When: Determining current page
        let page = engine.determineCurrentPage(for: .missingPermissions(missing: []), issues: issues)

        // Then: Should navigate to accessibility
        XCTAssertEqual(
            page, .accessibility, "Should navigate to accessibility when no input monitoring issues"
        )
    }

    func testNavigationServiceNotRunning() {
        // Given: System is ready but service not running
        let issues: [WizardIssue] = []

        // When: Determining current page with service not running state
        let page = engine.determineCurrentPage(for: .serviceNotRunning, issues: issues)

        // Then: Should navigate to service page
        XCTAssertEqual(page, .service, "Should navigate to service page when service not running")
    }

    func testNavigationReadyState() {
        // Given: System is ready (all components installed, service not started)
        let issues: [WizardIssue] = []

        // When: Determining current page with ready state
        let page = engine.determineCurrentPage(for: .ready, issues: issues)

        // Then: Should navigate to service page
        XCTAssertEqual(page, .service, "Should navigate to service page when ready to start service")
    }

    func testNavigationNoIssues() {
        // Given: No issues and active state
        let issues: [WizardIssue] = []

        // When: Determining current page
        let page = engine.determineCurrentPage(for: .active, issues: issues)

        // Then: Should navigate to summary
        XCTAssertEqual(page, .summary, "Should navigate to summary when no issues")
    }

    // MARK: - Page Order Tests

    func testPageOrder() {
        // Given: Navigation engine
        let expectedOrder: [WizardPage] = [
            .summary, // Overview
            .helper, // Privileged helper installation comes early to avoid repeated prompts
            .fullDiskAccess, // Optional FDA for better diagnostics
            .conflicts, // Must resolve conflicts first
            .accessibility, // Accessibility permission
            .inputMonitoring, // Input Monitoring permission
            .karabinerComponents, // Karabiner driver and VirtualHID setup
            .kanataComponents, // Kanata binary and service setup
            .service, // Start keyboard service
            .communication // Optional TCP/communication verification
        ]

        // When: Getting page order
        let actualOrder = engine.getPageOrder()

        // Then: Should match expected order
        XCTAssertEqual(actualOrder, expectedOrder, "Page order should follow expected flow")
    }

    func testPageIndex() {
        // Given: Navigation engine

        // When: Getting page indices
        let summaryIndex = engine.pageIndex(.summary)
        let conflictsIndex = engine.pageIndex(.conflicts)
        let serviceIndex = engine.pageIndex(.service)

        // Then: Should return correct indices
        XCTAssertEqual(summaryIndex, 0, "Summary should be first (index 0)")
        XCTAssertEqual(conflictsIndex, 3, "Conflicts should be at index 3")
        XCTAssertEqual(serviceIndex, 8, "Service should be index 8 in the expanded flow")
    }

    // MARK: - Blocking Page Tests

    func testBlockingPages() {
        // Given: Navigation engine

        // When: Checking if pages are blocking
        let conflictsBlocking = engine.isBlockingPage(.conflicts)
        let installationBlocking = engine.isBlockingPage(.kanataComponents)
        let permissionsBlocking = engine.isBlockingPage(.inputMonitoring)
        let backgroundServicesBlocking = engine.isBlockingPage(.service)
        let serviceBlocking = engine.isBlockingPage(.service)
        let summaryBlocking = engine.isBlockingPage(.summary)

        // Then: Should correctly identify blocking pages
        XCTAssertTrue(conflictsBlocking, "Conflicts should be blocking")
        XCTAssertTrue(installationBlocking, "Installation should be blocking")
        XCTAssertFalse(permissionsBlocking, "Permissions should not be blocking")
        XCTAssertFalse(backgroundServicesBlocking, "Background services should not be blocking")
        XCTAssertFalse(serviceBlocking, "Service should not be blocking")
        XCTAssertFalse(summaryBlocking, "Summary should not be blocking")
    }

    // MARK: - Progress Calculation Tests

    func testProgressCalculation() {
        // Given: Different system states
        let initializingProgress = engine.calculateProgress(for: .initializing)
        let conflictsProgress = engine.calculateProgress(for: .conflictsDetected(conflicts: []))
        let readyProgress = engine.calculateProgress(for: .ready)
        let activeProgress = engine.calculateProgress(for: .active)

        // Then: Progress should increase appropriately
        XCTAssertEqual(initializingProgress, 0.0, "Initializing should be 0% progress")
        XCTAssertEqual(conflictsProgress, 0.1, "Conflicts detected should be 10% progress")
        XCTAssertEqual(readyProgress, 0.9, "Ready should be 90% progress")
        XCTAssertEqual(activeProgress, 1.0, "Active should be 100% progress")

        // Progress should be monotonically increasing
        XCTAssertLessThan(initializingProgress, conflictsProgress)
        XCTAssertLessThan(conflictsProgress, readyProgress)
        XCTAssertLessThan(readyProgress, activeProgress)
    }

    func testProgressDescription() {
        // Given: Different system states
        let descriptions: [(WizardSystemState, String)] = [
            (.initializing, "Checking system..."),
            (.conflictsDetected(conflicts: []), "Resolving conflicts..."),
            (.ready, "Ready to start..."),
            (.active, "Setup complete!")
        ]

        // When/Then: Each state should have appropriate description
        for (state, expectedDescription) in descriptions {
            let actualDescription = engine.progressDescription(for: state)
            XCTAssertEqual(
                actualDescription, expectedDescription, "Description for \(state) should match"
            )
        }
    }

    // MARK: - Button State Tests

    func testPrimaryButtonText() {
        // Given: Different pages
        let buttonTexts: [(WizardPage, String)] = [
            (.conflicts, "Resolve Conflicts"),
            (.inputMonitoring, "Open System Settings"),
            (.accessibility, "Open System Settings"),
            (.karabinerComponents, "Install Karabiner Components"),
            (.kanataComponents, "Install Kanata Components"),
            (.service, "Start Keyboard Service")
        ]

        // When/Then: Each page should have appropriate button text
        for (page, expectedText) in buttonTexts {
            let actualText = engine.primaryButtonText(for: page, state: .initializing)
            XCTAssertEqual(actualText, expectedText, "Button text for \(page) should match")
        }
    }

    func testSummaryButtonTextVariation() {
        // Given: Summary page with different states
        let activeButtonText = engine.primaryButtonText(for: .summary, state: .active)
        let serviceNotRunningButtonText = engine.primaryButtonText(
            for: .summary, state: .serviceNotRunning
        )
        let readyButtonText = engine.primaryButtonText(for: .summary, state: .ready)

        // Then: Button text should vary based on state
        XCTAssertEqual(activeButtonText, "Close Setup", "Active state should show 'Close Setup'")
        XCTAssertEqual(
            serviceNotRunningButtonText, "Start Kanata Service",
            "Service not running should show 'Start Kanata Service'"
        )
        XCTAssertEqual(
            readyButtonText, "Start Kanata Service", "Ready state should show 'Start Kanata Service'"
        )
    }

    // MARK: - Navigation State Tests

    func testNavigationStateCreation() {
        // Given: Current page and system state
        let currentPage = WizardPage.conflicts
        let systemState = WizardSystemState.conflictsDetected(conflicts: [])
        let issues = [createTestIssue(category: .conflicts, title: "Test Conflict")]

        // When: Creating navigation state
        let navState = engine.createNavigationState(
            currentPage: currentPage,
            systemState: systemState,
            issues: issues
        )

        // Then: Navigation state should be correct
        XCTAssertEqual(navState.currentPage, currentPage)
        XCTAssertEqual(navState.availablePages, WizardPage.allCases)
        XCTAssertTrue(navState.canNavigatePrevious, "Should always allow going back")
    }

    // MARK: - Next Page Logic Tests

    func testNextPageLogic() {
        // Given: Current page and system state with issues
        let currentPage = WizardPage.conflicts
        let issues = [
            createTestIssue(
                category: .installation,
                title: "Kanata Binary Missing",
                identifier: .component(.kanataBinaryMissing)
            )
        ]
        let systemState = WizardSystemState.missingComponents(missing: [])

        // When: Getting next page
        let nextPage = engine.nextPage(from: currentPage, given: systemState, issues: issues)

        // Then: Should return the target page based on current issues
        XCTAssertEqual(nextPage, .kanataComponents, "Next page should be installation based on issues")
    }

    func testNextPageWhenAlreadyOnTarget() {
        // Given: Already on the target page but want to continue sequentially
        let currentPage = WizardPage.kanataComponents
        let issues = [
            createTestIssue(
                category: .installation,
                title: "Kanata Binary Missing",
                identifier: .component(.kanataBinaryMissing)
            )
        ]
        let systemState = WizardSystemState.missingComponents(missing: [])

        // When: Getting next page
        let nextPage = engine.nextPage(from: currentPage, given: systemState, issues: issues)

        // Then: Should continue to next page in sequence (.service comes after .kanataComponents)
        XCTAssertEqual(nextPage, .service, "Should continue to next page in sequence")
    }

    func testNextPageNoIssuesSequentialProgression() {
        // Given: On Input Monitoring page with no issues
        let currentPage = WizardPage.inputMonitoring
        let issues: [WizardIssue] = []
        let systemState = WizardSystemState.active

        // When: Getting next page
        let nextPage = engine.nextPage(from: currentPage, given: systemState, issues: issues)

        // Then: Should advance to next page (Karabiner components now follow input monitoring)
        XCTAssertEqual(nextPage, .karabinerComponents, "Should advance to karabiner components page")
    }

    // MARK: - Helper Methods

    private func createTestIssue(
        category: WizardIssue.IssueCategory,
        title: String,
        identifier: IssueIdentifier = .daemon
    ) -> WizardIssue {
        WizardIssue(
            identifier: identifier,
            severity: .error,
            category: category,
            title: title,
            description: "Test issue description",
            autoFixAction: nil,
            userAction: nil
        )
    }
}
