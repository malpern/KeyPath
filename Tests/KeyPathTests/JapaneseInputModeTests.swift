@testable import KeyPathAppKit
import XCTest

final class JapaneseInputModeTests: XCTestCase {
    // MARK: - Mode Detection from Input Source ID

    func testDetectsHiraganaMode() {
        // Kotoeri hiragana
        XCTAssertEqual(
            JapaneseInputMode.detect(from: "com.apple.inputmethod.Kotoeri.RomajiTyping.Japanese.Hiragana"),
            .hiragana
        )
        // Case insensitive
        XCTAssertEqual(
            JapaneseInputMode.detect(from: "com.example.HIRAGANA"),
            .hiragana
        )
    }

    func testDetectsKatakanaMode() {
        XCTAssertEqual(
            JapaneseInputMode.detect(from: "com.apple.inputmethod.Kotoeri.RomajiTyping.Japanese.Katakana"),
            .katakana
        )
        XCTAssertEqual(
            JapaneseInputMode.detect(from: "com.example.KATAKANA"),
            .katakana
        )
    }

    func testDetectsAlphanumericMode() {
        XCTAssertEqual(
            JapaneseInputMode.detect(from: "com.apple.inputmethod.Kotoeri.RomajiTyping.Japanese.Alphanumeric"),
            .alphanumeric
        )
    }

    func testRomajiTypingDefaultsToHiragana() {
        // "RomajiTyping" is the input method variant (vs Kana typing), not the mode
        // When no specific mode suffix, defaults to hiragana
        XCTAssertEqual(
            JapaneseInputMode.detect(from: "com.apple.inputmethod.Kotoeri.RomajiTyping.Japanese"),
            .hiragana
        )
    }

    func testDefaultsToHiraganaForGenericJapanese() {
        // Generic Japanese input without specific mode defaults to hiragana
        XCTAssertEqual(
            JapaneseInputMode.detect(from: "com.apple.inputmethod.Kotoeri.Japanese"),
            .hiragana
        )
        XCTAssertEqual(
            JapaneseInputMode.detect(from: "com.justsystems.inputmethod.atok.Japanese"),
            .hiragana
        )
    }

    func testReturnsUnknownForNonJapanese() {
        XCTAssertEqual(
            JapaneseInputMode.detect(from: "com.apple.keylayout.US"),
            .unknown
        )
        XCTAssertEqual(
            JapaneseInputMode.detect(from: "com.apple.keylayout.German"),
            .unknown
        )
    }

    // MARK: - Mode Indicators

    func testHiraganaIndicator() {
        XCTAssertEqual(JapaneseInputMode.hiragana.indicator, "あ")
    }

    func testKatakanaIndicator() {
        XCTAssertEqual(JapaneseInputMode.katakana.indicator, "ア")
    }

    func testAlphanumericIndicator() {
        XCTAssertEqual(JapaneseInputMode.alphanumeric.indicator, "A")
    }

    func testUnknownIndicatorIsNil() {
        XCTAssertNil(JapaneseInputMode.unknown.indicator)
    }

    // MARK: - Display Names

    func testDisplayNames() {
        XCTAssertEqual(JapaneseInputMode.hiragana.displayName, "Hiragana")
        XCTAssertEqual(JapaneseInputMode.katakana.displayName, "Katakana")
        XCTAssertEqual(JapaneseInputMode.alphanumeric.displayName, "Alphanumeric")
        XCTAssertEqual(JapaneseInputMode.unknown.displayName, "Unknown")
    }

    // MARK: - Real-world Input Source IDs

    func testRealKotoeriInputSourceIDs() {
        // These are actual input source IDs from macOS Kotoeri IME
        let hiraganaID = "com.apple.inputmethod.Kotoeri.RomajiTyping.Japanese"
        let katakanaID = "com.apple.inputmethod.Kotoeri.RomajiTyping.Japanese.Katakana"
        let alphanumericID = "com.apple.inputmethod.Kotoeri.RomajiTyping.Japanese.Alphanumeric"

        // Note: Generic Japanese ID defaults to hiragana (most common mode)
        XCTAssertEqual(JapaneseInputMode.detect(from: hiraganaID), .hiragana)
        XCTAssertEqual(JapaneseInputMode.detect(from: katakanaID), .katakana)
        XCTAssertEqual(JapaneseInputMode.detect(from: alphanumericID), .alphanumeric)
    }
}
