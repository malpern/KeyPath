import Foundation
@testable import KeyPathAppKit
@preconcurrency import XCTest

@MainActor
class ServiceHealthMonitorTests: XCTestCase {
    var monitor: ServiceHealthMonitor!

    override func setUp() async throws {
        try await super.setUp()
        monitor = ServiceHealthMonitor()
    }

    override func tearDown() async throws {
        monitor = nil
        try await super.tearDown()
    }

    // MARK: - Health Check Tests

    func testCheckServiceHealth_ProcessNotRunning() async {
        let status = ProcessHealthStatus(isRunning: false, pid: nil)
        let healthStatus = await monitor.checkServiceHealth(processStatus: status, tcpPort: 37000)

        XCTAssertFalse(healthStatus.isHealthy, "Should be unhealthy when process not running")
        XCTAssertTrue(healthStatus.shouldRestart, "Should recommend restart")
        XCTAssertEqual(healthStatus.reason, "Process not running")
    }

    func testCheckServiceHealth_ProcessRunning() async {
        // The TCP probe is skipped under tests and reports healthy.
        let status = ProcessHealthStatus(isRunning: true, pid: 1234)
        let healthStatus = await monitor.checkServiceHealth(processStatus: status, tcpPort: 37000)

        XCTAssertTrue(healthStatus.isHealthy)
        XCTAssertFalse(healthStatus.shouldRestart)
    }

    // MARK: - Grab-recovery guard (#625)

    func testGrabRecoveryGuard_boundsAttemptsThenGivesUp() {
        let t0 = Date()
        XCTAssertEqual(monitor.decideGrabRecovery(now: t0), .recover(attempt: 1))
        XCTAssertEqual(monitor.decideGrabRecovery(now: t0.addingTimeInterval(1)), .recover(attempt: 2))
        XCTAssertEqual(monitor.decideGrabRecovery(now: t0.addingTimeInterval(2)), .recover(attempt: 3))
        // 4th and beyond: budget exhausted → give up (don't restart forever).
        XCTAssertEqual(monitor.decideGrabRecovery(now: t0.addingTimeInterval(3)), .giveUp(attempts: 3))
        XCTAssertEqual(monitor.decideGrabRecovery(now: t0.addingTimeInterval(4)), .giveUp(attempts: 3))
    }

    func testGrabRecoveryGuard_resetsOnSuccess() async {
        let t0 = Date()
        _ = monitor.decideGrabRecovery(now: t0)
        _ = monitor.decideGrabRecovery(now: t0.addingTimeInterval(1))
        await monitor.recordGrabSuccess()
        // After a healthy grab, the budget is fresh.
        XCTAssertEqual(monitor.decideGrabRecovery(now: t0.addingTimeInterval(2)), .recover(attempt: 1))
    }

    func testGrabRecoveryGuard_freshEpisodeAfterQuietWindow() {
        let t0 = Date()
        _ = monitor.decideGrabRecovery(now: t0)
        _ = monitor.decideGrabRecovery(now: t0)
        _ = monitor.decideGrabRecovery(now: t0)
        XCTAssertEqual(monitor.decideGrabRecovery(now: t0.addingTimeInterval(1)), .giveUp(attempts: 3))
        // A failure long after the burst (> episode window) is a new episode → fresh budget.
        XCTAssertEqual(monitor.decideGrabRecovery(now: t0.addingTimeInterval(301)), .recover(attempt: 1))
    }
}
