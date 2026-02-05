import XCTest

@testable import KeyPathAppKit

final class LauncherKeymapTranslatorTests: XCTestCase {
    func testTranslatorUsesKeymapLabelForPunctuationKey() {
        let translator = LauncherKeymapTranslator(keymap: .qwertz, includePunctuation: false)

        XCTAssertEqual(translator.displayLabel(for: "semicolon"), "ö")
        XCTAssertEqual(translator.canonicalKey(for: "ö"), "semicolon")
    }

    func testTranslatorFallsBackToQwertyLabelForPunctuationKey() {
        let translator = LauncherKeymapTranslator(keymap: .qwertyUS, includePunctuation: false)

        XCTAssertEqual(translator.displayLabel(for: "semicolon"), ";")
        XCTAssertEqual(translator.canonicalKey(for: ";"), "semicolon")
    }
}
