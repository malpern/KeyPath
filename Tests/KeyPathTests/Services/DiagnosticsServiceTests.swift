import XCTest

@testable import KeyPathAppKit
@testable import KeyPathDaemonLifecycle

@MainActor
final class DiagnosticsServiceTests: XCTestCase {
    var service: DiagnosticsService!
    var processManager: ProcessLifecycleManager!

    override func setUp() {
        super.setUp()
        processManager = ProcessLifecycleManager()
        service = DiagnosticsService(processLifecycleManager: processManager)
    }

    override func tearDown() {
        service = nil
        processManager = nil
        super.tearDown()
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
}
