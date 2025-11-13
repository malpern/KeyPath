import XCTest
@testable @_spi(ServiceInstallTesting) import KeyPath

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

        let didInstall = try await PrivilegedOperationsCoordinator.shared._testEnsureServices(context: "unit-test")

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

        let first = try await PrivilegedOperationsCoordinator.shared._testEnsureServices(context: "unit-test")
        let second = try await PrivilegedOperationsCoordinator.shared._testEnsureServices(context: "unit-test")

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

        let didInstall = try await PrivilegedOperationsCoordinator.shared._testEnsureServices(context: "legacy-test")

        XCTAssertTrue(didInstall)
        XCTAssertEqual(installCount, 1)
    }
}
