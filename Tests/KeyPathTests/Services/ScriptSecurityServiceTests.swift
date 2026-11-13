import Foundation
@testable import KeyPathAppKit
import XCTest

@MainActor
final class ScriptSecurityServiceTests: XCTestCase {
    private var service: ScriptSecurityService!
    private var testDefaults: UserDefaults!
    private var suiteName: String!

    override func setUp() async throws {
        suiteName = "KeyPath.ScriptSecurityServiceTests.\(UUID().uuidString)"
        testDefaults = try XCTUnwrap(UserDefaults(suiteName: suiteName))
        testDefaults.removePersistentDomain(forName: suiteName)
        service = ScriptSecurityService(defaults: testDefaults, approvals: InMemoryScriptApprovalStore())
        service.resetAllSettings()
    }

    override func tearDown() async throws {
        // Reset after each test
        service?.isScriptExecutionEnabled = false
        if let suiteName {
            testDefaults?.removePersistentDomain(forName: suiteName)
        }
        service = nil
        testDefaults = nil
        suiteName = nil
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

    func testCheckExecutionNeedsConfirmationUntilApproved() {
        service.isScriptExecutionEnabled = true

        // /bin/bash is an executable that always exists
        guard case let .needsConfirmation(path, digest) = service.checkExecution(at: "/bin/bash") else {
            return XCTFail("An unapproved script must ask first")
        }
        XCTAssertEqual(path, "/bin/bash")

        service.alwaysAllow(path: path, digest: digest)
        XCTAssertEqual(service.approvedScriptCount, 1)
        guard case let .allowed(allowedDigest) = service.checkExecution(at: "/bin/bash") else {
            return XCTFail("An approved script with unchanged contents runs without asking")
        }
        XCTAssertEqual(allowedDigest, digest)
    }

    func testEditedScriptAsksAgain() throws {
        service.isScriptExecutionEnabled = true
        let script = FileManager.default.temporaryDirectory.appendingPathComponent("approval-\(UUID().uuidString).sh")
        try Data("#!/bin/sh\nexit 0\n".utf8).write(to: script)
        defer { try? FileManager.default.removeItem(at: script) }

        guard case let .needsConfirmation(path, digest) = service.checkExecution(at: script.path) else {
            return XCTFail("Expected a prompt")
        }
        service.alwaysAllow(path: path, digest: digest)
        try Data("#!/bin/sh\necho changed\n".utf8).write(to: script)

        guard case .needsConfirmation = service.checkExecution(at: script.path) else {
            return XCTFail("A changed script must ask again")
        }
    }

    func testRetiredBypassSettingIsRemoved() {
        testDefaults.set(true, forKey: "KeyPath.Security.BypassFirstRunDialog")
        _ = ScriptSecurityService(defaults: testDefaults, approvals: InMemoryScriptApprovalStore())
        XCTAssertNil(testDefaults.object(forKey: "KeyPath.Security.BypassFirstRunDialog"))
    }

    func testTildeExpansionInPath() {
        service.isScriptExecutionEnabled = true

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
        service.isScriptExecutionEnabled = true
        XCTAssertTrue(testDefaults.bool(forKey: "KeyPath.Security.ScriptExecutionEnabled"))
        service.isScriptExecutionEnabled = false
        XCTAssertFalse(testDefaults.bool(forKey: "KeyPath.Security.ScriptExecutionEnabled"))
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
        service.alwaysAllow(path: "/test.sh", digest: "abc")
        service.logExecution(path: "/test.sh", success: true, error: nil)

        service.resetAllSettings()

        XCTAssertFalse(service.isScriptExecutionEnabled)
        XCTAssertEqual(service.approvedScriptCount, 0)
        XCTAssertTrue(service.executionLog.isEmpty)
    }
}
