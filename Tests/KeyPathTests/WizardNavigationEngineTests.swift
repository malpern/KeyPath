import KeyPathCore
import KeyPathWizardCore
import ServiceManagement
@preconcurrency import XCTest

@testable import KeyPathAppKit

// Mock SMAppService that reports helper as installed and enabled
private struct MockEnabledSMAppService: SMAppServiceProtocol {
    var status: SMAppService.Status { .enabled }
    func register() throws {}
    func unregister() async throws {}
}

// Mock SMAppService that reports helper needs Login Items approval
private struct MockRequiresApprovalSMAppService: SMAppServiceProtocol {
    var status: SMAppService.Status { .requiresApproval }
    func register() throws {}
    func unregister() async throws {}
}

// Mock SMAppService that reports helper is not registered
private struct MockNotRegisteredSMAppService: SMAppServiceProtocol {
    var status: SMAppService.Status { .notRegistered }
    func register() throws {}
    func unregister() async throws {}
}

class WizardNavigationEngineTests: XCTestCase {
    var engine: WizardNavigationEngine!
    var originalSMServiceFactory: ((String) -> SMAppServiceProtocol)!
    var originalRunnerFactory: (() -> SubprocessRunning)!

    override func setUp() async throws {
        try await super.setUp()
        let newEngine = WizardNavigationEngine()
        engine = newEngine
        await MainActor.run {
            newEngine.markFDAPageShown()
        }

        // Save original factory and inject mock that reports helper as enabled
        // This prevents tests from routing to .helper page unexpectedly
        originalSMServiceFactory = HelperManager.smServiceFactory
        HelperManager.smServiceFactory = { _ in MockEnabledSMAppService() }

        originalRunnerFactory = HelperManager.subprocessRunnerFactory
        HelperManager.subprocessRunnerFactory = { SubprocessRunnerFake.shared }
        await SubprocessRunnerFake.shared.reset()
    }

    override func tearDown() async throws {
        // Restore original factory
        HelperManager.smServiceFactory = originalSMServiceFactory
        originalSMServiceFactory = nil
        HelperManager.subprocessRunnerFactory = originalRunnerFactory
        originalRunnerFactory = nil
        engine = nil
        try await super.tearDown()
    }

    // MARK: - Navigation Priority Tests

    func testNavigationPriorityConflictsFirst() async {
        // Given: System has conflicts and other issues
        let conflictIssue = createTestIssue(category: .conflicts, title: "Test Conflict")
        let permissionIssue = createTestIssue(category: .permissions, title: "Test Permission")
        let issues = [conflictIssue, permissionIssue]

        // When: Determining current page
        let page = await engine.determineCurrentPage(for: .conflictsDetected(conflicts: []), issues: issues)

        // Then: Should navigate to conflicts first
        XCTAssertEqual(page, .conflicts, "Conflicts should have highest priority")
    }

    func testNavigationPriorityHelperSecond() async {
        // Given: Helper needs approval (mock returns requiresApproval)
        // Temporarily override to simulate approval needed
        HelperManager.smServiceFactory = { _ in MockRequiresApprovalSMAppService() }

        let componentIssue = createTestIssue(
            category: .installation,
            title: "Kanata Binary Missing",
            identifier: .component(.kanataBinaryMissing)
        )
        let permissionIssue = createTestIssue(category: .permissions, title: "Test Permission")
        let issues = [componentIssue, permissionIssue]

        // When: Determining current page
        let page = await engine.determineCurrentPage(for: .missingComponents(missing: []), issues: issues)

        // Then: Should navigate to helper first (blocks other steps)
        XCTAssertEqual(page, .helper, "Helper should have second highest priority when approval needed")

        // Restore enabled mock
        HelperManager.smServiceFactory = { _ in MockEnabledSMAppService() }
    }

    func testNavigationPriorityInstallationAfterHelper() async {
        // Given: Helper is enabled (from setUp), system has component issues but no conflicts
        let componentIssue = createTestIssue(
            category: .installation,
            title: "Kanata Binary Missing",
            identifier: .component(.kanataBinaryMissing)
        )
        let permissionIssue = createTestIssue(category: .permissions, title: "Test Permission")
        let issues = [componentIssue, permissionIssue]

        // When: Determining current page (helper is mocked as enabled)
        let page = await engine.determineCurrentPage(for: .missingComponents(missing: []), issues: issues)

        // Then: Should navigate to kanata components (helper is satisfied)
        XCTAssertEqual(page, .kanataComponents, "Installation should be shown when helper is satisfied")
    }

    func testNavigationPriorityInputMonitoringThird() async {
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
        let page = await engine.determineCurrentPage(for: .missingPermissions(missing: []), issues: issues)

        // Then: Should navigate to input monitoring before accessibility
        XCTAssertEqual(page, .inputMonitoring, "Input monitoring should come before accessibility")
    }

    func testNavigationPriorityAccessibilityFourth() async {
        // Given: System has accessibility issues but no input monitoring issues
        let accessibilityIssue = createTestIssue(
            category: .permissions,
            title: "Kanata Accessibility",
            identifier: .permission(.kanataAccessibility)
        )
        let issues = [accessibilityIssue]

        // When: Determining current page
        let page = await engine.determineCurrentPage(for: .missingPermissions(missing: []), issues: issues)

        // Then: Should navigate to accessibility
        XCTAssertEqual(
            page, .accessibility, "Should navigate to accessibility when no input monitoring issues"
        )
    }

    func testNavigationDoesNotRouteToPermissionsForWarningOnly() async {
        // Given: Only a non-blocking permission warning (e.g. Kanata permissions not verified without FDA)
        let warningIssue = WizardIssue(
            identifier: .permission(.kanataInputMonitoring),
            severity: .warning,
            category: .permissions,
            title: "Kanata Input Monitoring (Not Verified)",
            description: "Not verified without Full Disk Access",
            autoFixAction: nil,
            userAction: nil
        )

        // When: System is otherwise ready but service not running
        let page = await engine.determineCurrentPage(for: .serviceNotRunning, issues: [warningIssue])

        // Then: Should route to service (not force the permission page)
        XCTAssertEqual(page, .service)
    }

    func testNavigationWarningOnlyDoesNotShowFDAPageWhenActive() async {
        // Given: Only a non-blocking permission warning (kanata not verified, e.g. no FDA)
        let warningIssue = WizardIssue(
            identifier: .permission(.kanataInputMonitoring),
            severity: .warning,
            category: .permissions,
            title: "Kanata Input Monitoring (Not Verified)",
            description: "Not verified without Full Disk Access",
            autoFixAction: nil,
            userAction: nil
        )

        // When: System is active
        let page = await engine.determineCurrentPage(for: .active, issues: [warningIssue])

        // Then: Should land on summary (and NOT show the optional FDA page when active)
        XCTAssertEqual(page, .summary)
    }

    func testNavigationServiceNotRunning() async {
        // Given: System is ready but service not running
        let issues: [WizardIssue] = []

        // When: Determining current page with service not running state
        let page = await engine.determineCurrentPage(for: .serviceNotRunning, issues: issues)

        // Then: Should navigate to service page
        XCTAssertEqual(page, .service, "Should navigate to service page when service not running")
    }

    func testNavigationReadyState() async {
        // Given: System is ready (all components installed, service not started)
        let issues: [WizardIssue] = []

        // When: Determining current page with ready state
        let page = await engine.determineCurrentPage(for: .ready, issues: issues)

        // Then: Should navigate to service page
        XCTAssertEqual(page, .service, "Should navigate to service page when ready to start service")
    }

    func testNavigationNoIssues() async {
        // Given: No issues and active state
        let issues: [WizardIssue] = []

        // When: Determining current page
        let page = await engine.determineCurrentPage(for: .active, issues: issues)

        // Then: Should navigate to summary
        XCTAssertEqual(page, .summary, "Should navigate to summary when no issues")
    }

    // MARK: - Page Order Tests

    func testPageOrder() async {
        // Given: Navigation engine
        let expectedOrder: [WizardPage] = [
            .summary, // Overview
            .kanataMigration, // Migrate existing Kanata configs
            .stopExternalKanata, // Stop external Kanata before setup
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
        let actualOrder = await engine.getPageOrder()

        // Then: Should match expected order
        XCTAssertEqual(actualOrder, expectedOrder, "Page order should follow expected flow")
    }

    func testPageIndex() async {
        // Given: Navigation engine

        // When: Getting page indices
        let summaryIndex = await engine.pageIndex(.summary)
        let conflictsIndex = await engine.pageIndex(.conflicts)
        let serviceIndex = await engine.pageIndex(.service)

        // Then: Should return correct indices
        XCTAssertEqual(summaryIndex, 0, "Summary should be first (index 0)")
        XCTAssertEqual(conflictsIndex, 5, "Conflicts should be at index 5")
        XCTAssertEqual(serviceIndex, 10, "Service should be index 10 in the expanded flow")
    }

    // MARK: - Blocking Page Tests

    func testBlockingPages() async {
        // Given: Navigation engine with helper mocked as enabled (from setUp)

        // When: Checking if pages are blocking
        let conflictsBlocking = await engine.isBlockingPage(.conflicts)
        let installationBlocking = await engine.isBlockingPage(.kanataComponents)
        let helperBlockingWhenEnabled = await engine.isBlockingPage(.helper) // Should NOT block when enabled
        let permissionsBlocking = await engine.isBlockingPage(.inputMonitoring)
        let backgroundServicesBlocking = await engine.isBlockingPage(.service)
        let serviceBlocking = await engine.isBlockingPage(.service)
        let summaryBlocking = await engine.isBlockingPage(.summary)

        // Then: Should correctly identify blocking pages
        XCTAssertTrue(conflictsBlocking, "Conflicts should be blocking")
        XCTAssertTrue(installationBlocking, "Installation should be blocking")
        XCTAssertFalse(helperBlockingWhenEnabled, "Helper should NOT be blocking when enabled")
        XCTAssertFalse(permissionsBlocking, "Permissions should not be blocking")
        XCTAssertFalse(backgroundServicesBlocking, "Background services should not be blocking")
        XCTAssertFalse(serviceBlocking, "Service should not be blocking")
        XCTAssertFalse(summaryBlocking, "Summary should not be blocking")
    }

    func testHelperBlockingWhenApprovalNeeded() async {
        // Given: Helper needs Login Items approval
        HelperManager.smServiceFactory = { _ in MockRequiresApprovalSMAppService() }

        // When: Checking if helper page is blocking
        let helperBlocking = await engine.isBlockingPage(.helper)

        // Then: Helper should be blocking when approval is needed
        XCTAssertTrue(helperBlocking, "Helper should be blocking when Login Items approval required")

        // Restore
        HelperManager.smServiceFactory = { _ in MockEnabledSMAppService() }
    }

    func testHelperBlockingWhenNotInstalled() async {
        // Given: Helper is not registered
        HelperManager.smServiceFactory = { _ in MockNotRegisteredSMAppService() }
        await SubprocessRunnerFake.shared.configureLaunchctlResult { _, _ in
            ProcessResult(
                exitCode: 1,
                stdout: "",
                stderr: "Could not find service",
                duration: 0.01
            )
        }

        // When: Checking if helper page is blocking
        let helperBlocking = await engine.isBlockingPage(.helper)

        // Then: Helper should be blocking when not installed
        XCTAssertTrue(helperBlocking, "Helper should be blocking when not installed")

        // Restore
        HelperManager.smServiceFactory = { _ in MockEnabledSMAppService() }
        await SubprocessRunnerFake.shared.reset()
        HelperManager.subprocessRunnerFactory = { SubprocessRunnerFake.shared }
    }

    // MARK: - Progress Calculation Tests

    func testProgressCalculation() async {
        // Given: Different system states
        let initializingProgress = await engine.calculateProgress(for: .initializing)
        let conflictsProgress = await engine.calculateProgress(for: .conflictsDetected(conflicts: []))
        let readyProgress = await engine.calculateProgress(for: .ready)
        let activeProgress = await engine.calculateProgress(for: .active)

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

    func testProgressDescription() async {
        // Given: Different system states
        let descriptions: [(WizardSystemState, String)] = [
            (.initializing, "Checking system..."),
            (.conflictsDetected(conflicts: []), "Resolving conflicts..."),
            (.ready, "Ready to start..."),
            (.active, "Setup complete!")
        ]

        // When/Then: Each state should have appropriate description
        for (state, expectedDescription) in descriptions {
            let actualDescription = await engine.progressDescription(for: state)
            XCTAssertEqual(
                actualDescription, expectedDescription, "Description for \(state) should match"
            )
        }
    }

    // MARK: - Button State Tests

    func testPrimaryButtonText() async {
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
            let actualText = await engine.primaryButtonText(for: page, state: .initializing)
            XCTAssertEqual(actualText, expectedText, "Button text for \(page) should match")
        }
    }

    func testSummaryButtonTextVariation() async {
        // Given: Summary page with different states
        let activeButtonText = await engine.primaryButtonText(for: .summary, state: .active)
        let serviceNotRunningButtonText = await engine.primaryButtonText(
            for: .summary, state: .serviceNotRunning
        )
        let readyButtonText = await engine.primaryButtonText(for: .summary, state: .ready)

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

    func testNavigationStateCreation() async {
        // Given: Current page and system state
        let currentPage = WizardPage.conflicts
        let systemState = WizardSystemState.conflictsDetected(conflicts: [])
        let issues = [createTestIssue(category: .conflicts, title: "Test Conflict")]

        // When: Creating navigation state
        let navState = await engine.createNavigationState(
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

    func testNextPageLogic() async {
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
        let nextPage = await engine.nextPage(from: currentPage, given: systemState, issues: issues)

        // Then: Should return the target page based on current issues
        XCTAssertEqual(nextPage, .kanataComponents, "Next page should be installation based on issues")
    }

    func testNextPageWhenAlreadyOnTarget() async {
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
        let nextPage = await engine.nextPage(from: currentPage, given: systemState, issues: issues)

        // Then: Should continue to next page in sequence (.service comes after .kanataComponents)
        XCTAssertEqual(nextPage, .service, "Should continue to next page in sequence")
    }

    func testNextPageNoIssuesSequentialProgression() async {
        // Given: On Input Monitoring page with no issues
        let currentPage = WizardPage.inputMonitoring
        let issues: [WizardIssue] = []
        let systemState = WizardSystemState.active

        // When: Getting next page
        let nextPage = await engine.nextPage(from: currentPage, given: systemState, issues: issues)

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
