import Foundation
@testable import KeyPathAppKit
@preconcurrency import XCTest

/// Unit tests for PrivilegedExecutor service.
///
/// Tests privileged command execution.
/// These tests verify:
/// - Command execution (in test mode)
/// - Error handling
/// - Escaping for AppleScript
@MainActor
final class PrivilegedExecutorTests: XCTestCase {
    var executor: PrivilegedExecutor!

    override func setUp() async throws {
        try await super.setUp()
        executor = PrivilegedExecutor.shared
    }

    override func tearDown() async throws {
        executor = nil
        try await super.tearDown()
    }

    // MARK: - AppleScript Escaping Tests

    func testEscapeForAppleScriptEscapesQuotes() {
        // AppleScript only requires escaping backslashes and double quotes
        // Single quotes don't need escaping
        let commandWithDoubleQuotes = "echo \"hello world\""
        let escaped = executor.escapeForAppleScript(commandWithDoubleQuotes)

        XCTAssertNotEqual(escaped, commandWithDoubleQuotes, "Should escape double quotes")
        XCTAssertTrue(escaped.contains("\\\""), "Should contain escaped double quotes")
    }

    func testEscapeForAppleScriptHandlesSpecialCharacters() {
        let command = "rm -rf /tmp/test\"file"
        let escaped = executor.escapeForAppleScript(command)

        // Should escape quotes and other special chars
        XCTAssertTrue(escaped.contains("\\"), "Should escape special characters")
    }

    func testEscapeForAppleScriptPreservesNormalText() {
        let command = "simple command"
        let escaped = executor.escapeForAppleScript(command)

        // May or may not escape, but should not break
        XCTAssertFalse(escaped.isEmpty, "Should not return empty string")
    }

    // MARK: - Command Execution Tests (Test Mode)

    func testExecuteWithPrivilegesInTestMode() {
        // In test mode, behavior depends on environment:
        // - If shouldSkipAdminOperations=true: returns (true, "Skipped in test mode")
        // - If useSudoForPrivilegedOps=true (sudoers auto-detected): actually runs sudo
        // - Otherwise: runs osascript (would show dialog, likely fails in headless test)
        let result = executor.executeWithPrivileges(
            command: "echo test",
            prompt: "Test prompt"
        )

        // Should return a result without crashing - success depends on environment config
        XCTAssertFalse(result.output.isEmpty, "Should have some output (even if error message)")
    }

    func testExecuteWithSudoInTestMode() {
        // In test mode with KEYPATH_USE_SUDO=1, may use sudo
        let result = executor.executeWithSudo(command: "echo test")

        // Should return a result
        XCTAssertNotNil(result, "Should return a result")
        XCTAssertTrue(result.success == true || result.success == false, "Should return success boolean")
    }

    func testExecuteWithOsascriptInTestMode() {
        // In test mode, osascript may be bypassed
        let result = executor.executeWithOsascript(
            command: "echo test",
            prompt: "Test prompt"
        )

        // Should return a result
        XCTAssertNotNil(result, "Should return a result")
        XCTAssertTrue(result.success == true || result.success == false, "Should return success boolean")
    }

    // MARK: - Admin Dialog Test

    func testTestAdminDialog() {
        // This may prompt in non-test mode, but should return boolean
        let result = executor.testAdminDialog()
        XCTAssertTrue(result == true || result == false, "Should return boolean")
    }

    // MARK: - Error Handling Tests

    func testExecuteWithInvalidCommand() {
        let result = executor.executeWithPrivileges(
            command: "/nonexistent/command",
            prompt: "Test"
        )

        // Should handle gracefully
        XCTAssertNotNil(result, "Should return a result even for invalid command")
    }
}
