import Foundation
@testable import KeyPathAppKit
import XCTest

final class KanataBinaryInstallerParsingTests: XCTestCase {
    func testParseTeamIdentifierFindsValueInCodesignOutput() {
        let output = """
        Executable=/Library/KeyPath/bin/kanata
        Identifier=com.example.kanata
        TeamIdentifier=ABCDE12345
        """

        XCTAssertEqual(KanataBinaryInstaller.parseTeamIdentifier(fromCodesignOutput: output), "ABCDE12345")
    }

    func testParseTeamIdentifierReturnsNilWhenMissing() {
        XCTAssertNil(KanataBinaryInstaller.parseTeamIdentifier(fromCodesignOutput: "no team here"))
    }

    func testShellSingleQuotedEscapesApostrophesForSingleQuotes() {
        XCTAssertEqual(KanataBinaryInstaller.shellSingleQuoted("abc'def"), "abc'\"'\"'def")
        XCTAssertEqual(KanataBinaryInstaller.shellSingleQuoted("plain"), "plain")
        XCTAssertEqual(KanataBinaryInstaller.shellSingleQuoted(""), "")
    }
}

