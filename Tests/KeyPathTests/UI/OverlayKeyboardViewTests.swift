@testable import KeyPathAppKit
import KeyPathCore
import XCTest

@MainActor
final class OverlayKeyboardViewTests: XCTestCase {
    // MARK: - keyCodeToKanataName Tests

    func testKeyCodeToKanataName_letterA() {
        XCTAssertEqual(OverlayKeyboardView.keyCodeToKanataName(0), "a")
    }

    func testKeyCodeToKanataName_letterS() {
        XCTAssertEqual(OverlayKeyboardView.keyCodeToKanataName(1), "s")
    }

    func testKeyCodeToKanataName_letterD() {
        XCTAssertEqual(OverlayKeyboardView.keyCodeToKanataName(2), "d")
    }

    func testKeyCodeToKanataName_letterF() {
        XCTAssertEqual(OverlayKeyboardView.keyCodeToKanataName(3), "f")
    }

    func testKeyCodeToKanataName_homeRow() {
        // Home row: ASDFGHJKL
        XCTAssertEqual(OverlayKeyboardView.keyCodeToKanataName(0), "a")
        XCTAssertEqual(OverlayKeyboardView.keyCodeToKanataName(1), "s")
        XCTAssertEqual(OverlayKeyboardView.keyCodeToKanataName(2), "d")
        XCTAssertEqual(OverlayKeyboardView.keyCodeToKanataName(3), "f")
        XCTAssertEqual(OverlayKeyboardView.keyCodeToKanataName(5), "g")
        XCTAssertEqual(OverlayKeyboardView.keyCodeToKanataName(4), "h")
        XCTAssertEqual(OverlayKeyboardView.keyCodeToKanataName(38), "j")
        XCTAssertEqual(OverlayKeyboardView.keyCodeToKanataName(40), "k")
        XCTAssertEqual(OverlayKeyboardView.keyCodeToKanataName(37), "l")
    }

    func testKeyCodeToKanataName_numbers() {
        XCTAssertEqual(OverlayKeyboardView.keyCodeToKanataName(18), "1")
        XCTAssertEqual(OverlayKeyboardView.keyCodeToKanataName(19), "2")
        XCTAssertEqual(OverlayKeyboardView.keyCodeToKanataName(20), "3")
        XCTAssertEqual(OverlayKeyboardView.keyCodeToKanataName(21), "4")
        XCTAssertEqual(OverlayKeyboardView.keyCodeToKanataName(23), "5")
        XCTAssertEqual(OverlayKeyboardView.keyCodeToKanataName(22), "6")
        XCTAssertEqual(OverlayKeyboardView.keyCodeToKanataName(26), "7")
        XCTAssertEqual(OverlayKeyboardView.keyCodeToKanataName(28), "8")
        XCTAssertEqual(OverlayKeyboardView.keyCodeToKanataName(25), "9")
        XCTAssertEqual(OverlayKeyboardView.keyCodeToKanataName(29), "0")
    }

    func testKeyCodeToKanataName_modifiers() {
        XCTAssertEqual(OverlayKeyboardView.keyCodeToKanataName(55), "leftmeta")
        XCTAssertEqual(OverlayKeyboardView.keyCodeToKanataName(54), "rightmeta")
        XCTAssertEqual(OverlayKeyboardView.keyCodeToKanataName(56), "leftshift")
        XCTAssertEqual(OverlayKeyboardView.keyCodeToKanataName(60), "rightshift")
        XCTAssertEqual(OverlayKeyboardView.keyCodeToKanataName(58), "leftalt")
        XCTAssertEqual(OverlayKeyboardView.keyCodeToKanataName(61), "rightalt")
        XCTAssertEqual(OverlayKeyboardView.keyCodeToKanataName(59), "leftctrl")
        XCTAssertEqual(OverlayKeyboardView.keyCodeToKanataName(57), "capslock")
        XCTAssertEqual(OverlayKeyboardView.keyCodeToKanataName(63), "fn")
    }

    func testKeyCodeToKanataName_specialKeys() {
        XCTAssertEqual(OverlayKeyboardView.keyCodeToKanataName(36), "enter")
        XCTAssertEqual(OverlayKeyboardView.keyCodeToKanataName(48), "tab")
        XCTAssertEqual(OverlayKeyboardView.keyCodeToKanataName(49), "space")
        XCTAssertEqual(OverlayKeyboardView.keyCodeToKanataName(51), "backspace")
        XCTAssertEqual(OverlayKeyboardView.keyCodeToKanataName(53), "esc")
    }

    func testKeyCodeToKanataName_arrowKeys() {
        XCTAssertEqual(OverlayKeyboardView.keyCodeToKanataName(123), "left")
        XCTAssertEqual(OverlayKeyboardView.keyCodeToKanataName(124), "right")
        XCTAssertEqual(OverlayKeyboardView.keyCodeToKanataName(125), "down")
        XCTAssertEqual(OverlayKeyboardView.keyCodeToKanataName(126), "up")
    }

    func testKeyCodeToKanataName_functionKeys() {
        XCTAssertEqual(OverlayKeyboardView.keyCodeToKanataName(122), "f1")
        XCTAssertEqual(OverlayKeyboardView.keyCodeToKanataName(120), "f2")
        XCTAssertEqual(OverlayKeyboardView.keyCodeToKanataName(99), "f3")
        XCTAssertEqual(OverlayKeyboardView.keyCodeToKanataName(118), "f4")
        XCTAssertEqual(OverlayKeyboardView.keyCodeToKanataName(96), "f5")
        XCTAssertEqual(OverlayKeyboardView.keyCodeToKanataName(97), "f6")
        XCTAssertEqual(OverlayKeyboardView.keyCodeToKanataName(98), "f7")
        XCTAssertEqual(OverlayKeyboardView.keyCodeToKanataName(100), "f8")
        XCTAssertEqual(OverlayKeyboardView.keyCodeToKanataName(101), "f9")
        XCTAssertEqual(OverlayKeyboardView.keyCodeToKanataName(109), "f10")
        XCTAssertEqual(OverlayKeyboardView.keyCodeToKanataName(103), "f11")
        XCTAssertEqual(OverlayKeyboardView.keyCodeToKanataName(111), "f12")
    }

    func testKeyCodeToKanataName_punctuation() {
        XCTAssertEqual(OverlayKeyboardView.keyCodeToKanataName(41), "semicolon")
        XCTAssertEqual(OverlayKeyboardView.keyCodeToKanataName(39), "apostrophe")
        XCTAssertEqual(OverlayKeyboardView.keyCodeToKanataName(43), "comma")
        XCTAssertEqual(OverlayKeyboardView.keyCodeToKanataName(47), "dot")
        XCTAssertEqual(OverlayKeyboardView.keyCodeToKanataName(44), "slash")
        XCTAssertEqual(OverlayKeyboardView.keyCodeToKanataName(33), "leftbrace")
        XCTAssertEqual(OverlayKeyboardView.keyCodeToKanataName(30), "rightbrace")
        XCTAssertEqual(OverlayKeyboardView.keyCodeToKanataName(42), "backslash")
        XCTAssertEqual(OverlayKeyboardView.keyCodeToKanataName(50), "grave")
        XCTAssertEqual(OverlayKeyboardView.keyCodeToKanataName(27), "minus")
        XCTAssertEqual(OverlayKeyboardView.keyCodeToKanataName(24), "equal")
    }

    func testKeyCodeToKanataName_navigationKeys() {
        XCTAssertEqual(OverlayKeyboardView.keyCodeToKanataName(115), "home")
        XCTAssertEqual(OverlayKeyboardView.keyCodeToKanataName(116), "pageup")
        XCTAssertEqual(OverlayKeyboardView.keyCodeToKanataName(119), "end")
        XCTAssertEqual(OverlayKeyboardView.keyCodeToKanataName(121), "pagedown")
        XCTAssertEqual(OverlayKeyboardView.keyCodeToKanataName(114), "help")
    }

    func testKeyCodeToKanataName_extendedFunctionKeys() {
        XCTAssertEqual(OverlayKeyboardView.keyCodeToKanataName(64), "f17")
        XCTAssertEqual(OverlayKeyboardView.keyCodeToKanataName(79), "f18")
        XCTAssertEqual(OverlayKeyboardView.keyCodeToKanataName(80), "f19")
        XCTAssertEqual(OverlayKeyboardView.keyCodeToKanataName(105), "f13")
        XCTAssertEqual(OverlayKeyboardView.keyCodeToKanataName(106), "f16")
        XCTAssertEqual(OverlayKeyboardView.keyCodeToKanataName(107), "f14")
        XCTAssertEqual(OverlayKeyboardView.keyCodeToKanataName(113), "f15")
    }

    func testKeyCodeToKanataName_rightControl() {
        XCTAssertEqual(OverlayKeyboardView.keyCodeToKanataName(102), "rightctrl")
    }

    func testKeyCodeToKanataName_unknownKeyCode() {
        XCTAssertEqual(OverlayKeyboardView.keyCodeToKanataName(255), "unknown-255")
        XCTAssertEqual(OverlayKeyboardView.keyCodeToKanataName(200), "unknown-200")
    }

    // MARK: - escLeftInset Tests

    func testEscLeftInset_macBookLayout() {
        let layout = PhysicalLayout.macBookUS
        let scale: CGFloat = 1.0
        let inset = OverlayKeyboardView.escLeftInset(for: layout, scale: scale)

        // ESC key should have a positive left inset (it's not at x=0 on MacBook layouts)
        XCTAssertGreaterThanOrEqual(inset, 0)
    }

    func testEscLeftInset_scalingAffectsInset() {
        let layout = PhysicalLayout.macBookUS
        let inset1 = OverlayKeyboardView.escLeftInset(for: layout, scale: 1.0)
        let inset2 = OverlayKeyboardView.escLeftInset(for: layout, scale: 2.0)

        // At 2x scale, the inset should be approximately 2x
        XCTAssertEqual(inset2, inset1 * 2, accuracy: 0.1)
    }

    func testEscLeftInset_customKeyUnitSize() {
        let layout = PhysicalLayout.macBookUS
        let inset1 = OverlayKeyboardView.escLeftInset(for: layout, scale: 1.0, keyUnitSize: 32)
        let inset2 = OverlayKeyboardView.escLeftInset(for: layout, scale: 1.0, keyUnitSize: 64)

        // Both should be valid non-negative insets
        // Note: If ESC is at x=0, inset is based on keyGap only, not keyUnitSize
        XCTAssertGreaterThanOrEqual(inset1, 0)
        XCTAssertGreaterThanOrEqual(inset2, 0)
    }

    func testEscLeftInset_customKeyGap() {
        let layout = PhysicalLayout.macBookUS
        let inset1 = OverlayKeyboardView.escLeftInset(for: layout, scale: 1.0, keyUnitSize: 32, keyGap: 2)
        let inset2 = OverlayKeyboardView.escLeftInset(for: layout, scale: 1.0, keyUnitSize: 32, keyGap: 4)

        // Larger key gap should result in larger inset
        XCTAssertGreaterThan(inset2, inset1)
    }
}
