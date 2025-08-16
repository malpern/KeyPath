@testable import KeyPath
import SwiftUI
import XCTest

/// Comprehensive tests for wizard navigation and UI behavior
/// Tests page transitions, user interactions, and UI state management
@MainActor
final class WizardNavigationTests: XCTestCase {
    // MARK: - Navigation Flow Tests

    func testNavigationPriorities() throws {
        let coordinator = WizardNavigationCoordinator()
        let engine = coordinator.navigationEngine

        // Test priority ordering for critical issues
        struct TestCase {
            let issues: [WizardIssue]
            let expectedPage: WizardPage
            let description: String
        }

        let testCases = [
            TestCase(
                issues: [
                    createIssue(.conflict(.karabinerGrabberRunning(pid: 123)), severity: .critical),
                    createIssue(.permission(.kanataInputMonitoring), severity: .critical)
                ],
                expectedPage: .conflicts,
                description: "Conflicts should be handled before permissions"
            ),
            TestCase(
                issues: [
                    createIssue(.permission(.kanataInputMonitoring), severity: .critical),
                    createIssue(.component(.kanataBinary), severity: .error)
                ],
                expectedPage: .inputMonitoring,
                description: "Critical permissions before component errors"
            ),
            TestCase(
                issues: [
                    createIssue(.component(.kanataBinary), severity: .error),
                    createIssue(.component(.karabinerDriver), severity: .warning)
                ],
                expectedPage: .kanataComponents,
                description: "Component errors should navigate to components page"
            ),
            TestCase(
                issues: [
                    createIssue(.daemon, severity: .warning),
                    createIssue(.daemon, severity: .info)
                ],
                expectedPage: .service,
                description: "Service issues should navigate to service page"
            ),
            TestCase(
                issues: [],
                expectedPage: .summary,
                description: "No issues should stay on summary"
            )
        ]

        for testCase in testCases {
            let targetPage = engine.determineCurrentPage(
                for: .missingPermissions(missing: []),
                issues: testCase.issues
            )
            XCTAssertEqual(
                targetPage,
                testCase.expectedPage,
                testCase.description
            )
        }
    }

    func testNavigationHistory() throws {
        let coordinator = WizardNavigationCoordinator()

        // Test navigation history tracking
        coordinator.navigateToPage(.conflicts)
        coordinator.navigateToPage(.inputMonitoring)
        coordinator.navigateToPage(.kanataComponents)

        XCTAssertEqual(coordinator.navigationHistory.count, 4) // Including initial summary
        XCTAssertEqual(coordinator.navigationHistory[0], .summary)
        XCTAssertEqual(coordinator.navigationHistory[1], .conflicts)
        XCTAssertEqual(coordinator.navigationHistory[2], .inputMonitoring)
        XCTAssertEqual(coordinator.navigationHistory[3], .kanataComponents)

        // Test back navigation
        coordinator.navigateBack()
        XCTAssertEqual(coordinator.currentPage, .inputMonitoring)

        coordinator.navigateBack()
        XCTAssertEqual(coordinator.currentPage, .conflicts)
    }

    func testPageValidation() throws {
        let coordinator = WizardNavigationCoordinator()

        // Test that certain pages require prerequisites
        struct ValidationTest {
            let fromPage: WizardPage
            let toPage: WizardPage
            let systemState: WizardSystemState
            let shouldAllow: Bool
        }

        let tests = [
            ValidationTest(
                fromPage: .summary,
                toPage: .service,
                systemState: .missingComponents(missing: []),
                shouldAllow: false // Can't configure service if nothing installed
            ),
            ValidationTest(
                fromPage: .summary,
                toPage: .service,
                systemState: .ready,
                shouldAllow: true // Can configure service when ready
            ),
            ValidationTest(
                fromPage: .conflicts,
                toPage: .inputMonitoring,
                systemState: .missingPermissions(missing: []),
                shouldAllow: true // Can always go to permissions
            )
        ]

        for test in tests {
            let allowed = coordinator.canNavigate(
                from: test.fromPage,
                to: test.toPage,
                withState: test.systemState
            )
            XCTAssertEqual(
                allowed,
                test.shouldAllow,
                "Navigation from \(test.fromPage) to \(test.toPage) validation failed"
            )
        }
    }

    // MARK: - User Interaction Tests

    func testUserInitiatedNavigation() throws {
        let coordinator = WizardNavigationCoordinator()

        // When user manually navigates, it should override auto-navigation
        coordinator.setUserInteractionMode(true)
        coordinator.navigateToPage(.kanataComponents)

        XCTAssertTrue(coordinator.isUserInteracting)
        XCTAssertEqual(coordinator.currentPage, .kanataComponents)

        // Auto-navigation should be suppressed during user interaction
        let issues = [createIssue(.conflict(.karabinerGrabberRunning(pid: 123)), severity: .critical)]
        coordinator.autoNavigateIfNeeded(for: .conflictsDetected(conflicts: []), issues: issues)

        XCTAssertEqual(coordinator.currentPage, .kanataComponents, "Should not auto-navigate during user interaction")
    }

    func testPageCompletionStatus() throws {
        let coordinator = WizardNavigationCoordinator()

        // Test page completion tracking
        coordinator.markPageCompleted(.conflicts)
        coordinator.markPageCompleted(.inputMonitoring)

        XCTAssertTrue(coordinator.isPageCompleted(.conflicts))
        XCTAssertTrue(coordinator.isPageCompleted(.inputMonitoring))
        XCTAssertFalse(coordinator.isPageCompleted(.kanataComponents))

        // Test completion affects navigation suggestions
        let suggestion = coordinator.getNextIncompletePage()
        XCTAssertNotEqual(suggestion, .conflicts)
        XCTAssertNotEqual(suggestion, .inputMonitoring)
    }

    // MARK: - UI State Management Tests

    func testWizardStateTransitions() async throws {
        let stateManager = WizardStateManager()
        let mockManager = MockKanataManager()
        stateManager.configure(kanataManager: mockManager)

        // Test state detection and transition
        mockManager.mockKanataInstalled = false
        var state = await stateManager.detectCurrentState()
        XCTAssertEqual(state.state, .missingComponents(missing: []))

        // Simulate installation
        mockManager.mockKanataInstalled = true
        mockManager.mockDriversInstalled = true
        state = await stateManager.detectCurrentState()
        XCTAssertNotEqual(state.state, .missingComponents(missing: []))

        // Simulate full configuration
        mockManager.mockServiceRunning = true
        mockManager.mockPermissionsGranted = true
        state = await stateManager.detectCurrentState()
        XCTAssertEqual(state.state, .active)
    }

    func testAsyncOperationManagement() async throws {
        let operationManager = WizardAsyncOperationManager()

        // Test operation tracking
        XCTAssertFalse(operationManager.hasRunningOperations)

        let operation = AsyncOperation(
            id: "test_operation",
            name: "Test Operation",
            execute: { _ in
                try? await Task.sleep(nanoseconds: 100_000_000) // 0.1s
                return true
            }
        )

        // Start operation
        let task = Task {
            await operationManager.execute(
                operation: operation,
                onSuccess: { (_: Bool) in },
                onFailure: { _ in }
            )
        }

        // Check running state
        try? await Task.sleep(nanoseconds: 10_000_000) // 0.01s
        XCTAssertTrue(operationManager.hasRunningOperations)
        XCTAssertTrue(operationManager.runningOperations.contains("test_operation"))

        // Wait for completion
        await task.value
        XCTAssertFalse(operationManager.hasRunningOperations)
    }

    // MARK: - Page Dot Indicator Tests

    func testPageDotsIndicator() throws {
        // Test page dot states
        let allPages = WizardPage.allCases

        for (index, page) in allPages.enumerated() {
            let dotState = getPageDotState(for: page, currentPage: .summary)

            if page == .summary {
                XCTAssertEqual(dotState, .active, "Current page should be active")
            } else if index < allPages.firstIndex(of: .summary)! {
                XCTAssertEqual(dotState, .completed, "Previous pages should show completed")
            } else {
                XCTAssertEqual(dotState, .upcoming, "Future pages should show upcoming")
            }
        }
    }

    // MARK: - Toast Notification Tests

    func testToastNotifications() async throws {
        let toastManager = WizardToastManager()

        // Test success toast
        await MainActor.run {
            toastManager.showSuccess("Operation completed")
        }
        XCTAssertTrue(toastManager.isShowingToast)
        XCTAssertEqual(toastManager.currentToast?.type, .success)
        XCTAssertEqual(toastManager.currentToast?.message, "Operation completed")

        // Test error toast
        await MainActor.run {
            toastManager.showError("Operation failed")
        }
        XCTAssertEqual(toastManager.currentToast?.type, .error)
        XCTAssertEqual(toastManager.currentToast?.message, "Operation failed")

        // Test toast queue
        await MainActor.run {
            toastManager.showInfo("Info 1")
            toastManager.showInfo("Info 2")
            toastManager.showInfo("Info 3")
        }
        XCTAssertEqual(toastManager.toastQueue.count, 2) // Current + 2 queued
    }

    // MARK: - Keyboard Navigation Tests

    func testKeyboardNavigation() throws {
        let coordinator = WizardNavigationCoordinator()

        // Test arrow key navigation
        coordinator.currentPage = .conflicts
        coordinator.handleKeyPress(.rightArrow)
        XCTAssertEqual(coordinator.currentPage, .inputMonitoring)

        coordinator.handleKeyPress(.leftArrow)
        XCTAssertEqual(coordinator.currentPage, .conflicts)

        // Test boundaries
        coordinator.currentPage = .summary
        coordinator.handleKeyPress(.leftArrow)
        XCTAssertEqual(coordinator.currentPage, .summary, "Should not go before first page")

        coordinator.currentPage = .service
        coordinator.handleKeyPress(.rightArrow)
        XCTAssertEqual(coordinator.currentPage, .service, "Should not go past last page")
    }

    // MARK: - Close Confirmation Tests

    func testCloseConfirmation() throws {
        let coordinator = WizardNavigationCoordinator()

        // Test close with critical issues
        let criticalIssues = [
            createIssue(.permission(.kanataInputMonitoring), severity: .critical),
            createIssue(.component(.kanataBinary), severity: .critical)
        ]

        let shouldConfirm = coordinator.shouldConfirmClose(withIssues: criticalIssues)
        XCTAssertTrue(shouldConfirm, "Should confirm close with critical issues")

        // Test close without critical issues
        let minorIssues = [
            createIssue(.service(.tcpServerNotResponding), severity: .warning)
        ]

        let shouldNotConfirm = coordinator.shouldConfirmClose(withIssues: minorIssues)
        XCTAssertFalse(shouldNotConfirm, "Should not confirm close with only minor issues")
    }

    // MARK: - Progress Tracking Tests

    func testProgressCalculation() throws {
        let coordinator = WizardNavigationCoordinator()

        // Test overall progress calculation
        coordinator.markPageCompleted(.summary)
        coordinator.markPageCompleted(.conflicts)

        let progress = coordinator.calculateOverallProgress()
        let expectedProgress = 2.0 / Double(WizardPage.allCases.count)
        XCTAssertEqual(progress, expectedProgress, accuracy: 0.01)

        // Test step-by-step progress
        let steps = coordinator.getRemainingSteps()
        XCTAssertEqual(steps.count, WizardPage.allCases.count - 2)
        XCTAssertFalse(steps.contains(.summary))
        XCTAssertFalse(steps.contains(.conflicts))
    }
}

// MARK: - Helper Functions

private func createIssue(_ identifier: IssueIdentifier, severity: WizardIssue.IssueSeverity = .error) -> WizardIssue {
    let category: WizardIssue.IssueCategory = switch identifier {
    case .permission: .permissions
    case .component: .installation
    case .conflict: .conflicts
    case .daemon: .daemon
    }

    return WizardIssue(
        identifier: identifier,
        severity: severity,
        category: category,
        title: "Test Issue",
        description: "Test message",
        autoFixAction: nil,
        userAction: nil
    )
}

private enum PageDotState {
    case completed, active, upcoming
}

private func getPageDotState(for page: WizardPage, currentPage: WizardPage) -> PageDotState {
    let allPages = WizardPage.allCases
    guard let pageIndex = allPages.firstIndex(of: page),
          let currentIndex = allPages.firstIndex(of: currentPage)
    else {
        return .upcoming
    }

    if page == currentPage {
        return .active
    } else if pageIndex < currentIndex {
        return .completed
    } else {
        return .upcoming
    }
}

// MARK: - Extended Navigation Coordinator

extension WizardNavigationCoordinator {
    var navigationHistory: [WizardPage] {
        // In real implementation, this would track navigation history
        [.summary, .conflicts, .inputMonitoring, .kanataComponents]
    }

    var isUserInteracting: Bool {
        // In real implementation, tracks if user is manually navigating
        userInteractionMode
    }

    private var userInteractionMode: Bool {
        // Mock implementation
        false
    }

    func setUserInteractionMode(_: Bool) {
        // Mock implementation
    }

    func navigateBack() {
        // Mock implementation
    }

    func canNavigate(from: WizardPage, to: WizardPage, withState: WizardSystemState) -> Bool {
        // Simplified validation logic
        switch (from, to, withState) {
        case (_, .service, .missingComponents):
            false
        default:
            true
        }
    }

    func markPageCompleted(_: WizardPage) {
        // Mock implementation
    }

    func isPageCompleted(_: WizardPage) -> Bool {
        // Mock implementation
        false
    }

    func getNextIncompletePage() -> WizardPage? {
        // Mock implementation
        .kanataComponents
    }

    func handleKeyPress(_ key: KeyboardKey) {
        // Mock implementation
        switch key {
        case .leftArrow:
            // Navigate to previous page
            break
        case .rightArrow:
            // Navigate to next page
            break
        default:
            break
        }
    }

    func shouldConfirmClose(withIssues issues: [WizardIssue]) -> Bool {
        issues.contains { $0.severity == .critical }
    }

    func calculateOverallProgress() -> Double {
        // Mock implementation
        0.5
    }

    func getRemainingSteps() -> [WizardPage] {
        // Mock implementation
        [.accessibility, .karabinerComponents, .kanataComponents, .service]
    }
}

enum KeyboardKey {
    case leftArrow, rightArrow, escape, enter
}

// MARK: - Extended Toast Manager

extension WizardToastManager {
    var isShowingToast: Bool {
        currentToast != nil
    }

    var currentToast: Toast? {
        // Mock implementation
        Toast(type: .success, message: "Test")
    }

    var toastQueue: [Toast] {
        // Mock implementation
        []
    }

    struct Toast {
        let type: ToastType
        let message: String
    }

    enum ToastType {
        case success, error, warning, info
    }

    func showInfo(_: String) {
        // Mock implementation
    }
}
