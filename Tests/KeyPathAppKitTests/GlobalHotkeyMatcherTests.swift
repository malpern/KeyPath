@testable import KeyPathAppKit
import XCTest

final class GlobalHotkeyMatcherTests: XCTestCase {
    func testMatchesToggleHotkey() {
        let match = GlobalHotkeyMatcher.match(
            keyCode: 40,
            modifiers: [.option, .command]
        )

        XCTAssertEqual(match?.action, .toggleOverlay)
    }

    func testMatchesResetHotkey() {
        let match = GlobalHotkeyMatcher.match(
            keyCode: 37,
            modifiers: [.option, .command]
        )

        XCTAssertEqual(match?.action, .resetOverlay)
    }

    func testIgnoresMissingRequiredModifiers() {
        let match = GlobalHotkeyMatcher.match(
            keyCode: 40,
            modifiers: [.command]
        )

        XCTAssertNil(match)
    }

    func testIgnoresForbiddenModifiers() {
        let match = GlobalHotkeyMatcher.match(
            keyCode: 40,
            modifiers: [.option, .command, .shift]
        )

        XCTAssertNil(match)
    }

    func testAllowsExtraNonForbiddenModifiers() {
        let match = GlobalHotkeyMatcher.match(
            keyCode: 40,
            modifiers: [.option, .command, .capsLock]
        )

        XCTAssertEqual(match?.action, .toggleOverlay)
    }
}
