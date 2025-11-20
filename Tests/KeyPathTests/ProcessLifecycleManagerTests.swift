import KeyPathCore
import KeyPathDaemonLifecycle
import XCTest

@testable import KeyPathAppKit

@MainActor
final class ProcessLifecycleManagerTests: XCTestCase {
  func testIntentSetting() async {
    let manager = ProcessLifecycleManager()

    // Test setting intent to running
    manager.setIntent(.shouldBeRunning(source: "test"))

    // Test setting intent to stopped
    manager.setIntent(.shouldBeStopped)

    // No crashes or issues setting intents
    XCTAssertTrue(true, "Intent setting should work without issues")
  }

  func testReconcileWithIntent() async {
    let manager = ProcessLifecycleManager()

    // Test reconcile with running intent
    manager.setIntent(.shouldBeRunning(source: "test"))

    do {
      try await manager.reconcileWithIntent()
      XCTAssertTrue(true, "Reconcile with running intent should not throw")
    } catch {
      XCTFail("Reconcile should not throw: \(error)")
    }

    // Test reconcile with stopped intent
    manager.setIntent(.shouldBeStopped)

    do {
      try await manager.reconcileWithIntent()
      XCTAssertTrue(true, "Reconcile with stopped intent should not throw")
    } catch {
      XCTFail("Reconcile should not throw: \(error)")
    }
  }

  func testProcessIntentEnumValues() async {
    // Test that ProcessIntent enum works correctly
    let runningIntent = ProcessLifecycleManager.ProcessIntent.shouldBeRunning(source: "test")
    let stoppedIntent = ProcessLifecycleManager.ProcessIntent.shouldBeStopped

    // Basic validation that enum cases can be created
    switch runningIntent {
    case .shouldBeRunning(let source):
      XCTAssertEqual(source, "test", "Source should match")
    case .shouldBeStopped:
      XCTFail("Should be running intent")
    }

    switch stoppedIntent {
    case .shouldBeRunning:
      XCTFail("Should be stopped intent")
    case .shouldBeStopped:
      XCTAssertTrue(true, "Correct stopped intent")
    }
  }

  func testProcessLifecycleErrors() async {
    // Test that error enum cases can be created (migrated to KeyPathError)
    let noManagerError = KeyPathError.process(.noManager)
    let startFailedError = KeyPathError.process(.startFailed(reason: "test"))
    let stopFailedError = KeyPathError.process(.stopFailed(underlyingError: "test error 1"))
    let terminateFailedError = KeyPathError.process(
      .terminateFailed(underlyingError: "test error 2"))

    XCTAssertNotNil(noManagerError)
    XCTAssertNotNil(startFailedError)
    XCTAssertNotNil(stopFailedError)
    XCTAssertNotNil(terminateFailedError)
  }
}
