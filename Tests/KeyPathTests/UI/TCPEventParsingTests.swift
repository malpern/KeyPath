@testable import KeyPathAppKit
import KeyPathCore
import XCTest

/// Tests for TCP event parsing in KeyboardVisualizationViewModel.
/// Verifies that key input, hold, tap, and message events are correctly
/// parsed and update the view model state.
final class TCPEventParsingTests: XCTestCase {

    // MARK: - Key Input Events

    @MainActor
    func testKeyPress_AddsToActiveKeys() {
        let vm = KeyboardVisualizationViewModel()
        vm.simulateTcpKeyInput(key: "a", action: "press")
        XCTAssertTrue(vm.pressedKeyCodes.contains(0), "Key 'a' (keyCode 0) should be pressed")
    }

    @MainActor
    func testKeyRelease_RemovesFromActiveKeys() {
        let vm = KeyboardVisualizationViewModel()
        vm.simulateTcpKeyInput(key: "a", action: "press")
        vm.simulateTcpKeyInput(key: "a", action: "release")
        XCTAssertFalse(vm.pressedKeyCodes.contains(0), "Key 'a' should be released")
    }

    @MainActor
    func testMultipleKeysPressed() {
        let vm = KeyboardVisualizationViewModel()
        vm.simulateTcpKeyInput(key: "a", action: "press")
        vm.simulateTcpKeyInput(key: "s", action: "press")
        XCTAssertTrue(vm.pressedKeyCodes.contains(0), "'a' should be pressed")
        XCTAssertTrue(vm.pressedKeyCodes.contains(1), "'s' should be pressed")
    }

    @MainActor
    func testUnknownKey_DoesNotCrash() {
        let vm = KeyboardVisualizationViewModel()
        vm.simulateTcpKeyInput(key: "nonexistent_key_zzz", action: "press")
        // Should not crash — unknown keys are silently ignored
    }

    @MainActor
    func testEmptyKeyName_DoesNotCrash() {
        let vm = KeyboardVisualizationViewModel()
        vm.simulateTcpKeyInput(key: "", action: "press")
    }

    @MainActor
    func testUnknownAction_DoesNotCrash() {
        let vm = KeyboardVisualizationViewModel()
        vm.simulateTcpKeyInput(key: "a", action: "unknown_action")
    }

    // MARK: - Hold Activated Events

    @MainActor
    func testHoldActivated_SetsHoldLabel() {
        let vm = KeyboardVisualizationViewModel()
        vm.simulateHoldActivated(key: "caps", action: "lctl")

        let capsKeyCode: UInt16 = 57
        XCTAssertTrue(
            vm.holdActiveKeyCodes.contains(capsKeyCode),
            "Caps should be in hold-active state"
        )
    }

    @MainActor
    func testHoldActivated_HyperAction() {
        let vm = KeyboardVisualizationViewModel()
        vm.simulateHoldActivated(key: "caps", action: "lctl+lmet+lalt+lsft")

        let capsKeyCode: UInt16 = 57
        XCTAssertTrue(vm.holdActiveKeyCodes.contains(capsKeyCode))
    }

    @MainActor
    func testHoldActivated_UnknownKey_DoesNotCrash() {
        let vm = KeyboardVisualizationViewModel()
        vm.simulateHoldActivated(key: "nonexistent", action: "lctl")
    }

    // MARK: - Tap Activated Events

    @MainActor
    func testTapActivated_DoesNotCrash() {
        let vm = KeyboardVisualizationViewModel()
        vm.simulateTapActivated(key: "caps", action: "esc")
    }

    @MainActor
    func testTapActivated_UnknownKey_DoesNotCrash() {
        let vm = KeyboardVisualizationViewModel()
        vm.simulateTapActivated(key: "zzz", action: "esc")
    }

    // MARK: - Modifier Key Names

    @MainActor
    func testModifierKeyNames_AllResolve() {
        let vm = KeyboardVisualizationViewModel()
        let modifiers = ["lmet", "rmet", "lctl", "rctl", "lalt", "ralt", "lsft", "rsft", "caps", "fn"]

        for mod in modifiers {
            vm.simulateTcpKeyInput(key: mod, action: "press")
            // Should not crash — all modifier names should resolve to valid key codes
        }
    }

    // MARK: - Common Key Names

    @MainActor
    func testCommonKeyNames_AllResolve() {
        let vm = KeyboardVisualizationViewModel()
        let keys = [
            "a", "b", "c", "d", "e", "f", "g", "h", "i", "j", "k", "l", "m",
            "n", "o", "p", "q", "r", "s", "t", "u", "v", "w", "x", "y", "z",
            "1", "2", "3", "4", "5", "6", "7", "8", "9", "0",
            "space", "spc", "enter", "ret", "return", "esc", "escape",
            "tab", "backspace", "bspc", "delete", "del",
            "left", "right", "up", "down",
            "f1", "f2", "f3", "f4", "f5", "f6", "f7", "f8", "f9", "f10", "f11", "f12",
        ]

        for key in keys {
            vm.simulateTcpKeyInput(key: key, action: "press")
            vm.simulateTcpKeyInput(key: key, action: "release")
        }

        XCTAssertTrue(vm.pressedKeyCodes.isEmpty, "All keys should be released")
    }

    // MARK: - Rapid Press/Release Sequences

    @MainActor
    func testRapidPressRelease_DoesNotLeakState() {
        let vm = KeyboardVisualizationViewModel()

        for _ in 0..<100 {
            vm.simulateTcpKeyInput(key: "a", action: "press")
            vm.simulateTcpKeyInput(key: "a", action: "release")
        }

        XCTAssertFalse(vm.pressedKeyCodes.contains(0), "No leaked press state after 100 cycles")
    }

    @MainActor
    func testDoublePress_WithoutRelease() {
        let vm = KeyboardVisualizationViewModel()
        vm.simulateTcpKeyInput(key: "a", action: "press")
        vm.simulateTcpKeyInput(key: "a", action: "press")

        XCTAssertTrue(vm.pressedKeyCodes.contains(0), "Should still be pressed")

        vm.simulateTcpKeyInput(key: "a", action: "release")
        XCTAssertFalse(vm.pressedKeyCodes.contains(0), "Single release should clear")
    }
}
