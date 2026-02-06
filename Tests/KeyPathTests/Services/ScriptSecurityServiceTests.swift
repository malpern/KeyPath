import Foundation
@testable import KeyPathAppKit
import XCTest

@MainActor
final class ScriptSecurityServiceTests: XCTestCase {
    private var service: ScriptSecurityService!

    override func setUp() async throws {
        service = ScriptSecurityService.shared
        // Reset to default state
        service.isScriptExecutionEnabled = false
        service.bypassFirstRunDialog = false
    }

    override func tearDown() async throws {
        // Reset after each test
        service.isScriptExecutionEnabled = false
        service.bypassFirstRunDialog = false
    }

    // MARK: - Execution Check Tests

    func testCheckExecutionWhenDisabled() {
        service.isScriptExecutionEnabled = false

        let result = service.checkExecution(at: "~/some/script.sh")

        if case .disabled = result {
            // Expected
        } else {
            XCTFail("Expected .disabled result when script execution is disabled")
        }
    }

    func testCheckExecutionFileNotFound() {
        service.isScriptExecutionEnabled = true

        // Use a path that definitely doesn't exist
        let result = service.checkExecution(at: "/nonexistent/path/to/script.sh")

        if case let .fileNotFound(path) = result {
            XCTAssertEqual(path, "/nonexistent/path/to/script.sh")
        } else {
            XCTFail("Expected .fileNotFound result for nonexistent file")
        }
    }

    func testCheckExecutionNeedsConfirmationWhenNotBypassed() {
        service.isScriptExecutionEnabled = true
        service.bypassFirstRunDialog = false

        // Use /bin/bash which is an executable that always exists
        let result = service.checkExecution(at: "/bin/bash")

        if case let .needsConfirmation(path) = result {
            XCTAssertEqual(path, "/bin/bash")
        } else {
            XCTFail("Expected .needsConfirmation result when dialog not bypassed, got \(result)")
        }
    }

    func testCheckExecutionAllowedWhenBypassed() {
        service.isScriptExecutionEnabled = true
        service.bypassFirstRunDialog = true

        // Use /bin/bash which is an executable that always exists
        let result = service.checkExecution(at: "/bin/bash")

        if case .allowed = result {
            // Expected
        } else {
            XCTFail("Expected .allowed result when dialog is bypassed, got \(result)")
        }
    }

    func testTildeExpansionInPath() {
        service.isScriptExecutionEnabled = true
        service.bypassFirstRunDialog = true

        // This should expand ~ to home directory
        let result = service.checkExecution(at: "~/nonexistent_file_12345.sh")

        // Should fail with fileNotFound (not crash on tilde expansion)
        if case let .fileNotFound(path) = result {
            XCTAssertTrue(path.hasPrefix("/Users/") || path.hasPrefix("/var/"), "Path should be expanded: \(path)")
            XCTAssertFalse(path.hasPrefix("~"), "Tilde should be expanded")
        } else {
            XCTFail("Expected .fileNotFound with expanded path")
        }
    }

    // MARK: - Script Type Detection Tests

    func testIsAppleScript() {
        XCTAssertTrue(service.isAppleScript("/path/to/script.applescript"))
        XCTAssertTrue(service.isAppleScript("/path/to/script.scpt"))
        XCTAssertTrue(service.isAppleScript("/path/to/script.APPLESCRIPT"))
        XCTAssertTrue(service.isAppleScript("/path/to/script.SCPT"))

        XCTAssertFalse(service.isAppleScript("/path/to/script.sh"))
        XCTAssertFalse(service.isAppleScript("/path/to/script.bash"))
        XCTAssertFalse(service.isAppleScript("/path/to/script"))
    }

    func testIsShellScript() {
        XCTAssertTrue(service.isShellScript("/path/to/script.sh"))
        XCTAssertTrue(service.isShellScript("/path/to/script.bash"))
        XCTAssertTrue(service.isShellScript("/path/to/script.zsh"))
        XCTAssertTrue(service.isShellScript("/path/to/script.SH"))

        XCTAssertFalse(service.isShellScript("/path/to/script.applescript"))
        XCTAssertFalse(service.isShellScript("/path/to/script.py"))
        XCTAssertFalse(service.isShellScript("/path/to/script"))
    }

    // MARK: - Settings Persistence Tests

    func testSettingsPersistence() {
        // This tests that settings are saved to UserDefaults
        service.isScriptExecutionEnabled = true
        service.bypassFirstRunDialog = true

        // Values should be stored
        XCTAssertTrue(service.isScriptExecutionEnabled)
        XCTAssertTrue(service.bypassFirstRunDialog)

        // Reset
        service.isScriptExecutionEnabled = false
        service.bypassFirstRunDialog = false

        XCTAssertFalse(service.isScriptExecutionEnabled)
        XCTAssertFalse(service.bypassFirstRunDialog)
    }

    // MARK: - Execution Logging Tests

    func testLogExecutionSuccess() throws {
        // Clear previous logs
        service.resetAllSettings()

        service.logExecution(path: "/test/script.sh", success: true, error: nil)

        let log = service.executionLog
        XCTAssertEqual(log.count, 1)

        let entry = try XCTUnwrap(log.first)
        XCTAssertEqual(entry["path"] as? String, "/test/script.sh")
        XCTAssertEqual(entry["success"] as? Bool, true)
        XCTAssertEqual(entry["error"] as? String, "")
    }

    func testLogExecutionFailure() throws {
        // Clear previous logs
        service.resetAllSettings()

        service.logExecution(path: "/test/script.sh", success: false, error: "Permission denied")

        let log = service.executionLog
        XCTAssertEqual(log.count, 1)

        let entry = try XCTUnwrap(log.first)
        XCTAssertEqual(entry["path"] as? String, "/test/script.sh")
        XCTAssertEqual(entry["success"] as? Bool, false)
        XCTAssertEqual(entry["error"] as? String, "Permission denied")
    }

    func testLogLimitedTo100Entries() throws {
        // Clear previous logs
        service.resetAllSettings()

        // Add 110 entries
        for i in 0 ..< 110 {
            service.logExecution(path: "/test/script\(i).sh", success: true, error: nil)
        }

        let log = service.executionLog
        XCTAssertEqual(log.count, 100, "Log should be limited to 100 entries")

        // First entry should be script10 (oldest kept)
        let firstEntry = try XCTUnwrap(log.first)
        XCTAssertEqual(firstEntry["path"] as? String, "/test/script10.sh")

        // Last entry should be script109 (newest)
        let lastEntry = try XCTUnwrap(log.last)
        XCTAssertEqual(lastEntry["path"] as? String, "/test/script109.sh")
    }

    // MARK: - Reset Tests

    func testResetAllSettings() {
        service.isScriptExecutionEnabled = true
        service.bypassFirstRunDialog = true
        service.logExecution(path: "/test.sh", success: true, error: nil)

        service.resetAllSettings()

        XCTAssertFalse(service.isScriptExecutionEnabled)
        XCTAssertFalse(service.bypassFirstRunDialog)
        XCTAssertTrue(service.executionLog.isEmpty)
    }
}
