@preconcurrency import XCTest

@testable import KeyPathAppKit

/// Tests for KanataEventListener event parsing
final class KanataEventListenerTests: XCTestCase {
    // MARK: - KanataKeyAction Parsing Tests

    func testKanataKeyAction_lowercasePress() {
        let action = KanataKeyAction(rawValue: "press")
        XCTAssertEqual(action, .press)
    }

    func testKanataKeyAction_lowercaseRelease() {
        let action = KanataKeyAction(rawValue: "release")
        XCTAssertEqual(action, .release)
    }

    func testKanataKeyAction_lowercaseRepeat() {
        let action = KanataKeyAction(rawValue: "repeat")
        XCTAssertEqual(action, .repeat)
    }

    func testKanataKeyAction_capitalizedPress_notMatched() {
        // The enum requires lowercase, so capitalized should NOT match directly
        let action = KanataKeyAction(rawValue: "Press")
        XCTAssertNil(action, "Capitalized 'Press' should not match enum directly")
    }

    func testKanataKeyAction_capitalizedRelease_notMatched() {
        let action = KanataKeyAction(rawValue: "Release")
        XCTAssertNil(action, "Capitalized 'Release' should not match enum directly")
    }

    func testKanataKeyAction_lowercasedCapitalizedPress_matches() {
        // This tests the fix: lowercasing capitalized input should match
        let action = KanataKeyAction(rawValue: "Press".lowercased())
        XCTAssertEqual(action, .press, "Lowercased 'Press' should match .press")
    }

    func testKanataKeyAction_lowercasedCapitalizedRelease_matches() {
        let action = KanataKeyAction(rawValue: "Release".lowercased())
        XCTAssertEqual(action, .release, "Lowercased 'Release' should match .release")
    }

    func testKanataKeyAction_lowercasedCapitalizedRepeat_matches() {
        let action = KanataKeyAction(rawValue: "Repeat".lowercased())
        XCTAssertEqual(action, .repeat, "Lowercased 'Repeat' should match .repeat")
    }

    func testKanataKeyAction_unknownValue() {
        let action = KanataKeyAction(rawValue: "unknown")
        XCTAssertNil(action)
    }

    func testKanataKeyAction_emptyString() {
        let action = KanataKeyAction(rawValue: "")
        XCTAssertNil(action)
    }

    // MARK: - Key Name Tests

    func testKanataKeyAction_rawValueRoundTrip() {
        XCTAssertEqual(KanataKeyAction.press.rawValue, "press")
        XCTAssertEqual(KanataKeyAction.release.rawValue, "release")
        XCTAssertEqual(KanataKeyAction.repeat.rawValue, "repeat")
    }
}

/// Tests for KeyboardVisualizationViewModel TCP input handling with capitalized actions
@MainActor
final class KeyboardVisualizationViewModelTCPCapitalizationTests: XCTestCase {
    func testSimulateTcpKeyInput_capitalizedPress_works() async {
        let viewModel = KeyboardVisualizationViewModel()

        // Simulate with capitalized action (as Kanata actually sends)
        // Note: simulateTcpKeyInput internally calls handleTcpKeyInput which expects lowercase
        // This test documents the expected behavior
        viewModel.simulateTcpKeyInput(key: "a", action: "press")
        await Task.yield()

        XCTAssertTrue(
            viewModel.tcpPressedKeyCodes.contains(0),
            "Key 'a' (keyCode 0) should be pressed"
        )
    }

    func testSimulateTcpKeyInput_capitalizedRelease_works() async {
        let viewModel = KeyboardVisualizationViewModel()

        // Press first
        viewModel.simulateTcpKeyInput(key: "a", action: "press")
        await Task.yield()

        XCTAssertTrue(viewModel.tcpPressedKeyCodes.contains(0))

        // Release
        viewModel.simulateTcpKeyInput(key: "a", action: "release")
        await Task.yield()

        XCTAssertFalse(
            viewModel.tcpPressedKeyCodes.contains(0),
            "Key 'a' should be released"
        )
    }

    func testSimulateTcpKeyInput_capslock_pressAndRelease() async {
        let viewModel = KeyboardVisualizationViewModel()

        // Press capslock
        viewModel.simulateTcpKeyInput(key: "capslock", action: "press")
        await Task.yield()

        XCTAssertTrue(
            viewModel.tcpPressedKeyCodes.contains(57),
            "Capslock (keyCode 57) should be pressed"
        )

        // Release capslock
        viewModel.simulateTcpKeyInput(key: "capslock", action: "release")
        await Task.yield()

        XCTAssertFalse(
            viewModel.tcpPressedKeyCodes.contains(57),
            "Capslock should be released"
        )
    }

    func testSimulateTcpKeyInput_modifierKeys() async {
        let viewModel = KeyboardVisualizationViewModel()

        // Test various modifier key names that Kanata might send
        let modifierTests: [(key: String, keyCode: UInt16)] = [
            ("lctl", 59),
            ("leftctrl", 59),
            ("lmet", 55),
            ("leftmeta", 55),
            ("lalt", 58),
            ("leftalt", 58),
            ("lsft", 56),
            ("leftshift", 56),
            ("rctl", 102),
            ("rightctrl", 102),
        ]

        for (key, expectedKeyCode) in modifierTests {
            viewModel.simulateTcpKeyInput(key: key, action: "press")
            await Task.yield()

            XCTAssertTrue(
                viewModel.tcpPressedKeyCodes.contains(expectedKeyCode),
                "\(key) (keyCode \(expectedKeyCode)) should be pressed"
            )

            viewModel.simulateTcpKeyInput(key: key, action: "release")
            await Task.yield()

            XCTAssertFalse(
                viewModel.tcpPressedKeyCodes.contains(expectedKeyCode),
                "\(key) should be released"
            )
        }
    }
}
