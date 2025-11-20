import Foundation
import XCTest

@testable import KeyPathAppKit
@testable import KeyPathCore

/// Tests for PrivilegedOperationsCoordinator
/// These verify the coordinator properly delegates to helper or sudo paths
@MainActor
final class PrivilegedOperationsCoordinatorTests: XCTestCase {
  private nonisolated(unsafe) var originalExecutor: AdminCommandExecutor!

  override func setUp() async throws {
    try await super.setUp()
    await MainActor.run {
      originalExecutor = AdminCommandExecutorHolder.shared
    }
  }

  override func tearDown() async throws {
    await MainActor.run {
      AdminCommandExecutorHolder.shared = originalExecutor
    }
    try await super.tearDown()
  }

  func testInstallLogRotationUsesAdminCommandExecutor() async {
    var commandsExecuted: [String] = []

    let fakeExecutor = FakeAdminCommandExecutor(resultProvider: { _, description in
      commandsExecuted.append(description)
      if description.contains("log rotation") {
        return CommandExecutionResult(exitCode: 1, output: "Permission denied")
      }
      return CommandExecutionResult(exitCode: 0, output: "")
    })

    await MainActor.run {
      AdminCommandExecutorHolder.shared = fakeExecutor
    }

    let coordinator = PrivilegedOperationsCoordinator.shared

    do {
      try await coordinator.installLogRotation()
      XCTFail("Expected installLogRotation to throw an error")
    } catch {
      // Expected error path
      XCTAssertTrue(
        commandsExecuted.contains { $0.contains("log rotation") },
        "Should have attempted log rotation via AdminCommandExecutor"
      )
    }
  }

  func testCoordinatorSingletonExists() {
    let coordinator = PrivilegedOperationsCoordinator.shared
    XCTAssertNotNil(coordinator, "Coordinator should be accessible")
  }

  func testOperationModeIsDirectSudoInDebug() {
    #if DEBUG
      XCTAssertEqual(
        PrivilegedOperationsCoordinator.operationMode,
        .directSudo,
        "Debug builds should use directSudo mode"
      )
    #endif
  }
}
