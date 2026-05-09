@testable import KeyPathAppKit
import XCTest

final class LabelMetadataTests: XCTestCase {
    // MARK: - Symbol inputs (existing behavior)

    func testSymbolEscReturnsWordLabel() {
        XCTAssertEqual(LabelMetadata.forLabel("⎋").wordLabel, "esc")
    }

    func testSymbolCapsLockReturnsWordLabel() {
        XCTAssertEqual(LabelMetadata.forLabel("⇪").wordLabel, "caps lock")
    }

    func testSymbolShiftReturnsWordLabel() {
        XCTAssertEqual(LabelMetadata.forLabel("⇧").wordLabel, "shift")
    }

    func testSymbolReturnReturnsWordLabel() {
        XCTAssertEqual(LabelMetadata.forLabel("↩").wordLabel, "return")
    }

    func testSymbolDeleteReturnsWordLabel() {
        XCTAssertEqual(LabelMetadata.forLabel("⌫").wordLabel, "delete")
    }

    func testSymbolTabReturnsWordLabel() {
        XCTAssertEqual(LabelMetadata.forLabel("⇥").wordLabel, "tab")
    }

    // MARK: - Case-insensitive text inputs (regression: augmentWithPushMsgActions uses .capitalized)

    func testCapitalizedEscReturnsWordLabel() {
        XCTAssertEqual(LabelMetadata.forLabel("Esc").wordLabel, "esc")
    }

    func testLowercaseEscReturnsWordLabel() {
        XCTAssertEqual(LabelMetadata.forLabel("esc").wordLabel, "esc")
    }

    func testUppercaseESCReturnsWordLabel() {
        XCTAssertEqual(LabelMetadata.forLabel("ESC").wordLabel, "esc")
    }

    func testCapitalizedCapsLockReturnsWordLabel() {
        XCTAssertEqual(LabelMetadata.forLabel("Caps Lock").wordLabel, "caps lock")
    }

    func testLowercaseCapsLockReturnsWordLabel() {
        XCTAssertEqual(LabelMetadata.forLabel("caps lock").wordLabel, "caps lock")
    }

    // MARK: - Single-character symbols are not lowercased

    func testSingleLetterDoesNotMatchSpecialKey() {
        XCTAssertNil(LabelMetadata.forLabel("A").wordLabel)
    }

    func testSingleDigitDoesNotMatchSpecialKey() {
        XCTAssertNil(LabelMetadata.forLabel("5").wordLabel)
    }

    // MARK: - Shift symbols unaffected

    func testShiftSymbolForNumberRow() {
        XCTAssertEqual(LabelMetadata.forLabel("1").shiftSymbol, "!")
        XCTAssertEqual(LabelMetadata.forLabel("9").shiftSymbol, "(")
    }

    func testShiftSymbolForPunctuation() {
        XCTAssertEqual(LabelMetadata.forLabel(",").shiftSymbol, "<")
        XCTAssertEqual(LabelMetadata.forLabel("/").shiftSymbol, "?")
    }
}
