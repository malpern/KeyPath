@testable import KeyPathAppKit
@testable import KeyPathCore
@testable import KeyPathInstallationWizard
@preconcurrency import XCTest

final class VHIDDeviceManagerTests: XCTestCase {
    override func tearDown() {
        super.tearDown()
        // Reset ALL test seams to avoid leaking into other tests
        VHIDDeviceManager.testPIDProvider = nil
        VHIDDeviceManager.testShellProvider = nil
        VHIDDeviceManager.testInstalledVersionProvider = nil
        KeyPathCore.FeatureFlags.testStartupMode = nil
    }

    // MARK: - Version Mismatch Tests

    func testHasVersionMismatch_V5InstalledRequiresV6() {
        // Simulate v5.0.0 installed when v6.2.0 is required
        VHIDDeviceManager.testInstalledVersionProvider = { "5.0.0" }
        let mgr = VHIDDeviceManager()
        XCTAssertTrue(mgr.hasVersionMismatch(), "v5 installed with v6 required should be a mismatch")
    }

    func testHasVersionMismatch_V6InstalledRequiresV6() {
        // Simulate v6.2.0 installed when v6.2.0 is required
        VHIDDeviceManager.testInstalledVersionProvider = { "6.2.0" }
        let mgr = VHIDDeviceManager()
        XCTAssertFalse(mgr.hasVersionMismatch(), "v6 installed with v6 required should NOT be a mismatch")
    }

    func testHasVersionMismatch_V6_1InstalledRequiresV6_2() {
        VHIDDeviceManager.testInstalledVersionProvider = { "6.1.0" }
        let mgr = VHIDDeviceManager()
        XCTAssertTrue(mgr.hasVersionMismatch(), "v6.1 installed with v6.2 required should be a mismatch")
    }

    func testHasVersionMismatch_V6_0InstalledRequiresV6_2() {
        VHIDDeviceManager.testInstalledVersionProvider = { "6.0.0" }
        let mgr = VHIDDeviceManager()
        XCTAssertTrue(mgr.hasVersionMismatch(), "v6.0 installed with v6.2 required should be a mismatch")
    }

    func testHasVersionMismatch_NewerCompatibleV6Release() {
        VHIDDeviceManager.testInstalledVersionProvider = { "6.14.0" }
        let mgr = VHIDDeviceManager()
        XCTAssertFalse(mgr.hasVersionMismatch(), "a newer v6 release should remain compatible")
    }

    func testHasVersionMismatch_NoVersionInstalled() {
        // Simulate no driver installed
        VHIDDeviceManager.testInstalledVersionProvider = { nil }
        let mgr = VHIDDeviceManager()
        XCTAssertFalse(mgr.hasVersionMismatch(), "No driver installed should NOT be a mismatch (can't mismatch nothing)")
    }

    func testGetVersionMismatchMessage_ReturnsMessageForMismatch() {
        VHIDDeviceManager.testInstalledVersionProvider = { "5.0.0" }
        let mgr = VHIDDeviceManager()
        let message = mgr.getVersionMismatchMessage()
        XCTAssertNotNil(message, "Should return message when version mismatch exists")
        XCTAssertTrue(message?.contains("5.0.0") ?? false, "Message should mention installed version")
        XCTAssertTrue(message?.contains("6.2.0") ?? false, "Message should mention required version")
    }

    func testGetVersionMismatchMessage_ReturnsNilWhenCompatible() {
        VHIDDeviceManager.testInstalledVersionProvider = { "6.2.0" }
        let mgr = VHIDDeviceManager()
        let message = mgr.getVersionMismatchMessage()
        XCTAssertNil(message, "Should return nil when versions are compatible")
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

    func testDetectRunningUsesInjectedSystemStateProviderForProcessDiscovery() async {
        KeyPathCore.FeatureFlags.testStartupMode = false
        VHIDDeviceManager.testPIDProvider = nil
        let runner = SubprocessRunnerFake.shared
        await runner.reset()
        await runner.configurePgrepResult { pattern in
            pattern == "Karabiner-VirtualHIDDevice-Daemon" ? [12345] : []
        }

        let provider = SystemStateProvider(probes: runner.systemProbeClient())
        let mgr = VHIDDeviceManager(systemStateProvider: provider)
        let running = await mgr.detectRunning()
        let commands = await runner.executedCommands

        XCTAssertTrue(running, "Injected provider should report the daemon as running")
        XCTAssertTrue(
            commands.contains { $0.executable == "/usr/bin/pgrep" && $0.args == ["-f", "Karabiner-VirtualHIDDevice-Daemon"] },
            "VHIDDeviceManager should use the injected provider for daemon process discovery"
        )
    }

    func testGetDaemonPIDsUsesInjectedSystemStateProviderForProcessDiscovery() async {
        KeyPathCore.FeatureFlags.testStartupMode = false
        VHIDDeviceManager.testPIDProvider = nil
        let runner = SubprocessRunnerFake.shared
        await runner.reset()
        await runner.configurePgrepResult { pattern in
            pattern == "Karabiner-VirtualHIDDevice-Daemon" ? [12345, 67890] : []
        }

        let provider = SystemStateProvider(probes: runner.systemProbeClient())
        let mgr = VHIDDeviceManager(systemStateProvider: provider)
        let pids = await mgr.getDaemonPIDs()
        let commands = await runner.executedCommands

        XCTAssertEqual(pids, ["12345", "67890"])
        XCTAssertTrue(
            commands.contains { $0.executable == "/usr/bin/pgrep" && $0.args == ["-f", "Karabiner-VirtualHIDDevice-Daemon"] },
            "VHIDDeviceManager should use the injected provider when collecting daemon PIDs"
        )
    }

    func testCheckLaunchctlHealthUsesInjectedSystemStateProvider() async {
        let runner = SubprocessRunnerFake.shared
        await runner.reset()
        await runner.configureLaunchctlResult { subcommand, args in
            if subcommand == "print", args == ["system/com.keypath.karabiner-vhiddaemon"] {
                return ProcessResult(
                    exitCode: 0,
                    stdout: """
                    state = running
                    pid = 24680
                    """,
                    stderr: "",
                    duration: 0.01
                )
            }
            return ProcessResult(exitCode: 113, stdout: "", stderr: "not found", duration: 0.01)
        }

        let provider = SystemStateProvider(probes: runner.systemProbeClient())
        let mgr = VHIDDeviceManager(systemStateProvider: provider)
        let healthy = await mgr.checkLaunchctlHealth()
        let commands = await runner.executedCommands

        XCTAssertEqual(healthy, true)
        XCTAssertTrue(
            commands.contains { $0.executable == "/bin/launchctl" && $0.args == ["print", "system/com.keypath.karabiner-vhiddaemon"] },
            "VHIDDeviceManager should use its injected provider for launchctl service-state evidence"
        )
    }

    func testDuplicateProcessRaceUsesInjectedLaunchctlEvidence() async {
        KeyPathCore.FeatureFlags.testStartupMode = false
        VHIDDeviceManager.testPIDProvider = nil
        let runner = SubprocessRunnerFake.shared
        await runner.reset()
        await runner.configurePgrepResult { pattern in
            pattern == "Karabiner-VirtualHIDDevice-Daemon" ? [111, 222] : []
        }
        await runner.configureLaunchctlResult { subcommand, args in
            if subcommand == "print", args == ["system/com.keypath.karabiner-vhiddaemon"] {
                return ProcessResult(exitCode: 0, stdout: "pid = 111", stderr: "", duration: 0.01)
            }
            return ProcessResult(exitCode: 113, stdout: "", stderr: "not found", duration: 0.01)
        }

        let provider = SystemStateProvider(probes: runner.systemProbeClient())
        let mgr = VHIDDeviceManager(systemStateProvider: provider)
        let running = await mgr.detectRunning()
        let commands = await runner.executedCommands

        XCTAssertTrue(running, "Injected launchctl evidence should suppress duplicate-process false positives")
        XCTAssertTrue(
            commands.contains { $0.executable == "/usr/bin/pgrep" && $0.args == ["-f", "Karabiner-VirtualHIDDevice-Daemon"] }
        )
        XCTAssertTrue(
            commands.contains { $0.executable == "/bin/launchctl" && $0.args == ["print", "system/com.keypath.karabiner-vhiddaemon"] }
        )
    }

    // MARK: - Startup Mode Tests

    func testDetectRunning_StartupMode_DaemonRunning() async {
        // Simulate startup mode active
        KeyPathCore.FeatureFlags.testStartupMode = true

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
        KeyPathCore.FeatureFlags.testStartupMode = true

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
        KeyPathCore.FeatureFlags.testStartupMode = true

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
        KeyPathCore.FeatureFlags.testStartupMode = false

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
        KeyPathCore.FeatureFlags.testStartupMode = true

        // Verify PID collection is skipped in startup mode
        VHIDDeviceManager.testPIDProvider = { ["should", "not", "be", "called"] }

        let mgr = VHIDDeviceManager()
        let pids = await mgr.getDaemonPIDs()

        XCTAssertTrue(pids.isEmpty, "Startup mode should skip PID collection and return empty array")
    }

    func testStartupMode_RaceConditionPrevention() async {
        // This test verifies the fix for the race condition that caused wizard false positives
        // When startup mode is active, we should get consistent results from rapid health checks

        KeyPathCore.FeatureFlags.testStartupMode = true
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

    // MARK: - Bundled Driver Version Tests

    func testBundledDriverVersion_IsValidSemver() {
        let version = WizardSystemPaths.bundledVHIDDriverVersion
        let components = version.split(separator: ".")
        XCTAssertEqual(components.count, 3, "Version should be semver format (x.y.z)")
        XCTAssertTrue(components.allSatisfy { Int($0) != nil }, "All version components should be numeric")
    }

    func testBundledDriverMajorVersion_MatchesFullVersion() {
        let fullVersion = WizardSystemPaths.bundledVHIDDriverVersion
        let majorVersion = WizardSystemPaths.bundledVHIDDriverMajorVersion
        let expectedMajor = Int(fullVersion.split(separator: ".").first ?? "0") ?? 0
        XCTAssertEqual(majorVersion, expectedMajor, "Major version should match first component of full version")
    }

    func testRequiredDriverVersion_UsesBundledVersion() {
        // VHIDDeviceManager.requiredDriverVersionString should match WizardSystemPaths
        XCTAssertEqual(
            VHIDDeviceManager.requiredDriverVersionString,
            WizardSystemPaths.bundledVHIDDriverVersion,
            "VHIDDeviceManager should use bundled version as single source of truth"
        )
    }
}
