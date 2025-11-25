import XCTest

@testable import KeyPathAppKit

final class VHIDDeviceManagerTests: XCTestCase {
    override func tearDown() {
        super.tearDown()
        // Reset ALL test seams to avoid leaking into other tests
        VHIDDeviceManager.testPIDProvider = nil
        VHIDDeviceManager.testShellProvider = nil
        FeatureFlags.testStartupMode = nil
    }

    func testDetectRunning_UnhealthyWithDuplicates() async {
        // Provide two PIDs to simulate duplicate daemons
        VHIDDeviceManager.testPIDProvider = { ["123", "456"] }
        let mgr = VHIDDeviceManager()
        let running = await mgr.detectRunning()
        XCTAssertFalse(running, "Duplicate daemons should be considered unhealthy")
    }

    func testDetectRunning_HealthySingleInstance() async {
        VHIDDeviceManager.testPIDProvider = { ["123"] }
        let mgr = VHIDDeviceManager()
        let running = await mgr.detectRunning()
        XCTAssertTrue(running, "Single daemon should be healthy")
    }

    func testDetectRunning_NotRunning() async {
        VHIDDeviceManager.testPIDProvider = { [] }
        let mgr = VHIDDeviceManager()
        let running = await mgr.detectRunning()
        XCTAssertFalse(running, "No daemon should be reported as not running")
    }

    // MARK: - Startup Mode Tests

    func testDetectRunning_StartupMode_DaemonRunning() async {
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
        let running = await mgr.detectRunning()
        XCTAssertTrue(running, "Startup mode with running daemon should return healthy")
    }

    func testDetectRunning_StartupMode_DaemonNotRunning() async {
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
        let running = await mgr.detectRunning()
        XCTAssertFalse(
            running, "Startup mode with daemon not running should return not running"
        )
    }

    func testEvaluateDaemonProcess_StartupMode_UsesFastCheck() async {
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
        _ = await mgr.detectRunning()

        XCTAssertTrue(launchctlCalled, "Startup mode should use launchctl for fast health check")
    }

    func testDetectRunning_NormalMode_BypassesFastCheck() async {
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
        _ = await mgr.detectRunning()

        XCTAssertFalse(shellCommandCalled, "Normal mode should NOT use shell command, should use pgrep")
    }

    func testGetDaemonPIDs_StartupMode_ReturnsEmpty() async {
        // Simulate startup mode active
        FeatureFlags.testStartupMode = true

        // Verify PID collection is skipped in startup mode
        VHIDDeviceManager.testPIDProvider = { ["should", "not", "be", "called"] }

        let mgr = VHIDDeviceManager()
        let pids = mgr.getDaemonPIDs()

        XCTAssertTrue(pids.isEmpty, "Startup mode should skip PID collection and return empty array")
    }

    func testStartupMode_RaceConditionPrevention() async {
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
        var results: [Bool] = []
        for _ in 0 ..< 10 {
            await results.append(mgr.detectRunning())
        }

        // All results should be consistent (all true in this case since daemon is "running")
        XCTAssertTrue(
            results.allSatisfy { $0 == true }, "Rapid health checks should return consistent results"
        )
    }
}
