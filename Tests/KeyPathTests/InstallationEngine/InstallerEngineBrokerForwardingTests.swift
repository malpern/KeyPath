@preconcurrency import XCTest

@testable import KeyPathAppKit

@MainActor
final class InstallerEngineBrokerForwardingTests: XCTestCase {
    func testUninstallVirtualHIDDriversRoutesToBroker() async throws {
        let coordinator = PrivilegedCoordinatorStub()
        let broker = PrivilegeBroker(coordinator: coordinator)
        let engine = InstallerEngine()

        try await engine.uninstallVirtualHIDDrivers(using: broker)

        XCTAssertEqual(coordinator.uninstallVirtualHIDDriversCallCount, 1)
    }

    func testDisableKarabinerGrabberRoutesToBroker() async throws {
        let coordinator = PrivilegedCoordinatorStub()
        let broker = PrivilegeBroker(coordinator: coordinator)
        let engine = InstallerEngine()

        try await engine.disableKarabinerGrabber(using: broker)

        XCTAssertEqual(coordinator.disableKarabinerGrabberCallCount, 1)
    }

    func testRestartKarabinerDaemonRoutesToBroker() async throws {
        let coordinator = PrivilegedCoordinatorStub(restartReturnValue: true)
        let broker = PrivilegeBroker(coordinator: coordinator)
        let engine = InstallerEngine()

        let result = try await engine.restartKarabinerDaemon(using: broker)

        XCTAssertTrue(result)
        XCTAssertEqual(coordinator.restartKarabinerDaemonVerifiedCallCount, 1)
    }
}

// MARK: - Test Doubles

private final class PrivilegedCoordinatorStub: PrivilegedOperationsCoordinating {
    var restartReturnValue: Bool

    init(restartReturnValue: Bool = true) {
        self.restartReturnValue = restartReturnValue
    }

    // Counters
    private(set) var uninstallVirtualHIDDriversCallCount = 0
    private(set) var disableKarabinerGrabberCallCount = 0
    private(set) var restartKarabinerDaemonVerifiedCallCount = 0

    // Required protocol methods
    func installLaunchDaemon(plistPath _: String, serviceID _: String) async throws {}
    func cleanupPrivilegedHelper() async throws {}
    func installAllLaunchDaemonServices(kanataBinaryPath _: String, kanataConfigPath _: String, tcpPort _: Int) async throws {}
    func installAllLaunchDaemonServices() async throws {}
    func restartUnhealthyServices() async throws {}
    func installServicesIfUninstalled(context _: String) async throws -> Bool { false }
    func installLaunchDaemonServicesWithoutLoading() async throws {}
    func installLogRotation() async throws {}
    func regenerateServiceConfiguration() async throws {}
    func repairVHIDDaemonServices() async throws {}
    func downloadAndInstallCorrectVHIDDriver() async throws {}
    func installBundledKanata() async throws {}
    func activateVirtualHIDManager() async throws {}
    func terminateProcess(pid _: Int32) async throws {}
    func killAllKanataProcesses() async throws {}
    func restartKarabinerDaemonVerified() async throws -> Bool {
        restartKarabinerDaemonVerifiedCallCount += 1
        return restartReturnValue
    }

    func uninstallVirtualHIDDrivers() async throws {
        uninstallVirtualHIDDriversCallCount += 1
    }

    func disableKarabinerGrabber() async throws {
        disableKarabinerGrabberCallCount += 1
    }

    func sudoExecuteCommand(_: String, description _: String) async throws {}
}
