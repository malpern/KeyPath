@preconcurrency import XCTest
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
            context: "unit-test"
        )

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
            context: "unit-test"
        )
        let second = try await PrivilegedOperationsCoordinator.shared._testEnsureServices(
            context: "unit-test"
        )

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
            context: "legacy-test"
        )

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
            context: "pending-test"
        )

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
            context: "conflict-test"
        )

        XCTAssertTrue(didInstall)
        XCTAssertEqual(installCount, 1)
    }

    // MARK: - Stale Recovery Counter Tests

    /// Verify the counter resets when system becomes healthy (skipNoInstall path)
    func testStaleRecoveryCounterResetsAcrossHealthyPeriods() async throws {
        PrivilegedOperationsCoordinator._testResetServiceInstallGuard()

        // Simulate 3 stale recovery attempts (should all bypass throttle)
        for i in 1 ... 3 {
            let decision = PrivilegedOperationsCoordinator._testDecideInstallGuard(
                state: .smappserviceActive,
                staleEnabledRegistration: true
            )
            XCTAssertEqual(
                decision,
                .run(reason: "stale-enabled-registration (recovery-attempt=\(i))", bypassedThrottle: true),
                "Stale attempt \(i) should bypass throttle"
            )
        }

        // System becomes healthy — counter should reset via skipNoInstall path
        let healthyDecision = PrivilegedOperationsCoordinator._testDecideInstallGuard(
            state: .smappserviceActive,
            staleEnabledRegistration: false
        )
        XCTAssertEqual(healthyDecision, .skipNoInstall)

        // Next stale event should start fresh at attempt 1, not 4
        let afterResetDecision = PrivilegedOperationsCoordinator._testDecideInstallGuard(
            state: .smappserviceActive,
            staleEnabledRegistration: true
        )
        XCTAssertEqual(
            afterResetDecision,
            .run(reason: "stale-enabled-registration (recovery-attempt=1)", bypassedThrottle: true),
            "After healthy period, stale counter should restart at 1"
        )
    }

    /// Verify that exceeding the bypass limit applies throttle
    func testStaleRecoveryCounterExceedingLimitAppliesThrottle() async throws {
        PrivilegedOperationsCoordinator._testResetServiceInstallGuard()
        let now = Date()

        // Exhaust all 3 bypass attempts
        for _ in 1 ... 3 {
            _ = PrivilegedOperationsCoordinator._testDecideInstallGuard(
                state: .smappserviceActive,
                staleEnabledRegistration: true,
                now: now
            )
        }

        // 4th attempt with recent lastAttempt should be throttled
        let throttled = PrivilegedOperationsCoordinator._testDecideInstallGuard(
            state: .smappserviceActive,
            staleEnabledRegistration: true,
            now: now,
            lastAttempt: now
        )
        if case .throttled = throttled {
            // expected
        } else {
            XCTFail("Expected throttled, got \(throttled)")
        }
    }
}
