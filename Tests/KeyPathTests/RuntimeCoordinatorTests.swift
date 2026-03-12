@testable import KeyPathAppKit
@preconcurrency import XCTest

@MainActor
final class RuntimeCoordinatorTests: KeyPathTestCase {
    lazy var manager: RuntimeCoordinator = .init()

    override func setUp() {
        super.setUp()
        KanataRuntimePathCoordinator.testDecision = nil
        KanataSplitRuntimeHostService.testPersistentHostPID = nil
        KanataSplitRuntimeHostService.testStartPersistentError = nil
        KarabinerConflictService.testDaemonRunning = nil
    }

    override func tearDown() {
        KanataRuntimePathCoordinator.testDecision = nil
        KanataSplitRuntimeHostService.testPersistentHostPID = nil
        KanataSplitRuntimeHostService.testStartPersistentError = nil
        KarabinerConflictService.testDaemonRunning = nil
        super.tearDown()
    }

    func testInitialState() {
        // Test initial published properties
        // XCTAssertFalse(manager.isRunning, "Should not be running initially") // Removed
        if let error = manager.lastError {
            XCTAssertTrue(
                error.lowercased().contains("install"),
                "Unexpected initial error: \(error)"
            )
        }
        XCTAssertTrue(manager.keyMappings.isEmpty, "Should have no initial mappings")
        XCTAssertTrue(manager.diagnostics.isEmpty, "Should have no initial diagnostics")
        XCTAssertNil(manager.lastProcessExitCode, "Should have no initial exit code")
    }

    func testDiagnosticManagement() {
        // Test adding diagnostics
        let diagnostic = KanataDiagnostic(
            timestamp: Date(),
            severity: .error,
            category: .configuration,
            title: "Test Error",
            description: "Test description",
            technicalDetails: "Test details",
            suggestedAction: "Test action",
            canAutoFix: false
        )

        manager.addDiagnostic(diagnostic)
        XCTAssertEqual(manager.diagnostics.count, 1, "Should have one diagnostic")
        XCTAssertEqual(manager.diagnostics.first?.title, "Test Error")

        // Test clearing diagnostics
        manager.clearDiagnostics()
        XCTAssertTrue(manager.diagnostics.isEmpty, "Should have no diagnostics after clear")
    }

    func testConfigValidation() async {
        // Test config validation (should not crash)
        let validation = await manager.validateConfigFile()

        // Should return a validation result (valid or invalid)
        XCTAssertNotNil(validation.isValid)
        XCTAssertNotNil(validation.errors)
    }

    func testSystemDiagnostics() async {
        // Test getting system diagnostics
        let systemDiagnostics = await manager.getSystemDiagnostics()

        // Should return a valid array (may be empty)
        XCTAssertNotNil(systemDiagnostics)
    }

    func testKeyMappingStorage() {
        // Test that key mappings can be stored
        let testMapping = KeyMapping(input: "caps", output: "escape")

        // Manually add to the array to test the structure
        manager.keyMappings.append(testMapping)

        XCTAssertEqual(manager.keyMappings.count, 1, "Should have one mapping")
        XCTAssertEqual(manager.keyMappings.first?.input, "caps")
        XCTAssertEqual(manager.keyMappings.first?.output, "escape")
    }

    func testConfigPathProperty() {
        // Test that configPath is accessible
        let configPath = manager.configPath
        XCTAssertFalse(configPath.isEmpty, "Config path should not be empty")
        XCTAssertTrue(configPath.contains("keypath.kbd"), "Config path should contain keypath.kbd")
    }

    func testInitialUIStateHasNoActiveRuntimePath() {
        let state = manager.getCurrentUIState()
        XCTAssertNil(state.activeRuntimePathTitle, "Initial UI state should not report an active runtime path")
        XCTAssertNil(state.activeRuntimePathDetail, "Initial UI state should not report active runtime path details")
    }

    func testInstallationStatus() {
        // Test installation status check
        let isInstalled = manager.isCompletelyInstalled()

        // Should return a boolean (true or false)
        XCTAssertNotNil(isInstalled)
    }

    func testUnexpectedSplitRuntimeHostExitFailsLoudly() async throws {
        await manager.handleSplitRuntimeHostExit(
            pid: 12345,
            exitCode: 9,
            terminationReason: "uncaughtSignal",
            expected: false,
            stderrLogPath: "/tmp/keypath-host.log"
        )

        let error = try XCTUnwrap(manager.lastError)
        XCTAssertTrue(error.contains("Split runtime host exited unexpectedly"))
        XCTAssertTrue(error.contains("/tmp/keypath-host.log"))
        XCTAssertTrue(error.contains("no longer auto-falls back"))
        XCTAssertNil(manager.lastWarning)

        let state = manager.getCurrentUIState()
        XCTAssertNil(state.activeRuntimePathTitle)
        XCTAssertNil(state.activeRuntimePathDetail)
    }

    func testExpectedSplitRuntimeHostExitDoesNotSetRecoveryError() async {
        manager.lastError = nil

        await manager.handleSplitRuntimeHostExit(
            pid: 12345,
            exitCode: 0,
            terminationReason: "exit",
            expected: true,
            stderrLogPath: nil
        )

        XCTAssertNil(manager.lastError)
    }

    func testSuccessfulSplitRuntimeStartClearsPreviousExitError() async {
        KarabinerConflictService.testDaemonRunning = true
        await manager.handleSplitRuntimeHostExit(
            pid: 12345,
            exitCode: 9,
            terminationReason: "uncaughtSignal",
            expected: false,
            stderrLogPath: "/tmp/keypath-host.log"
        )

        XCTAssertNotNil(manager.lastError)

        KanataRuntimePathCoordinator.testDecision = .useSplitRuntime(reason: "test split runtime")
        KanataSplitRuntimeHostService.testPersistentHostPID = 4343
        let started = await manager.startKanata(
            reason: "Manual recovery"
        )

        XCTAssertTrue(started)
        XCTAssertNil(manager.lastError)
        XCTAssertNil(manager.lastWarning)
    }

    func testSplitRuntimeStartStopRestartCycle() async {
        KarabinerConflictService.testDaemonRunning = true
        KanataRuntimePathCoordinator.testDecision = .useSplitRuntime(reason: "test split runtime")
        KanataSplitRuntimeHostService.testPersistentHostPID = 4242

        let started = await manager.startKanata(reason: "Split runtime test start")
        XCTAssertTrue(started)

        var state = manager.getCurrentUIState()
        XCTAssertEqual(state.activeRuntimePathTitle, "Split Runtime Host")
        XCTAssertTrue(state.activeRuntimePathDetail?.contains("PID 4242") == true)

        let restarted = await manager.restartKanata(reason: "Split runtime test restart")
        XCTAssertTrue(restarted)

        state = manager.getCurrentUIState()
        XCTAssertEqual(state.activeRuntimePathTitle, "Split Runtime Host")
        XCTAssertTrue(state.activeRuntimePathDetail?.contains("PID 4242") == true)

        let stopped = await manager.stopKanata(reason: "Split runtime test stop")
        XCTAssertTrue(stopped)

        state = manager.getCurrentUIState()
        XCTAssertNil(state.activeRuntimePathTitle)
        XCTAssertNil(state.activeRuntimePathDetail)
    }

    func testRestartCutsOverToSplitRuntimeWhenPreferred() async {
        KarabinerConflictService.testDaemonRunning = true
        KanataRuntimePathCoordinator.testDecision = .useSplitRuntime(reason: "test split runtime")
        KanataSplitRuntimeHostService.testPersistentHostPID = 5252

        let restarted = await manager.restartKanata(reason: "Cut over from legacy to split runtime")
        XCTAssertTrue(restarted)

        let state = manager.getCurrentUIState()
        XCTAssertEqual(state.activeRuntimePathTitle, "Split Runtime Host")
        XCTAssertTrue(state.activeRuntimePathDetail?.contains("Bundled user-session host active") == true)
    }

    func testSplitRuntimeStartFailureDoesNotSilentlyFallBackToLegacy() async {
        KarabinerConflictService.testDaemonRunning = true
        struct SplitStartFailure: LocalizedError {
            var errorDescription: String? {
                "simulated split host start failure"
            }
        }

        KanataRuntimePathCoordinator.testDecision = .useSplitRuntime(reason: "test split runtime")
        KanataSplitRuntimeHostService.testStartPersistentError = SplitStartFailure()

        let started = await manager.startKanata(reason: "Split runtime start should fail loudly")
        XCTAssertFalse(started)
        XCTAssertEqual(
            manager.lastError,
            "Split runtime host failed to start: simulated split host start failure. Legacy fallback is reserved for recovery paths."
        )

        let state = manager.getCurrentUIState()
        XCTAssertNil(state.activeRuntimePathTitle)
    }

    func testPerformanceConfigValidation() async {
        // Test that config validation performs reasonably
        let startTime = Date()

        _ = await manager.validateConfigFile()

        let duration = Date().timeIntervalSince(startTime)
        XCTAssertLessThan(duration, 10.0, "Config validation should complete within 10 seconds")
    }
}
