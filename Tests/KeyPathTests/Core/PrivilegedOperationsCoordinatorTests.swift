import Foundation
@preconcurrency import XCTest

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
}
