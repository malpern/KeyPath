import Foundation
@testable import KeyPathAppKit
@preconcurrency import XCTest

/// Golden tests that capture the current behavior of ServiceInstallGuard (install decision logic)
/// and KanataReadinessResult (readiness semantics). These tests must pass both before and after
/// the PrivilegedOperationsRouter deletion — they prove behavioral equivalence.
///
/// Naming convention: test_<scenario>_<expectedBehavior>
@MainActor
final class PrivilegedOperationsGoldenTests: XCTestCase {
    override func setUp() async throws {
        try await super.setUp()
        ServiceInstallGuard.reset()
    }

    override func tearDown() async throws {
        ServiceInstallGuard.reset()
        try await super.tearDown()
    }

    // MARK: - ServiceInstallGuard: Basic State Routing

    func test_uninstalled_runsInstall() {
        let decision = ServiceInstallGuard.decide(
            state: .uninstalled,
            staleEnabledRegistration: false,
            now: Date(),
            lastAttempt: nil
        )
        XCTAssertEqual(decision, .run(reason: "state=Uninstalled", bypassedThrottle: false))
    }

    func test_smappserviceActive_healthy_skipsInstall() {
        let decision = ServiceInstallGuard.decide(
            state: .smappserviceActive,
            staleEnabledRegistration: false,
            now: Date(),
            lastAttempt: nil
        )
        XCTAssertEqual(decision, .skipNoInstall)
    }

    func test_smappservicePending_skipsPendingApproval() {
        let decision = ServiceInstallGuard.decide(
            state: .smappservicePending,
            staleEnabledRegistration: false,
            now: Date(),
            lastAttempt: nil
        )
        XCTAssertEqual(decision, .skipPendingApproval)
    }

    func test_legacyActive_runsMigrationInstall() {
        let decision = ServiceInstallGuard.decide(
            state: .legacyActive,
            staleEnabledRegistration: false,
            now: Date(),
            lastAttempt: nil
        )
        XCTAssertEqual(decision, .run(reason: "state=Legacy launchctl", bypassedThrottle: false))
    }

    func test_conflicted_runsInstall() {
        let decision = ServiceInstallGuard.decide(
            state: .conflicted,
            staleEnabledRegistration: false,
            now: Date(),
            lastAttempt: nil
        )
        XCTAssertEqual(decision, .run(reason: "state=Conflicted (both methods active)", bypassedThrottle: false))
    }

    func test_unknown_skipsInstall() {
        let decision = ServiceInstallGuard.decide(
            state: .unknown,
            staleEnabledRegistration: false,
            now: Date(),
            lastAttempt: nil
        )
        XCTAssertEqual(decision, .skipNoInstall,
                       "Unknown state doesn't need installation or migration")
    }

    // MARK: - ServiceInstallGuard: Throttling

    func test_rapidRepeat_throttled() {
        let now = Date()
        _ = ServiceInstallGuard.decide(
            state: .uninstalled,
            staleEnabledRegistration: false,
            now: now,
            lastAttempt: nil
        )
        let decision = ServiceInstallGuard.decide(
            state: .uninstalled,
            staleEnabledRegistration: false,
            now: now,
            lastAttempt: now
        )
        if case .throttled = decision {
            // expected
        } else {
            XCTFail("Expected throttled, got \(decision)")
        }
    }

    func test_afterThrottleExpires_runsAgain() {
        let now = Date()
        let longAgo = now.addingTimeInterval(-60)
        let decision = ServiceInstallGuard.decide(
            state: .uninstalled,
            staleEnabledRegistration: false,
            now: now,
            lastAttempt: longAgo
        )
        XCTAssertEqual(decision, .run(reason: "state=Uninstalled", bypassedThrottle: false))
    }

    // MARK: - ServiceInstallGuard: Stale Recovery

    func test_staleEnabled_firstAttempt_bypassesThrottle() {
        let decision = ServiceInstallGuard.decide(
            state: .smappserviceActive,
            staleEnabledRegistration: true,
            now: Date(),
            lastAttempt: nil
        )
        XCTAssertEqual(
            decision,
            .run(reason: "stale-enabled-registration (recovery-attempt=1)", bypassedThrottle: true)
        )
    }

    func test_staleEnabled_threeAttempts_allBypassThrottle() {
        let now = Date()
        for i in 1 ... 3 {
            let decision = ServiceInstallGuard.decide(
                state: .smappserviceActive,
                staleEnabledRegistration: true,
                now: now,
                lastAttempt: now
            )
            XCTAssertEqual(
                decision,
                .run(reason: "stale-enabled-registration (recovery-attempt=\(i))", bypassedThrottle: true),
                "Stale attempt \(i) should bypass throttle"
            )
        }
    }

    func test_staleEnabled_fourthAttempt_throttled() {
        let now = Date()
        for _ in 1 ... 3 {
            _ = ServiceInstallGuard.decide(
                state: .smappserviceActive,
                staleEnabledRegistration: true,
                now: now,
                lastAttempt: nil
            )
        }
        let decision = ServiceInstallGuard.decide(
            state: .smappserviceActive,
            staleEnabledRegistration: true,
            now: now,
            lastAttempt: now
        )
        if case .throttled = decision {
            // expected
        } else {
            XCTFail("Expected throttled after bypass limit, got \(decision)")
        }
    }

    func test_staleEnabled_fourthAttempt_noRecentAttempt_runsWithThrottleApplied() {
        let now = Date()
        for _ in 1 ... 3 {
            _ = ServiceInstallGuard.decide(
                state: .smappserviceActive,
                staleEnabledRegistration: true,
                now: now,
                lastAttempt: nil
            )
        }
        let decision = ServiceInstallGuard.decide(
            state: .smappserviceActive,
            staleEnabledRegistration: true,
            now: now,
            lastAttempt: nil
        )
        XCTAssertEqual(
            decision,
            .run(reason: "stale-enabled-registration (throttle-applied after 3 bypasses)", bypassedThrottle: false)
        )
    }

    // MARK: - ServiceInstallGuard: Counter Reset

    func test_staleCounterResetsAfterHealthyPeriod() {
        let now = Date()

        for _ in 1 ... 3 {
            _ = ServiceInstallGuard.decide(
                state: .smappserviceActive,
                staleEnabledRegistration: true,
                now: now,
                lastAttempt: nil
            )
        }

        let healthy = ServiceInstallGuard.decide(
            state: .smappserviceActive,
            staleEnabledRegistration: false,
            now: now,
            lastAttempt: nil
        )
        XCTAssertEqual(healthy, .skipNoInstall, "Healthy state should skip install")

        let afterReset = ServiceInstallGuard.decide(
            state: .smappserviceActive,
            staleEnabledRegistration: true,
            now: now,
            lastAttempt: nil
        )
        XCTAssertEqual(
            afterReset,
            .run(reason: "stale-enabled-registration (recovery-attempt=1)", bypassedThrottle: true),
            "Counter should restart at 1 after healthy period"
        )
    }

    func test_staleCounterResetsWhenNotStale() {
        _ = ServiceInstallGuard.decide(
            state: .smappserviceActive,
            staleEnabledRegistration: true,
            now: Date(),
            lastAttempt: nil
        )
        XCTAssertEqual(ServiceInstallGuard.staleRecoveryAttemptCount, 1)

        _ = ServiceInstallGuard.decide(
            state: .uninstalled,
            staleEnabledRegistration: false,
            now: Date(),
            lastAttempt: nil
        )
        XCTAssertEqual(ServiceInstallGuard.staleRecoveryAttemptCount, 0, "Non-stale install resets counter")
    }

    // MARK: - ServiceInstallGuard: Pending Approval Priority

    func test_pendingApproval_trumpsEverythingElse() {
        let decision = ServiceInstallGuard.decide(
            state: .smappservicePending,
            staleEnabledRegistration: true,
            now: Date(),
            lastAttempt: nil
        )
        XCTAssertEqual(decision, .skipPendingApproval,
                        "Pending approval takes priority even with stale registration")
    }

    // MARK: - KanataReadinessResult: Semantics

    func test_readinessReady_isSuccess() {
        XCTAssertTrue(KanataReadinessResult.ready.isSuccess)
    }

    func test_readinessPendingApproval_isSuccess() {
        XCTAssertTrue(KanataReadinessResult.pendingApproval.isSuccess)
    }

    func test_readinessTimedOut_isNotSuccess() {
        XCTAssertFalse(KanataReadinessResult.timedOut.isSuccess)
    }

    func test_readinessStaleRegistration_isNotSuccess() {
        XCTAssertFalse(KanataReadinessResult.staleRegistration.isSuccess)
    }

    func test_readinessLaunchctlNotFound_isNotSuccess() {
        XCTAssertFalse(KanataReadinessResult.launchctlNotFoundPersistent.isSuccess)
    }

    func test_readinessTcpPortInUse_isNotSuccess() {
        XCTAssertFalse(KanataReadinessResult.tcpPortInUse.isSuccess)
    }

    func test_allReadinessResults_haveNonEmptyDescriptions() {
        let results: [KanataReadinessResult] = [
            .ready, .pendingApproval, .staleRegistration,
            .launchctlNotFoundPersistent, .tcpPortInUse, .timedOut,
        ]
        for result in results {
            XCTAssertFalse(result.failureDescription.isEmpty, "\(result) should have a description")
        }
    }

    // MARK: - PID Validation (pure logic preserved from PrivilegedOperationsRouter)

    func test_invalidPID_zero_throws() async {
        let coordinator = PrivilegedOperationsRouter.shared
        do {
            try await coordinator.terminateProcess(pid: 0)
            XCTFail("Expected error for PID 0")
        } catch {
            guard case let PrivilegedOperationError.operationFailed(msg) = error else {
                XCTFail("Expected operationFailed, got \(error)")
                return
            }
            XCTAssertTrue(msg.contains("Invalid process ID"))
        }
    }

    func test_invalidPID_negative_throws() async {
        let coordinator = PrivilegedOperationsRouter.shared
        do {
            try await coordinator.terminateProcess(pid: -1)
            XCTFail("Expected error for negative PID")
        } catch {
            guard case let PrivilegedOperationError.operationFailed(msg) = error else {
                XCTFail("Expected operationFailed, got \(error)")
                return
            }
            XCTAssertTrue(msg.contains("Invalid process ID"))
        }
    }
}
