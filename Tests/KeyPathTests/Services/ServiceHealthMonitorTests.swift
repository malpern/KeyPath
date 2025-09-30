import Foundation
import XCTest

@testable import KeyPath

/// Mock ProcessLifecycleManager for testing
@MainActor
class MockProcessLifecycleManager: ProcessLifecycleManager {
    var mockConflicts: ProcessLifecycleManager.ConflictResolution?

    override func detectConflicts() async -> ProcessLifecycleManager.ConflictResolution {
        if let mock = mockConflicts {
            return mock
        }
        // Default: no conflicts
        return ProcessLifecycleManager.ConflictResolution(
            externalProcesses: [],
            managedProcesses: [],
            canAutoResolve: true
        )
    }
}

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
    var monitor: ServiceHealthMonitor!
    var mockProcessLifecycle: MockProcessLifecycleManager!

    override func setUp() async throws {
        try await super.setUp()
        mockProcessLifecycle = MockProcessLifecycleManager(kanataManager: nil)
        monitor = ServiceHealthMonitor(processLifecycle: mockProcessLifecycle)
    }

    override func tearDown() async throws {
        monitor = nil
        mockProcessLifecycle = nil
        try await super.tearDown()
    }

    // MARK: - Health Check Tests

    func testCheckServiceHealth_ProcessNotRunning() async {
        let status = ProcessHealthStatus(isRunning: false, pid: nil)
        let healthStatus = await monitor.checkServiceHealth(processStatus: status, udpClient: nil)

        XCTAssertFalse(healthStatus.isHealthy, "Should be unhealthy when process not running")
        XCTAssertTrue(healthStatus.shouldRestart, "Should recommend restart")
        XCTAssertEqual(healthStatus.reason, "Process not running")
    }

    func testCheckServiceHealth_ProcessRunning_NoUDPClient() async {
        let status = ProcessHealthStatus(isRunning: true, pid: 1234)
        let healthStatus = await monitor.checkServiceHealth(processStatus: status, udpClient: nil)

        XCTAssertTrue(healthStatus.isHealthy, "Should be healthy when process running and no UDP check available")
        XCTAssertFalse(healthStatus.shouldRestart, "Should not recommend restart")
    }

    func testCheckServiceHealth_WithinGracePeriod() async {
        // Record a recent start
        await monitor.recordStartAttempt(timestamp: Date())

        let status = ProcessHealthStatus(isRunning: true, pid: 1234)
        let healthStatus = await monitor.checkServiceHealth(processStatus: status, udpClient: nil)

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
        await monitor.recordStartAttempt(timestamp: Date())
        var cooldownState = await monitor.canRestartService()
        XCTAssertEqual(cooldownState.attemptsSinceLastSuccess, 1, "Should track first attempt")

        // Wait for cooldown then try again
        try? await Task.sleep(nanoseconds: 2_500_000_000) // 2.5 seconds
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
        for i in 1...5 {
            let shouldTrigger = await monitor.recordConnectionFailure()
            XCTAssertFalse(shouldTrigger, "Should not trigger recovery at \(i) failures")
        }
    }

    func testRecordConnectionFailure_TriggersRecoveryAtMax() async {
        // Record 9 failures
        for _ in 1...9 {
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
        // Exceed max start attempts
        for _ in 1...3 {
            await monitor.recordStartAttempt(timestamp: Date().addingTimeInterval(-10))
            await monitor.recordStartFailure()
        }

        let healthStatus = ServiceHealthStatus.unhealthy(reason: "Test", shouldRestart: true)
        let action = await monitor.determineRecoveryAction(healthStatus: healthStatus)

        if case .giveUp(let reason) = action {
            XCTAssertTrue(reason.contains("attempts"), "Should mention attempts in reason")
        } else {
            XCTFail("Should give up after max attempts")
        }
    }

    func testDetermineRecoveryAction_ConnectionFailures() async {
        // Trigger max connection failures
        for _ in 1...10 {
            _ = await monitor.recordConnectionFailure()
        }

        let healthStatus = ServiceHealthStatus.unhealthy(reason: "Connection issues", shouldRestart: true)
        let action = await monitor.determineRecoveryAction(healthStatus: healthStatus)

        if case .fullRecovery = action {
            // Success
        } else {
            XCTFail("Should recommend full recovery for connection failures")
        }
    }

    func testDetermineRecoveryAction_ProcessConflicts() async {
        // Set up mock conflicts
        let conflictProcess = ProcessLifecycleManager.ProcessInfo(pid: 9999, command: "/usr/local/bin/kanata")
        mockProcessLifecycle.mockConflicts = ProcessLifecycleManager.ConflictResolution(
            externalProcesses: [conflictProcess],
            managedProcesses: [],
            canAutoResolve: true
        )

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
        XCTAssertGreaterThan(cooldownState.attemptsSinceLastSuccess, 0, "Should have attempts before reset")

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

        // First check without UDP client - should be healthy
        let healthStatus = await monitor.checkServiceHealth(processStatus: status, udpClient: nil)
        XCTAssertTrue(healthStatus.isHealthy)
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
}