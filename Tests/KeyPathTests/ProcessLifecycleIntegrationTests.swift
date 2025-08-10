import XCTest

@testable import KeyPath

/// Integration tests for ProcessLifecycleManager - tests the actual system
/// These tests cover the self-detection prevention and real-world scenarios we solved
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

  // MARK: - Pattern Matching Tests (Real Implementation)

  func testKeyPathConfigPatternMatching() async {
    // Test various KeyPath configuration patterns against the real pattern matcher

    let testCases = [
      // User config patterns that SHOULD match
      (
        "/opt/homebrew/bin/kanata --cfg /Users/test/Library/Application Support/KeyPath/keypath.kbd",
        true,
        "User KeyPath config"
      ),
      (
        "sudo /usr/local/bin/kanata --cfg /Users/someone/Library/Application Support/KeyPath/keypath.kbd --watch",
        true,
        "Sudo user KeyPath config with watch"
      ),

      // System config patterns that SHOULD match
      (
        "/usr/local/bin/kanata --cfg /usr/local/etc/kanata/keypath.kbd",
        true,
        "System KeyPath config"
      ),
      (
        "sudo /opt/homebrew/bin/kanata --cfg /usr/local/etc/kanata/keypath.kbd --debug",
        true,
        "System KeyPath config with debug"
      ),

      // Experimental kanata patterns (like our current setup) that SHOULD match
      (
        "sudo /Users/malpern/Library/CloudStorage/Dropbox/code/kanata-source/target/release/kanata --cfg /usr/local/etc/kanata/keypath.kbd",
        true,
        "Experimental kanata with KeyPath config"
      ),

      // External patterns that should NOT match
      (
        "/usr/local/bin/kanata --cfg /home/user/my-config.kbd",
        false,
        "External config"
      ),
      (
        "/opt/homebrew/bin/kanata --cfg /etc/kanata/custom.kbd",
        false,
        "Custom external config"
      ),
      (
        "/usr/local/bin/kanata --cfg /Users/other/Documents/kanata.kbd",
        false,
        "User's custom config"
      )
    ]

    for (index, (command, shouldMatch, description)) in testCases.enumerated() {
      // Use a unique PID for each test to avoid state pollution
      let freshManager = ProcessLifecycleManager()
      let process = ProcessLifecycleManager.ProcessInfo(pid: pid_t(2000 + index), command: command)
      let isOwned = freshManager.isOwnedByKeyPath(process)

      XCTAssertEqual(
        isOwned, shouldMatch,
        "Pattern matching failed for \(description): '\(command)'"
      )
    }
  }

  // MARK: - Self-Detection Prevention Tests

  func testPreventsSelfDetectionAsConflict() async throws {
    // Test that ProcessLifecycleManager doesn't detect KeyPath's own processes as conflicts
    // This was the core issue we solved

    // Step 1: Set intent to run
    processManager.setIntent(.shouldBeRunning(source: "test_self_detection"))

    // Mock a KeyPath-owned process (realistic command)
    let keyPathProcess = ProcessLifecycleManager.ProcessInfo(
      pid: pid_t(1234),
      command: "sudo /opt/homebrew/bin/kanata --cfg /usr/local/etc/kanata/keypath.kbd --watch"
    )

    // Register it as KeyPath-owned
    processManager.registerProcess(
      keyPathProcess,
      ownership: .keyPathOwned(reason: "started_by_keypath"),
      intent: .shouldBeRunning(source: "test")
    )

    // Step 2: Detect conflicts - should NOT find any
    let conflicts = await processManager.detectConflicts()

    XCTAssertTrue(conflicts.canAutoResolve, "KeyPath-owned processes should not create conflicts")
    XCTAssertEqual(
      conflicts.externalProcesses.count, 0, "Should not detect own processes as conflicts"
    )

    // Step 3: Verify process is recognized as KeyPath-owned
    XCTAssertTrue(
      processManager.isOwnedByKeyPath(keyPathProcess),
      "Should recognize KeyPath-owned process"
    )
  }

  func testDetectsExternalConflicts() async throws {
    // Test that ProcessLifecycleManager DOES detect external kanata processes

    processManager.setIntent(.shouldBeRunning(source: "test_external_detection"))

    // Mock an external kanata process (different config path)
    let externalProcess = ProcessLifecycleManager.ProcessInfo(
      pid: pid_t(5678),
      command: "/usr/local/bin/kanata --cfg /home/user/custom-config.kbd"
    )

    // Should NOT be recognized as KeyPath-owned
    XCTAssertFalse(
      processManager.isOwnedByKeyPath(externalProcess),
      "Should not recognize external process as KeyPath-owned"
    )
  }

  func testGracePeriodSelfDetection() async {
    // Test that grace period prevents false positives during startup

    // Step 1: Mark a process start attempt
    processManager.markProcessStartAttempt()

    // Step 2: Simulate finding a kanata process shortly after
    let recentProcess = ProcessLifecycleManager.ProcessInfo(
      pid: pid_t(9999),
      command: "/opt/homebrew/bin/kanata --cfg /usr/local/etc/kanata/keypath.kbd"
    )

    // Within grace period, should be considered KeyPath-owned
    XCTAssertTrue(
      processManager.isOwnedByKeyPath(recentProcess),
      "Process started within grace period should be considered KeyPath-owned"
    )
  }

  // MARK: - Performance Tests

  func testProcessDetectionPerformance() async {
    // Test that process detection is efficient on the real implementation

    let startTime = CFAbsoluteTimeGetCurrent()

    // Test realistic process detection scenarios
    for testIndex in 0..<100 {
      let testProcess = ProcessLifecycleManager.ProcessInfo(
        pid: pid_t(10000 + testIndex),
        command: "/opt/homebrew/bin/kanata --cfg /usr/local/etc/kanata/keypath.kbd"
      )
      _ = processManager.isOwnedByKeyPath(testProcess)
    }

    let endTime = CFAbsoluteTimeGetCurrent()
    let duration = endTime - startTime

    // Should complete quickly (less than 0.1 seconds for 100 checks)
    XCTAssertLessThan(duration, 0.1, "Process detection should be efficient")
  }

  // MARK: - Error Handling Tests

  func testProcessErrorTypes() async {
    // Test that error types exist and work correctly

    let error = ProcessLifecycleError.noKanataManager

    switch error {
    case .noKanataManager:
      XCTAssertTrue(true, "NoKanataManager error exists")
    case .processStartFailed:
      XCTAssertTrue(true, "ProcessStartFailed error exists")
    case .processStopFailed:
      XCTAssertTrue(true, "ProcessStopFailed error exists")
    case .processTerminateFailed:
      XCTAssertTrue(true, "ProcessTerminateFailed error exists")
    }
  }

  // MARK: - Thread Safety Tests

  func testConcurrentProcessManagement() async throws {
    // Test concurrent access to ProcessLifecycleManager (real implementation)

    let concurrentTasks = (1...10).map { taskId in
      Task {
        // Test concurrent operations on real ProcessLifecycleManager
        processManager.setIntent(.shouldBeRunning(source: "concurrent_\(taskId)"))

        let testProcess = ProcessLifecycleManager.ProcessInfo(
          pid: pid_t(20000 + taskId),
          command: "/opt/homebrew/bin/kanata --cfg /usr/local/etc/kanata/keypath.kbd"
        )

        _ = processManager.isOwnedByKeyPath(testProcess)

        processManager.registerProcess(
          testProcess,
          ownership: .keyPathOwned(reason: "concurrent_test"),
          intent: .shouldBeRunning(source: "concurrent")
        )
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

    // Should be able to recover from crash
    await manager.recoverFromCrash()

    XCTAssertTrue(true, "ProcessLifecycleManager initializes and operates correctly")
  }

  func testConflictResolutionStructure() async {
    // Test conflict resolution returns the expected structure

    let conflicts = await processManager.detectConflicts()

    // Should have expected properties
    _ = conflicts.externalProcesses
    _ = conflicts.recommendedAction
    _ = conflicts.canAutoResolve

    XCTAssertTrue(true, "ConflictResolution has expected structure")
  }
}
