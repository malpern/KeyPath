import XCTest

@testable import KeyPathAppKit

@MainActor
final class HelperMaintenanceTests: XCTestCase {
  private var originalExecutor: AdminCommandExecutor!

  override func setUp() async throws {
    try await super.setUp()
    originalExecutor = AdminCommandExecutorHolder.shared
  }

  override func tearDown() async throws {
    try await super.tearDown()
    HelperMaintenance.testDuplicateAppPathsOverride = nil
    HelperMaintenance.shared.applyTestHooks(nil)
    HelperManager.testHelperFunctionalityOverride = nil
    HelperManager.testInstallHelperOverride = nil
    AdminCommandExecutorHolder.shared = originalExecutor
  }

  func testDetectDuplicateAppCopiesFiltersBuildPathsAndSortsApplicationsFirst() {
    HelperMaintenance.testDuplicateAppPathsOverride = {
      [
        "/Users/test/Downloads/KeyPath.app",
        "/dist/KeyPath.app",
        "/Applications/KeyPath.app",
        "/Users/test/KeyPath.app"
      ]
    }

    let copies = HelperMaintenance.shared.detectDuplicateAppCopies()
    XCTAssertEqual(copies.first, "/Applications/KeyPath.app")
    let remaining = Set(copies.dropFirst())
    XCTAssertEqual(
      remaining,
      Set([
        "/Users/test/KeyPath.app",
        "/Users/test/Downloads/KeyPath.app"
      ])
    )
  }

  func testRunCleanupLogsWarningForDuplicateCopies() async {
    HelperMaintenance.testDuplicateAppPathsOverride = {
      [
        "/Applications/KeyPath.app",
        "/Users/other/KeyPath.app"
      ]
    }

    let hooks = HelperMaintenance.TestHooks(
      unregisterHelper: {},
      bootoutHelperJob: {},
      removeLegacyHelperArtifacts: { _ in .removed },
      registerHelper: { true }
    )
    HelperMaintenance.shared.applyTestHooks(hooks)
    HelperManager.testHelperFunctionalityOverride = { true }

    let success = await HelperMaintenance.shared.runCleanupAndRepair(useAppleScriptFallback: false)
    XCTAssertTrue(success)
    XCTAssertTrue(
      HelperMaintenance.shared.logLines.contains {
        $0.contains("Multiple KeyPath.app copies detected:")
      })
  }

  func testAdminCleanupFallbackFailureAbortsRun() async {
    HelperMaintenance.testDuplicateAppPathsOverride = { ["/Applications/KeyPath.app"] }

    let fakeExecutor = FakeAdminCommandExecutor(resultProvider: { _, _ in
      CommandExecutionResult(exitCode: 1, output: "Permission denied")
    })
    AdminCommandExecutorHolder.shared = fakeExecutor

    var attempts = 0
    let hooks = HelperMaintenance.TestHooks(
      unregisterHelper: {},
      bootoutHelperJob: {},
      registerHelper: {
        attempts += 1
        // Simulate primary failure; after cleanup still fail
        return attempts > 10  // never reached, keeps returning false
      }
    )
    HelperMaintenance.shared.applyTestHooks(hooks)
    HelperManager.testHelperFunctionalityOverride = { true }

    let success = await HelperMaintenance.shared.runCleanupAndRepair(useAppleScriptFallback: true)
    XCTAssertFalse(success)
    XCTAssertTrue(
      HelperMaintenance.shared.logLines.contains { $0.localizedCaseInsensitiveContains("failed") },
      "Log should include admin cleanup failure"
    )
  }

  func testAdminCleanupFallbackSucceedsWithExecutor() async {
    HelperMaintenance.testDuplicateAppPathsOverride = { ["/Applications/KeyPath.app"] }

    let fakeExecutor = FakeAdminCommandExecutor()
    AdminCommandExecutorHolder.shared = fakeExecutor

    var attempts = 0
    let hooks = HelperMaintenance.TestHooks(
      unregisterHelper: {},
      bootoutHelperJob: {},
      registerHelper: {
        attempts += 1
        // Fail first time to trigger cleanup; succeed after cleanup
        return attempts > 1
      }
    )
    HelperMaintenance.shared.applyTestHooks(hooks)
    HelperManager.testHelperFunctionalityOverride = { true }

    let success = await HelperMaintenance.shared.runCleanupAndRepair(useAppleScriptFallback: true)
    XCTAssertTrue(success)
    XCTAssertTrue(
      fakeExecutor.commands.contains { $0.description.contains("Remove legacy helper artifacts") }
    )
    XCTAssertTrue(
      HelperMaintenance.shared.logLines.contains {
        $0.localizedCaseInsensitiveContains("removed legacy helper artifacts")
      }
    )
  }

  func testRunCleanupIsIdempotentWithoutDuplicates() async {
    HelperMaintenance.testDuplicateAppPathsOverride = { ["/Applications/KeyPath.app"] }
    let hooks = HelperMaintenance.TestHooks(
      unregisterHelper: {},
      bootoutHelperJob: {},
      removeLegacyHelperArtifacts: { _ in .removed },
      registerHelper: { true }
    )
    HelperMaintenance.shared.applyTestHooks(hooks)
    HelperManager.testHelperFunctionalityOverride = { true }

    let first = await HelperMaintenance.shared.runCleanupAndRepair(useAppleScriptFallback: false)
    XCTAssertTrue(first)
    let second = await HelperMaintenance.shared.runCleanupAndRepair(useAppleScriptFallback: false)
    XCTAssertTrue(second)
  }
}
