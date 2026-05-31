@testable import KeyPathAppKit
import XCTest

/// Verifies the international LogicalKeymaps added in #289 are registered and
/// produce the correct per-key labels. Layouts verified against kbdlayout.info
/// (Norwegian) and en.wikipedia.org/wiki/JCUKEN (Russian).
final class InternationalLogicalKeymapTests: XCTestCase {
    // macOS virtual key codes for keys outside the QWERTY-label lookup table.
    private let leftBracket: UInt16 = 33 // US `[`, right of P
    private let rightBracket: UInt16 = 30 // US `]`
    private let apostrophe: UInt16 = 39 // US `'`, right of `;`
    private let grave: UInt16 = 50 // US backtick

    private func keyCode(_ qwerty: String) -> UInt16 {
        guard let code = LogicalKeymap.keyCode(forQwertyLabel: qwerty) else {
            fatalError("no keycode for \(qwerty)")
        }
        return code
    }

    // MARK: - Registration

    func testNewKeymapsAreRegistered() {
        XCTAssertNotNil(LogicalKeymap.find(id: "norwegian"))
        XCTAssertNotNil(LogicalKeymap.find(id: "russian"))
        XCTAssertTrue(LogicalKeymap.internationalLayouts.contains { $0.id == "norwegian" })
        XCTAssertTrue(LogicalKeymap.internationalLayouts.contains { $0.id == "russian" })
        XCTAssertTrue(LogicalKeymap.all.contains { $0.id == "norwegian" })
        XCTAssertTrue(LogicalKeymap.all.contains { $0.id == "russian" })
    }

    // MARK: - Norwegian

    func testNorwegianCoreLabels() {
        let nb = LogicalKeymap.norwegian
        // Letters follow QWERTY...
        XCTAssertEqual(nb.label(for: keyCode("q"), includeExtraKeys: false), "q")
        XCTAssertEqual(nb.label(for: keyCode("a"), includeExtraKeys: false), "a")
        XCTAssertEqual(nb.label(for: keyCode("z"), includeExtraKeys: false), "z")
        // ...except Ø replaces the home-row `;`, and `-` sits in the US `/` slot.
        XCTAssertEqual(nb.label(for: keyCode(";"), includeExtraKeys: false), "ø")
        XCTAssertEqual(nb.label(for: keyCode("/"), includeExtraKeys: false), "-")
    }

    func testNorwegianExtraLetters() {
        let nb = LogicalKeymap.norwegian
        // Å (right of P) and Æ (right of Ø) are outside the 30-key block.
        XCTAssertEqual(nb.label(for: leftBracket, includeExtraKeys: true), "å")
        XCTAssertEqual(nb.label(for: apostrophe, includeExtraKeys: true), "æ")
        // Not shown when extra keys are toggled off.
        XCTAssertNil(nb.label(for: leftBracket, includeExtraKeys: false))
    }

    // MARK: - Russian (ЙЦУКЕН)

    func testRussianCoreLabels() {
        let ru = LogicalKeymap.russian
        XCTAssertEqual(ru.label(for: keyCode("q"), includeExtraKeys: false), "й")
        XCTAssertEqual(ru.label(for: keyCode("a"), includeExtraKeys: false), "ф")
        XCTAssertEqual(ru.label(for: keyCode("z"), includeExtraKeys: false), "я")
        XCTAssertEqual(ru.label(for: keyCode("p"), includeExtraKeys: false), "з")
        XCTAssertEqual(ru.label(for: keyCode(";"), includeExtraKeys: false), "ж")
    }

    func testRussianExtraLetters() {
        let ru = LogicalKeymap.russian
        XCTAssertEqual(ru.label(for: leftBracket, includeExtraKeys: true), "х")
        XCTAssertEqual(ru.label(for: rightBracket, includeExtraKeys: true), "ъ")
        XCTAssertEqual(ru.label(for: apostrophe, includeExtraKeys: true), "э")
        XCTAssertEqual(ru.label(for: grave, includeExtraKeys: true), "ё")
    }
}
