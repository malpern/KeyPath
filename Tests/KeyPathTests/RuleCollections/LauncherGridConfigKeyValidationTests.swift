import XCTest

@testable import KeyPathAppKit

final class LauncherGridConfigKeyValidationTests: XCTestCase {
    func testNormalizeKeyConvertsPunctuationAliases() {
        XCTAssertEqual(LauncherGridConfig.normalizeKey(";"), "semicolon")
        XCTAssertEqual(LauncherGridConfig.normalizeKey("["), "leftbrace")
    }

    func testIsValidKeyAcceptsCanonicalPunctuation() {
        XCTAssertTrue(LauncherGridConfig.isValidKey("semicolon"))
        XCTAssertTrue(LauncherGridConfig.isValidKey(LauncherGridConfig.normalizeKey(";")))
    }

    func testIsValidKeyRejectsUnknown() {
        XCTAssertFalse(LauncherGridConfig.isValidKey("ö"))
    }

    func testSuggestionKeyOrderIncludesPunctuation() {
        XCTAssertTrue(LauncherGridConfig.suggestionKeyOrder.contains("semicolon"))
    }
}
