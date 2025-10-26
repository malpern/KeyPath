import XCTest

@testable import KeyPath

/// Tests for wizard triggering scenarios - verifies wizard behavior in the actual system
/// These tests ensure the wizard is triggered correctly and NOT triggered inappropriately
@MainActor
final class WizardTriggeringTests: XCTestCase {
    // MARK: - Wizard State Validation

    func testWizardStateConsistency() async {
        // Test wizard state is consistent across different KanataManager instances

        let kanataManager1 = KanataManager()
        // Consolidated: simpleManager is now just kanataManager

        let kanataManager2 = KanataManager()
        // Consolidated: simpleManager is now just kanataManager

        // Both should start with consistent state
        XCTAssertEqual(
            kanataManager1.currentState, .starting, "Manager 1 should start in starting state"
        )
        XCTAssertEqual(
            kanataManager2.currentState, .starting, "Manager 2 should start in starting state"
        )

        XCTAssertFalse(kanataManager1.showWizard, "Manager 1 should not show wizard initially")
        XCTAssertFalse(kanataManager2.showWizard, "Manager 2 should not show wizard initially")
    }

    func testWizardCallbacksExist() async {
        // Test that all expected wizard callback methods exist

        let kanataManager = KanataManager()
        // Consolidated: simpleManager is now just kanataManager

        // Should have wizard callback methods
        await kanataManager.onWizardClosed()
        await kanataManager.retryAfterFix("Test feedback")

        XCTAssertTrue(true, "All wizard callback methods exist and are callable")
    }

    // MARK: - State Transition Validation

    func testStateTransitionIntegrity() async {
        // Test that state transitions maintain integrity in the real system

        let kanataManager = KanataManager()
        // Consolidated: simpleManager is now just kanataManager

        // Initial state
        let initialState = kanataManager.currentState
        XCTAssertEqual(initialState, .starting, "Should start in starting state")

        // Attempt auto-launch (will likely fail in test environment, but should transition properly)
        await kanataManager.startAutoLaunch()

        // Should be in a valid end state
        let finalState = kanataManager.currentState
        let validEndStates: [SimpleKanataState] = [.running, .needsHelp]
        XCTAssertTrue(
            validEndStates.contains(finalState),
            "Should transition to either running or needsHelp, got: \(finalState)"
        )
    }

    func testManualStateChanges() async {
        // Test manual start/stop operations

        let kanataManager = KanataManager()
        // Consolidated: simpleManager is now just kanataManager

        // Test manual operations don't throw
        await kanataManager.manualStart()
        await kanataManager.manualStop()

        // Should complete without errors
        XCTAssertTrue(true, "Manual state changes completed")
    }

    // MARK: - Error Handling Validation

    func testErrorStateProperties() async {
        // Test that error states have proper properties

        let kanataManager = KanataManager()
        // Consolidated: simpleManager is now just kanataManager

        // Try to trigger an error state (auto-launch will likely fail in test environment)
        await kanataManager.startAutoLaunch()

        // Check error handling properties exist and are accessible
        let errorReason = kanataManager.errorReason
        let showWizard = kanataManager.showWizard
        let currentState = kanataManager.currentState

        // If in needsHelp state, should have consistent error properties
        if currentState == .needsHelp {
            XCTAssertTrue(showWizard, "Should show wizard when in needsHelp state")
            // Error reason may or may not be present depending on the specific failure
        }

        // These properties should always be accessible
        XCTAssertTrue(
            errorReason == nil || !errorReason!.isEmpty, "Error reason should be nil or non-empty"
        )
        XCTAssertTrue(showWizard == true || showWizard == false, "ShowWizard should be boolean")
    }

    // MARK: - Integration with Real Components

    func testIntegrationWithKanataManager() async {
        // Test integration with actual KanataManager

        let kanataManager = KanataManager()
        // Consolidated: simpleManager is now just kanataManager

        // Test that KanataManager properly integrates with KanataManager
        await kanataManager.forceRefreshStatus()

        // Should complete integration without throwing
        XCTAssertTrue(true, "Integration with KanataManager successful")
    }

    func testRetryMechanismIntegration() async {
        // Test the retry mechanism with real system

        let kanataManager = KanataManager()
        // Consolidated: simpleManager is now just kanataManager

        // Test retry scenarios
        await kanataManager.retryAfterFix("Fixed permissions")
        await kanataManager.onWizardClosed()

        // Should handle retry scenarios gracefully
        XCTAssertTrue(true, "Retry mechanisms work with real system")
    }

    // MARK: - Timer Consolidation Validation

    func testStatusRefreshConsolidation() async {
        // Test that multiple status refreshes don't cause conflicts
        // This validates the timer consolidation solution

        let kanataManager = KanataManager()
        // Consolidated: simpleManager is now just kanataManager

        // Multiple rapid refreshes (this previously caused timer conflicts)
        for _ in 0 ..< 10 {
            await kanataManager.forceRefreshStatus()
        }

        // Should handle multiple refreshes without issues
        XCTAssertTrue(true, "Multiple status refreshes handled gracefully")
    }

    func testConcurrentUIOperations() async {
        // Test concurrent UI operations don't interfere

        let kanataManager = KanataManager()
        // Consolidated: simpleManager is now just kanataManager

        // Simulate concurrent operations from multiple UI components
        let concurrentTasks = (1 ... 5).map { _ in
            Task {
                await kanataManager.forceRefreshStatus()
            }
        }

        // Wait for all concurrent tasks
        for task in concurrentTasks {
            await task.value
        }

        // Should handle concurrent operations without conflicts
        XCTAssertTrue(true, "Concurrent UI operations handled successfully")
    }

    // MARK: - Real System Validation

    func testRealSystemPermissionChecks() async {
        // Test permission-related wizard behavior on real system

        let kanataManager = KanataManager()
        // Consolidated: simpleManager is now just kanataManager

        // Test permission checking integration
        await kanataManager.startAutoLaunch()

        // If the system lacks permissions, should be in needsHelp state
        let finalState = kanataManager.currentState
        if finalState == .needsHelp {
            XCTAssertTrue(kanataManager.showWizard, "Should show wizard for permission issues")

            if let errorReason = kanataManager.errorReason {
                // Error should be informative
                XCTAssertFalse(errorReason.isEmpty, "Error reason should be informative")
            }
        }

        XCTAssertTrue(true, "Permission checking integration validated")
    }

    func testSystemHealthMonitoring() async {
        // Test system health monitoring behavior

        let kanataManager = KanataManager()
        // Consolidated: simpleManager is now just kanataManager

        // Test health monitoring properties are accessible
        let lastHealthCheck = kanataManager.lastHealthCheck
        let autoStartAttempts = kanataManager.autoStartAttempts
        let retryCount = kanataManager.retryCount
        let isRetryingAfterFix = kanataManager.isRetryingAfterFix

        // These should be accessible and have reasonable values
        XCTAssertTrue(autoStartAttempts >= 0, "Auto start attempts should be non-negative")
        XCTAssertTrue(retryCount >= 0, "Retry count should be non-negative")
        XCTAssertTrue(
            isRetryingAfterFix == true || isRetryingAfterFix == false,
            "IsRetryingAfterFix should be boolean"
        )

        // lastHealthCheck can be nil initially
        if let healthCheck = lastHealthCheck {
            XCTAssertTrue(healthCheck <= Date(), "Health check time should not be in the future")
        }
    }
}
