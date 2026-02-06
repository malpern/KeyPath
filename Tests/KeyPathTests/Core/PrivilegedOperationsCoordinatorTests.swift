import Foundation
@testable import KeyPathAppKit
@testable import KeyPathCore
@preconcurrency import XCTest

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
            #if DEBUG
                PrivilegedOperationsCoordinator.resetTestingState()
            #endif
        }
        try await super.tearDown()
    }

    func testInstallLogRotationExecutesWithoutCrash() async {
        // This test verifies that installLogRotation() executes without crashing.
        // In test mode, privileged operations are skipped via TestEnvironment.shouldSkipAdminOperations,
        // so we just verify the method completes (whether success or expected failure).
        // The actual implementation uses AdminCommandExecutor (backed by PrivilegedCommandRunner).

        let coordinator = PrivilegedOperationsCoordinator.shared

        do {
            try await coordinator.installLogRotation()
            // Success in test mode (admin ops skipped)
        } catch {
            // Also acceptable - may fail due to permissions in some test environments
            // The key thing is it didn't crash
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

    func testRestartKarabinerDaemonUsesSingleBatch() async throws {
        let fakeExecutor = FakeAdminCommandExecutor()
        AdminCommandExecutorHolder.shared = fakeExecutor
        VHIDDeviceManager.testPIDProvider = { ["123"] }
        defer {
            VHIDDeviceManager.testPIDProvider = nil
            AdminCommandExecutorHolder.shared = originalExecutor
        }

        let coordinator = PrivilegedOperationsCoordinator.shared
        let success = try await coordinator.restartKarabinerDaemonVerified()

        XCTAssertTrue(success)
        XCTAssertEqual(fakeExecutor.batches.count, 1)
    }

    func testInstallServicesIfUninstalledSkipsWhenApprovalPending() async throws {
        #if DEBUG
            PrivilegedOperationsCoordinator.resetTestingState()
            PrivilegedOperationsCoordinator.serviceStateOverride = { .smappservicePending }
            PrivilegedOperationsCoordinator.installAllServicesOverride = {
                XCTFail("Install should not run while SMAppService approval is pending")
            }
        #endif

        let coordinator = PrivilegedOperationsCoordinator.shared
        let didInstall = try await coordinator.installServicesIfUninstalled(context: "test-pending")
        XCTAssertFalse(didInstall)
    }

    func testInstallServicesIfUninstalledRunsInstallWhenUninstalled() async throws {
        #if DEBUG
            PrivilegedOperationsCoordinator.resetTestingState()
            var installCallCount = 0
            PrivilegedOperationsCoordinator.serviceStateOverride = { .uninstalled }
            PrivilegedOperationsCoordinator.installAllServicesOverride = {
                installCallCount += 1
            }
        #endif

        let coordinator = PrivilegedOperationsCoordinator.shared
        let didInstall = try await coordinator.installServicesIfUninstalled(context: "test-uninstalled")
        XCTAssertTrue(didInstall)
        #if DEBUG
            XCTAssertEqual(installCallCount, 1)
        #endif
    }

    func testInstallServicesIfUninstalledThrottlesRepeatedAttempts() async throws {
        #if DEBUG
            PrivilegedOperationsCoordinator.resetTestingState()
            var installCallCount = 0
            PrivilegedOperationsCoordinator.serviceStateOverride = { .uninstalled }
            PrivilegedOperationsCoordinator.installAllServicesOverride = {
                installCallCount += 1
            }
        #endif

        let coordinator = PrivilegedOperationsCoordinator.shared
        let first = try await coordinator.installServicesIfUninstalled(context: "test-throttle-1")
        let second = try await coordinator.installServicesIfUninstalled(context: "test-throttle-2")

        XCTAssertTrue(first)
        XCTAssertFalse(second)
        #if DEBUG
            XCTAssertEqual(installCallCount, 1)
        #endif
    }

    func testTerminateProcessRejectsInvalidPIDWithoutRunningCommands() async throws {
        let fakeExecutor = FakeAdminCommandExecutor()
        AdminCommandExecutorHolder.shared = fakeExecutor

        let coordinator = PrivilegedOperationsCoordinator.shared

        await XCTAssertThrowsErrorAsync(try coordinator.terminateProcess(pid: 0)) { error in
            guard case let PrivilegedOperationError.operationFailed(message) = error else {
                XCTFail("Expected operationFailed error, got \(error)")
                return
            }
            XCTAssertTrue(message.contains("Invalid process ID"))
        }

        XCTAssertTrue(fakeExecutor.commands.isEmpty)
        XCTAssertTrue(fakeExecutor.batches.isEmpty)
    }
}
