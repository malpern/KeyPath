import Darwin
import Foundation
@testable import KeyPathAppKit
@testable import KeyPathCore
@testable import KeyPathInstallationWizard
@preconcurrency import XCTest

/// Tests for PrivilegedOperationsRouter
/// These verify the coordinator properly delegates to helper or sudo paths
@MainActor
final class PrivilegedOperationsRouterTests: XCTestCase {
    private nonisolated(unsafe) var originalExecutor: AdminCommandExecutor!
    private nonisolated(unsafe) var originalSudoEnv: String?
    private var previousSudoEnv: String?
    private nonisolated(unsafe) var originalAllowAdminOperationsInTests = false

    override func setUp() async throws {
        try await super.setUp()
        previousSudoEnv = ProcessInfo.processInfo.environment["KEYPATH_USE_SUDO"]
        setenv("KEYPATH_USE_SUDO", "0", 1)
        await MainActor.run {
            originalExecutor = AdminCommandExecutorHolder.shared
            originalSudoEnv = ProcessInfo.processInfo.environment["KEYPATH_USE_SUDO"]
            originalAllowAdminOperationsInTests = TestEnvironment.allowAdminOperationsInTests
            TestEnvironment.allowAdminOperationsInTests = false
            setenv("KEYPATH_USE_SUDO", "0", 1)
        }
    }

    override func tearDown() async throws {
        await MainActor.run {
            AdminCommandExecutorHolder.shared = originalExecutor
            #if DEBUG
                PrivilegedOperationsRouter.resetTestingState()
                KanataDaemonManager.registeredButNotLoadedOverride = nil
                ServiceHealthChecker.runtimeSnapshotOverride = nil
                ServiceHealthChecker.recentlyRestartedOverride = nil
                HelperManager.testHelperFunctionalityOverride = nil
            #endif
            TestEnvironment.allowAdminOperationsInTests = originalAllowAdminOperationsInTests
            if let originalSudoEnv {
                setenv("KEYPATH_USE_SUDO", originalSudoEnv, 1)
            } else {
                unsetenv("KEYPATH_USE_SUDO")
            }
            originalSudoEnv = nil
            originalAllowAdminOperationsInTests = false
        }
        if let previousSudoEnv {
            setenv("KEYPATH_USE_SUDO", previousSudoEnv, 1)
        } else {
            unsetenv("KEYPATH_USE_SUDO")
        }
        previousSudoEnv = nil
        try await super.tearDown()
    }

    func testInstallNewsyslogConfigExecutesWithoutCrash() async {
        // This test verifies that installNewsyslogConfig() executes without crashing.
        // In test mode, privileged operations are skipped via TestEnvironment.shouldSkipAdminOperations,
        // so we just verify the method completes (whether success or expected failure).
        // The actual implementation uses AdminCommandExecutor (backed by PrivilegedCommandRunner).

        let coordinator = PrivilegedOperationsRouter.shared

        do {
            try await coordinator.installNewsyslogConfig()
            // Success in test mode (admin ops skipped)
        } catch {
            // Also acceptable - may fail due to permissions in some test environments
            // The key thing is it didn't crash
        }
    }

    func testCoordinatorSingletonExists() {
        let coordinator = PrivilegedOperationsRouter.shared
        XCTAssertNotNil(coordinator, "Coordinator should be accessible")
    }

    func testOperationModeIsDirectSudoInTests() {
        XCTAssertEqual(
            PrivilegedOperationsRouter.operationMode,
            .directSudo,
            "Tests should use directSudo mode so they do not touch the installed helper"
        )
    }

    func testRestartKarabinerDaemonUsesSingleBatch() async throws {
        let fakeExecutor = FakeAdminCommandExecutor()
        AdminCommandExecutorHolder.shared = fakeExecutor
        VHIDDeviceManager.testPIDProvider = { ["123"] }
        defer {
            VHIDDeviceManager.testPIDProvider = nil
            AdminCommandExecutorHolder.shared = originalExecutor
        }

        let coordinator = PrivilegedOperationsRouter.shared
        let success = try await coordinator.restartKarabinerDaemonVerified()

        XCTAssertTrue(success)
        XCTAssertEqual(fakeExecutor.batches.count, 1)
    }

    func testInstallServicesIfUninstalledSkipsWhenApprovalPending() async throws {
        #if DEBUG
            PrivilegedOperationsRouter.resetTestingState()
            PrivilegedOperationsRouter.serviceStateOverride = { .smappservicePending }
            PrivilegedOperationsRouter.installAllServicesOverride = {
                XCTFail("Install should not run while SMAppService approval is pending")
            }
        #endif

        let coordinator = PrivilegedOperationsRouter.shared
        let didInstall = try await coordinator.installServicesIfUninstalled(context: "test-pending")
        XCTAssertFalse(didInstall)
    }

    func testInstallServicesIfUninstalledRunsInstallWhenUninstalled() async throws {
        #if DEBUG
            PrivilegedOperationsRouter.resetTestingState()
            var installCallCount = 0
            PrivilegedOperationsRouter.serviceStateOverride = { .uninstalled }
            PrivilegedOperationsRouter.installAllServicesOverride = {
                installCallCount += 1
            }
        #endif

        let coordinator = PrivilegedOperationsRouter.shared
        let didInstall = try await coordinator.installServicesIfUninstalled(context: "test-uninstalled")
        XCTAssertTrue(didInstall)
        #if DEBUG
            XCTAssertEqual(installCallCount, 1)
        #endif
    }

    func testInstallServicesIfUninstalledThrottlesRepeatedAttempts() async throws {
        #if DEBUG
            PrivilegedOperationsRouter.resetTestingState()
            var installCallCount = 0
            PrivilegedOperationsRouter.serviceStateOverride = { .uninstalled }
            PrivilegedOperationsRouter.installAllServicesOverride = {
                installCallCount += 1
            }
        #endif

        let coordinator = PrivilegedOperationsRouter.shared
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
            PrivilegedOperationsRouter.resetTestingState()
            var installCallCount = 0
            PrivilegedOperationsRouter.serviceStateOverride = { .smappserviceActive }
            KanataDaemonManager.registeredButNotLoadedOverride = { true }
            PrivilegedOperationsRouter.installAllServicesOverride = {
                installCallCount += 1
            }
        #endif

        let coordinator = PrivilegedOperationsRouter.shared
        let didInstall = try await coordinator.installServicesIfUninstalled(context: "test-stale-enabled")

        XCTAssertTrue(didInstall)
        #if DEBUG
            XCTAssertEqual(installCallCount, 1)
        #endif
    }

    func testInstallServicesIfUninstalledBypassesThrottleForStaleEnabledRecovery() async throws {
        #if DEBUG
            PrivilegedOperationsRouter.resetTestingState()
            var installCallCount = 0
            PrivilegedOperationsRouter.serviceStateOverride = { .smappserviceActive }
            KanataDaemonManager.registeredButNotLoadedOverride = { true }
            PrivilegedOperationsRouter.installAllServicesOverride = {
                installCallCount += 1
            }
        #endif

        let coordinator = PrivilegedOperationsRouter.shared
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
            PrivilegedOperationsRouter.resetTestingState()
            var installCallCount = 0
            PrivilegedOperationsRouter.serviceStateOverride = { .smappserviceActive }
            KanataDaemonManager.registeredButNotLoadedOverride = { true }
            PrivilegedOperationsRouter.installAllServicesOverride = {
                installCallCount += 1
            }
        #endif

        let coordinator = PrivilegedOperationsRouter.shared
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
            PrivilegedOperationsRouter.resetTestingState()
            var installCallCount = 0
            PrivilegedOperationsRouter.serviceStateOverride = { .smappserviceActive }
            KanataDaemonManager.registeredButNotLoadedOverride = { false }
            PrivilegedOperationsRouter.installAllServicesOverride = {
                installCallCount += 1
            }
        #endif

        let coordinator = PrivilegedOperationsRouter.shared
        let didInstall = try await coordinator.installServicesIfUninstalled(context: "test-healthy-enabled")

        XCTAssertFalse(didInstall)
        #if DEBUG
            XCTAssertEqual(installCallCount, 0)
        #endif
    }

    func testRestartUnhealthyServicesFailsWhenPostconditionTimesOut() async throws {
        #if DEBUG
            PrivilegedOperationsRouter.resetTestingState()
            PrivilegedOperationsRouter.serviceStateOverride = { .smappserviceActive }
            KanataDaemonManager.registeredButNotLoadedOverride = { false }
            PrivilegedOperationsRouter.killExistingKanataProcessesOverride = {}
            PrivilegedOperationsRouter.kanataReadinessOverride = { _ in .timedOut }
        #endif

        let coordinator = PrivilegedOperationsRouter.shared
        do {
            try await coordinator.recoverRequiredRuntimeServices()
            XCTFail("Expected recoverRequiredRuntimeServices to fail when postcondition does not become ready")
        } catch let PrivilegedOperationError.operationFailed(message) {
            XCTAssertTrue(message.contains("postcondition failed"))
        } catch {
            XCTFail("Unexpected error type: \(error)")
        }
    }

    func testRestartUnhealthyServicesClearsExistingKanataProcessesBeforeRestart() async throws {
        #if DEBUG
            PrivilegedOperationsRouter.resetTestingState()
            PrivilegedOperationsRouter.serviceStateOverride = { .smappserviceActive }
            KanataDaemonManager.registeredButNotLoadedOverride = { false }
            var killCalls = 0
            PrivilegedOperationsRouter.killExistingKanataProcessesOverride = {
                killCalls += 1
            }
            PrivilegedOperationsRouter.kanataReadinessOverride = { _ in .ready }
        #else
            throw XCTSkip("Uses DEBUG-only PrivilegedOperationsRouter test overrides")
        #endif

        let coordinator = PrivilegedOperationsRouter.shared
        try await coordinator.recoverRequiredRuntimeServices()

        #if DEBUG
            XCTAssertEqual(killCalls, 1)
        #endif
    }

    func testHelperBackedVHIDRepairFailsWhenPostconditionFails() async throws {
        #if DEBUG
            PrivilegedOperationsRouter.resetTestingState()
            PrivilegedOperationsRouter.operationModeOverride = .privilegedHelper
            HelperManager.testHelperFunctionalityOverride = { true }
            var helperRepairCalls = 0
            PrivilegedOperationsRouter.helperRepairVHIDDaemonServicesOverride = {
                helperRepairCalls += 1
            }
            PrivilegedOperationsRouter.vhidServicesPostconditionOverride = { _ in false }
        #else
            throw XCTSkip("Uses DEBUG-only PrivilegedOperationsRouter test overrides")
        #endif

        let coordinator = PrivilegedOperationsRouter.shared
        do {
            try await coordinator.repairVHIDDaemonServices()
            XCTFail("Expected helper-backed VHID repair to fail when postcondition fails")
        } catch let PrivilegedOperationError.operationFailed(message) {
            XCTAssertTrue(message.contains("VHID services postcondition failed"))
        } catch {
            XCTFail("Unexpected error type: \(error)")
        }

        #if DEBUG
            XCTAssertEqual(helperRepairCalls, 1)
        #endif
    }

    func testLostHelperReplyWithSatisfiedPostconditionSkipsFallback() async throws {
        #if DEBUG
            PrivilegedOperationsRouter.resetTestingState()
            PrivilegedOperationsRouter.operationModeOverride = .privilegedHelper
            PrivilegedOperationsRouter.helperRepairVHIDDaemonServicesOverride = {
                throw HelperManagerError.ambiguousOutcome("reply lost")
            }
            PrivilegedOperationsRouter.vhidServicesPostconditionOverride = { _ in true }
            var fallbackCalls = 0
            PrivilegedOperationsRouter.sudoRepairVHIDServicesOverride = { fallbackCalls += 1 }
        #else
            throw XCTSkip("Uses DEBUG-only PrivilegedOperationsRouter test overrides")
        #endif

        try await PrivilegedOperationsRouter.shared.repairVHIDDaemonServices()

        #if DEBUG
            XCTAssertEqual(fallbackCalls, 0)
        #endif
    }

    func testFailedHelperWithUnsatisfiedPostconditionInvokesFallbackOnce() async throws {
        #if DEBUG
            PrivilegedOperationsRouter.resetTestingState()
            PrivilegedOperationsRouter.operationModeOverride = .privilegedHelper
            PrivilegedOperationsRouter.helperRepairVHIDDaemonServicesOverride = {
                throw HelperManagerError.operationFailed("failed")
            }
            var verificationCalls = 0
            PrivilegedOperationsRouter.vhidServicesPostconditionOverride = { _ in
                verificationCalls += 1
                return verificationCalls > 1
            }
            var fallbackCalls = 0
            PrivilegedOperationsRouter.sudoRepairVHIDServicesOverride = { fallbackCalls += 1 }
        #else
            throw XCTSkip("Uses DEBUG-only PrivilegedOperationsRouter test overrides")
        #endif

        try await PrivilegedOperationsRouter.shared.repairVHIDDaemonServices()

        #if DEBUG
            XCTAssertEqual(fallbackCalls, 1)
            XCTAssertEqual(verificationCalls, 2)
        #endif
    }

    func testRuntimeRecoveryLostHelperReplyWithReadyRuntimeSkipsFallback() async throws {
        #if DEBUG
            PrivilegedOperationsRouter.resetTestingState()
            PrivilegedOperationsRouter.operationModeOverride = .privilegedHelper
            PrivilegedOperationsRouter.serviceStateOverride = { .smappserviceActive }
            KanataDaemonManager.registeredButNotLoadedOverride = { false }
            PrivilegedOperationsRouter.killExistingKanataProcessesOverride = {}
            PrivilegedOperationsRouter.helperRecoverRequiredRuntimeServicesOverride = {
                throw HelperManagerError.ambiguousOutcome("reply lost")
            }
            PrivilegedOperationsRouter.kanataReadinessOverride = { _ in .ready }
            var fallbackCalls = 0
            PrivilegedOperationsRouter.sudoRestartServicesOverride = { fallbackCalls += 1 }
        #else
            throw XCTSkip("Uses DEBUG-only PrivilegedOperationsRouter test overrides")
        #endif

        try await PrivilegedOperationsRouter.shared.recoverRequiredRuntimeServices()

        #if DEBUG
            XCTAssertEqual(fallbackCalls, 0)
        #endif
    }

    func testRuntimeRecoveryLostKillReplyWithStoppedRuntimeSkipsKillFallback() async throws {
        #if DEBUG
            PrivilegedOperationsRouter.resetTestingState()
            PrivilegedOperationsRouter.operationModeOverride = .privilegedHelper
            PrivilegedOperationsRouter.serviceStateOverride = { .smappserviceActive }
            KanataDaemonManager.registeredButNotLoadedOverride = { false }
            PrivilegedOperationsRouter.helperKillAllKanataOverride = {
                throw HelperManagerError.ambiguousOutcome("reply lost")
            }
            PrivilegedOperationsRouter.kanataStoppedPostconditionOverride = { _ in true }
            var killFallbackCalls = 0
            PrivilegedOperationsRouter.sudoKillAllKanataOverride = { killFallbackCalls += 1 }
            PrivilegedOperationsRouter.helperRecoverRequiredRuntimeServicesOverride = {}
            PrivilegedOperationsRouter.kanataReadinessOverride = { _ in .ready }
        #else
            throw XCTSkip("Uses DEBUG-only PrivilegedOperationsRouter test overrides")
        #endif

        try await PrivilegedOperationsRouter.shared.recoverRequiredRuntimeServices()

        #if DEBUG
            XCTAssertEqual(killFallbackCalls, 0)
        #endif
    }

    func testNewsyslogLostHelperReplyWithInstalledConfigSkipsFallback() async throws {
        #if DEBUG
            PrivilegedOperationsRouter.resetTestingState()
            PrivilegedOperationsRouter.operationModeOverride = .privilegedHelper
            PrivilegedOperationsRouter.helperInstallNewsyslogConfigOverride = {
                throw HelperManagerError.ambiguousOutcome("reply lost")
            }
            PrivilegedOperationsRouter.newsyslogPostconditionOverride = { true }
            var fallbackCalls = 0
            PrivilegedOperationsRouter.sudoInstallNewsyslogConfigOverride = { fallbackCalls += 1 }
        #else
            throw XCTSkip("Uses DEBUG-only PrivilegedOperationsRouter test overrides")
        #endif

        try await PrivilegedOperationsRouter.shared.installNewsyslogConfig()

        #if DEBUG
            XCTAssertEqual(fallbackCalls, 0)
        #endif
    }

    func testDriverInstallLostHelperReplyWithInstalledDriverSkipsFallback() async throws {
        #if DEBUG
            PrivilegedOperationsRouter.resetTestingState()
            PrivilegedOperationsRouter.operationModeOverride = .privilegedHelper
            PrivilegedOperationsRouter.bundledVHIDDriverPackagePathOverride = { "/tmp/test-driver.pkg" }
            PrivilegedOperationsRouter.helperInstallCorrectVHIDDriverOverride = {
                throw HelperManagerError.ambiguousOutcome("reply lost")
            }
            PrivilegedOperationsRouter.vhidDriverPostconditionOverride = { _ in true }
            var fallbackCalls = 0
            PrivilegedOperationsRouter.sudoInstallCorrectVHIDDriverOverride = { fallbackCalls += 1 }
        #else
            throw XCTSkip("Uses DEBUG-only PrivilegedOperationsRouter test overrides")
        #endif

        try await PrivilegedOperationsRouter.shared.downloadAndInstallCorrectVHIDDriver()

        #if DEBUG
            XCTAssertEqual(fallbackCalls, 0)
        #endif
    }

    func testProcessTerminationLostHelperReplyWithExitedProcessSkipsFallback() async throws {
        #if DEBUG
            PrivilegedOperationsRouter.resetTestingState()
            PrivilegedOperationsRouter.operationModeOverride = .privilegedHelper
            PrivilegedOperationsRouter.helperTerminateProcessOverride = { _ in
                throw HelperManagerError.ambiguousOutcome("reply lost")
            }
            PrivilegedOperationsRouter.processTerminatedPostconditionOverride = { _, _ in true }
            var fallbackCalls = 0
            PrivilegedOperationsRouter.sudoTerminateProcessOverride = { _ in fallbackCalls += 1 }
        #else
            throw XCTSkip("Uses DEBUG-only PrivilegedOperationsRouter test overrides")
        #endif

        try await PrivilegedOperationsRouter.shared.terminateProcess(pid: 42)

        #if DEBUG
            XCTAssertEqual(fallbackCalls, 0)
        #endif
    }

    func testKillAllLostHelperReplyWithStoppedRuntimeSkipsFallback() async throws {
        #if DEBUG
            PrivilegedOperationsRouter.resetTestingState()
            PrivilegedOperationsRouter.operationModeOverride = .privilegedHelper
            PrivilegedOperationsRouter.helperKillAllKanataOverride = {
                throw HelperManagerError.ambiguousOutcome("reply lost")
            }
            PrivilegedOperationsRouter.kanataStoppedPostconditionOverride = { _ in true }
            var fallbackCalls = 0
            PrivilegedOperationsRouter.sudoKillAllKanataOverride = { fallbackCalls += 1 }
        #else
            throw XCTSkip("Uses DEBUG-only PrivilegedOperationsRouter test overrides")
        #endif

        try await PrivilegedOperationsRouter.shared.killAllKanataProcesses()

        #if DEBUG
            XCTAssertEqual(fallbackCalls, 0)
        #endif
    }

    func testKillAllFailedHelperWithRunningRuntimeInvokesFallbackOnce() async throws {
        #if DEBUG
            PrivilegedOperationsRouter.resetTestingState()
            PrivilegedOperationsRouter.operationModeOverride = .privilegedHelper
            PrivilegedOperationsRouter.helperKillAllKanataOverride = {
                throw HelperManagerError.operationFailed("failed")
            }
            var verificationCalls = 0
            PrivilegedOperationsRouter.kanataStoppedPostconditionOverride = { _ in
                verificationCalls += 1
                return verificationCalls > 1
            }
            var fallbackCalls = 0
            PrivilegedOperationsRouter.sudoKillAllKanataOverride = { fallbackCalls += 1 }
        #else
            throw XCTSkip("Uses DEBUG-only PrivilegedOperationsRouter test overrides")
        #endif

        try await PrivilegedOperationsRouter.shared.killAllKanataProcesses()

        #if DEBUG
            XCTAssertEqual(fallbackCalls, 1)
            XCTAssertEqual(verificationCalls, 2)
        #endif
    }

    func testRuntimeInstallUsesSMAppServiceAwareInstallPathBeforeKanataPostcondition() async throws {
        #if DEBUG
            PrivilegedOperationsRouter.resetTestingState()
            PrivilegedOperationsRouter.operationModeOverride = .privilegedHelper
            var installAllServicesCalls = 0
            PrivilegedOperationsRouter.installAllServicesOverride = {
                installAllServicesCalls += 1
            }
            PrivilegedOperationsRouter.vhidServicesPostconditionOverride = { _ in true }
            PrivilegedOperationsRouter.kanataReadinessOverride = { _ in .timedOut }
        #else
            throw XCTSkip("Uses DEBUG-only PrivilegedOperationsRouter test overrides")
        #endif

        let coordinator = PrivilegedOperationsRouter.shared
        do {
            try await coordinator.installRequiredRuntimeServices()
            XCTFail("Expected runtime install to fail when Kanata postcondition fails")
        } catch let PrivilegedOperationError.operationFailed(message) {
            XCTAssertTrue(message.contains("Kanata postcondition failed"))
        } catch {
            XCTFail("Unexpected error type: \(error)")
        }

        #if DEBUG
            XCTAssertEqual(installAllServicesCalls, 1)
        #endif
    }

    func testActivateVirtualHIDManagerFailsWhenPostconditionFails() async throws {
        #if DEBUG
            PrivilegedOperationsRouter.resetTestingState()
            var activationCalls = 0
            PrivilegedOperationsRouter.activateVirtualHIDManagerOverride = {
                activationCalls += 1
            }
            PrivilegedOperationsRouter.vhidServicesPostconditionOverride = { _ in false }
        #else
            throw XCTSkip("Uses DEBUG-only PrivilegedOperationsRouter test overrides")
        #endif

        let coordinator = PrivilegedOperationsRouter.shared
        do {
            try await coordinator.activateVirtualHIDManager()
            XCTFail("Expected activateVirtualHIDManager to fail when postcondition fails")
        } catch let PrivilegedOperationError.operationFailed(message) {
            XCTAssertTrue(message.contains("VHID services postcondition failed"))
        } catch {
            XCTFail("Unexpected error type: \(error)")
        }

        #if DEBUG
            XCTAssertEqual(activationCalls, 1)
        #endif
    }

    func testDownloadAndInstallCorrectVHIDDriverFailsWhenDriverPostconditionFails() async throws {
        #if DEBUG
            PrivilegedOperationsRouter.resetTestingState()
            var installCalls = 0
            PrivilegedOperationsRouter.downloadAndInstallCorrectVHIDDriverOverride = {
                installCalls += 1
            }
            PrivilegedOperationsRouter.vhidDriverPostconditionOverride = { _ in false }
        #else
            throw XCTSkip("Uses DEBUG-only PrivilegedOperationsRouter test overrides")
        #endif

        let coordinator = PrivilegedOperationsRouter.shared
        do {
            try await coordinator.downloadAndInstallCorrectVHIDDriver()
            XCTFail("Expected downloadAndInstallCorrectVHIDDriver to fail when postcondition fails")
        } catch let PrivilegedOperationError.operationFailed(message) {
            XCTAssertTrue(message.contains("VHID driver postcondition failed"))
        } catch {
            XCTFail("Unexpected error type: \(error)")
        }

        #if DEBUG
            XCTAssertEqual(installCalls, 1)
        #endif
    }

    func testDownloadAndInstallCorrectVHIDDriverAllowsInstalledButNotEnabledPostcondition() async throws {
        #if DEBUG
            PrivilegedOperationsRouter.resetTestingState()
            var installCalls = 0
            PrivilegedOperationsRouter.downloadAndInstallCorrectVHIDDriverOverride = {
                installCalls += 1
            }
            ServiceHealthChecker.vhidDriverExtensionStatusOverride = { .installedButNotEnabled }
        #else
            throw XCTSkip("Uses DEBUG-only PrivilegedOperationsRouter test overrides")
        #endif

        let coordinator = PrivilegedOperationsRouter.shared
        try await coordinator.downloadAndInstallCorrectVHIDDriver()

        #if DEBUG
            XCTAssertEqual(installCalls, 1)
        #endif
    }

    func testTerminateProcessFailsWhenPostconditionFails() async throws {
        #if DEBUG
            PrivilegedOperationsRouter.resetTestingState()
            PrivilegedOperationsRouter.processTerminatedPostconditionOverride = { _, _ in false }
        #else
            throw XCTSkip("Uses DEBUG-only PrivilegedOperationsRouter test overrides")
        #endif
        let fakeExecutor = FakeAdminCommandExecutor()
        AdminCommandExecutorHolder.shared = fakeExecutor

        let coordinator = PrivilegedOperationsRouter.shared
        do {
            try await coordinator.terminateProcess(pid: 12345)
            XCTFail("Expected terminateProcess to fail when postcondition fails")
        } catch let PrivilegedOperationError.operationFailed(message) {
            XCTAssertTrue(message.contains("Process termination postcondition failed"))
        } catch {
            XCTFail("Unexpected error type: \(error)")
        }

        XCTAssertEqual(fakeExecutor.commands.count, 1)
        XCTAssertEqual(fakeExecutor.commands.first?.description, "Terminate process 12345")
    }

    func testTerminateProcessWaitsForProcessToExitAfterCommandSuccess() async throws {
        #if DEBUG
            PrivilegedOperationsRouter.resetTestingState()
        #else
            throw XCTSkip("Uses DEBUG-only PrivilegedOperationsRouter test setup")
        #endif

        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/bin/sleep")
        process.arguments = ["5"]
        try process.run()
        defer {
            if process.isRunning {
                process.terminate()
            }
        }

        let pid = Int32(process.processIdentifier)
        let fakeExecutor = FakeAdminCommandExecutor(resultProvider: { _, description in
            if description == "Terminate process \(pid)" {
                DispatchQueue.global().asyncAfter(deadline: .now() + 0.2) {
                    Darwin.kill(pid, SIGTERM)
                }
            }
            return CommandExecutionResult(exitCode: 0, output: "")
        })
        AdminCommandExecutorHolder.shared = fakeExecutor

        let coordinator = PrivilegedOperationsRouter.shared
        try await coordinator.terminateProcess(pid: pid)

        XCTAssertEqual(fakeExecutor.commands.count, 1)
    }

    func testKillAllKanataProcessesFailsWhenPostconditionFails() async throws {
        #if DEBUG
            PrivilegedOperationsRouter.resetTestingState()
            PrivilegedOperationsRouter.kanataStoppedPostconditionOverride = { _ in false }
        #else
            throw XCTSkip("Uses DEBUG-only PrivilegedOperationsRouter test overrides")
        #endif
        let fakeExecutor = FakeAdminCommandExecutor()
        AdminCommandExecutorHolder.shared = fakeExecutor

        let coordinator = PrivilegedOperationsRouter.shared
        do {
            try await coordinator.killAllKanataProcesses()
            XCTFail("Expected killAllKanataProcesses to fail when postcondition fails")
        } catch let PrivilegedOperationError.operationFailed(message) {
            XCTAssertTrue(message.contains("Kanata stopped postcondition failed"))
        } catch {
            XCTFail("Unexpected error type: \(error)")
        }

        XCTAssertEqual(fakeExecutor.commands.count, 1)
        XCTAssertEqual(fakeExecutor.commands.first?.description, "Kill all Kanata processes")
    }

    func testRegenerateServiceConfigurationAllowsPendingApprovalPostcondition() async throws {
        #if DEBUG
            PrivilegedOperationsRouter.resetTestingState()
            PrivilegedOperationsRouter.kanataReadinessOverride = { _ in .pendingApproval }
        #endif

        let coordinator = PrivilegedOperationsRouter.shared
        do {
            try await coordinator.regenerateServiceConfiguration()
        } catch {
            XCTFail("Expected regenerateServiceConfiguration to accept pending approval, got: \(error)")
        }
    }

    func testTerminateProcessRejectsInvalidPIDWithoutRunningCommands() async throws {
        let fakeExecutor = FakeAdminCommandExecutor()
        AdminCommandExecutorHolder.shared = fakeExecutor

        let coordinator = PrivilegedOperationsRouter.shared

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
