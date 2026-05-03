@testable import KeyPathAppKit
@preconcurrency import XCTest

/// Tests for the VirtualHID safety invariant:
/// Kanata must never run without a healthy VirtualHID daemon.
///
/// Uses the pure `VHIDSafetyCheck` struct so no singletons or real
/// system services are needed.
@MainActor
final class VHIDSafetyInvariantTests: KeyPathTestCase {

    // MARK: - Emergency Stop Decision

    func test_emergencyStop_triggeredWhenKanataRunningWithoutVHID() {
        let result = VHIDSafetyCheck.shouldEmergencyStop(
            kanataRunning: true,
            vhidDaemonHealthy: false
        )
        XCTAssertTrue(result, "Should trigger emergency stop when kanata is running but VHID is unhealthy")
    }

    func test_noEmergencyStop_whenVHIDHealthy() {
        let result = VHIDSafetyCheck.shouldEmergencyStop(
            kanataRunning: true,
            vhidDaemonHealthy: true
        )
        XCTAssertFalse(result, "Should NOT trigger emergency stop when VHID is healthy")
    }

    func test_noEmergencyStop_whenKanataNotRunning() {
        // VHID unhealthy but kanata not running — nothing to stop
        let unhealthy = VHIDSafetyCheck.shouldEmergencyStop(
            kanataRunning: false,
            vhidDaemonHealthy: false
        )
        XCTAssertFalse(unhealthy, "Should NOT trigger emergency stop when kanata is not running (VHID unhealthy)")

        // VHID healthy and kanata not running — nothing to stop
        let healthy = VHIDSafetyCheck.shouldEmergencyStop(
            kanataRunning: false,
            vhidDaemonHealthy: true
        )
        XCTAssertFalse(healthy, "Should NOT trigger emergency stop when kanata is not running (VHID healthy)")
    }

    // MARK: - Start Gate Decision

    func test_startKanata_refusesWhenVHIDUnhealthy() {
        let result = VHIDSafetyCheck.canStartKanata(vhidDaemonHealthy: false)
        XCTAssertFalse(result, "Should refuse to start kanata when VHID daemon is not healthy")
    }

    func test_startKanata_proceedsWhenVHIDHealthy() {
        let result = VHIDSafetyCheck.canStartKanata(vhidDaemonHealthy: true)
        XCTAssertTrue(result, "Should allow starting kanata when VHID daemon is healthy")
    }
}
