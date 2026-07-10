@testable import KeyPathAppKit
@testable import KeyPathInstallationWizard
@preconcurrency import XCTest

@MainActor
final class InstallerEngineBrokerForwardingTests: KeyPathTestCase {
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

    func testDirectPrivilegedRoutesShareInstallerTransactionGate() async throws {
        let coordinator = BlockingPrivilegedCoordinatorStub()
        let broker = PrivilegeBroker(coordinator: coordinator)
        let engine = InstallerEngine()

        let disableTask = Task {
            try await engine.disableKarabinerGrabber(using: broker)
        }
        await coordinator.waitUntilDisableEntered()

        let restartStarted = expectation(description: "restart route started")
        let restartTask = Task {
            restartStarted.fulfill()
            return try await engine.restartKarabinerDaemon(using: broker)
        }
        await fulfillment(of: [restartStarted])
        await Task.yield()

        XCTAssertEqual(
            coordinator.restartKarabinerDaemonVerifiedCallCount,
            0,
            "A second public privileged route must wait for the active installer transaction"
        )

        coordinator.releaseDisable()
        try await disableTask.value
        let restartSucceeded = try await restartTask.value
        XCTAssertTrue(restartSucceeded)
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
    func cleanupPrivilegedHelper() async throws {}
    func installRequiredRuntimeServices() async throws {}
    func recoverRequiredRuntimeServices() async throws {}
    func installServicesIfUninstalled(context _: String) async throws -> Bool {
        false
    }

    func installNewsyslogConfig() async throws {}
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

private final class BlockingPrivilegedCoordinatorStub: PrivilegedOperationsCoordinating {
    private var disableEntered = false
    private var disableEnteredWaiters: [CheckedContinuation<Void, Never>] = []
    private var disableRelease: CheckedContinuation<Void, Never>?
    private(set) var restartKarabinerDaemonVerifiedCallCount = 0

    func waitUntilDisableEntered() async {
        if disableEntered { return }
        await withCheckedContinuation { continuation in
            disableEnteredWaiters.append(continuation)
        }
    }

    func releaseDisable() {
        disableRelease?.resume()
        disableRelease = nil
    }

    func disableKarabinerGrabber() async throws {
        disableEntered = true
        disableEnteredWaiters.forEach { $0.resume() }
        disableEnteredWaiters.removeAll()
        await withCheckedContinuation { continuation in
            disableRelease = continuation
        }
    }

    func restartKarabinerDaemonVerified() async throws -> Bool {
        restartKarabinerDaemonVerifiedCallCount += 1
        return true
    }

    func cleanupPrivilegedHelper() async throws {}
    func installRequiredRuntimeServices() async throws {}
    func recoverRequiredRuntimeServices() async throws {}
    func installServicesIfUninstalled(context _: String) async throws -> Bool {
        false
    }

    func installNewsyslogConfig() async throws {}
    func regenerateServiceConfiguration() async throws {}
    func repairVHIDDaemonServices() async throws {}
    func downloadAndInstallCorrectVHIDDriver() async throws {}
    func activateVirtualHIDManager() async throws {}
    func terminateProcess(pid _: Int32) async throws {}
    func killAllKanataProcesses() async throws {}
    func uninstallVirtualHIDDrivers() async throws {}
    func sudoExecuteCommand(_: String, description _: String) async throws {}
}
