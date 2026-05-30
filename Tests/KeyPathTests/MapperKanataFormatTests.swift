@testable import KeyPathAppKit
import KeyPathCore
import XCTest

/// Tests for KeyMappingFormatter: KeySequence → kanata format conversion.
final class MapperKanataFormatTests: XCTestCase {
    // MARK: - Single Key Formatting

    func testSingleLetterKey() {
        let seq = makeSequence(keys: [KeyPress(baseKey: "a", modifiers: [], keyCode: 0)])
        XCTAssertEqual(KeyMappingFormatter.toKanataFormat(seq), "a")
    }

    func testSingleLetterKeyUppercasedToLowercase() {
        let seq = makeSequence(keys: [KeyPress(baseKey: "A", modifiers: [], keyCode: 0)])
        XCTAssertEqual(KeyMappingFormatter.toKanataFormat(seq), "a")
    }

    func testSpecialKeyMapping_Space() {
        let seq = makeSequence(keys: [KeyPress(baseKey: "space", modifiers: [], keyCode: 49)])
        XCTAssertEqual(KeyMappingFormatter.toKanataFormat(seq), "spc")
    }

    func testSpecialKeyMapping_Return() {
        let seq = makeSequence(keys: [KeyPress(baseKey: "return", modifiers: [], keyCode: 36)])
        XCTAssertEqual(KeyMappingFormatter.toKanataFormat(seq), "ret")
    }

    func testSpecialKeyMapping_Enter() {
        let seq = makeSequence(keys: [KeyPress(baseKey: "enter", modifiers: [], keyCode: 36)])
        XCTAssertEqual(KeyMappingFormatter.toKanataFormat(seq), "ret")
    }

    func testSpecialKeyMapping_Escape() {
        let seq = makeSequence(keys: [KeyPress(baseKey: "escape", modifiers: [], keyCode: 53)])
        XCTAssertEqual(KeyMappingFormatter.toKanataFormat(seq), "esc")
    }

    func testSpecialKeyMapping_Backspace() {
        let seq = makeSequence(keys: [KeyPress(baseKey: "backspace", modifiers: [], keyCode: 51)])
        XCTAssertEqual(KeyMappingFormatter.toKanataFormat(seq), "bspc")
    }

    func testSpecialKeyMapping_Delete() {
        let seq = makeSequence(keys: [KeyPress(baseKey: "delete", modifiers: [], keyCode: 117)])
        XCTAssertEqual(KeyMappingFormatter.toKanataFormat(seq), "del")
    }

    // MARK: - Modifier Formatting

    func testControlModifier() {
        let seq = makeSequence(keys: [KeyPress(baseKey: "c", modifiers: .control, keyCode: 8)])
        XCTAssertEqual(KeyMappingFormatter.toKanataFormat(seq), "C-c")
    }

    func testOptionModifier() {
        let seq = makeSequence(keys: [KeyPress(baseKey: "a", modifiers: .option, keyCode: 0)])
        XCTAssertEqual(KeyMappingFormatter.toKanataFormat(seq), "A-a")
    }

    func testShiftModifier() {
        let seq = makeSequence(keys: [KeyPress(baseKey: "a", modifiers: .shift, keyCode: 0)])
        XCTAssertEqual(KeyMappingFormatter.toKanataFormat(seq), "S-a")
    }

    func testCommandModifier() {
        let seq = makeSequence(keys: [KeyPress(baseKey: "s", modifiers: .command, keyCode: 1)])
        XCTAssertEqual(KeyMappingFormatter.toKanataFormat(seq), "M-s")
    }

    func testMultipleModifiers_ControlShift() {
        let mods: ModifierSet = [.control, .shift]
        let seq = makeSequence(keys: [KeyPress(baseKey: "a", modifiers: mods, keyCode: 0)])
        XCTAssertEqual(KeyMappingFormatter.toKanataFormat(seq), "S-C-a")
    }

    func testAllModifiers() {
        let mods: ModifierSet = [.control, .option, .shift, .command]
        let seq = makeSequence(keys: [KeyPress(baseKey: "a", modifiers: mods, keyCode: 0)])
        XCTAssertEqual(KeyMappingFormatter.toKanataFormat(seq), "M-S-A-C-a")
    }

    // MARK: - Sequence Formatting

    func testMultiKeySequence() {
        let seq = makeSequence(
            keys: [
                KeyPress(baseKey: "g", modifiers: [], keyCode: 5),
                KeyPress(baseKey: "g", modifiers: [], keyCode: 5),
            ],
            mode: .sequence
        )
        XCTAssertEqual(KeyMappingFormatter.toKanataFormat(seq), "g g")
    }

    func testSequenceWithMixedModifiers() {
        let seq = makeSequence(
            keys: [
                KeyPress(baseKey: "k", modifiers: .command, keyCode: 40),
                KeyPress(baseKey: "c", modifiers: .command, keyCode: 8),
            ],
            mode: .sequence
        )
        XCTAssertEqual(KeyMappingFormatter.toKanataFormat(seq), "M-k M-c")
    }

    // MARK: - Layer Conversion

    func testLayerFromString_Base() {
        XCTAssertEqual(KeyMappingFormatter.layerFromString("base"), .base)
    }

    func testLayerFromString_Nav() {
        XCTAssertEqual(KeyMappingFormatter.layerFromString("nav"), .navigation)
    }

    func testLayerFromString_Navigation() {
        XCTAssertEqual(KeyMappingFormatter.layerFromString("navigation"), .navigation)
    }

    func testLayerFromString_Custom() {
        XCTAssertEqual(KeyMappingFormatter.layerFromString("vim"), .custom("vim"))
    }

    func testLayerFromString_CaseInsensitive() {
        XCTAssertEqual(KeyMappingFormatter.layerFromString("BASE"), .base)
        XCTAssertEqual(KeyMappingFormatter.layerFromString("Nav"), .navigation)
    }

    // MARK: - URL Domain Extraction

    func testExtractDomain_HTTPS() {
        XCTAssertEqual(KeyMappingFormatter.extractDomain(from: "https://github.com/path"), "github.com")
    }

    func testExtractDomain_HTTP() {
        XCTAssertEqual(KeyMappingFormatter.extractDomain(from: "http://example.com/foo"), "example.com")
    }

    func testExtractDomain_NakedDomain() {
        XCTAssertEqual(KeyMappingFormatter.extractDomain(from: "google.com"), "google.com")
    }

    // MARK: - keyOutputFromPress (Multi-Tap helper)

    @MainActor
    func testKeyOutputFromPress_PlainKey() {
        let press = KeyPress(baseKey: "a", modifiers: [], keyCode: 0)
        XCTAssertEqual(MapperViewModel.keyOutputFromPress(press), "a")
    }

    @MainActor
    func testKeyOutputFromPress_WithCommand() {
        let press = KeyPress(baseKey: "s", modifiers: .command, keyCode: 1)
        XCTAssertEqual(MapperViewModel.keyOutputFromPress(press), "M-s")
    }

    @MainActor
    func testKeyOutputFromPress_AllModifiers() {
        let mods: ModifierSet = [.command, .control, .option, .shift]
        let press = KeyPress(baseKey: "a", modifiers: mods, keyCode: 0)
        XCTAssertEqual(MapperViewModel.keyOutputFromPress(press), "M-C-A-S-a")
    }

    // MARK: - Helpers

    private func makeSequence(keys: [KeyPress], mode: CaptureMode = .single) -> KeySequence {
        KeySequence(keys: keys, captureMode: mode)
    }
}
