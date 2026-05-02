import Foundation
@testable @_spi(ServiceInstallTesting) import KeyPathAppKit
@testable import KeyPathInstallationWizard
@testable import KeyPathCore
@preconcurrency import XCTest

/// Golden tests that capture the current behavior of PrivilegedOperationsCoordinator before
/// the runtime simplification refactor (see `docs/analysis/runtime-layer-simplification-plan.md`).
///
/// These tests must pass both before and after the refactor — they prove behavioral
/// equivalence as `decideInstallGuard`, `verifyKanataReadinessAfterInstall`, and the
/// `KanataReadinessResult` / `InstallGuardDecision` value types migrate to their new homes
/// (`InstallerEngine` precondition / postcondition, `ServiceHealthChecker`).
///
/// Same approach as the wizard simplification (Tests/KeyPathTests/InstallationWizard/WizardGoldenTests.swift).
///
/// Naming convention: `test_<scenario>_<expectedBehavior>`.
@MainActor
final class PrivilegedOperationsGoldenTests: XCTestCase {
    private nonisolated(unsafe) var originalExecutor: AdminCommandExecutor!

    override func setUp() async throws {
        try await super.setUp()
        await MainActor.run {
            originalExecutor = AdminCommandExecutorHolder.shared
            #if DEBUG
                PrivilegedOperationsCoordinator.resetTestingState()
            #endif
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

    // MARK: - decideInstallGuard: Pure Decision Matrix

    /// Pending approval short-circuits all other logic — never run install while
    /// SMAppService awaits user approval in System Settings.
    func test_decideInstallGuard_pendingApproval_returnsSkipPendingApproval() {
        #if DEBUG
            PrivilegedOperationsCoordinator._testResetServiceInstallGuard()
            let decision = PrivilegedOperationsCoordinator._testDecideInstallGuard(
                state: .smappservicePending,
                staleEnabledRegistration: false
            )
            XCTAssertEqual(decision, .skipPendingApproval)
        #endif
    }

    /// Pending approval beats stale flag — approval gate is the highest priority.
    func test_decideInstallGuard_pendingApprovalWithStaleFlag_stillSkips() {
        #if DEBUG
            PrivilegedOperationsCoordinator._testResetServiceInstallGuard()
            let decision = PrivilegedOperationsCoordinator._testDecideInstallGuard(
                state: .smappservicePending,
                staleEnabledRegistration: true
            )
            XCTAssertEqual(decision, .skipPendingApproval)
        #endif
    }

    /// Healthy enabled SMAppService should not trigger install.
    func test_decideInstallGuard_smappserviceHealthy_returnsSkipNoInstall() {
        #if DEBUG
            PrivilegedOperationsCoordinator._testResetServiceInstallGuard()
            let decision = PrivilegedOperationsCoordinator._testDecideInstallGuard(
                state: .smappserviceActive,
                staleEnabledRegistration: false
            )
            XCTAssertEqual(decision, .skipNoInstall)
        #endif
    }

    /// Unknown state with no stale flag — no install needed.
    func test_decideInstallGuard_unknownNoStale_returnsSkipNoInstall() {
        #if DEBUG
            PrivilegedOperationsCoordinator._testResetServiceInstallGuard()
            let decision = PrivilegedOperationsCoordinator._testDecideInstallGuard(
                state: .unknown,
                staleEnabledRegistration: false
            )
            XCTAssertEqual(decision, .skipNoInstall)
        #endif
    }

    /// Uninstalled with no prior attempt — run install (no throttle to honor).
    func test_decideInstallGuard_uninstalledNoLastAttempt_returnsRun() {
        #if DEBUG
            PrivilegedOperationsCoordinator._testResetServiceInstallGuard()
            let decision = PrivilegedOperationsCoordinator._testDecideInstallGuard(
                state: .uninstalled,
                staleEnabledRegistration: false,
                now: Date(),
                lastAttempt: nil
            )
            XCTAssertEqual(
                decision,
                .run(reason: "state=Uninstalled", bypassedThrottle: false)
            )
        #endif
    }

    /// Legacy plist present — migration path runs install.
    func test_decideInstallGuard_legacyActive_returnsRunForMigration() {
        #if DEBUG
            PrivilegedOperationsCoordinator._testResetServiceInstallGuard()
            let decision = PrivilegedOperationsCoordinator._testDecideInstallGuard(
                state: .legacyActive,
                staleEnabledRegistration: false,
                now: Date(),
                lastAttempt: nil
            )
            XCTAssertEqual(
                decision,
                .run(reason: "state=Legacy launchctl", bypassedThrottle: false)
            )
        #endif
    }

    /// Conflicted state (legacy + SMAppService both active) — run install to resolve.
    func test_decideInstallGuard_conflicted_returnsRunForMigration() {
        #if DEBUG
            PrivilegedOperationsCoordinator._testResetServiceInstallGuard()
            let decision = PrivilegedOperationsCoordinator._testDecideInstallGuard(
                state: .conflicted,
                staleEnabledRegistration: false,
                now: Date(),
                lastAttempt: nil
            )
            XCTAssertEqual(
                decision,
                .run(reason: "state=Conflicted (both methods active)", bypassedThrottle: false)
            )
        #endif
    }

    /// Within the 30-second throttle window — skip install.
    func test_decideInstallGuard_uninstalledWithinThrottleWindow_returnsThrottled() {
        #if DEBUG
            PrivilegedOperationsCoordinator._testResetServiceInstallGuard()
            let now = Date()
            let recent = now.addingTimeInterval(-5) // 5s ago, within 30s throttle
            let decision = PrivilegedOperationsCoordinator._testDecideInstallGuard(
                state: .uninstalled,
                staleEnabledRegistration: false,
                now: now,
                lastAttempt: recent
            )
            guard case let .throttled(remaining) = decision else {
                XCTFail("Expected .throttled, got \(decision)")
                return
            }
            XCTAssertGreaterThan(remaining, 24, "Should have ~25s remaining")
            XCTAssertLessThanOrEqual(remaining, 25)
        #endif
    }

    /// Outside the throttle window — run install again.
    func test_decideInstallGuard_uninstalledOutsideThrottleWindow_returnsRun() {
        #if DEBUG
            PrivilegedOperationsCoordinator._testResetServiceInstallGuard()
            let now = Date()
            let stale = now.addingTimeInterval(-60) // 60s ago, outside 30s throttle
            let decision = PrivilegedOperationsCoordinator._testDecideInstallGuard(
                state: .uninstalled,
                staleEnabledRegistration: false,
                now: now,
                lastAttempt: stale
            )
            XCTAssertEqual(
                decision,
                .run(reason: "state=Uninstalled", bypassedThrottle: false)
            )
        #endif
    }

    // MARK: - decideInstallGuard: Stale Recovery Counter

    /// Stale recovery on enabled SMAppService — bypass throttle for first 3 attempts.
    func test_decideInstallGuard_staleRecoveryAttempt1_bypassesThrottle() {
        #if DEBUG
            PrivilegedOperationsCoordinator._testResetServiceInstallGuard()
            let decision = PrivilegedOperationsCoordinator._testDecideInstallGuard(
                state: .smappserviceActive,
                staleEnabledRegistration: true
            )
            XCTAssertEqual(
                decision,
                .run(reason: "stale-enabled-registration (recovery-attempt=1)", bypassedThrottle: true)
            )
        #endif
    }

    /// Each consecutive stale recovery increments the counter — attempts 2 and 3 also bypass.
    func test_decideInstallGuard_staleRecoveryAttempts2And3_bypassThrottle() {
        #if DEBUG
            PrivilegedOperationsCoordinator._testResetServiceInstallGuard()

            _ = PrivilegedOperationsCoordinator._testDecideInstallGuard(
                state: .smappserviceActive,
                staleEnabledRegistration: true
            )
            let second = PrivilegedOperationsCoordinator._testDecideInstallGuard(
                state: .smappserviceActive,
                staleEnabledRegistration: true
            )
            let third = PrivilegedOperationsCoordinator._testDecideInstallGuard(
                state: .smappserviceActive,
                staleEnabledRegistration: true
            )
            XCTAssertEqual(
                second,
                .run(reason: "stale-enabled-registration (recovery-attempt=2)", bypassedThrottle: true)
            )
            XCTAssertEqual(
                third,
                .run(reason: "stale-enabled-registration (recovery-attempt=3)", bypassedThrottle: true)
            )
        #endif
    }

    /// After 3 bypasses, throttle applies even for stale recovery (when within the window).
    func test_decideInstallGuard_staleRecoveryAttempt4_appliesThrottle() {
        #if DEBUG
            PrivilegedOperationsCoordinator._testResetServiceInstallGuard()
            let now = Date()
            // Exhaust the 3 bypass attempts.
            for _ in 1 ... 3 {
                _ = PrivilegedOperationsCoordinator._testDecideInstallGuard(
                    state: .smappserviceActive,
                    staleEnabledRegistration: true,
                    now: now
                )
            }

            // 4th attempt with recent lastAttempt should be throttled.
            let fourth = PrivilegedOperationsCoordinator._testDecideInstallGuard(
                state: .smappserviceActive,
                staleEnabledRegistration: true,
                now: now,
                lastAttempt: now
            )
            guard case .throttled = fourth else {
                XCTFail("Expected .throttled after 3 bypasses, got \(fourth)")
                return
            }
        #endif
    }

    /// Beyond the bypass cap, but with the throttle window expired, the decision is
    /// .run with `bypassedThrottle == false` (throttle applied, ran anyway because
    /// the timer is up).
    func test_decideInstallGuard_staleRecoveryBeyondCap_runsWhenThrottleWindowExpired() {
        #if DEBUG
            PrivilegedOperationsCoordinator._testResetServiceInstallGuard()
            let now = Date()

            // Exhaust the 3 bypass attempts.
            for _ in 1 ... 3 {
                _ = PrivilegedOperationsCoordinator._testDecideInstallGuard(
                    state: .smappserviceActive,
                    staleEnabledRegistration: true,
                    now: now
                )
            }

            // 4th attempt outside throttle window should run (no throttle bypass).
            let fourth = PrivilegedOperationsCoordinator._testDecideInstallGuard(
                state: .smappserviceActive,
                staleEnabledRegistration: true,
                now: now.addingTimeInterval(60),
                lastAttempt: now
            )
            XCTAssertEqual(
                fourth,
                .run(
                    reason: "stale-enabled-registration (throttle-applied after 3 bypasses)",
                    bypassedThrottle: false
                )
            )
        #endif
    }

    /// Counter resets when system becomes healthy (skipNoInstall path).
    func test_decideInstallGuard_staleRecoveryCounterResetsAfterHealthy() {
        #if DEBUG
            PrivilegedOperationsCoordinator._testResetServiceInstallGuard()

            // Use 2 stale attempts.
            _ = PrivilegedOperationsCoordinator._testDecideInstallGuard(
                state: .smappserviceActive,
                staleEnabledRegistration: true
            )
            _ = PrivilegedOperationsCoordinator._testDecideInstallGuard(
                state: .smappserviceActive,
                staleEnabledRegistration: true
            )

            // System becomes healthy.
            let healthy = PrivilegedOperationsCoordinator._testDecideInstallGuard(
                state: .smappserviceActive,
                staleEnabledRegistration: false
            )
            XCTAssertEqual(healthy, .skipNoInstall)

            // Next stale event starts fresh at attempt 1.
            let fresh = PrivilegedOperationsCoordinator._testDecideInstallGuard(
                state: .smappserviceActive,
                staleEnabledRegistration: true
            )
            XCTAssertEqual(
                fresh,
                .run(reason: "stale-enabled-registration (recovery-attempt=1)", bypassedThrottle: true)
            )
        #endif
    }

    /// Counter also resets when a non-stale install runs (the `else` branch in
    /// `decideInstallGuard` clears the counter when `staleEnabledRegistration == false`
    /// during an install path).
    func test_decideInstallGuard_staleCounterResetsOnNonStaleRun() {
        #if DEBUG
            PrivilegedOperationsCoordinator._testResetServiceInstallGuard()

            // Two stale attempts.
            _ = PrivilegedOperationsCoordinator._testDecideInstallGuard(
                state: .smappserviceActive,
                staleEnabledRegistration: true
            )
            _ = PrivilegedOperationsCoordinator._testDecideInstallGuard(
                state: .smappserviceActive,
                staleEnabledRegistration: true
            )

            // Non-stale install path — should reset counter.
            let now = Date()
            _ = PrivilegedOperationsCoordinator._testDecideInstallGuard(
                state: .uninstalled,
                staleEnabledRegistration: false,
                now: now,
                lastAttempt: nil
            )

            // New stale event starts fresh at attempt 1.
            let fresh = PrivilegedOperationsCoordinator._testDecideInstallGuard(
                state: .smappserviceActive,
                staleEnabledRegistration: true
            )
            XCTAssertEqual(
                fresh,
                .run(reason: "stale-enabled-registration (recovery-attempt=1)", bypassedThrottle: true)
            )
        #endif
    }

    // MARK: - KanataReadinessResult: Value Type Invariants

    func test_kanataReadinessResult_ready_isSuccess() {
        XCTAssertTrue(PrivilegedOperationsCoordinator.KanataReadinessResult.ready.isSuccess)
    }

    func test_kanataReadinessResult_pendingApproval_isSuccess() {
        XCTAssertTrue(PrivilegedOperationsCoordinator.KanataReadinessResult.pendingApproval.isSuccess)
    }

    func test_kanataReadinessResult_staleRegistration_isFailure() {
        XCTAssertFalse(PrivilegedOperationsCoordinator.KanataReadinessResult.staleRegistration.isSuccess)
    }

    func test_kanataReadinessResult_launchctlNotFoundPersistent_isFailure() {
        XCTAssertFalse(
            PrivilegedOperationsCoordinator.KanataReadinessResult.launchctlNotFoundPersistent.isSuccess
        )
    }

    func test_kanataReadinessResult_tcpPortInUse_isFailure() {
        XCTAssertFalse(PrivilegedOperationsCoordinator.KanataReadinessResult.tcpPortInUse.isSuccess)
    }

    func test_kanataReadinessResult_timedOut_isFailure() {
        XCTAssertFalse(PrivilegedOperationsCoordinator.KanataReadinessResult.timedOut.isSuccess)
    }

    /// Failure descriptions are surfaced in user-visible error messages — they must be
    /// non-empty for every case.
    func test_kanataReadinessResult_allCasesHaveNonEmptyDescription() {
        let cases: [PrivilegedOperationsCoordinator.KanataReadinessResult] = [
            .ready, .pendingApproval, .staleRegistration,
            .launchctlNotFoundPersistent, .tcpPortInUse, .timedOut,
        ]
        for c in cases {
            XCTAssertFalse(
                c.failureDescription.isEmpty,
                "KanataReadinessResult.\(c) must have a non-empty failureDescription"
            )
        }
    }

    /// Each failure description should be unique (so callers can distinguish causes
    /// in logs and error reports).
    func test_kanataReadinessResult_failureDescriptionsAreUnique() {
        let descriptions: [String] = [
            PrivilegedOperationsCoordinator.KanataReadinessResult.ready.failureDescription,
            PrivilegedOperationsCoordinator.KanataReadinessResult.pendingApproval.failureDescription,
            PrivilegedOperationsCoordinator.KanataReadinessResult.staleRegistration.failureDescription,
            PrivilegedOperationsCoordinator.KanataReadinessResult.launchctlNotFoundPersistent.failureDescription,
            PrivilegedOperationsCoordinator.KanataReadinessResult.tcpPortInUse.failureDescription,
            PrivilegedOperationsCoordinator.KanataReadinessResult.timedOut.failureDescription,
        ]
        XCTAssertEqual(Set(descriptions).count, descriptions.count)
    }

    // MARK: - InstallGuardDecision: Value Type Invariants

    func test_installGuardDecision_skipNoInstall_isEquatable() {
        XCTAssertEqual(
            PrivilegedOperationsCoordinator.InstallGuardDecision.skipNoInstall,
            PrivilegedOperationsCoordinator.InstallGuardDecision.skipNoInstall
        )
        XCTAssertNotEqual(
            PrivilegedOperationsCoordinator.InstallGuardDecision.skipNoInstall,
            PrivilegedOperationsCoordinator.InstallGuardDecision.skipPendingApproval
        )
    }

    func test_installGuardDecision_run_carriesReasonAndBypassFlag() {
        let a = PrivilegedOperationsCoordinator.InstallGuardDecision.run(
            reason: "x", bypassedThrottle: true
        )
        let b = PrivilegedOperationsCoordinator.InstallGuardDecision.run(
            reason: "x", bypassedThrottle: false
        )
        XCTAssertNotEqual(a, b, "bypassedThrottle flag must be part of equality")

        let c = PrivilegedOperationsCoordinator.InstallGuardDecision.run(
            reason: "x", bypassedThrottle: true
        )
        XCTAssertEqual(a, c)
    }

    func test_installGuardDecision_throttled_carriesRemaining() {
        let a = PrivilegedOperationsCoordinator.InstallGuardDecision.throttled(remaining: 10)
        let b = PrivilegedOperationsCoordinator.InstallGuardDecision.throttled(remaining: 20)
        XCTAssertNotEqual(a, b)
    }

    // MARK: - installServicesIfUninstalled: Behavioral Contract

    /// When SMAppService is pending approval, install must not run.
    func test_installServicesIfUninstalled_pendingApproval_returnsFalse() async throws {
        #if DEBUG
            PrivilegedOperationsCoordinator.serviceStateOverride = { .smappservicePending }
            PrivilegedOperationsCoordinator.installAllServicesOverride = {
                XCTFail("Install must not run when SMAppService approval is pending")
            }
        #endif

        let coordinator = PrivilegedOperationsCoordinator.shared
        let didInstall = try await coordinator.installServicesIfUninstalled(context: "golden-pending")
        XCTAssertFalse(didInstall)
    }

    /// When the service is uninstalled, install runs and the method returns true.
    func test_installServicesIfUninstalled_uninstalled_runsAndReturnsTrue() async throws {
        #if DEBUG
            var installCount = 0
            PrivilegedOperationsCoordinator.serviceStateOverride = { .uninstalled }
            PrivilegedOperationsCoordinator.installAllServicesOverride = {
                installCount += 1
            }
        #endif

        let coordinator = PrivilegedOperationsCoordinator.shared
        let didInstall = try await coordinator.installServicesIfUninstalled(context: "golden-uninstalled")
        XCTAssertTrue(didInstall)
        #if DEBUG
            XCTAssertEqual(installCount, 1)
        #endif
    }

    /// Healthy SMAppService — install does not run, returns false.
    func test_installServicesIfUninstalled_healthySMAppService_returnsFalse() async throws {
        #if DEBUG
            PrivilegedOperationsCoordinator.serviceStateOverride = { .smappserviceActive }
            KanataDaemonManager.registeredButNotLoadedOverride = { false }
            PrivilegedOperationsCoordinator.installAllServicesOverride = {
                XCTFail("Install must not run when SMAppService is healthy")
            }
        #endif

        let coordinator = PrivilegedOperationsCoordinator.shared
        let didInstall = try await coordinator.installServicesIfUninstalled(context: "golden-healthy")
        XCTAssertFalse(didInstall)
    }

    /// Stale SMAppService registration (enabled but launchd cannot load) triggers
    /// install — even though state is .smappserviceActive.
    func test_installServicesIfUninstalled_staleEnabledRegistration_runsInstall() async throws {
        #if DEBUG
            var installCount = 0
            PrivilegedOperationsCoordinator.serviceStateOverride = { .smappserviceActive }
            KanataDaemonManager.registeredButNotLoadedOverride = { true }
            PrivilegedOperationsCoordinator.installAllServicesOverride = {
                installCount += 1
            }
        #endif

        let coordinator = PrivilegedOperationsCoordinator.shared
        let didInstall = try await coordinator.installServicesIfUninstalled(context: "golden-stale")
        XCTAssertTrue(didInstall)
        #if DEBUG
            XCTAssertEqual(installCount, 1)
        #endif
    }

    /// Stale recovery bypasses the normal throttle for up to 3 consecutive attempts.
    func test_installServicesIfUninstalled_staleRecovery_bypassesThrottleUpTo3Times() async throws {
        #if DEBUG
            var installCount = 0
            PrivilegedOperationsCoordinator.serviceStateOverride = { .smappserviceActive }
            KanataDaemonManager.registeredButNotLoadedOverride = { true }
            PrivilegedOperationsCoordinator.installAllServicesOverride = {
                installCount += 1
            }
        #endif

        let coordinator = PrivilegedOperationsCoordinator.shared
        let first = try await coordinator.installServicesIfUninstalled(context: "golden-stale-1")
        let second = try await coordinator.installServicesIfUninstalled(context: "golden-stale-2")
        let third = try await coordinator.installServicesIfUninstalled(context: "golden-stale-3")
        let fourth = try await coordinator.installServicesIfUninstalled(context: "golden-stale-4")

        XCTAssertTrue(first)
        XCTAssertTrue(second)
        XCTAssertTrue(third)
        XCTAssertFalse(fourth, "Fourth stale attempt must be throttled")
        #if DEBUG
            XCTAssertEqual(installCount, 3)
        #endif
    }

    /// Repeated uninstalled-state calls hit the throttle and skip the second install.
    func test_installServicesIfUninstalled_repeatCalls_areThrottled() async throws {
        #if DEBUG
            var installCount = 0
            PrivilegedOperationsCoordinator.serviceStateOverride = { .uninstalled }
            PrivilegedOperationsCoordinator.installAllServicesOverride = {
                installCount += 1
            }
        #endif

        let coordinator = PrivilegedOperationsCoordinator.shared
        let first = try await coordinator.installServicesIfUninstalled(context: "golden-throttle-1")
        let second = try await coordinator.installServicesIfUninstalled(context: "golden-throttle-2")

        XCTAssertTrue(first)
        XCTAssertFalse(second, "Second call within throttle window must not run install")
        #if DEBUG
            XCTAssertEqual(installCount, 1)
        #endif
    }

    // MARK: - recoverRequiredRuntimeServices: Postcondition Enforcement

    /// Postcondition `.ready` → success.
    func test_recoverRequiredRuntimeServices_postconditionReady_succeeds() async throws {
        #if DEBUG
            PrivilegedOperationsCoordinator.serviceStateOverride = { .smappserviceActive }
            KanataDaemonManager.registeredButNotLoadedOverride = { false }
            PrivilegedOperationsCoordinator.killExistingKanataProcessesOverride = {}
            PrivilegedOperationsCoordinator.kanataReadinessOverride = { _ in .ready }
        #else
            throw XCTSkip("Requires DEBUG-only test overrides")
        #endif

        let coordinator = PrivilegedOperationsCoordinator.shared
        try await coordinator.recoverRequiredRuntimeServices()
    }

    /// Postcondition `.pendingApproval` is treated as success — user must approve in
    /// System Settings, but the install ran successfully.
    func test_recoverRequiredRuntimeServices_postconditionPendingApproval_succeeds() async throws {
        #if DEBUG
            PrivilegedOperationsCoordinator.serviceStateOverride = { .smappserviceActive }
            KanataDaemonManager.registeredButNotLoadedOverride = { false }
            PrivilegedOperationsCoordinator.killExistingKanataProcessesOverride = {}
            PrivilegedOperationsCoordinator.kanataReadinessOverride = { _ in .pendingApproval }
        #else
            throw XCTSkip("Requires DEBUG-only test overrides")
        #endif

        let coordinator = PrivilegedOperationsCoordinator.shared
        try await coordinator.recoverRequiredRuntimeServices()
    }

    /// Postcondition `.timedOut` → throws operationFailed with a postcondition message.
    func test_recoverRequiredRuntimeServices_postconditionTimedOut_throwsPostconditionFailed() async throws {
        #if DEBUG
            PrivilegedOperationsCoordinator.serviceStateOverride = { .smappserviceActive }
            KanataDaemonManager.registeredButNotLoadedOverride = { false }
            PrivilegedOperationsCoordinator.killExistingKanataProcessesOverride = {}
            PrivilegedOperationsCoordinator.kanataReadinessOverride = { _ in .timedOut }
        #else
            throw XCTSkip("Requires DEBUG-only test overrides")
        #endif

        let coordinator = PrivilegedOperationsCoordinator.shared
        do {
            try await coordinator.recoverRequiredRuntimeServices()
            XCTFail("Expected postcondition failure to throw")
        } catch let PrivilegedOperationError.operationFailed(message) {
            XCTAssertTrue(
                message.contains("postcondition failed"),
                "Error message must surface postcondition failure: \(message)"
            )
            XCTAssertTrue(
                message.contains(
                    PrivilegedOperationsCoordinator.KanataReadinessResult.timedOut.failureDescription
                ),
                "Error message must include the readiness failure description: \(message)"
            )
        } catch {
            XCTFail("Unexpected error type: \(error)")
        }
    }

    /// Postcondition `.staleRegistration` → throws operationFailed with stale-registration
    /// failure description.
    func test_recoverRequiredRuntimeServices_postconditionStaleRegistration_throwsPostconditionFailed() async throws {
        #if DEBUG
            PrivilegedOperationsCoordinator.serviceStateOverride = { .smappserviceActive }
            KanataDaemonManager.registeredButNotLoadedOverride = { false }
            PrivilegedOperationsCoordinator.killExistingKanataProcessesOverride = {}
            PrivilegedOperationsCoordinator.kanataReadinessOverride = { _ in .staleRegistration }
        #else
            throw XCTSkip("Requires DEBUG-only test overrides")
        #endif

        let coordinator = PrivilegedOperationsCoordinator.shared
        do {
            try await coordinator.recoverRequiredRuntimeServices()
            XCTFail("Expected postcondition failure to throw")
        } catch let PrivilegedOperationError.operationFailed(message) {
            XCTAssertTrue(message.contains("postcondition failed"))
            XCTAssertTrue(
                message.contains(
                    PrivilegedOperationsCoordinator.KanataReadinessResult.staleRegistration
                        .failureDescription
                ),
                "Error message must include staleRegistration failure description: \(message)"
            )
        } catch {
            XCTFail("Unexpected error type: \(error)")
        }
    }

    /// Postcondition `.tcpPortInUse` → throws operationFailed with port-in-use description.
    func test_recoverRequiredRuntimeServices_postconditionTCPPortInUse_throwsPostconditionFailed() async throws {
        #if DEBUG
            PrivilegedOperationsCoordinator.serviceStateOverride = { .smappserviceActive }
            KanataDaemonManager.registeredButNotLoadedOverride = { false }
            PrivilegedOperationsCoordinator.killExistingKanataProcessesOverride = {}
            PrivilegedOperationsCoordinator.kanataReadinessOverride = { _ in .tcpPortInUse }
        #else
            throw XCTSkip("Requires DEBUG-only test overrides")
        #endif

        let coordinator = PrivilegedOperationsCoordinator.shared
        do {
            try await coordinator.recoverRequiredRuntimeServices()
            XCTFail("Expected postcondition failure to throw")
        } catch let PrivilegedOperationError.operationFailed(message) {
            XCTAssertTrue(message.contains("postcondition failed"))
            XCTAssertTrue(
                message.contains(
                    PrivilegedOperationsCoordinator.KanataReadinessResult.tcpPortInUse
                        .failureDescription
                ),
                "Error message must include tcpPortInUse failure description: \(message)"
            )
        } catch {
            XCTFail("Unexpected error type: \(error)")
        }
    }

    /// Recovery clears existing Kanata processes before attempting service restart
    /// (prevents TCP port collisions).
    func test_recoverRequiredRuntimeServices_clearsKanataProcessesBeforeRestart() async throws {
        #if DEBUG
            var killCalls = 0
            PrivilegedOperationsCoordinator.serviceStateOverride = { .smappserviceActive }
            KanataDaemonManager.registeredButNotLoadedOverride = { false }
            PrivilegedOperationsCoordinator.killExistingKanataProcessesOverride = {
                killCalls += 1
            }
            PrivilegedOperationsCoordinator.kanataReadinessOverride = { _ in .ready }
        #else
            throw XCTSkip("Requires DEBUG-only test overrides")
        #endif

        let coordinator = PrivilegedOperationsCoordinator.shared
        try await coordinator.recoverRequiredRuntimeServices()
        #if DEBUG
            XCTAssertEqual(killCalls, 1, "Existing Kanata processes must be cleared exactly once")
        #endif
    }

    // MARK: - regenerateServiceConfiguration: Postcondition Enforcement

    /// regenerateServiceConfiguration treats `.pendingApproval` as success.
    func test_regenerateServiceConfiguration_postconditionPendingApproval_succeeds() async throws {
        #if DEBUG
            PrivilegedOperationsCoordinator.kanataReadinessOverride = { _ in .pendingApproval }
        #else
            throw XCTSkip("Requires DEBUG-only test overrides")
        #endif

        let coordinator = PrivilegedOperationsCoordinator.shared
        try await coordinator.regenerateServiceConfiguration()
    }

    /// regenerateServiceConfiguration throws when readiness times out.
    func test_regenerateServiceConfiguration_postconditionTimedOut_throws() async throws {
        #if DEBUG
            PrivilegedOperationsCoordinator.kanataReadinessOverride = { _ in .timedOut }
        #else
            throw XCTSkip("Requires DEBUG-only test overrides")
        #endif

        let coordinator = PrivilegedOperationsCoordinator.shared
        do {
            try await coordinator.regenerateServiceConfiguration()
            XCTFail("Expected timeout to throw")
        } catch let PrivilegedOperationError.operationFailed(message) {
            XCTAssertTrue(message.contains("postcondition failed"))
        } catch {
            XCTFail("Unexpected error type: \(error)")
        }
    }

    // MARK: - Process Termination Contract

    /// Invalid PIDs are rejected before any privileged command is dispatched.
    func test_terminateProcess_pidZero_throwsBeforeRunningCommand() async throws {
        let fakeExecutor = FakeAdminCommandExecutor()
        AdminCommandExecutorHolder.shared = fakeExecutor

        let coordinator = PrivilegedOperationsCoordinator.shared
        do {
            try await coordinator.terminateProcess(pid: 0)
            XCTFail("Expected invalid PID to throw")
        } catch let PrivilegedOperationError.operationFailed(message) {
            XCTAssertTrue(message.contains("Invalid process ID"))
        } catch {
            XCTFail("Unexpected error type: \(error)")
        }

        XCTAssertTrue(
            fakeExecutor.commands.isEmpty,
            "Invalid-PID rejection must short-circuit before issuing any commands"
        )
        XCTAssertTrue(fakeExecutor.batches.isEmpty)
    }

    /// Negative PIDs are also rejected.
    func test_terminateProcess_negativePID_throwsBeforeRunningCommand() async throws {
        let fakeExecutor = FakeAdminCommandExecutor()
        AdminCommandExecutorHolder.shared = fakeExecutor

        let coordinator = PrivilegedOperationsCoordinator.shared
        do {
            try await coordinator.terminateProcess(pid: -42)
            XCTFail("Expected negative PID to throw")
        } catch let PrivilegedOperationError.operationFailed(message) {
            XCTAssertTrue(message.contains("Invalid process ID"))
        } catch {
            XCTFail("Unexpected error type: \(error)")
        }

        XCTAssertTrue(fakeExecutor.commands.isEmpty)
        XCTAssertTrue(fakeExecutor.batches.isEmpty)
    }

    // MARK: - Karabiner Daemon Restart Contract

    /// Verified Karabiner daemon restart issues a single privileged batch (not multiple
    /// admin prompts).
    func test_restartKarabinerDaemonVerified_usesSinglePrivilegedBatch() async throws {
        let fakeExecutor = FakeAdminCommandExecutor()
        AdminCommandExecutorHolder.shared = fakeExecutor
        VHIDDeviceManager.testPIDProvider = { ["123"] }
        defer {
            VHIDDeviceManager.testPIDProvider = nil
        }

        let coordinator = PrivilegedOperationsCoordinator.shared
        let success = try await coordinator.restartKarabinerDaemonVerified()

        XCTAssertTrue(success)
        XCTAssertEqual(
            fakeExecutor.batches.count, 1,
            "Restart must consolidate to a single batch to avoid repeated admin prompts"
        )
    }

    // MARK: - Operation Mode

    /// In DEBUG builds, the coordinator must use direct sudo (no helper XPC).
    func test_operationMode_debug_isDirectSudo() {
        #if DEBUG
            XCTAssertEqual(PrivilegedOperationsCoordinator.operationMode, .directSudo)
        #endif
    }
}
