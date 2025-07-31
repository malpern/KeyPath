import XCTest
@testable import KeyPath

/// Tests for wizard navigation logic
/// Following our testing best practices: Testing BEHAVIOR, not implementation
class WizardNavigationEngineTests: XCTestCase {
    
    var navigationEngine: WizardNavigationEngine!
    
    override func setUp() {
        super.setUp()
        navigationEngine = WizardNavigationEngine()
    }
    
    // MARK: - Page Determination Tests (Real Business Logic)
    
    func testDeterminesCorrectPageForInitializing() {
        // Given: System is initializing
        let state: WizardSystemState = .initializing
        
        // When: Determining current page
        let page = navigationEngine.determineCurrentPage(for: state)
        
        // Then: Should show summary page during initialization
        XCTAssertEqual(page, .summary, "Should show summary page when initializing")
    }
    
    func testDeterminesCorrectPageForConflicts() {
        // Given: System has conflicts
        let conflicts: [SystemConflict] = [.kanataProcessRunning(pid: 123, command: "kanata")]
        let state: WizardSystemState = .conflictsDetected(conflicts: conflicts)
        
        // When: Determining current page
        let page = navigationEngine.determineCurrentPage(for: state)
        
        // Then: Should show conflicts page
        XCTAssertEqual(page, .conflicts, "Should show conflicts page when conflicts detected")
    }
    
    func testDeterminesCorrectPageForMissingPermissions() {
        // Given: Missing input monitoring permissions
        let missing: [PermissionRequirement] = [.keyPathInputMonitoring, .kanataInputMonitoring]
        let state: WizardSystemState = .missingPermissions(missing: missing)
        
        // When: Determining current page
        let page = navigationEngine.determineCurrentPage(for: state)
        
        // Then: Should show input monitoring page (prioritized first)
        XCTAssertEqual(page, .inputMonitoring, "Should prioritize input monitoring permissions")
    }
    
    func testDeterminesCorrectPageForMissingAccessibilityOnly() {
        // Given: Missing only accessibility permissions
        let missing: [PermissionRequirement] = [.keyPathAccessibility, .kanataAccessibility]
        let state: WizardSystemState = .missingPermissions(missing: missing)
        
        // When: Determining current page
        let page = navigationEngine.determineCurrentPage(for: state)
        
        // Then: Should show accessibility page
        XCTAssertEqual(page, .accessibility, "Should show accessibility page when only accessibility missing")
    }
    
    func testDeterminesCorrectPageForMissingComponents() {
        // Given: Missing components
        let missing: [ComponentRequirement] = [.kanataBinary]
        let state: WizardSystemState = .missingComponents(missing: missing)
        
        // When: Determining current page
        let page = navigationEngine.determineCurrentPage(for: state)
        
        // Then: Should show installation page
        XCTAssertEqual(page, .installation, "Should show installation page when components missing")
    }
    
    func testDeterminesCorrectPageForDaemonNotRunning() {
        // Given: Daemon not running
        let state: WizardSystemState = .daemonNotRunning
        
        // When: Determining current page
        let page = navigationEngine.determineCurrentPage(for: state)
        
        // Then: Should show daemon page
        XCTAssertEqual(page, .daemon, "Should show daemon page when daemon not running")
    }
    
    func testDeterminesCorrectPageForServiceStates() {
        // Given: Various service states
        let serviceNotRunning: WizardSystemState = .serviceNotRunning
        let ready: WizardSystemState = .ready
        let active: WizardSystemState = .active
        
        // When: Determining current page for each state
        let serviceNotRunningPage = navigationEngine.determineCurrentPage(for: serviceNotRunning)
        let readyPage = navigationEngine.determineCurrentPage(for: ready)
        let activePage = navigationEngine.determineCurrentPage(for: active)
        
        // Then: Should all show summary page
        XCTAssertEqual(serviceNotRunningPage, .summary, "Should show summary when service not running")
        XCTAssertEqual(readyPage, .summary, "Should show summary when ready")
        XCTAssertEqual(activePage, .summary, "Should show summary when active")
    }
    
    // MARK: - Navigation State Tests (Real Business Logic)
    
    func testCreatesCorrectNavigationStateWhenOnTargetPage() {
        // Given: Currently on conflicts page with conflicts detected
        let currentPage: WizardPage = .conflicts
        let conflicts: [SystemConflict] = [.kanataProcessRunning(pid: 123, command: "kanata")]
        let systemState: WizardSystemState = .conflictsDetected(conflicts: conflicts)
        
        // When: Creating navigation state
        let navState = navigationEngine.createNavigationState(currentPage: currentPage, systemState: systemState)
        
        // Then: Should not need auto-navigation (already on correct page)
        XCTAssertEqual(navState.currentPage, currentPage, "Should preserve current page")
        XCTAssertFalse(navState.shouldAutoNavigate, "Should not auto-navigate when on correct page")
        XCTAssertTrue(navState.canNavigatePrevious, "Should allow manual navigation")
    }
    
    func testCreatesCorrectNavigationStateWhenNotOnTargetPage() {
        // Given: Currently on summary page but have conflicts
        let currentPage: WizardPage = .summary
        let conflicts: [SystemConflict] = [.kanataProcessRunning(pid: 123, command: "kanata")]
        let systemState: WizardSystemState = .conflictsDetected(conflicts: conflicts)
        
        // When: Creating navigation state
        let navState = navigationEngine.createNavigationState(currentPage: currentPage, systemState: systemState)
        
        // Then: Should suggest auto-navigation to conflicts page
        XCTAssertEqual(navState.currentPage, currentPage, "Should preserve current page")
        XCTAssertTrue(navState.shouldAutoNavigate, "Should auto-navigate to correct page")
        XCTAssertTrue(navState.canNavigateNext, "Should allow navigation to next page")
    }
    
    // MARK: - Progress Calculation Tests (Real Business Logic)
    
    func testCalculatesCorrectProgressForEachState() {
        // Given: All possible system states
        let states: [(WizardSystemState, Double)] = [
            (.initializing, 0.0),
            (.conflictsDetected(conflicts: []), 0.1),
            (.missingComponents(missing: []), 0.2),
            (.missingPermissions(missing: []), 0.5),
            (.daemonNotRunning, 0.8),
            (.serviceNotRunning, 0.9),
            (.ready, 0.9),
            (.active, 1.0)
        ]
        
        // When/Then: Calculate progress for each state
        for (state, expectedProgress) in states {
            let progress = navigationEngine.calculateProgress(for: state)
            XCTAssertEqual(progress, expectedProgress, accuracy: 0.01, 
                          "Progress for \(state) should be \(expectedProgress)")
        }
    }
    
    func testProgressDescriptionsAreUserFriendly() {
        // Given: All possible system states
        let states: [WizardSystemState] = [
            .initializing,
            .conflictsDetected(conflicts: []),
            .missingComponents(missing: []),
            .missingPermissions(missing: []),
            .daemonNotRunning,
            .serviceNotRunning,
            .ready,
            .active
        ]
        
        // When/Then: Get progress description for each state
        for state in states {
            let description = navigationEngine.progressDescription(for: state)
            
            // Should be user-friendly (not empty, not technical)
            XCTAssertFalse(description.isEmpty, "Progress description should not be empty for \(state)")
            XCTAssertFalse(description.contains("nil"), "Progress description should not contain technical terms")
            XCTAssertTrue(description.count > 5, "Progress description should be meaningful for \(state)")
        }
    }
    
    // MARK: - Button State Tests (Real Business Logic)
    
    func testPrimaryButtonTextForConflictsPage() {
        // Given: Conflicts page
        let page: WizardPage = .conflicts
        let state: WizardSystemState = .conflictsDetected(conflicts: [])
        
        // When: Getting button text
        let buttonText = navigationEngine.primaryButtonText(for: page, state: state)
        
        // Then: Should show resolve conflicts text
        XCTAssertEqual(buttonText, "Resolve Conflicts", "Should show appropriate button text for conflicts")
    }
    
    func testPrimaryButtonTextForSummaryPageWithDifferentStates() {
        // Given: Summary page with different system states
        let page: WizardPage = .summary
        
        let activeState: WizardSystemState = .active
        let readyState: WizardSystemState = .ready
        let initializingState: WizardSystemState = .initializing
        
        // When: Getting button text for each state
        let activeButtonText = navigationEngine.primaryButtonText(for: page, state: activeState)
        let readyButtonText = navigationEngine.primaryButtonText(for: page, state: readyState)
        let initializingButtonText = navigationEngine.primaryButtonText(for: page, state: initializingState)
        
        // Then: Should show appropriate text for each state
        XCTAssertEqual(activeButtonText, "Close Setup", "Should show close setup when active")
        XCTAssertEqual(readyButtonText, "Start Kanata Service", "Should show start service when ready")
        XCTAssertEqual(initializingButtonText, "Continue Setup", "Should show continue setup when initializing")
    }
    
    func testPrimaryButtonEnabledStateForConflicts() {
        // Given: Conflicts page with and without conflicts
        let page: WizardPage = .conflicts
        let withConflicts: WizardSystemState = .conflictsDetected(conflicts: [.kanataProcessRunning(pid: 123, command: "kanata")])
        let withoutConflicts: WizardSystemState = .conflictsDetected(conflicts: [])
        
        // When: Checking if button should be enabled
        let enabledWithConflicts = navigationEngine.isPrimaryButtonEnabled(for: page, state: withConflicts)
        let enabledWithoutConflicts = navigationEngine.isPrimaryButtonEnabled(for: page, state: withoutConflicts)
        
        // Then: Should only be enabled when there are conflicts to resolve
        XCTAssertTrue(enabledWithConflicts, "Should enable button when conflicts exist")
        XCTAssertFalse(enabledWithoutConflicts, "Should disable button when no conflicts exist")
    }
    
    func testPrimaryButtonDisabledWhenProcessing() {
        // Given: Any page with processing state
        let page: WizardPage = .conflicts
        let state: WizardSystemState = .conflictsDetected(conflicts: [.kanataProcessRunning(pid: 123, command: "kanata")])
        
        // When: Checking if button should be enabled while processing
        let enabledWhenNotProcessing = navigationEngine.isPrimaryButtonEnabled(for: page, state: state, isProcessing: false)
        let enabledWhenProcessing = navigationEngine.isPrimaryButtonEnabled(for: page, state: state, isProcessing: true)
        
        // Then: Should be disabled when processing
        XCTAssertTrue(enabledWhenNotProcessing, "Should be enabled when not processing")
        XCTAssertFalse(enabledWhenProcessing, "Should be disabled when processing")
    }
    
    // MARK: - Page Ordering Tests (Real Business Logic)
    
    func testPageOrderReflectsLogicalSetupFlow() {
        // When: Getting page order
        let order = navigationEngine.getPageOrder()
        
        // Then: Should follow logical setup sequence
        XCTAssertEqual(order.first, .conflicts, "Should resolve conflicts first")
        XCTAssertTrue(order.contains(.inputMonitoring), "Should include input monitoring permissions")
        XCTAssertTrue(order.contains(.accessibility), "Should include accessibility permissions")
        XCTAssertTrue(order.contains(.installation), "Should include component installation")
        XCTAssertTrue(order.contains(.daemon), "Should include daemon startup")
        XCTAssertEqual(order.last, .summary, "Should end with summary")
        
        // Permissions should come before installation
        let inputMonitoringIndex = order.firstIndex(of: .inputMonitoring)!
        let installationIndex = order.firstIndex(of: .installation)!
        XCTAssertLessThan(inputMonitoringIndex, installationIndex, "Permissions should come before installation")
    }
    
    func testIdentifiesBlockingPagesCorrectly() {
        // Given: All pages
        let allPages = WizardPage.allCases
        
        // When/Then: Check blocking status for each page
        for page in allPages {
            let isBlocking = navigationEngine.isBlockingPage(page)
            
            switch page {
            case .conflicts, .installation:
                XCTAssertTrue(isBlocking, "\(page) should be blocking")
            case .inputMonitoring, .accessibility, .daemon, .summary:
                XCTAssertFalse(isBlocking, "\(page) should not be blocking")
            }
        }
    }
    
    // MARK: - Navigation Flow Tests (Real Business Logic)
    
    func testNextPageLogicForTypicalFlow() {
        // Given: Various current pages and states
        let scenarios: [(WizardPage, WizardSystemState, WizardPage?)] = [
            // If on summary but have conflicts, should go to conflicts
            (.summary, .conflictsDetected(conflicts: [.kanataProcessRunning(pid: 123, command: "kanata")]), .conflicts),
            // If on conflicts page with conflicts, should stay (no next page)
            (.conflicts, .conflictsDetected(conflicts: [.kanataProcessRunning(pid: 123, command: "kanata")]), nil),
            // If on summary when active, should stay (no next page)
            (.summary, .active, nil)
        ]
        
        // When/Then: Test next page logic for each scenario
        for (currentPage, state, expectedNext) in scenarios {
            let nextPage = navigationEngine.nextPage(from: currentPage, given: state)
            XCTAssertEqual(nextPage, expectedNext, 
                          "Next page from \(currentPage) with state \(state) should be \(String(describing: expectedNext))")
        }
    }
    
    // MARK: - Navigation Validation Tests (Real Business Logic)
    
    func testCanAlwaysNavigateManually() {
        // Given: Any two pages
        let fromPage: WizardPage = .summary
        let toPage: WizardPage = .conflicts
        let state: WizardSystemState = .active
        
        // When: Checking if navigation is allowed
        let canNavigate = navigationEngine.canNavigate(from: fromPage, to: toPage, given: state)
        
        // Then: Should always allow manual navigation (users control via page dots)
        XCTAssertTrue(canNavigate, "Should always allow manual navigation between pages")
    }
    
    // MARK: - Button Visibility Tests (Real Business Logic)
    
    func testNextButtonVisibilityLogic() {
        // Given: Different page and state combinations
        let scenarios: [(WizardPage, WizardSystemState, Bool)] = [
            // Should show next when not on final state
            (.conflicts, .conflictsDetected(conflicts: []), true),
            (.installation, .missingComponents(missing: []), true),
            // Should not show next when on summary with active state
            (.summary, .active, false)
        ]
        
        // When/Then: Test next button visibility for each scenario
        for (page, state, shouldShow) in scenarios {
            let showNext = navigationEngine.shouldShowNextButton(for: page, state: state)
            XCTAssertEqual(showNext, shouldShow, 
                          "Next button visibility for \(page) with \(state) should be \(shouldShow)")
        }
    }
    
    func testPreviousButtonVisibilityLogic() {
        // Given: Different page and state combinations
        let normalState: WizardSystemState = .conflictsDetected(conflicts: [])
        let activeState: WizardSystemState = .active
        
        // When: Checking previous button visibility
        let showPrevNormal = navigationEngine.shouldShowPreviousButton(for: .conflicts, state: normalState)
        let showPrevSummaryActive = navigationEngine.shouldShowPreviousButton(for: .summary, state: activeState)
        let showPrevSummaryNormal = navigationEngine.shouldShowPreviousButton(for: .summary, state: normalState)
        
        // Then: Should allow going back except on summary when active
        XCTAssertTrue(showPrevNormal, "Should show previous button on normal pages")
        XCTAssertFalse(showPrevSummaryActive, "Should not show previous on summary when active")
        XCTAssertTrue(showPrevSummaryNormal, "Should show previous on summary when not active")
    }
}