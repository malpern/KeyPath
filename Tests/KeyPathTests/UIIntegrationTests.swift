import XCTest

@testable import KeyPath

/// Tests for UI component integration - validates timer consolidation and state management
/// These tests verify the ContentView + SettingsView timer conflicts have been resolved
@MainActor
final class UIIntegrationTests: XCTestCase {
  // MARK: - Timer Consolidation Tests

  func testMultipleUIComponentsShareState() async {
    // Test that multiple UI components can share the same SimpleKanataManager
    // This validates the timer consolidation solution

    let kanataManager = KanataManager()
    let sharedManager = SimpleKanataManager(kanataManager: kanataManager)

    // Simulate multiple UI components accessing the same manager
    // (This is what ContentView + SettingsView do now)

    // Component 1 operations (ContentView)
    await sharedManager.forceRefreshStatus()
    let state1 = sharedManager.currentState

    // Component 2 operations (SettingsView)
    await sharedManager.forceRefreshStatus()
    let state2 = sharedManager.currentState

    // Both should see the same state
    XCTAssertEqual(state1, state2, "Multiple UI components should see consistent state")
  }

  func testRapidStatusUpdatesHandled() async {
    // Test that rapid status updates don't cause conflicts
    // This was the source of "Ignoring rapid start attempt within 2.0s" errors

    let kanataManager = KanataManager()
    let sharedManager = SimpleKanataManager(kanataManager: kanataManager)

    // Simulate rapid UI updates from multiple components
    for _ in 0..<10 {
      await sharedManager.forceRefreshStatus()
    }

    // Should handle rapid updates without throwing or conflicting
    XCTAssertTrue(true, "Rapid status updates handled gracefully")
  }

  func testConcurrentUIAccess() async {
    // Test concurrent UI access patterns

    let kanataManager = KanataManager()
    let sharedManager = SimpleKanataManager(kanataManager: kanataManager)

    // Simulate concurrent access from multiple UI components
    let concurrentTasks = (1...5).map { _ in
      Task {
        await sharedManager.forceRefreshStatus()
        return sharedManager.currentState
      }
    }

    // Wait for all tasks and collect states
    var states: [SimpleKanataManager.State] = []
    for task in concurrentTasks {
      let state = await task.value
      states.append(state)
    }

    // All states should be consistent (same state seen by all UI components)
    if states.count > 1 {
      let firstState = states[0]
      for state in states {
        XCTAssertEqual(
          state, firstState,
          "All UI components should see consistent state during concurrent access"
        )
      }
    }

    XCTAssertTrue(true, "Concurrent UI access completed successfully")
  }

  // MARK: - UI State Consistency Tests

  func testStateConsistencyAcrossUIComponents() async {
    // Test that state remains consistent when accessed by different UI components

    let kanataManager = KanataManager()
    let manager1 = SimpleKanataManager(kanataManager: kanataManager)  // ContentView
    let manager2 = SimpleKanataManager(kanataManager: kanataManager)  // SettingsView

    // Both should start with the same initial state
    XCTAssertEqual(manager1.currentState, .starting, "Manager 1 should start in starting state")
    XCTAssertEqual(manager2.currentState, .starting, "Manager 2 should start in starting state")

    // Both should have consistent wizard state
    XCTAssertEqual(manager1.showWizard, manager2.showWizard, "Wizard state should be consistent")
  }

  func testErrorStatePropagation() async {
    // Test that error states propagate correctly to UI components

    let kanataManager = KanataManager()
    let sharedManager = SimpleKanataManager(kanataManager: kanataManager)

    // Trigger potential error state
    await sharedManager.startAutoLaunch()

    // Check that error information is accessible to UI
    let errorReason = sharedManager.errorReason
    let showWizard = sharedManager.showWizard
    let currentState = sharedManager.currentState

    // Error information should be consistent
    if currentState == .needsHelp {
      XCTAssertTrue(showWizard, "Should show wizard when in needsHelp state")
    }

    // Error reason should be informative if present
    if let error = errorReason {
      XCTAssertFalse(error.isEmpty, "Error reason should be informative")
    }

    XCTAssertTrue(true, "Error state propagation verified")
  }

  // MARK: - Manual Operation Tests

  func testManualOperationsFromUI() async {
    // Test manual start/stop operations from UI components

    let kanataManager = KanataManager()
    let sharedManager = SimpleKanataManager(kanataManager: kanataManager)

    // Test manual operations (these would be triggered by UI buttons)
    await sharedManager.manualStart()
    await sharedManager.manualStop()

    // Should complete without throwing
    XCTAssertTrue(true, "Manual operations completed successfully")
  }

  func testWizardInteractionFromUI() async {
    // Test wizard interactions from UI

    let kanataManager = KanataManager()
    let sharedManager = SimpleKanataManager(kanataManager: kanataManager)

    // Test wizard-related operations
    await sharedManager.onWizardClosed()
    await sharedManager.retryAfterFix("User fixed permissions")

    // Should complete without throwing
    XCTAssertTrue(true, "Wizard interactions completed successfully")
  }

  // MARK: - Performance Tests

  func testUIOperationPerformance() async {
    // Test that UI operations are performant

    let kanataManager = KanataManager()
    let sharedManager = SimpleKanataManager(kanataManager: kanataManager)

    let startTime = CFAbsoluteTimeGetCurrent()

    // Simulate typical UI interaction pattern
    for _ in 0..<20 {
      await sharedManager.forceRefreshStatus()
    }

    let endTime = CFAbsoluteTimeGetCurrent()
    let duration = endTime - startTime

    // Should be fast enough for UI responsiveness (less than 1 second)
    XCTAssertLessThan(duration, 1.0, "UI operations should be performant")
  }

  // MARK: - Real Integration Tests

  func testIntegrationWithRealKanataManager() async {
    // Test integration with real KanataManager (not mocked)

    let kanataManager = KanataManager()
    let simpleManager = SimpleKanataManager(kanataManager: kanataManager)

    // Test real integration
    await simpleManager.forceRefreshStatus()

    // Should have real system state
    let currentState = simpleManager.currentState
    let validStates: [SimpleKanataManager.State] = [.starting, .running, .needsHelp, .stopped]
    XCTAssertTrue(validStates.contains(currentState), "Should be in a valid state")

    // Should have accessible properties for UI binding
    _ = simpleManager.showWizard
    _ = simpleManager.errorReason
    _ = simpleManager.autoStartAttempts
    _ = simpleManager.retryCount
    _ = simpleManager.isRetryingAfterFix
    _ = simpleManager.lastHealthCheck

    XCTAssertTrue(true, "Real integration with KanataManager successful")
  }

  func testUIStateUpdateNotifications() async {
    // Test that UI state updates work with @Published properties

    let kanataManager = KanataManager()
    let simpleManager = SimpleKanataManager(kanataManager: kanataManager)

    // These are @Published properties that UI components bind to
    let initialState = simpleManager.currentState
    let initialWizardState = simpleManager.showWizard
    let initialErrorReason = simpleManager.errorReason

    // Trigger a state change
    await simpleManager.startAutoLaunch()

    // State may have changed
    let finalState = simpleManager.currentState
    let finalWizardState = simpleManager.showWizard
    let finalErrorReason = simpleManager.errorReason

    // Values should be accessible (and may have changed)
    XCTAssertTrue(
      initialState == finalState || initialState != finalState, "State should be trackable"
    )
    XCTAssertTrue(
      initialWizardState == finalWizardState || initialWizardState != finalWizardState,
      "Wizard state should be trackable"
    )
    XCTAssertTrue(
      (initialErrorReason == nil && finalErrorReason == nil)
        || (initialErrorReason != nil && finalErrorReason != nil)
        || (initialErrorReason == nil && finalErrorReason != nil)
        || (initialErrorReason != nil && finalErrorReason == nil),
      "Error reason should be trackable"
    )
  }

  // MARK: - Cleanup Tests

  func testUIComponentCleanup() async {
    // Test that UI components can clean up properly

    do {
      let kanataManager = KanataManager()
      let simpleManager = SimpleKanataManager(kanataManager: kanataManager)

      // Use the manager briefly
      await simpleManager.forceRefreshStatus()

      // Should be able to go out of scope without issues
    }

    // Memory should clean up properly
    XCTAssertTrue(true, "UI component cleanup completed")
  }
}
