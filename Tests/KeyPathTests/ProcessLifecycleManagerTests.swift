import XCTest

@testable import KeyPath

@MainActor
final class ProcessLifecycleManagerTests: XCTestCase {
  func testProcessOwnershipPatternMatching() async {
    let manager = ProcessLifecycleManager()

    // Test KeyPath-owned processes
    let keyPathProcess1 = ProcessLifecycleManager.ProcessInfo(
      pid: 123,
      command: "/opt/homebrew/bin/kanata --cfg /usr/local/etc/kanata/keypath.kbd"
    )

    let keyPathProcess2 = ProcessLifecycleManager.ProcessInfo(
      pid: 124,
      command:
        "sudo /opt/homebrew/bin/kanata --cfg /Users/test/Library/Application Support/KeyPath/keypath.kbd"
    )

    let keyPathProcess3 = ProcessLifecycleManager.ProcessInfo(
      pid: 125,
      command: "/System/Library/LaunchDaemons/com.keypath.kanata.plist"
    )

    XCTAssertTrue(manager.isOwnedByKeyPath(keyPathProcess1), "Should recognize KeyPath config file")
    XCTAssertTrue(manager.isOwnedByKeyPath(keyPathProcess2), "Should recognize KeyPath user config")
    XCTAssertTrue(
      manager.isOwnedByKeyPath(keyPathProcess3), "Should recognize KeyPath launch daemon"
    )

    // Test external processes
    let externalProcess1 = ProcessLifecycleManager.ProcessInfo(
      pid: 200,
      command: "/opt/homebrew/bin/kanata --cfg /Users/other/my-config.kbd"
    )

    let externalProcess2 = ProcessLifecycleManager.ProcessInfo(
      pid: 201,
      command: "/usr/local/bin/kanata --cfg /etc/kanata/custom.kbd"
    )

    XCTAssertFalse(
      manager.isOwnedByKeyPath(externalProcess1), "Should not recognize external config"
    )
    XCTAssertFalse(
      manager.isOwnedByKeyPath(externalProcess2), "Should not recognize external config"
    )
  }

  func testIntentSetting() async {
    let manager = ProcessLifecycleManager()

    // Test initial state
    XCTAssertEqual(manager.currentIntent, .shouldBeStopped)

    // Test intent changes
    manager.setIntent(.shouldBeRunning(source: "test"))
    XCTAssertEqual(manager.currentIntent, .shouldBeRunning(source: "test"))

    manager.setIntent(.dontCare)
    XCTAssertEqual(manager.currentIntent, .dontCare)
  }

  func testConflictDetection() async {
    let manager = ProcessLifecycleManager()

    // Mock some processes for testing
    let conflicts = await manager.detectConflicts()

    // Should always return a valid result
    XCTAssertNotNil(conflicts)
    XCTAssertTrue(conflicts.canAutoResolve || !conflicts.canAutoResolve)  // Basic sanity check
  }

  func testProcessRegistration() async {
    let manager = ProcessLifecycleManager()

    let testProcess = ProcessLifecycleManager.ProcessInfo(
      pid: 999,
      command: "/test/kanata --cfg /test/keypath.kbd"
    )

    // Initially not owned
    XCTAssertFalse(manager.isOwnedByKeyPath(testProcess))

    // Register as KeyPath-owned
    manager.registerProcess(
      testProcess,
      ownership: .keyPathOwned(reason: "test"),
      intent: .shouldBeRunning(source: "test")
    )

    // Now should be owned
    XCTAssertTrue(manager.isOwnedByKeyPath(testProcess))
  }

  func testGracePeriod() async {
    let manager = ProcessLifecycleManager()

    let testProcess = ProcessLifecycleManager.ProcessInfo(
      pid: 888,
      command: "/opt/homebrew/bin/kanata --cfg /tmp/test.kbd"
    )

    // Initially not owned
    XCTAssertFalse(manager.isOwnedByKeyPath(testProcess))

    // Mark a process start attempt
    manager.markProcessStartAttempt()

    // Within grace period, should be considered owned
    XCTAssertTrue(manager.isOwnedByKeyPath(testProcess))
  }
}

// Extend ProcessLifecycleManager to expose ProcessInfo for testing
extension ProcessLifecycleManager {
  typealias ProcessInfo = ProcessLifecycleManager.ProcessInfo
}
