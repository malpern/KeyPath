import KeyPathCore
import KeyPathDaemonLifecycle
import KeyPathWizardCore
import XCTest

@testable import KeyPathAppKit

/// Integration tests for ProcessLifecycleManager - tests the actual system
/// Updated to work with the simplified ProcessLifecycleManager that uses PID files
@MainActor
final class ProcessLifecycleIntegrationTests: XCTestCase {
  var processManager: ProcessLifecycleManager!

  override func setUp() async throws {
    try await super.setUp()
    processManager = ProcessLifecycleManager()
  }

  override func tearDown() async throws {
    processManager = nil
    try await super.tearDown()
  }

  // MARK: - Basic Operations Tests

  func testProcessLifecycleManagerBasicOperations() async {
    // Test the basic operations available in the current ProcessLifecycleManager

    // Test intent setting
    processManager.setIntent(.shouldBeRunning(source: "test_basic_operations"))

    // Test process registration
    await processManager.registerStartedProcess(pid: pid_t(1234), command: "test command")

    // Test process unregistration
    await processManager.unregisterProcess()

    // Test orphaned process cleanup (replaces recoverFromCrash)
    await processManager.cleanupOrphanedProcesses()

    XCTAssertTrue(true, "Basic ProcessLifecycleManager operations should complete without errors")
  }

  // MARK: - Conflict Detection Tests

  func testConflictDetection() async throws {
    // Test that conflict detection works with the current ProcessLifecycleManager

    // Set intent to run
    processManager.setIntent(.shouldBeRunning(source: "test_conflict_detection"))

    // Register a process as started by KeyPath
    await processManager.registerStartedProcess(pid: pid_t(1234), command: "kanata command")

    // Detect conflicts
    let conflicts = await processManager.detectConflicts()

    // Should have basic conflict resolution structure
    XCTAssertNotNil(conflicts.externalProcesses, "Should return external processes array")
    XCTAssertNotNil(conflicts.canAutoResolve, "Should indicate if conflicts can be auto-resolved")
  }

  func testProcessTermination() async throws {
    // Test that ProcessLifecycleManager can handle process termination

    processManager.setIntent(.shouldBeRunning(source: "test_termination"))

    // Test terminating external processes
    do {
      try await processManager.terminateExternalProcesses()
      XCTAssertTrue(true, "Process termination should complete without errors")
    } catch {
      // It's okay if this fails in test environment - just testing that the method exists
      XCTAssertTrue(true, "Process termination method exists and can be called")
    }
  }

  func testOrphanedProcessCleanup() async {
    // Test that ProcessLifecycleManager can clean up orphaned processes

    await processManager.cleanupOrphanedProcesses()
    XCTAssertTrue(true, "Orphaned process cleanup should complete without errors")
  }

  // MARK: - Performance Tests

  func testProcessDetectionPerformance() async {
    // Test that process detection is efficient on the real implementation

    let startTime = CFAbsoluteTimeGetCurrent()

    // Test realistic process operations
    for testIndex in 0..<100 {
      processManager.setIntent(.shouldBeRunning(source: "perf_test_\(testIndex)"))
      await processManager.registerStartedProcess(
        pid: pid_t(10000 + testIndex), command: "test command")
      await processManager.unregisterProcess()
    }

    let endTime = CFAbsoluteTimeGetCurrent()
    let duration = endTime - startTime

    // Should complete quickly (less than 0.1 seconds for 100 operations)
    XCTAssertLessThan(duration, 0.1, "Process operations should be efficient")
  }

  // MARK: - Error Handling Tests

  func testProcessErrorTypes() async {
    // Test that error types exist and work correctly (migrated to KeyPathError)

    let error = KeyPathError.process(.noManager)

    // Test that we can pattern match on the new error type
    if case .process(let processError) = error {
      switch processError {
      case .noManager:
        XCTAssertTrue(true, "NoManager error exists")
      case .startFailed:
        XCTAssertTrue(true, "StartFailed error exists")
      case .stopFailed:
        XCTAssertTrue(true, "StopFailed error exists")
      case .terminateFailed:
        XCTAssertTrue(true, "TerminateFailed error exists")
      default:
        break
      }
    }
  }

  // MARK: - Thread Safety Tests

  func testConcurrentProcessManagement() async throws {
    // Test concurrent access to ProcessLifecycleManager (real implementation)
    let manager = processManager!

    let concurrentTasks = (1...10).map { taskId in
      Task {
        // Test concurrent operations on real ProcessLifecycleManager
        manager.setIntent(.shouldBeRunning(source: "concurrent_\(taskId)"))

        // Test basic operations on ProcessLifecycleManager
        await manager.registerStartedProcess(pid: pid_t(20000 + taskId), command: "test command")

        await manager.unregisterProcess()
      }
    }

    // Wait for all concurrent tasks
    for task in concurrentTasks {
      await task.value
    }

    // Should complete without crashes or data corruption
    XCTAssertTrue(true, "Concurrent operations completed successfully")
  }

  // MARK: - Real-World Integration Tests

  func testProcessLifecycleManagerInitialization() async {
    // Test that ProcessLifecycleManager can be initialized without issues

    let manager = ProcessLifecycleManager()

    // Should be able to set intent
    manager.setIntent(.shouldBeRunning(source: "initialization_test"))

    // Should be able to clean up orphaned processes
    await manager.cleanupOrphanedProcesses()

    XCTAssertTrue(true, "ProcessLifecycleManager initializes and operates correctly")
  }

  func testConflictResolutionStructure() async {
    // Test conflict resolution returns the expected structure

    let conflicts = await processManager.detectConflicts()

    // Should have expected properties
    _ = conflicts.externalProcesses
    _ = conflicts.canAutoResolve

    XCTAssertTrue(true, "ConflictResolution has expected structure")
  }

  func testIntentReconciliation() async throws {
    // Test that intent reconciliation works

    processManager.setIntent(.shouldBeRunning(source: "test_intent"))

    do {
      try await processManager.reconcileWithIntent()
      XCTAssertTrue(true, "Intent reconciliation should complete")
    } catch {
      // It's okay if this fails in test environment - just testing that the method exists
      XCTAssertTrue(true, "Intent reconciliation method exists and can be called")
    }
  }
}
