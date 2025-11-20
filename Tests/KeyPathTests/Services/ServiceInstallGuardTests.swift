import XCTest

@testable @_spi(ServiceInstallTesting) import KeyPathAppKit

@MainActor
final class ServiceInstallGuardTests: XCTestCase {
  override func tearDown() async throws {
    PrivilegedOperationsCoordinator._testResetServiceInstallGuard()
    try await super.tearDown()
  }

  func testAutoInstallRunsWhenServiceIsMissing() async throws {
    var serviceState: KanataDaemonManager.ServiceManagementState = .uninstalled
    PrivilegedOperationsCoordinator.serviceStateOverride = { serviceState }

    var installCount = 0
    PrivilegedOperationsCoordinator.installAllServicesOverride = {
      installCount += 1
      serviceState = .smappserviceActive
    }

    let didInstall = try await PrivilegedOperationsCoordinator.shared._testEnsureServices(
      context: "unit-test")

    XCTAssertTrue(didInstall)
    XCTAssertEqual(installCount, 1)
  }

  func testInstallGuardThrottlesRapidRepeats() async throws {
    PrivilegedOperationsCoordinator._testResetServiceInstallGuard()
    PrivilegedOperationsCoordinator.serviceStateOverride = { .uninstalled }

    var installCount = 0
    PrivilegedOperationsCoordinator.installAllServicesOverride = {
      installCount += 1
    }

    let first = try await PrivilegedOperationsCoordinator.shared._testEnsureServices(
      context: "unit-test")
    let second = try await PrivilegedOperationsCoordinator.shared._testEnsureServices(
      context: "unit-test")

    XCTAssertTrue(first)
    XCTAssertFalse(second, "Second call should be throttled and report no install")
    XCTAssertEqual(installCount, 1)
  }

  func testLegacyStateTriggersMigrationInstall() async throws {
    var serviceState: KanataDaemonManager.ServiceManagementState = .legacyActive
    PrivilegedOperationsCoordinator.serviceStateOverride = { serviceState }

    var installCount = 0
    PrivilegedOperationsCoordinator.installAllServicesOverride = {
      installCount += 1
      serviceState = .smappserviceActive
    }

    let didInstall = try await PrivilegedOperationsCoordinator.shared._testEnsureServices(
      context: "legacy-test")

    XCTAssertTrue(didInstall)
    XCTAssertEqual(installCount, 1)
  }

  func testPendingApprovalSkipsAutoInstall() async throws {
    PrivilegedOperationsCoordinator.serviceStateOverride = { .smappservicePending }
    var installCount = 0
    PrivilegedOperationsCoordinator.installAllServicesOverride = {
      installCount += 1
    }

    let didInstall = try await PrivilegedOperationsCoordinator.shared._testEnsureServices(
      context: "pending-test")

    XCTAssertFalse(didInstall)
    XCTAssertEqual(installCount, 0)
  }

  func testConflictedStateTriggersAutoInstall() async throws {
    var serviceState: KanataDaemonManager.ServiceManagementState = .conflicted
    PrivilegedOperationsCoordinator.serviceStateOverride = { serviceState }

    var installCount = 0
    PrivilegedOperationsCoordinator.installAllServicesOverride = {
      installCount += 1
      serviceState = .smappserviceActive
    }

    let didInstall = try await PrivilegedOperationsCoordinator.shared._testEnsureServices(
      context: "conflict-test")

    XCTAssertTrue(didInstall)
    XCTAssertEqual(installCount, 1)
  }
}
