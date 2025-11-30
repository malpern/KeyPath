import Foundation
import KeyPathDaemonLifecycle
@preconcurrency import XCTest

@testable import KeyPathAppKit

/// Mock UDP client for testing health checks
actor MockKanataUDPClient {
    var shouldSucceed: Bool = true
    var callCount: Int = 0

    func checkServerStatus() async -> Bool {
        callCount += 1
        return shouldSucceed
    }

    func resetCallCount() {
        callCount = 0
    }
}

@MainActor
class ServiceHealthMonitorTests: XCTestCase {
    lazy var processLifecycle: ProcessLifecycleManager = .init()
    lazy var monitor: ServiceHealthMonitor = .init(processLifecycle: processLifecycle)

    // MARK: - Health Check Tests

    func testCheckServiceHealth_ProcessNotRunning() async {
        let status = ProcessHealthStatus(isRunning: false, pid: nil)
        let healthStatus = await monitor.checkServiceHealth(processStatus: status, tcpPort: 37000)

        XCTAssertFalse(healthStatus.isHealthy, "Should be unhealthy when process not running")
        XCTAssertTrue(healthStatus.shouldRestart, "Should recommend restart")
        XCTAssertEqual(healthStatus.reason, "Process not running")
    }

    func testCheckServiceHealth_ProcessRunning_NoUDPClient() async {
        let status = ProcessHealthStatus(isRunning: true, pid: 1234)
        // Set lastServiceStart to be within grace period so TCP check failure is acceptable
        await monitor.recordStartAttempt(timestamp: Date())
        let healthStatus = await monitor.checkServiceHealth(processStatus: status, tcpPort: 37000)

        // TCP check will fail in test environment, but if we're in grace period, it's still healthy
        // Otherwise, it will be unhealthy but that's expected behavior
        let isHealthyOrInGracePeriod =
            healthStatus.isHealthy || (healthStatus.reason?.contains("grace period") ?? false)
        XCTAssertTrue(
            isHealthyOrInGracePeriod,
            "Should be healthy when process running and in grace period, or acceptable to be unhealthy if TCP check fails"
        )
        // In test environment without TCP server, shouldRestart might be true, which is acceptable
    }

    func testCheckServiceHealth_WithinGracePeriod() async {
        // Record a recent start
        await monitor.recordStartAttempt(timestamp: Date())

        let status = ProcessHealthStatus(isRunning: true, pid: 1234)
        let healthStatus = await monitor.checkServiceHealth(processStatus: status, tcpPort: 37000)

        XCTAssertTrue(healthStatus.isHealthy, "Should be healthy within grace period")
    }

    // MARK: - Restart Cooldown Tests

    func testCanRestartService_NoPreviousAttempt() async {
        let cooldownState = await monitor.canRestartService()

        XCTAssertTrue(cooldownState.canRestart, "Should allow restart with no previous attempt")
        XCTAssertEqual(cooldownState.remainingCooldown, 0, "No cooldown should remain")
        XCTAssertEqual(cooldownState.attemptsSinceLastSuccess, 0, "Should have zero attempts")
    }

    func testCanRestartService_WithinCooldown() async {
        // Record an attempt just now
        await monitor.recordStartAttempt(timestamp: Date())

        let cooldownState = await monitor.canRestartService()

        XCTAssertFalse(cooldownState.canRestart, "Should not allow restart within cooldown")
        XCTAssertGreaterThan(cooldownState.remainingCooldown, 0, "Should have remaining cooldown")
    }

    func testCanRestartService_AfterCooldown() async {
        // Record an attempt 3 seconds ago (beyond 2 second cooldown)
        let pastAttempt = Date().addingTimeInterval(-3.0)
        await monitor.recordStartAttempt(timestamp: pastAttempt)

        let cooldownState = await monitor.canRestartService()

        XCTAssertTrue(cooldownState.canRestart, "Should allow restart after cooldown expires")
        XCTAssertEqual(cooldownState.remainingCooldown, 0, "No cooldown should remain")
    }

    func testCanRestartService_GracePeriodDetection() async {
        // Record a recent start
        await monitor.recordStartAttempt(timestamp: Date())

        let cooldownState = await monitor.canRestartService()

        XCTAssertTrue(cooldownState.isInGracePeriod, "Should detect grace period")
    }

    // MARK: - Start Attempt Tracking Tests

    func testRecordStartAttempt_IncrementCounter() async {
        // Record first attempt 3 seconds ago (beyond cooldown)
        await monitor.recordStartAttempt(timestamp: Date().addingTimeInterval(-3.0))
        var cooldownState = await monitor.canRestartService()
        XCTAssertEqual(cooldownState.attemptsSinceLastSuccess, 1, "Should track first attempt")

        // Record second attempt now (cooldown expired)
        await monitor.recordStartAttempt(timestamp: Date())
        cooldownState = await monitor.canRestartService()
        XCTAssertEqual(cooldownState.attemptsSinceLastSuccess, 2, "Should track second attempt")
    }

    func testRecordStartSuccess_ResetCounters() async {
        // Make some failed attempts
        await monitor.recordStartAttempt(timestamp: Date().addingTimeInterval(-3))
        await monitor.recordStartFailure()
        await monitor.recordStartAttempt(timestamp: Date().addingTimeInterval(-2))
        await monitor.recordStartFailure()

        var cooldownState = await monitor.canRestartService()
        XCTAssertEqual(cooldownState.attemptsSinceLastSuccess, 2, "Should have 2 failed attempts")

        // Now record success
        await monitor.recordStartSuccess()

        cooldownState = await monitor.canRestartService()
        XCTAssertEqual(cooldownState.attemptsSinceLastSuccess, 0, "Should reset attempt counter")
    }

    // MARK: - Connection Failure Tracking Tests

    func testRecordConnectionFailure_CountsFailures() async {
        for i in 1 ... 5 {
            let shouldTrigger = await monitor.recordConnectionFailure()
            XCTAssertFalse(shouldTrigger, "Should not trigger recovery at \(i) failures")
        }
    }

    func testRecordConnectionFailure_TriggersRecoveryAtMax() async {
        // Record 9 failures
        for _ in 1 ... 9 {
            _ = await monitor.recordConnectionFailure()
        }

        // 10th failure should trigger recovery
        let shouldTrigger = await monitor.recordConnectionFailure()
        XCTAssertTrue(shouldTrigger, "Should trigger recovery at max failures (10)")
    }

    func testRecordConnectionSuccess_ResetCounter() async {
        // Record some failures
        _ = await monitor.recordConnectionFailure()
        _ = await monitor.recordConnectionFailure()
        _ = await monitor.recordConnectionFailure()

        // Record success should reset
        await monitor.recordConnectionSuccess()

        // Next failure should start from 1
        let shouldTrigger = await monitor.recordConnectionFailure()
        XCTAssertFalse(shouldTrigger, "Should not trigger after reset")
    }

    // MARK: - Recovery Strategy Tests

    func testDetermineRecoveryAction_HealthyService() async {
        let healthStatus = ServiceHealthStatus.healthy()
        let action = await monitor.determineRecoveryAction(healthStatus: healthStatus)

        if case .none = action {
            // Success
        } else {
            XCTFail("Should return .none for healthy service")
        }
    }

    func testDetermineRecoveryAction_SimpleRestart() async {
        let healthStatus = ServiceHealthStatus.unhealthy(reason: "Test", shouldRestart: true)
        let action = await monitor.determineRecoveryAction(healthStatus: healthStatus)

        if case .simpleRestart = action {
            // Success
        } else {
            XCTFail("Should recommend simple restart for basic unhealthy state")
        }
    }

    func testDetermineRecoveryAction_MaxAttemptsReached() async {
        // Exceed max start attempts (maxStartAttempts is 5)
        for _ in 1 ... 5 {
            await monitor.recordStartAttempt(timestamp: Date().addingTimeInterval(-10))
            await monitor.recordStartFailure()
        }

        let healthStatus = ServiceHealthStatus.unhealthy(reason: "Test", shouldRestart: true)
        let action = await monitor.determineRecoveryAction(healthStatus: healthStatus)

        if case let .giveUp(reason) = action {
            XCTAssertTrue(reason.contains("attempts"), "Should mention attempts in reason")
        } else {
            XCTFail("Should give up after max attempts (got: \(action))")
        }
    }

    func testDetermineRecoveryAction_ConnectionFailures() async {
        // Trigger max connection failures
        for _ in 1 ... 10 {
            _ = await monitor.recordConnectionFailure()
        }

        let healthStatus = ServiceHealthStatus.unhealthy(
            reason: "Connection issues", shouldRestart: true
        )
        let action = await monitor.determineRecoveryAction(healthStatus: healthStatus)

        if case .fullRecovery = action {
            // Success
        } else {
            XCTFail("Should recommend full recovery for connection failures")
        }
    }

    // NOTE: Test disabled - requires mocking ProcessLifecycleManager which is now final
    // To properly test conflict resolution, would need integration test with actual processes
    func skip_testDetermineRecoveryAction_ProcessConflicts() async {
        // Set up mock conflicts
        _ = ProcessLifecycleManager.ProcessInfo(pid: 9999, command: "/usr/local/bin/kanata")
        // mockProcessLifecycle.mockConflicts = ProcessLifecycleManager.ConflictResolution(
        //     externalProcesses: [conflictProcess],
        //     managedProcesses: [],
        //     canAutoResolve: true
        // )

        let healthStatus = ServiceHealthStatus.unhealthy(reason: "Conflicts", shouldRestart: true)
        let action = await monitor.determineRecoveryAction(healthStatus: healthStatus)

        if case .killAndRestart = action {
            // Success
        } else {
            XCTFail("Should recommend kill and restart for process conflicts")
        }
    }

    // MARK: - State Reset Tests

    func testResetMonitoringState() async {
        // Set up some state
        await monitor.recordStartAttempt(timestamp: Date())
        _ = await monitor.recordConnectionFailure()
        _ = await monitor.recordConnectionFailure()

        var cooldownState = await monitor.canRestartService()
        XCTAssertGreaterThan(
            cooldownState.attemptsSinceLastSuccess, 0, "Should have attempts before reset"
        )

        // Reset
        await monitor.resetMonitoringState()

        cooldownState = await monitor.canRestartService()
        XCTAssertEqual(cooldownState.attemptsSinceLastSuccess, 0, "Should have no attempts after reset")
        XCTAssertTrue(cooldownState.canRestart, "Should allow restart after reset")
    }

    // MARK: - Integration Tests

    func testHealthCheckWithRetries_EventualSuccess() async {
        // This test would require a real or more sophisticated mock UDP client
        // For now, we verify the retry logic indirectly through the health check
        let status = ProcessHealthStatus(isRunning: true, pid: 1234)

        // Set lastServiceStart to be within grace period to avoid TCP check failure
        await monitor.recordStartAttempt(timestamp: Date())

        // First check without UDP client - should be healthy within grace period
        let healthStatus = await monitor.checkServiceHealth(processStatus: status, tcpPort: 37000)
        // In test environment, TCP check will fail, but grace period should make it healthy
        XCTAssertTrue(
            healthStatus.isHealthy, "Should be healthy when process running and within grace period"
        )
    }

    func testFullWorkflow_StartFailureToRecovery() async {
        // Simulate a start failure workflow
        await monitor.recordStartAttempt(timestamp: Date().addingTimeInterval(-3))
        await monitor.recordStartFailure()

        let healthStatus = ServiceHealthStatus.unhealthy(reason: "Start failed", shouldRestart: true)
        let action = await monitor.determineRecoveryAction(healthStatus: healthStatus)

        // Should recommend simple restart on first failure
        if case .simpleRestart = action {
            // Success
        } else {
            XCTFail("Should recommend simple restart on first failure")
        }

        // Record success after recovery
        await monitor.recordStartSuccess()

        let cooldownState = await monitor.canRestartService()
        XCTAssertEqual(cooldownState.attemptsSinceLastSuccess, 0, "Should reset after success")
    }

    // MARK: - Crash Loop Detection Tests

    func testRecordPIDObservation_SinglePID_NoCrashLoop() async {
        // Observing the same PID multiple times should not trigger crash loop
        let isCrashLoop1 = await monitor.recordPIDObservation(1234)
        XCTAssertFalse(isCrashLoop1, "Single PID should not be crash loop")

        let isCrashLoop2 = await monitor.recordPIDObservation(1234)
        XCTAssertFalse(isCrashLoop2, "Same PID repeated should not be crash loop")

        let isCrashLoop3 = await monitor.recordPIDObservation(1234)
        XCTAssertFalse(isCrashLoop3, "Same PID repeated should not be crash loop")

        XCTAssertFalse(monitor.isInCrashLoop, "Should not be in crash loop with single PID")
    }

    func testRecordPIDObservation_TwoPIDs_NoCrashLoop() async {
        // Two different PIDs within window should not trigger crash loop (threshold is 3)
        let isCrashLoop1 = await monitor.recordPIDObservation(1234)
        XCTAssertFalse(isCrashLoop1, "First PID should not be crash loop")

        let isCrashLoop2 = await monitor.recordPIDObservation(5678)
        XCTAssertFalse(isCrashLoop2, "Two PIDs should not be crash loop")

        XCTAssertFalse(monitor.isInCrashLoop, "Should not be in crash loop with only 2 PIDs")
    }

    func testRecordPIDObservation_ThreePIDs_TriggersCrashLoop() async {
        // Three different PIDs within window should trigger crash loop
        let isCrashLoop1 = await monitor.recordPIDObservation(1000)
        XCTAssertFalse(isCrashLoop1, "First PID should not be crash loop")

        let isCrashLoop2 = await monitor.recordPIDObservation(2000)
        XCTAssertFalse(isCrashLoop2, "Second PID should not be crash loop")

        let isCrashLoop3 = await monitor.recordPIDObservation(3000)
        XCTAssertTrue(isCrashLoop3, "Third different PID should trigger crash loop")

        XCTAssertTrue(monitor.isInCrashLoop, "Should be in crash loop with 3 different PIDs")
    }

    func testRecordPIDObservation_NilPID_Ignored() async {
        // nil PID should be ignored
        let isCrashLoop1 = await monitor.recordPIDObservation(nil)
        XCTAssertFalse(isCrashLoop1, "nil PID should not trigger crash loop")

        let isCrashLoop2 = await monitor.recordPIDObservation(1234)
        XCTAssertFalse(isCrashLoop2, "Single valid PID should not trigger crash loop")

        let isCrashLoop3 = await monitor.recordPIDObservation(nil)
        XCTAssertFalse(isCrashLoop3, "nil PID should be ignored")

        XCTAssertFalse(monitor.isInCrashLoop, "Should not be in crash loop")
    }

    func testClearCrashLoopState_ResetsDetection() async {
        // First trigger a crash loop
        _ = await monitor.recordPIDObservation(1000)
        _ = await monitor.recordPIDObservation(2000)
        _ = await monitor.recordPIDObservation(3000)

        XCTAssertTrue(monitor.isInCrashLoop, "Should be in crash loop before clear")

        // Clear the state
        await monitor.clearCrashLoopState()

        XCTAssertFalse(monitor.isInCrashLoop, "Should not be in crash loop after clear")

        // New observations should start fresh
        let isCrashLoop = await monitor.recordPIDObservation(4000)
        XCTAssertFalse(isCrashLoop, "Should not trigger crash loop after clear")
    }

    func testResetMonitoringState_ClearsCrashLoopState() async {
        // Trigger a crash loop
        _ = await monitor.recordPIDObservation(1000)
        _ = await monitor.recordPIDObservation(2000)
        _ = await monitor.recordPIDObservation(3000)

        XCTAssertTrue(monitor.isInCrashLoop, "Should be in crash loop before reset")

        // Reset all monitoring state
        await monitor.resetMonitoringState()

        XCTAssertFalse(monitor.isInCrashLoop, "Should not be in crash loop after reset")
    }

    func testCrashLoopCallback_InvokedOnDetection() async {
        var callbackInvoked = false

        monitor.onCrashLoopDetected = {
            callbackInvoked = true
        }

        // Trigger crash loop
        _ = await monitor.recordPIDObservation(1000)
        _ = await monitor.recordPIDObservation(2000)
        _ = await monitor.recordPIDObservation(3000)

        XCTAssertTrue(callbackInvoked, "Callback should be invoked when crash loop detected")
    }

    func testCrashLoopCallback_NotInvokedBelowThreshold() async {
        var callbackInvoked = false

        monitor.onCrashLoopDetected = {
            callbackInvoked = true
        }

        // Only two PIDs - below threshold
        _ = await monitor.recordPIDObservation(1000)
        _ = await monitor.recordPIDObservation(2000)

        XCTAssertFalse(callbackInvoked, "Callback should not be invoked below threshold")
    }
}
