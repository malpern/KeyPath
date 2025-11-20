@testable import KeyPathAppKit
import XCTest

final class VHIDDeviceManagerTests: XCTestCase {
    override func tearDown() {
        super.tearDown()
        // Reset ALL test seams to avoid leaking into other tests
        VHIDDeviceManager.testPIDProvider = nil
        VHIDDeviceManager.testShellProvider = nil
        FeatureFlags.testStartupMode = nil
    }

    func testDetectRunning_UnhealthyWithDuplicates() {
        // Provide two PIDs to simulate duplicate daemons
        VHIDDeviceManager.testPIDProvider = { ["123", "456"] }
        let mgr = VHIDDeviceManager()
        XCTAssertFalse(mgr.detectRunning(), "Duplicate daemons should be considered unhealthy")
    }

    func testDetectRunning_HealthySingleInstance() {
        VHIDDeviceManager.testPIDProvider = { ["123"] }
        let mgr = VHIDDeviceManager()
        XCTAssertTrue(mgr.detectRunning(), "Single daemon should be healthy")
    }

    func testDetectRunning_NotRunning() {
        VHIDDeviceManager.testPIDProvider = { [] }
        let mgr = VHIDDeviceManager()
        XCTAssertFalse(mgr.detectRunning(), "No daemon should be reported as not running")
    }

    // MARK: - Startup Mode Tests

    func testDetectRunning_StartupMode_DaemonRunning() {
        // Simulate startup mode active
        FeatureFlags.testStartupMode = true

        // Mock launchctl list showing daemon is running
        VHIDDeviceManager.testShellProvider = { command in
            if command.contains("launchctl list") {
                return """
                {
                    "LimitLoadToSessionType" = "Aqua";
                    "Label" = "com.keypath.karabiner-vhiddaemon";
                    "TimeOut" = 30;
                    "OnDemand" = false;
                    "LastExitStatus" = 0;
                    "PID" = 12345;
                    "Program" = "/Applications/KeyPath.app/Contents/Resources/Karabiner-DriverKit-VirtualHIDDevice/Applications/Karabiner-VHIDDevice.app/Contents/MacOS/Karabiner-VHIDDevice";
                };
                """
            }
            return ""
        }

        let mgr = VHIDDeviceManager()
        XCTAssertTrue(mgr.detectRunning(), "Startup mode with running daemon should return healthy")
    }

    func testDetectRunning_StartupMode_DaemonNotRunning() {
        // Simulate startup mode active
        FeatureFlags.testStartupMode = true

        // Mock launchctl list showing daemon is NOT running (no PID field)
        VHIDDeviceManager.testShellProvider = { command in
            if command.contains("launchctl list") {
                return "Could not find service \"com.keypath.karabiner-vhiddaemon\" in domain for port"
            }
            return ""
        }

        let mgr = VHIDDeviceManager()
        XCTAssertFalse(mgr.detectRunning(), "Startup mode with daemon not running should return not running")
    }

    func testEvaluateDaemonProcess_StartupMode_UsesFastCheck() {
        // Simulate startup mode active
        FeatureFlags.testStartupMode = true

        var launchctlCalled = false
        VHIDDeviceManager.testShellProvider = { command in
            if command.contains("launchctl list") {
                launchctlCalled = true
                return """
                {
                    "PID" = 12345;
                };
                """
            }
            return ""
        }

        let mgr = VHIDDeviceManager()
        _ = mgr.detectRunning()

        XCTAssertTrue(launchctlCalled, "Startup mode should use launchctl for fast health check")
    }

    func testDetectRunning_NormalMode_BypassesFastCheck() {
        // Normal mode (startup mode not active)
        FeatureFlags.testStartupMode = false

        // Provide PID via normal test seam
        VHIDDeviceManager.testPIDProvider = { ["12345"] }

        var shellCommandCalled = false
        VHIDDeviceManager.testShellProvider = { _ in
            shellCommandCalled = true
            return ""
        }

        let mgr = VHIDDeviceManager()
        _ = mgr.detectRunning()

        XCTAssertFalse(shellCommandCalled, "Normal mode should NOT use shell command, should use pgrep")
    }

    func testGetDaemonPIDs_StartupMode_ReturnsEmpty() {
        // Simulate startup mode active
        FeatureFlags.testStartupMode = true

        // Verify PID collection is skipped in startup mode
        VHIDDeviceManager.testPIDProvider = { ["should", "not", "be", "called"] }

        let mgr = VHIDDeviceManager()
        let pids = mgr.getDaemonPIDs()

        XCTAssertTrue(pids.isEmpty, "Startup mode should skip PID collection and return empty array")
    }

    func testStartupMode_RaceConditionPrevention() {
        // This test verifies the fix for the race condition that caused wizard false positives
        // When startup mode is active, we should get consistent results from rapid health checks

        FeatureFlags.testStartupMode = true
        VHIDDeviceManager.testShellProvider = { command in
            if command.contains("launchctl list") {
                return """
                {
                    "PID" = 12345;
                };
                """
            }
            return ""
        }

        let mgr = VHIDDeviceManager()

        // Perform multiple rapid health checks (simulating wizard behavior)
        let results = (0..<10).map { _ in mgr.detectRunning() }

        // All results should be consistent (all true in this case since daemon is "running")
        XCTAssertTrue(results.allSatisfy { $0 == true }, "Rapid health checks should return consistent results")
    }
}
