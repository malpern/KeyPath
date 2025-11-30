@testable import KeyPathAppKit
@preconcurrency import XCTest

final class KanataManagerBreakageSummaryTests: XCTestCase {
    func testSummaryTreatsHealthySinglePIDAsHealthy() {
        let status = VirtualHIDDaemonStatus(
            pids: ["123"],
            owners: [],
            serviceInstalled: true,
            serviceState: "running",
            serviceHealthy: true
        )

        let summary = KanataManager.makeVirtualHIDBreakageSummary(
            status: status,
            driverEnabled: true,
            installedVersion: "5.0.0",
            hasMismatch: false
        )

        XCTAssertFalse(summary.contains("status check failed"), "Should not report failure when healthy")
        XCTAssertTrue(summary.contains("launchctl reports healthy"))
    }

    func testSummaryReportsFailureWhenLaunchctlHealthyIsFalse() {
        let status = VirtualHIDDaemonStatus(
            pids: ["123"],
            owners: [],
            serviceInstalled: true,
            serviceState: "running",
            serviceHealthy: false
        )

        let summary = KanataManager.makeVirtualHIDBreakageSummary(
            status: status,
            driverEnabled: true,
            installedVersion: "5.0.0",
            hasMismatch: false
        )

        XCTAssertTrue(summary.contains("health check failed"))
    }
}
