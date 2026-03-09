@testable import KeyPathAppKit
@testable import KeyPathCore
@testable import KeyPathDaemonLifecycle
@preconcurrency import XCTest

@MainActor
final class DiagnosticsServiceTests: XCTestCase {
    var service: DiagnosticsService!
    var processManager: ProcessLifecycleManager!

    @MainActor
    override func setUp() async throws {
        try await super.setUp()
        processManager = ProcessLifecycleManager()
        service = DiagnosticsService(processLifecycleManager: processManager)
    }

    @MainActor
    override func tearDown() async throws {
        service = nil
        processManager = nil
        try await super.tearDown()
    }

    // MARK: - Failure Diagnosis Tests

    func testDiagnosePermissionError() {
        let diagnostics = service.diagnoseKanataFailure(
            exitCode: 1,
            output: "IOHIDDeviceOpen error: exclusive access denied"
        )

        XCTAssertEqual(diagnostics.count, 1)
        XCTAssertEqual(diagnostics[0].title, "Permission Denied")
        XCTAssertEqual(diagnostics[0].severity, .error)
        XCTAssertEqual(diagnostics[0].category, .permissions)
        XCTAssertFalse(diagnostics[0].canAutoFix)
    }

    func testDiagnoseConfigurationError() {
        let diagnostics = service.diagnoseKanataFailure(
            exitCode: 1,
            output: "Error in configuration: invalid syntax"
        )

        XCTAssertEqual(diagnostics.count, 1)
        XCTAssertEqual(diagnostics[0].title, "Invalid Configuration")
        XCTAssertEqual(diagnostics[0].severity, .error)
        XCTAssertEqual(diagnostics[0].category, .configuration)
        XCTAssertTrue(diagnostics[0].canAutoFix)
    }

    func testDiagnoseDeviceConflict() {
        let diagnostics = service.diagnoseKanataFailure(
            exitCode: 1,
            output: "device already open by another process"
        )

        XCTAssertEqual(diagnostics.count, 1)
        XCTAssertEqual(diagnostics[0].title, "Device Conflict")
        XCTAssertEqual(diagnostics[0].severity, .error)
        XCTAssertEqual(diagnostics[0].category, .conflict)
        XCTAssertFalse(diagnostics[0].canAutoFix)
    }

    func testDiagnoseSIGKILL() {
        let diagnostics = service.diagnoseKanataFailure(
            exitCode: -9,
            output: "Process killed"
        )

        XCTAssertEqual(diagnostics.count, 1)
        XCTAssertEqual(diagnostics[0].title, "Process Terminated")
        XCTAssertEqual(diagnostics[0].severity, .warning)
        XCTAssertEqual(diagnostics[0].category, .process)
        XCTAssertTrue(diagnostics[0].canAutoFix)
    }

    func testDiagnoseSIGTERM() {
        let diagnostics = service.diagnoseKanataFailure(
            exitCode: -15,
            output: "Process terminated gracefully"
        )

        XCTAssertEqual(diagnostics.count, 1)
        XCTAssertEqual(diagnostics[0].title, "Process Stopped")
        XCTAssertEqual(diagnostics[0].severity, .info)
        XCTAssertEqual(diagnostics[0].category, .process)
        XCTAssertFalse(diagnostics[0].canAutoFix)
    }

    func testDiagnoseVirtualHIDConnectionFailure() {
        let diagnostics = service.diagnoseKanataFailure(
            exitCode: 6,
            output: "connect_failed asio.system:61 Connection refused"
        )

        XCTAssertEqual(diagnostics.count, 1)
        XCTAssertEqual(diagnostics[0].title, "VirtualHID Connection Failed")
        XCTAssertEqual(diagnostics[0].severity, .error)
        XCTAssertEqual(diagnostics[0].category, .conflict)
        XCTAssertTrue(diagnostics[0].canAutoFix)
    }

    func testDiagnoseGenericExitCode6() {
        let diagnostics = service.diagnoseKanataFailure(
            exitCode: 6,
            output: "Some other error"
        )

        XCTAssertEqual(diagnostics.count, 1)
        XCTAssertEqual(diagnostics[0].title, "Access Denied")
        XCTAssertEqual(diagnostics[0].severity, .error)
        XCTAssertEqual(diagnostics[0].category, .permissions)
        XCTAssertFalse(diagnostics[0].canAutoFix)
    }

    func testDiagnosePermissionRelatedUnknownExitCode() {
        let diagnostics = service.diagnoseKanataFailure(
            exitCode: 42,
            output: "permission denied: cannot access resource"
        )

        XCTAssertEqual(diagnostics.count, 1)
        XCTAssertEqual(diagnostics[0].title, "Possible Permission Issue")
        XCTAssertEqual(diagnostics[0].severity, .error)
        XCTAssertEqual(diagnostics[0].category, .permissions)
        XCTAssertFalse(diagnostics[0].canAutoFix)
    }

    func testDiagnoseUnknownExitCode() {
        let diagnostics = service.diagnoseKanataFailure(
            exitCode: 99,
            output: "Unexpected error occurred"
        )

        XCTAssertEqual(diagnostics.count, 1)
        XCTAssertEqual(diagnostics[0].title, "Unexpected Exit")
        XCTAssertEqual(diagnostics[0].severity, .error)
        XCTAssertEqual(diagnostics[0].category, .process)
        XCTAssertFalse(diagnostics[0].canAutoFix)
    }

    // MARK: - Process Conflict Tests

    func testCheckProcessConflictsReturnsNonNilResult() async {
        // Since ProcessLifecycleManager is final and can't be mocked,
        // we test that the method returns a valid result
        let diagnostics = await service.checkProcessConflicts()

        // Result should be an array (possibly empty if no processes are running)
        XCTAssertNotNil(diagnostics)
    }

    // MARK: - Log Analysis Tests

    func testAnalyzeLogFileNotFound() async {
        let diagnostics = await service.analyzeLogFile(path: "/tmp/nonexistent-log-file.log")

        XCTAssertEqual(diagnostics.count, 1)
        XCTAssertEqual(diagnostics[0].title, "Log File Not Found")
        XCTAssertEqual(diagnostics[0].severity, .warning)
        XCTAssertEqual(diagnostics[0].category, .system)
    }

    func testAnalyzeLogFileWithPermissionError() async {
        // Create a temporary log file with permission error
        let tempPath = NSTemporaryDirectory() + "test-kanata-\(UUID().uuidString).log"
        let logContent = """
        [INFO] Kanata starting...
        [ERROR] IOHIDDeviceOpen error: exclusive access denied
        [INFO] Shutting down
        """
        try? logContent.write(toFile: tempPath, atomically: true, encoding: .utf8)
        defer { try? FileManager.default.removeItem(atPath: tempPath) }

        let diagnostics = await service.analyzeLogFile(path: tempPath)

        XCTAssertGreaterThanOrEqual(diagnostics.count, 1)
        let permissionError = diagnostics.first { $0.title == "Permission Error in Logs" }
        XCTAssertNotNil(permissionError)
        XCTAssertEqual(permissionError?.severity, .error)
        XCTAssertEqual(permissionError?.category, .permissions)
    }

    func testAnalyzeLogFileWithConnectionError() async {
        // Create a temporary log file with connection error
        let tempPath = NSTemporaryDirectory() + "test-kanata-\(UUID().uuidString).log"
        let logContent = """
        [INFO] Kanata starting...
        [ERROR] connect_failed asio.system:61 Connection refused
        [INFO] Shutting down
        """
        try? logContent.write(toFile: tempPath, atomically: true, encoding: .utf8)
        defer { try? FileManager.default.removeItem(atPath: tempPath) }

        let diagnostics = await service.analyzeLogFile(path: tempPath)

        XCTAssertGreaterThanOrEqual(diagnostics.count, 1)
        let connectionError = diagnostics.first { $0.title == "VirtualHID Connection Error in Logs" }
        XCTAssertNotNil(connectionError)
        XCTAssertEqual(connectionError?.severity, .error)
        XCTAssertEqual(connectionError?.category, .conflict)
        XCTAssertTrue(connectionError?.canAutoFix ?? false)
    }

    func testAnalyzeLogFileWithGenericError() async {
        // Create a temporary log file with generic error
        let tempPath = NSTemporaryDirectory() + "test-kanata-\(UUID().uuidString).log"
        let logContent = """
        [INFO] Kanata starting...
        [ERROR] Something went wrong
        [INFO] Shutting down
        """
        try? logContent.write(toFile: tempPath, atomically: true, encoding: .utf8)
        defer { try? FileManager.default.removeItem(atPath: tempPath) }

        let diagnostics = await service.analyzeLogFile(path: tempPath)

        XCTAssertGreaterThanOrEqual(diagnostics.count, 1)
        let genericError = diagnostics.first { $0.title == "Error Found in Logs" }
        XCTAssertNotNil(genericError)
        XCTAssertEqual(genericError?.severity, .error)
        XCTAssertEqual(genericError?.category, .process)
    }

    func testAnalyzeLogFileWithCleanLogs() async {
        // Create a temporary log file with no errors
        let tempPath = NSTemporaryDirectory() + "test-kanata-\(UUID().uuidString).log"
        let logContent = """
        [INFO] Kanata starting...
        [INFO] Configuration loaded successfully
        [INFO] Running normally
        """
        try? logContent.write(toFile: tempPath, atomically: true, encoding: .utf8)
        defer { try? FileManager.default.removeItem(atPath: tempPath) }

        let diagnostics = await service.analyzeLogFile(path: tempPath)

        XCTAssertEqual(diagnostics.count, 0)
    }

    // MARK: - Diagnostic Type Tests

    func testDiagnosticSeverityEmojis() {
        XCTAssertEqual(DiagnosticSeverity.info.emoji, "ℹ️")
        XCTAssertEqual(DiagnosticSeverity.warning.emoji, "⚠️")
        XCTAssertEqual(DiagnosticSeverity.error.emoji, "❌")
        XCTAssertEqual(DiagnosticSeverity.critical.emoji, "🚨")
    }

    func testDiagnosticCategoryRawValues() {
        XCTAssertEqual(DiagnosticCategory.configuration.rawValue, "Configuration")
        XCTAssertEqual(DiagnosticCategory.permissions.rawValue, "Permissions")
        XCTAssertEqual(DiagnosticCategory.process.rawValue, "Process")
        XCTAssertEqual(DiagnosticCategory.system.rawValue, "System")
        XCTAssertEqual(DiagnosticCategory.conflict.rawValue, "Conflict")
    }

    func testRuntimePathDiagnosticForSplitRuntimeReady() {
        let diagnostic = DiagnosticsService.makeRuntimePathDiagnostic(
            for: .useSplitRuntime(reason: "bundled host is ready")
        )

        XCTAssertEqual(diagnostic.title, "Runtime Path: Split Runtime Ready")
        XCTAssertEqual(diagnostic.severity, .info)
        XCTAssertEqual(diagnostic.category, .system)
        XCTAssertEqual(diagnostic.technicalDetails, "bundled host is ready")
        XCTAssertFalse(diagnostic.canAutoFix)
    }

    func testRuntimePathDiagnosticForLegacyFallback() {
        let diagnostic = DiagnosticsService.makeRuntimePathDiagnostic(
            for: .useLegacySystemBinary(reason: "legacy is still required")
        )

        XCTAssertEqual(diagnostic.title, "Runtime Path: Legacy Fallback Active")
        XCTAssertEqual(diagnostic.severity, .warning)
        XCTAssertEqual(diagnostic.category, .system)
        XCTAssertEqual(diagnostic.technicalDetails, "legacy is still required")
        XCTAssertFalse(diagnostic.canAutoFix)
    }

    func testRuntimePathDiagnosticForBlockedPath() {
        let diagnostic = DiagnosticsService.makeRuntimePathDiagnostic(
            for: .blocked(reason: "nothing is viable")
        )

        XCTAssertEqual(diagnostic.title, "Runtime Path: Split Runtime Blocked")
        XCTAssertEqual(diagnostic.severity, .error)
        XCTAssertEqual(diagnostic.category, .system)
        XCTAssertEqual(diagnostic.technicalDetails, "nothing is viable")
        XCTAssertFalse(diagnostic.canAutoFix)
    }

    func testOutputBridgeSmokeDiagnosticForSuccess() {
        let report = KanataOutputBridgeSmokeReport(
            session: KanataOutputBridgeSession(
                sessionID: "session-42",
                socketPath: "/tmp/session-42.sock",
                socketDirectory: "/tmp",
                hostPID: 42,
                hostUID: 501,
                hostGID: 20
            ),
            handshake: .ready(version: 1),
            ping: .pong,
            syncedModifiers: KanataOutputBridgeModifierState(leftShift: true),
            syncModifiers: .acknowledged(sequence: nil),
            emittedKeyEvent: KanataOutputBridgeKeyEvent(
                usagePage: 0x07,
                usage: 0x04,
                action: .keyDown,
                sequence: 5
            ),
            emitKey: .acknowledged(sequence: 5),
            reset: nil
        )

        let diagnostic = DiagnosticsService.makeOutputBridgeSmokeDiagnostic(for: report)

        XCTAssertEqual(diagnostic.title, "Experimental Output Bridge Smoke Passed")
        XCTAssertEqual(diagnostic.severity, .info)
        XCTAssertEqual(diagnostic.category, .system)
        XCTAssertTrue(diagnostic.technicalDetails.contains("session=session-42"))
        XCTAssertTrue(diagnostic.technicalDetails.contains("handshake=ready(version: 1)"))
        XCTAssertTrue(diagnostic.technicalDetails.contains("sync_modifiers_response=Optional"))
        XCTAssertTrue(diagnostic.technicalDetails.contains("emit_response=Optional"))
        XCTAssertFalse(diagnostic.canAutoFix)
    }

    func testOutputBridgeSmokeDiagnosticForFailure() {
        let diagnostic = DiagnosticsService.makeOutputBridgeSmokeFailureDiagnostic(
            error: HelperManagerError.operationFailed("timed out")
        )

        XCTAssertEqual(diagnostic.title, "Experimental Output Bridge Smoke Failed")
        XCTAssertEqual(diagnostic.severity, .warning)
        XCTAssertEqual(diagnostic.category, .system)
        XCTAssertEqual(
            diagnostic.technicalDetails,
            HelperManagerError.operationFailed("timed out").localizedDescription
        )
        XCTAssertFalse(diagnostic.canAutoFix)
    }

    func testHostPassthruDiagnosticForSuccess() {
        let report = DiagnosticsService.HostPassthruDiagnosticReport(
            exitCode: 0,
            stderr: "[kanata-launcher] Experimental passthru-only host mode completed",
            launcherPath: "/Applications/KeyPath.app/Contents/Library/KeyPath/kanata-launcher",
            sessionID: "session-42",
            socketPath: "/Library/KeyPath/run/kpko/k-session42.sock"
        )

        let diagnostic = DiagnosticsService.makeHostPassthruDiagnostic(for: report)

        XCTAssertEqual(diagnostic.title, "Experimental Host Passthru Diagnostic Passed")
        XCTAssertEqual(diagnostic.severity, .info)
        XCTAssertEqual(diagnostic.category, .system)
        XCTAssertTrue(diagnostic.technicalDetails.contains("exit_code=0"))
        XCTAssertTrue(diagnostic.technicalDetails.contains(report.launcherPath))
        XCTAssertTrue(diagnostic.technicalDetails.contains("session=session-42"))
        XCTAssertTrue(diagnostic.technicalDetails.contains("socket=/Library/KeyPath/run/kpko/k-session42.sock"))
        XCTAssertFalse(diagnostic.canAutoFix)
    }

    func testHostPassthruDiagnosticForFailure() {
        struct DummyError: LocalizedError {
            var errorDescription: String? { "launcher failed to start" }
        }

        let diagnostic = DiagnosticsService.makeHostPassthruFailureDiagnostic(error: DummyError())

        XCTAssertEqual(diagnostic.title, "Experimental Host Passthru Diagnostic Failed")
        XCTAssertEqual(diagnostic.severity, .warning)
        XCTAssertEqual(diagnostic.category, .system)
        XCTAssertEqual(diagnostic.technicalDetails, "launcher failed to start")
        XCTAssertFalse(diagnostic.canAutoFix)
    }

    func testHostPassthruDiagnosticTreatsForwardingFailureAsFailure() {
        let report = DiagnosticsService.HostPassthruDiagnosticReport(
            exitCode: 0,
            stderr: """
            [kanata-launcher] Experimental passthru runtime drained output event: value=1 page=7 code=4
            [kanata-launcher] Experimental passthru forwarding failed: Output bridge socket at /Library/KeyPath/run/kpko/k-stale.sock is stale or not listening.
            [kanata-launcher] Experimental passthru-only host mode completed
            """,
            launcherPath: "/Applications/KeyPath.app/Contents/Library/KeyPath/kanata-launcher",
            sessionID: "session-stale",
            socketPath: "/Library/KeyPath/run/kpko/k-stale.sock"
        )

        let diagnostic = DiagnosticsService.makeHostPassthruDiagnostic(for: report)

        XCTAssertEqual(diagnostic.title, "Experimental Host Passthru Diagnostic Failed")
        XCTAssertEqual(diagnostic.severity, .warning)
        XCTAssertTrue(diagnostic.technicalDetails.contains("session=session-stale"))
        XCTAssertTrue(diagnostic.technicalDetails.contains("stale or not listening"))
    }
}
