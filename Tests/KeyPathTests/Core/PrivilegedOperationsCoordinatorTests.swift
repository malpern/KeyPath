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
                KanataDaemonManager.registeredButNotLoadedOverride = nil
                ServiceHealthChecker.runtimeSnapshotOverride = nil
                ServiceHealthChecker.recentlyRestartedOverride = nil
            #endif
        }
        try await super.tearDown()
    }

    func testInstallNewsyslogConfigExecutesWithoutCrash() async {
        // This test verifies that installNewsyslogConfig() executes without crashing.
        // In test mode, privileged operations are skipped via TestEnvironment.shouldSkipAdminOperations,
        // so we just verify the method completes (whether success or expected failure).
        // The actual implementation uses AdminCommandExecutor (backed by PrivilegedCommandRunner).

        let coordinator = PrivilegedOperationsCoordinator.shared

        do {
            try await coordinator.installNewsyslogConfig()
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

    func testInstallServicesIfUninstalledRunsInstallWhenSMAppServiceIsStaleEnabled() async throws {
#if DEBUG
            PrivilegedOperationsCoordinator.resetTestingState()
            var installCallCount = 0
            PrivilegedOperationsCoordinator.serviceStateOverride = { .smappserviceActive }
            KanataDaemonManager.registeredButNotLoadedOverride = { true }
            PrivilegedOperationsCoordinator.installAllServicesOverride = {
                installCallCount += 1
            }
#endif

        let coordinator = PrivilegedOperationsCoordinator.shared
        let didInstall = try await coordinator.installServicesIfUninstalled(context: "test-stale-enabled")

        XCTAssertTrue(didInstall)
#if DEBUG
            XCTAssertEqual(installCallCount, 1)
#endif
    }

    func testInstallServicesIfUninstalledBypassesThrottleForStaleEnabledRecovery() async throws {
#if DEBUG
            PrivilegedOperationsCoordinator.resetTestingState()
            var installCallCount = 0
            PrivilegedOperationsCoordinator.serviceStateOverride = { .smappserviceActive }
            KanataDaemonManager.registeredButNotLoadedOverride = { true }
            PrivilegedOperationsCoordinator.installAllServicesOverride = {
                installCallCount += 1
            }
#endif

        let coordinator = PrivilegedOperationsCoordinator.shared
        let first = try await coordinator.installServicesIfUninstalled(context: "test-stale-throttle-1")
        let second = try await coordinator.installServicesIfUninstalled(context: "test-stale-throttle-2")

        XCTAssertTrue(first)
        XCTAssertTrue(second, "Stale registration recovery must bypass normal install throttle")
#if DEBUG
            XCTAssertEqual(installCallCount, 2)
#endif
    }

    func testInstallServicesIfUninstalledLimitsRepeatedStaleBypassAttempts() async throws {
#if DEBUG
            PrivilegedOperationsCoordinator.resetTestingState()
            var installCallCount = 0
            PrivilegedOperationsCoordinator.serviceStateOverride = { .smappserviceActive }
            KanataDaemonManager.registeredButNotLoadedOverride = { true }
            PrivilegedOperationsCoordinator.installAllServicesOverride = {
                installCallCount += 1
            }
#endif

        let coordinator = PrivilegedOperationsCoordinator.shared
        let first = try await coordinator.installServicesIfUninstalled(context: "test-stale-cap-1")
        let second = try await coordinator.installServicesIfUninstalled(context: "test-stale-cap-2")
        let third = try await coordinator.installServicesIfUninstalled(context: "test-stale-cap-3")
        let fourth = try await coordinator.installServicesIfUninstalled(context: "test-stale-cap-4")

        XCTAssertTrue(first)
        XCTAssertTrue(second)
        XCTAssertTrue(third)
        XCTAssertFalse(fourth, "Stale recovery bypass should stop after configured cap")
#if DEBUG
            XCTAssertEqual(installCallCount, 3)
#endif
    }

    func testInstallServicesIfUninstalledSkipsWhenSMAppServiceIsHealthyEnabled() async throws {
#if DEBUG
            PrivilegedOperationsCoordinator.resetTestingState()
            var installCallCount = 0
            PrivilegedOperationsCoordinator.serviceStateOverride = { .smappserviceActive }
            KanataDaemonManager.registeredButNotLoadedOverride = { false }
            PrivilegedOperationsCoordinator.installAllServicesOverride = {
                installCallCount += 1
            }
#endif

        let coordinator = PrivilegedOperationsCoordinator.shared
        let didInstall = try await coordinator.installServicesIfUninstalled(context: "test-healthy-enabled")

        XCTAssertFalse(didInstall)
#if DEBUG
            XCTAssertEqual(installCallCount, 0)
#endif
    }

    func testRestartUnhealthyServicesFailsWhenPostconditionTimesOut() async throws {
#if DEBUG
            PrivilegedOperationsCoordinator.resetTestingState()
            PrivilegedOperationsCoordinator.serviceStateOverride = { .smappserviceActive }
            KanataDaemonManager.registeredButNotLoadedOverride = { false }
            PrivilegedOperationsCoordinator.kanataReadinessOverride = { _ in .timedOut }
#endif

        let coordinator = PrivilegedOperationsCoordinator.shared
        do {
            try await coordinator.restartUnhealthyServices()
            XCTFail("Expected restartUnhealthyServices to fail when postcondition does not become ready")
        } catch let PrivilegedOperationError.operationFailed(message) {
            XCTAssertTrue(message.contains("postcondition failed"))
        } catch {
            XCTFail("Unexpected error type: \(error)")
        }
    }

    func testRegenerateServiceConfigurationAllowsPendingApprovalPostcondition() async throws {
#if DEBUG
            PrivilegedOperationsCoordinator.resetTestingState()
            PrivilegedOperationsCoordinator.kanataReadinessOverride = { _ in .pendingApproval }
#endif

        let coordinator = PrivilegedOperationsCoordinator.shared
        do {
            try await coordinator.regenerateServiceConfiguration()
        } catch {
            XCTFail("Expected regenerateServiceConfiguration to accept pending approval, got: \(error)")
        }
    }

    func testInstallBundledKanataFailsWhenReadinessTimesOut() async throws {
#if DEBUG
            PrivilegedOperationsCoordinator.resetTestingState()
            PrivilegedOperationsCoordinator.serviceStateOverride = { .smappserviceActive }
            KanataDaemonManager.registeredButNotLoadedOverride = { false }
            PrivilegedOperationsCoordinator.installBundledKanataBinaryOverride = {}
            PrivilegedOperationsCoordinator.kanataReadinessOverride = { _ in .timedOut }
#endif

        let coordinator = PrivilegedOperationsCoordinator.shared
        do {
            try await coordinator.installBundledKanata()
            XCTFail("Expected installBundledKanata to fail when readiness times out")
        } catch let PrivilegedOperationError.operationFailed(message) {
            XCTAssertTrue(message.contains("postcondition failed"))
        } catch {
            XCTFail("Unexpected error type: \(error)")
        }
    }

    func testInstallBundledKanataSucceedsWhenReadinessBecomesReady() async throws {
        #if DEBUG
            PrivilegedOperationsCoordinator.resetTestingState()
            PrivilegedOperationsCoordinator.serviceStateOverride = { .smappserviceActive }
            KanataDaemonManager.registeredButNotLoadedOverride = { false }
            PrivilegedOperationsCoordinator.installBundledKanataBinaryOverride = {}
            PrivilegedOperationsCoordinator.kanataReadinessOverride = { _ in .ready }
        #else
            throw XCTSkip("Uses DEBUG-only PrivilegedOperationsCoordinator test overrides")
        #endif

        let coordinator = PrivilegedOperationsCoordinator.shared
        do {
            try await coordinator.installBundledKanata()
        } catch {
            XCTFail("Expected installBundledKanata to succeed after readiness recovered, got: \(error)")
        }
    }

    func testInstallBundledKanataIgnoresLaunchctl113ThresholdDuringRestartGrace() async throws {
#if DEBUG
            PrivilegedOperationsCoordinator.resetTestingState()
            PrivilegedOperationsCoordinator.serviceStateOverride = { .smappserviceActive }
            KanataDaemonManager.registeredButNotLoadedOverride = { false }
            PrivilegedOperationsCoordinator.installBundledKanataBinaryOverride = {}
            var probeCount = 0
            ServiceHealthChecker.runtimeSnapshotOverride = {
                probeCount += 1
                let ready = probeCount >= 4
                return ServiceHealthChecker.KanataServiceRuntimeSnapshot(
                    managementState: .smappserviceActive,
                    isRunning: ready,
                    isResponding: ready,
                    launchctlExitCode: ready ? 0 : 113,
                    staleEnabledRegistration: false,
                    recentlyRestarted: !ready
                )
            }
#endif

        let coordinator = PrivilegedOperationsCoordinator.shared
        do {
            try await coordinator.installBundledKanata()
        } catch {
            XCTFail("Expected restart grace window to suppress early launchctl 113 failure, got: \(error)")
        }
    }

    func testInstallBundledKanataFailsForHistoricalStaleThrottleAndLaunchctl113Sequence() async throws {
#if DEBUG
            PrivilegedOperationsCoordinator.resetTestingState()
            var installCallCount = 0
            PrivilegedOperationsCoordinator.installAllServicesOverride = {
                installCallCount += 1
            }

            // Seed throttle window with a normal install.
            PrivilegedOperationsCoordinator.serviceStateOverride = { .uninstalled }
            let coordinator = PrivilegedOperationsCoordinator.shared
            let firstInstall = try await coordinator.installServicesIfUninstalled(context: "seed-throttle")
            XCTAssertTrue(firstInstall)
            XCTAssertEqual(installCallCount, 1)

            // Historical sequence:
            // 1) Stale SMAppService registration is detected while still inside throttle window.
            // 2) Recovery must bypass throttle.
            // 3) launchctl repeatedly reports not-found and TCP remains unresponsive.
            PrivilegedOperationsCoordinator.serviceStateOverride = { .smappserviceActive }
            KanataDaemonManager.registeredButNotLoadedOverride = { true }
            PrivilegedOperationsCoordinator.installBundledKanataBinaryOverride = {}

            ServiceHealthChecker.runtimeSnapshotOverride = {
                ServiceHealthChecker.KanataServiceRuntimeSnapshot(
                    managementState: .smappserviceActive,
                    isRunning: false,
                    isResponding: false,
                    launchctlExitCode: 113,
                    staleEnabledRegistration: false,
                    recentlyRestarted: false
                )
            }
#else
            let coordinator = PrivilegedOperationsCoordinator.shared
#endif

        do {
            try await coordinator.installBundledKanata()
            XCTFail("Expected installBundledKanata to fail for persistent launchctl 113 + no TCP sequence")
        } catch let PrivilegedOperationError.operationFailed(message) {
            XCTAssertTrue(message.contains("postcondition failed"))
        } catch {
            XCTFail("Unexpected error type: \(error)")
        }

#if DEBUG
            XCTAssertEqual(
                installCallCount,
                2,
                "Stale recovery should run even inside throttle window, then fail on readiness postcondition"
            )
#endif
    }

    func testTerminateProcessRejectsInvalidPIDWithoutRunningCommands() async throws {
        let fakeExecutor = FakeAdminCommandExecutor()
        AdminCommandExecutorHolder.shared = fakeExecutor

        let coordinator = PrivilegedOperationsCoordinator.shared

        do {
            try await coordinator.terminateProcess(pid: 0)
            XCTFail("Expected terminateProcess to throw for invalid PID")
        } catch {
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
