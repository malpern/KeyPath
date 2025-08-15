@testable import KeyPath
import XCTest

/// Comprehensive tests for wizard state detection logic
/// Tests all edge cases and complex scenarios for system state detection
@MainActor
final class WizardStateDetectionTests: XCTestCase {
    // MARK: - Path Normalization Tests

    func testPathNormalization() throws {
        let detector = SystemStateDetector(
            kanataManager: KanataManager(),
            launchDaemonInstaller: LaunchDaemonInstaller()
        )

        // Test tilde expansion
        XCTAssertEqual(
            detector.normalizePath("~/Library/KeyPath"),
            "\(NSHomeDirectory())/Library/KeyPath"
        )

        // Test relative path resolution
        XCTAssertEqual(
            detector.normalizePath("./config.kbd"),
            "\(FileManager.default.currentDirectoryPath)/config.kbd"
        )

        // Test parent directory navigation
        let parentPath = detector.normalizePath("../config.kbd")
        XCTAssertTrue(parentPath.hasPrefix("/"))
        XCTAssertFalse(parentPath.contains(".."))

        // Test already absolute path
        XCTAssertEqual(
            detector.normalizePath("/usr/local/bin/kanata"),
            "/usr/local/bin/kanata"
        )

        // Test path with trailing slash removal
        XCTAssertEqual(
            detector.normalizePath("/usr/local/bin/"),
            "/usr/local/bin"
        )

        // Test empty path handling
        XCTAssertEqual(
            detector.normalizePath(""),
            FileManager.default.currentDirectoryPath
        )
    }

    func testCommandLineParsing() throws {
        let detector = SystemStateDetector(
            kanataManager: KanataManager(),
            launchDaemonInstaller: LaunchDaemonInstaller()
        )

        // Test simple command
        let simple = detector.parseCommandLineForConfigPath(
            "/usr/local/bin/kanata --cfg /test/config.kbd"
        )
        XCTAssertEqual(simple, "/test/config.kbd")

        // Test with quotes
        let quoted = detector.parseCommandLineForConfigPath(
            "/usr/local/bin/kanata --cfg \"/path with spaces/config.kbd\""
        )
        XCTAssertEqual(quoted, "/path with spaces/config.kbd")

        // Test with single quotes
        let singleQuoted = detector.parseCommandLineForConfigPath(
            "/usr/local/bin/kanata --cfg '/another path/config.kbd'"
        )
        XCTAssertEqual(singleQuoted, "/another path/config.kbd")

        // Test with multiple arguments
        let multiple = detector.parseCommandLineForConfigPath(
            "/usr/local/bin/kanata --port 54141 --cfg /test/config.kbd --watch --debug"
        )
        XCTAssertEqual(multiple, "/test/config.kbd")

        // Test with equals sign syntax
        let equals = detector.parseCommandLineForConfigPath(
            "/usr/local/bin/kanata --cfg=/test/config.kbd"
        )
        XCTAssertEqual(equals, "/test/config.kbd")

        // Test without config flag
        let noConfig = detector.parseCommandLineForConfigPath(
            "/usr/local/bin/kanata --watch --debug"
        )
        XCTAssertNil(noConfig)

        // Test with escaped quotes
        let escaped = detector.parseCommandLineForConfigPath(
            "/usr/local/bin/kanata --cfg \"/path with \\\"quotes\\\"/config.kbd\""
        )
        XCTAssertEqual(escaped, "/path with \"quotes\"/config.kbd")
    }

    // MARK: - Complex State Detection Scenarios

    func testPartialInstallationStates() async throws {
        // Scenario 1: Kanata installed but no drivers
        let scenario1 = MockSystemStateBuilder()
            .withKanataInstalled(true)
            .withDriversInstalled(false)
            .withServiceRunning(false)
            .build()

        let state1 = await scenario1.detectSystemState()
        XCTAssertEqual(state1.state, .partiallyConfigured)
        XCTAssertTrue(state1.issues.contains { $0.category == .installation })

        // Scenario 2: Drivers installed but no Kanata
        let scenario2 = MockSystemStateBuilder()
            .withKanataInstalled(false)
            .withDriversInstalled(true)
            .withServiceRunning(false)
            .build()

        let state2 = await scenario2.detectSystemState()
        XCTAssertEqual(state2.state, .needsConfiguration)
        XCTAssertTrue(state2.issues.contains { $0.identifier == .component(.kanataNotInstalled) })

        // Scenario 3: Everything installed but no permissions
        let scenario3 = MockSystemStateBuilder()
            .withKanataInstalled(true)
            .withDriversInstalled(true)
            .withPermissions(input: false, accessibility: false)
            .withServiceRunning(false)
            .build()

        let state3 = await scenario3.detectSystemState()
        XCTAssertEqual(state3.state, .needsHelp)
        XCTAssertTrue(state3.issues.contains { $0.category == .permissions })
    }

    func testConflictDetectionPriorities() async throws {
        // Multiple conflicts should be prioritized correctly
        let scenario = MockSystemStateBuilder()
            .withKanataInstalled(true)
            .withKarabinerRunning(true)
            .withOrphanedProcess(pid: 1234, configPath: "/wrong/path")
            .withExternalProcesses([
                ProcessLifecycleManager.ProcessInfo(pid: 5678, command: "kanata --cfg /other/path")
            ])
            .build()

        let state = await scenario.detectSystemState()

        // Should detect all conflicts
        XCTAssertTrue(state.issues.contains { $0.identifier == .conflict(.karabinerRunning) })
        XCTAssertTrue(state.issues.contains { $0.identifier == .service(.orphanedProcess) })

        // Should prioritize critical conflicts
        let criticalIssues = state.issues.filter { $0.severity == .critical }
        XCTAssertFalse(criticalIssues.isEmpty)
    }

    func testServiceHealthDetection() async throws {
        // Test unhealthy service states
        let unhealthyScenario = MockSystemStateBuilder()
            .withKanataInstalled(true)
            .withDriversInstalled(true)
            .withServiceRunning(true)
            .withTCPServerResponding(false)
            .withServiceCrashCount(3)
            .build()

        let unhealthyState = await unhealthyScenario.detectSystemState()
        XCTAssertTrue(unhealthyState.issues.contains { $0.identifier == .service(.tcpServerNotResponding) })
        XCTAssertTrue(unhealthyState.issues.contains { $0.identifier == .service(.repeatedCrashes) })

        // Test healthy service
        let healthyScenario = MockSystemStateBuilder()
            .withKanataInstalled(true)
            .withDriversInstalled(true)
            .withServiceRunning(true)
            .withTCPServerResponding(true)
            .withServiceCrashCount(0)
            .build()

        let healthyState = await healthyScenario.detectSystemState()
        XCTAssertFalse(healthyState.issues.contains { $0.category == .service })
    }

    // MARK: - Decision Matrix Tests

    func testOrphanedProcessDecisionMatrix() throws {
        let detector = SystemStateDetector(
            kanataManager: KanataManager(),
            launchDaemonInstaller: LaunchDaemonInstaller()
        )

        // Matrix test cases
        struct TestCase {
            let name: String
            let orphanedProcess: ProcessLifecycleManager.ProcessInfo?
            let configPath: String
            let launchDaemonInstalled: Bool
            let expectedAction: AutoFixAction?
        }

        let testCases = [
            TestCase(
                name: "No orphaned process",
                orphanedProcess: nil,
                configPath: "/config.kbd",
                launchDaemonInstalled: true,
                expectedAction: nil
            ),
            TestCase(
                name: "Orphaned with matching config, no daemon",
                orphanedProcess: ProcessLifecycleManager.ProcessInfo(
                    pid: 100,
                    command: "kanata --cfg /config.kbd"
                ),
                configPath: "/config.kbd",
                launchDaemonInstalled: false,
                expectedAction: .adoptOrphanedProcess
            ),
            TestCase(
                name: "Orphaned with different config",
                orphanedProcess: ProcessLifecycleManager.ProcessInfo(
                    pid: 200,
                    command: "kanata --cfg /other.kbd"
                ),
                configPath: "/config.kbd",
                launchDaemonInstalled: true,
                expectedAction: .replaceOrphanedProcess
            ),
            TestCase(
                name: "Orphaned with matching config and daemon",
                orphanedProcess: ProcessLifecycleManager.ProcessInfo(
                    pid: 300,
                    command: "kanata --cfg /config.kbd --port 54141"
                ),
                configPath: "/config.kbd",
                launchDaemonInstalled: true,
                expectedAction: .replaceOrphanedProcess
            )
        ]

        for testCase in testCases {
            let result = detector.computeOrphanedProcessAutoFixWithMocks(
                orphanedProcess: testCase.orphanedProcess,
                configPath: testCase.configPath,
                launchDaemonInstalled: testCase.launchDaemonInstalled
            )

            XCTAssertEqual(
                result.autoFix,
                testCase.expectedAction,
                "Failed: \(testCase.name)"
            )
        }
    }

    // MARK: - Race Condition Tests

    func testConcurrentStateDetection() async throws {
        let detector = SystemStateDetector(
            kanataManager: KanataManager(),
            launchDaemonInstaller: LaunchDaemonInstaller()
        )

        // Run multiple concurrent state detections
        async let state1 = detector.detectSystemState()
        async let state2 = detector.detectSystemState()
        async let state3 = detector.detectSystemState()

        let states = await [state1, state2, state3]

        // All should return consistent results
        let firstState = states[0].state
        XCTAssertTrue(states.allSatisfy { $0.state == firstState })
    }

    func testStateTransitionValidation() async throws {
        // Test valid state transitions
        let validTransitions: [(WizardSystemState, WizardSystemState)] = [
            (.notInstalled, .needsConfiguration),
            (.needsConfiguration, .partiallyConfigured),
            (.partiallyConfigured, .configurationComplete),
            (.configurationComplete, .fullyOperational),
            (.fullyOperational, .needsHelp) // Can regress if issues arise
        ]

        for (from, to) in validTransitions {
            XCTAssertTrue(
                isValidTransition(from: from, to: to),
                "Transition from \(from) to \(to) should be valid"
            )
        }

        // Test invalid transitions
        let invalidTransitions: [(WizardSystemState, WizardSystemState)] = [
            (.fullyOperational, .notInstalled), // Can't uninstall to nothing
            (.notInstalled, .fullyOperational) // Can't skip all steps
        ]

        for (from, to) in invalidTransitions {
            XCTAssertFalse(
                isValidTransition(from: from, to: to),
                "Transition from \(from) to \(to) should be invalid"
            )
        }
    }

    // Helper function for state transition validation
    private func isValidTransition(from: WizardSystemState, to: WizardSystemState) -> Bool {
        // Define valid state transition rules
        switch (from, to) {
        case (.notInstalled, .needsConfiguration),
             (.needsConfiguration, .partiallyConfigured),
             (.partiallyConfigured, .configurationComplete),
             (.configurationComplete, .fullyOperational):
            true
        case (_, .needsHelp):
            true // Can always need help
        case (.needsHelp, _):
            true // Can recover from needing help
        default:
            false
        }
    }
}

// MARK: - Mock Builder

/// Builder pattern for creating test scenarios
@MainActor
class MockSystemStateBuilder {
    private var kanataInstalled = false
    private var driversInstalled = false
    private var serviceRunning = false
    private var inputMonitoring = true
    private var accessibility = true
    private var karabinerRunning = false
    private var tcpResponding = true
    private var crashCount = 0
    private var orphanedProcess: ProcessLifecycleManager.ProcessInfo?
    private var externalProcesses: [ProcessLifecycleManager.ProcessInfo] = []

    func withKanataInstalled(_ installed: Bool) -> Self {
        kanataInstalled = installed
        return self
    }

    func withDriversInstalled(_ installed: Bool) -> Self {
        driversInstalled = installed
        return self
    }

    func withServiceRunning(_ running: Bool) -> Self {
        serviceRunning = running
        return self
    }

    func withPermissions(input: Bool, accessibility: Bool) -> Self {
        inputMonitoring = input
        self.accessibility = accessibility
        return self
    }

    func withKarabinerRunning(_ running: Bool) -> Self {
        karabinerRunning = running
        return self
    }

    func withTCPServerResponding(_ responding: Bool) -> Self {
        tcpResponding = responding
        return self
    }

    func withServiceCrashCount(_ count: Int) -> Self {
        crashCount = count
        return self
    }

    func withOrphanedProcess(pid: pid_t, configPath: String) -> Self {
        orphanedProcess = ProcessLifecycleManager.ProcessInfo(
            pid: pid,
            command: "kanata --cfg \(configPath)"
        )
        return self
    }

    func withExternalProcesses(_ processes: [ProcessLifecycleManager.ProcessInfo]) -> Self {
        externalProcesses = processes
        return self
    }

    func build() -> SystemStateDetector {
        let mockManager = MockKanataManager()
        mockManager.mockKanataInstalled = kanataInstalled
        mockManager.mockDriversInstalled = driversInstalled
        mockManager.mockServiceRunning = serviceRunning
        mockManager.mockInputMonitoringGranted = inputMonitoring
        mockManager.mockAccessibilityGranted = accessibility
        mockManager.mockKarabinerRunning = karabinerRunning
        mockManager.mockTCPServerResponding = tcpResponding
        mockManager.mockOrphanedProcess = orphanedProcess
        mockManager.mockConflictingProcesses = externalProcesses

        return SystemStateDetector(
            kanataManager: mockManager,
            launchDaemonInstaller: MockLaunchDaemonInstaller()
        )
    }
}
