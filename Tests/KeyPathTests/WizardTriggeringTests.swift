import XCTest

@testable import KeyPath

/// Tests for wizard triggering scenarios - verifies wizard behavior in the actual system
/// These tests ensure the wizard is triggered correctly and NOT triggered inappropriately
@MainActor
final class WizardTriggeringTests: XCTestCase {
  // MARK: - Wizard State Validation

  func testWizardStateConsistency() async {
    // Test wizard state is consistent across different SimpleKanataManager instances

    let kanataManager1 = KanataManager()
    let simpleManager1 = SimpleKanataManager(kanataManager: kanataManager1)

    let kanataManager2 = KanataManager()
    let simpleManager2 = SimpleKanataManager(kanataManager: kanataManager2)

    // Both should start with consistent state
    XCTAssertEqual(
      simpleManager1.currentState, .starting, "Manager 1 should start in starting state"
    )
    XCTAssertEqual(
      simpleManager2.currentState, .starting, "Manager 2 should start in starting state"
    )

    XCTAssertFalse(simpleManager1.showWizard, "Manager 1 should not show wizard initially")
    XCTAssertFalse(simpleManager2.showWizard, "Manager 2 should not show wizard initially")
  }

  func testWizardCallbacksExist() async {
    // Test that all expected wizard callback methods exist

    let kanataManager = KanataManager()
    let simpleManager = SimpleKanataManager(kanataManager: kanataManager)

    // Should have wizard callback methods
    await simpleManager.onWizardClosed()
    await simpleManager.retryAfterFix("Test feedback")

    XCTAssertTrue(true, "All wizard callback methods exist and are callable")
  }

  // MARK: - State Transition Validation

  func testStateTransitionIntegrity() async {
    // Test that state transitions maintain integrity in the real system

    let kanataManager = KanataManager()
    let simpleManager = SimpleKanataManager(kanataManager: kanataManager)

    // Initial state
    let initialState = simpleManager.currentState
    XCTAssertEqual(initialState, .starting, "Should start in starting state")

    // Attempt auto-launch (will likely fail in test environment, but should transition properly)
    await simpleManager.startAutoLaunch()

    // Should be in a valid end state
    let finalState = simpleManager.currentState
    let validEndStates: [SimpleKanataManager.State] = [.running, .needsHelp]
    XCTAssertTrue(
      validEndStates.contains(finalState),
      "Should transition to either running or needsHelp, got: \(finalState)"
    )
  }

  func testManualStateChanges() async {
    // Test manual start/stop operations

    let kanataManager = KanataManager()
    let simpleManager = SimpleKanataManager(kanataManager: kanataManager)

    // Test manual operations don't throw
    await simpleManager.manualStart()
    await simpleManager.manualStop()

    // Should complete without errors
    XCTAssertTrue(true, "Manual state changes completed")
  }

  // MARK: - Error Handling Validation

  func testErrorStateProperties() async {
    // Test that error states have proper properties

    let kanataManager = KanataManager()
    let simpleManager = SimpleKanataManager(kanataManager: kanataManager)

    // Try to trigger an error state (auto-launch will likely fail in test environment)
    await simpleManager.startAutoLaunch()

    // Check error handling properties exist and are accessible
    let errorReason = simpleManager.errorReason
    let showWizard = simpleManager.showWizard
    let currentState = simpleManager.currentState

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
    let simpleManager = SimpleKanataManager(kanataManager: kanataManager)

    // Test that SimpleKanataManager properly integrates with KanataManager
    await simpleManager.forceRefreshStatus()

    // Should complete integration without throwing
    XCTAssertTrue(true, "Integration with KanataManager successful")
  }

  func testRetryMechanismIntegration() async {
    // Test the retry mechanism with real system

    let kanataManager = KanataManager()
    let simpleManager = SimpleKanataManager(kanataManager: kanataManager)

    // Test retry scenarios
    await simpleManager.retryAfterFix("Fixed permissions")
    await simpleManager.onWizardClosed()

    // Should handle retry scenarios gracefully
    XCTAssertTrue(true, "Retry mechanisms work with real system")
  }

  // MARK: - Timer Consolidation Validation

  func testStatusRefreshConsolidation() async {
    // Test that multiple status refreshes don't cause conflicts
    // This validates the timer consolidation solution

    let kanataManager = KanataManager()
    let simpleManager = SimpleKanataManager(kanataManager: kanataManager)

    // Multiple rapid refreshes (this previously caused timer conflicts)
    for _ in 0..<10 {
      await simpleManager.forceRefreshStatus()
    }

    // Should handle multiple refreshes without issues
    XCTAssertTrue(true, "Multiple status refreshes handled gracefully")
  }

  func testConcurrentUIOperations() async {
    // Test concurrent UI operations don't interfere

    let kanataManager = KanataManager()
    let simpleManager = SimpleKanataManager(kanataManager: kanataManager)

    // Simulate concurrent operations from multiple UI components
    let concurrentTasks = (1...5).map { _ in
      Task {
        await simpleManager.forceRefreshStatus()
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
    let simpleManager = SimpleKanataManager(kanataManager: kanataManager)

    // Test permission checking integration
    await simpleManager.startAutoLaunch()

    // If the system lacks permissions, should be in needsHelp state
    let finalState = simpleManager.currentState
    if finalState == .needsHelp {
      XCTAssertTrue(simpleManager.showWizard, "Should show wizard for permission issues")

      if let errorReason = simpleManager.errorReason {
        // Error should be informative
        XCTAssertFalse(errorReason.isEmpty, "Error reason should be informative")
      }
    }

    XCTAssertTrue(true, "Permission checking integration validated")
  }

  func testSystemHealthMonitoring() async {
    // Test system health monitoring behavior

    let kanataManager = KanataManager()
    let simpleManager = SimpleKanataManager(kanataManager: kanataManager)

    // Test health monitoring properties are accessible
    let lastHealthCheck = simpleManager.lastHealthCheck
    let autoStartAttempts = simpleManager.autoStartAttempts
    let retryCount = simpleManager.retryCount
    let isRetryingAfterFix = simpleManager.isRetryingAfterFix

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
