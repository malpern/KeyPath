@testable import KeyPathAppKit
@testable import KeyPathCore
@preconcurrency import XCTest

@MainActor
final class DiagnosticsServiceTests: XCTestCase {
    var service: DiagnosticsService!
    var processManager: KanataProcessDetector!

    @MainActor
    override func setUp() async throws {
        try await super.setUp()
        processManager = KanataProcessDetector()
        service = DiagnosticsService(processDetector: processManager)
    }

    @MainActor
    override func tearDown() async throws {
        service = nil
        processManager = nil
        try await super.tearDown()
    }

    // MARK: - Process Conflict Tests

    func testCheckProcessConflictsReturnsNonNilResult() async {
        // KanataProcessDetector skips process discovery under tests,
        // we test that the method returns a valid result
        let diagnostics = await service.checkProcessConflicts()

        // Result should be an array (possibly empty if no processes are running)
        XCTAssertNotNil(diagnostics)
    }

    func testKarabinerGrabberDetectionUsesInjectedSystemStateProvider() async {
        let runner = SubprocessRunnerFake()
        await runner.configurePgrepResult { pattern in
            pattern == "karabiner_grabber" ? [1234] : []
        }

        let provider = SystemStateProvider(probes: runner.systemProbeClient())
        let service = DiagnosticsService(
            processDetector: processManager,
            systemStateProvider: provider
        )

        let isRunning = await service.isKarabinerElementsRunning()
        let commands = await runner.executedCommands

        XCTAssertTrue(isRunning)
        XCTAssertTrue(
            commands.contains { $0.executable == "/usr/bin/pgrep" && $0.args == ["-f", "karabiner_grabber"] },
            "DiagnosticsService should use the injected provider for Karabiner grabber discovery"
        )
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
