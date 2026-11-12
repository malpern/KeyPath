@testable import KeyPathCore
import XCTest

/// The one privileged command left is installing the keypath-cli link, and its
/// paths reach AppleScript through `escapeForAppleScript`.
final class PrivilegedCommandRunnerTests: XCTestCase {
    func testEscapingKeepsQuotesAndBackslashesInsideTheAppleScriptString() {
        XCTAssertEqual(
            PrivilegedCommandRunner.escapeForAppleScript(#"ln -sfn '/Apps/Key "Path"\x' /usr/local/bin/keypath"#),
            #"ln -sfn '/Apps/Key \"Path\"\\x' /usr/local/bin/keypath"#
        )
    }

    func testTestsNeverReachTheAdminDialog() {
        let result = PrivilegedCommandRunner.execute(command: "false", prompt: "unused")
        XCTAssertTrue(result.success)
        XCTAssertEqual(result.output, "Skipped in test mode")
    }
}
