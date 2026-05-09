@testable import KeyPathAppKit
import XCTest

/// Exhaustive data-driven tests for LabelMetadata.forLabel().
/// Covers all ~31 known mappings to catch regressions when entries are added/changed.
final class LabelMetadataExhaustiveTests: XCTestCase {

    // MARK: - Wide Modifier Word Labels

    func testAllWideModifierSymbolsProduceWordLabels() {
        let expected: [(String, String)] = [
            ("⇧", "shift"),
            ("↩", "return"),
            ("⌫", "delete"),
            ("⇥", "tab"),
            ("⇪", "caps lock"),
            ("⎋", "esc"),
        ]
        for (symbol, word) in expected {
            let metadata = LabelMetadata.forLabel(symbol)
            XCTAssertEqual(metadata.wordLabel, word, "Symbol '\(symbol)' should produce word label '\(word)'")
        }
    }

    func testMultiCharModifierNames() {
        let metadata = LabelMetadata.forLabel("caps lock")
        XCTAssertEqual(metadata.wordLabel, "caps lock")

        let escMetadata = LabelMetadata.forLabel("esc")
        XCTAssertEqual(escMetadata.wordLabel, "esc")
    }

    func testCaseInsensitiveMultiCharLabels() {
        XCTAssertEqual(LabelMetadata.forLabel("Esc").wordLabel, "esc")
        XCTAssertEqual(LabelMetadata.forLabel("ESC").wordLabel, "esc")
        XCTAssertEqual(LabelMetadata.forLabel("Caps Lock").wordLabel, "caps lock")
    }

    // MARK: - Bottom Modifier Word Labels

    func testAllBottomModifierSymbols() {
        let expected: [(String, String)] = [
            ("⌃", "control"),
            ("⌥", "option"),
            ("⌘", "command"),
        ]
        for (symbol, word) in expected {
            let metadata = LabelMetadata.forLabel(symbol)
            XCTAssertEqual(metadata.wordLabel, word, "Symbol '\(symbol)' should produce '\(word)'")
        }
    }

    // MARK: - Special Modifier Symbols

    func testHyperAndMehSymbols() {
        XCTAssertEqual(LabelMetadata.forLabel("✦").wordLabel, "hyper")
        XCTAssertEqual(LabelMetadata.forLabel("◆").wordLabel, "meh")
    }

    // MARK: - Number Row Shift Symbols (Exhaustive)

    func testAllNumberRowShiftSymbols() {
        let expected: [(String, String)] = [
            ("1", "!"), ("2", "@"), ("3", "#"), ("4", "$"), ("5", "%"),
            ("6", "^"), ("7", "&"), ("8", "*"), ("9", "("), ("0", ")"),
        ]
        for (number, shift) in expected {
            let metadata = LabelMetadata.forLabel(number)
            XCTAssertEqual(metadata.shiftSymbol, shift, "Number '\(number)' should have shift symbol '\(shift)'")
            XCTAssertNil(metadata.wordLabel, "Number '\(number)' should not have a word label")
        }
    }

    // MARK: - Dual Symbol Keys (Exhaustive)

    func testAllDualSymbolKeys() {
        let expected: [(String, String)] = [
            (",", "<"), (".", ">"), ("/", "?"), (";", ":"),
            ("'", "\""), ("[", "{"), ("]", "}"), ("\\", "|"),
            ("`", "~"), ("-", "_"), ("=", "+"),
        ]
        for (key, shift) in expected {
            let metadata = LabelMetadata.forLabel(key)
            XCTAssertEqual(metadata.shiftSymbol, shift, "Key '\(key)' should have shift symbol '\(shift)'")
        }
    }

    // MARK: - Default / Unknown Labels

    func testUnknownLabel_ReturnsEmptyMetadata() {
        let metadata = LabelMetadata.forLabel("Q")
        XCTAssertNil(metadata.wordLabel)
        XCTAssertNil(metadata.shiftSymbol)
    }

    func testSingleLetterLabel_ReturnsEmptyMetadata() {
        for letter in "ABCDEFGHIJKLMNOPQRSTUVWXYZ" {
            let metadata = LabelMetadata.forLabel(String(letter))
            XCTAssertNil(metadata.wordLabel, "Letter '\(letter)' should not have a word label")
        }
    }

    func testEmptyLabel_ReturnsEmptyMetadata() {
        let metadata = LabelMetadata.forLabel("")
        XCTAssertNil(metadata.wordLabel)
        XCTAssertNil(metadata.shiftSymbol)
    }

    // MARK: - SF Symbol Lookup by KeyCode (Function Keys)

    func testAllFunctionKeySFSymbols() {
        let expected: [(UInt16, String)] = [
            (122, "sun.min"),     // F1
            (120, "sun.max"),     // F2
            (99, "rectangle.3.group"), // F3
            (118, "magnifyingglass"),  // F4
            (96, "mic"),          // F5
            (97, "moon"),         // F6
            (98, "backward"),     // F7
            (100, "playpause"),   // F8
            (101, "forward"),     // F9
            (109, "speaker.slash"), // F10
        ]
        for (keyCode, symbol) in expected {
            XCTAssertEqual(
                LabelMetadata.sfSymbol(forKeyCode: keyCode), symbol,
                "KeyCode \(keyCode) should map to SF Symbol '\(symbol)'"
            )
        }
    }

    func testNonFunctionKeyCode_ReturnsNil() {
        XCTAssertNil(LabelMetadata.sfSymbol(forKeyCode: 0), "A key should not have SF Symbol")
        XCTAssertNil(LabelMetadata.sfSymbol(forKeyCode: 49), "Space should not have SF Symbol")
    }
}
