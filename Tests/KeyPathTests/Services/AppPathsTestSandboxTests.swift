@testable import KeyPathAppKit
import KeyPathCore
import XCTest

/// Guards against unit tests writing to (or deleting from) real user
/// directories. Every service that persists diagnostics or support data must
/// resolve its paths through `AppPaths`, which redirects into a per-process
/// temp sandbox while tests run. A regression here means tests can pollute or
/// destroy genuine crash logs, incident snapshots, and telemetry.
@MainActor
final class AppPathsTestSandboxTests: XCTestCase {
    private var realLogsDir: String {
        FileManager.default.homeDirectoryForCurrentUser
            .appendingPathComponent("Library/Logs/KeyPath", isDirectory: true).path
    }

    private var realSupportDir: String {
        FileManager.default.homeDirectoryForCurrentUser
            .appendingPathComponent("Library/Application Support/KeyPath", isDirectory: true).path
    }

    private func assertSandboxed(_ url: URL, file: StaticString = #filePath, line: UInt = #line) {
        XCTAssertTrue(
            url.path.hasPrefix(AppPaths.testSandboxDirectory.path),
            "\(url.path) must live under the test sandbox \(AppPaths.testSandboxDirectory.path)",
            file: file, line: line
        )
        XCTAssertFalse(
            url.path.hasPrefix(realLogsDir) || url.path.hasPrefix(realSupportDir),
            "\(url.path) must not point at a real user directory during tests",
            file: file, line: line
        )
    }

    func testTestEnvironmentIsDetected() {
        // The redirect only engages when test detection works; if this fails,
        // every other assertion in this file is vacuous.
        XCTAssertTrue(TestEnvironment.isRunningTests)
    }

    func testSandboxDirectoryLivesUnderTemporaryDirectory() {
        XCTAssertTrue(
            AppPaths.testSandboxDirectory.path
                .hasPrefix(FileManager.default.temporaryDirectory.path)
        )
    }

    func testLogsDirectoryIsSandboxed() {
        assertSandboxed(AppPaths.logsDirectory)
    }

    func testApplicationSupportDirectoryIsSandboxed() {
        assertSandboxed(AppPaths.applicationSupportDirectory)
    }

    func testCrashLogFileIsSandboxed() {
        assertSandboxed(AppPaths.crashLogFile)
        XCTAssertEqual(AppPaths.crashLogFile.lastPathComponent, "crashes.log")
    }

    func testKindaVimTelemetryDefaultFileIsSandboxed() {
        let url = KindaVimTelemetryStore.defaultFileURL
        assertSandboxed(url)
        XCTAssertEqual(url.lastPathComponent, "kindavim-telemetry.json")
    }

    func testStuckKeyDiagnosticsDirectoryIsSandboxed() {
        let dir = StuckKeyRecoveryService.diagnosticsDirectory
        assertSandboxed(dir)
        XCTAssertEqual(dir.lastPathComponent, "stuck-key-incidents")
    }
}
