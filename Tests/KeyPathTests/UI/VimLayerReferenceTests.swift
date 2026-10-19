@testable import KeyPathAppKit
import KeyPathRulesCore
import XCTest

final class VimLayerReferenceTests: XCTestCase {
    func testCuratedKeysUseReadableTitlesInsteadOfCatalogDescriptions() {
        let entry = VimLayerReference.entry(for: KeyMapping(
            input: "h", action: .keystroke(key: "left"), description: "h — left"
        ))
        XCTAssertEqual(entry.title, "Left")
        XCTAssertEqual(entry.sends, "←")
        XCTAssertEqual(entry.category, .navigation)
    }

    func testDollarIsDrawnOnTheFourKey() {
        let entry = VimLayerReference.entry(for: KeyMapping(
            input: "4", action: .keystroke(key: "M-right"), description: "$ — line end"
        ))
        XCTAssertEqual(entry.input, "4")
        XCTAssertEqual(entry.capLabel, "$")
        XCTAssertEqual(entry.listLabel, "$")
        XCTAssertEqual(entry.sends, "⌘→")
    }

    func testShiftAndControlVariantsComeFromTheMappingNotTheCuratedTable() {
        let g = VimLayerReference.entry(for: KeyMapping(
            input: "g", action: .keystroke(key: "M-up"), shiftedOutput: "M-down"
        ))
        XCTAssertEqual(g.listLabel, "gg")
        XCTAssertEqual(g.shift, .init(label: "⇧G", title: "Bottom of document", sends: "⌘↓"))
        XCTAssertNil(g.ctrl)

        let d = VimLayerReference.entry(for: KeyMapping(
            input: "d", action: .keystroke(key: "A-bspc"), ctrlOutput: "pgdn"
        ))
        XCTAssertEqual(d.sends, "⌥⌫")
        XCTAssertEqual(d.ctrl, .init(label: "⌃d", title: "Page down", sends: "Page Down"))
        XCTAssertNil(d.shift)

        // A curated shift title is not shown unless the mapping actually has a shift output.
        let a = VimLayerReference.entry(for: KeyMapping(input: "a", action: .keystroke(key: "right")))
        XCTAssertNil(a.shift)
        XCTAssertNil(a.variant(for: .shift))
    }

    func testUnknownKeysFallBackToTheirDescriptionAndHaveNoCategory() {
        let entry = VimLayerReference.entry(for: KeyMapping(
            input: "w", action: .keystroke(key: "A-right"), description: "w — word forward"
        ))
        XCTAssertEqual(entry.title, "Word forward")
        XCTAssertEqual(entry.sends, "⌥→")
        XCTAssertNil(entry.category)
    }

    func testOutputSymbolsKeepMultiKeySequencesAndCombinedModifiers() {
        XCTAssertEqual(VimLayerReference.symbols(for: "M-S-z"), "⌘⇧Z")
        XCTAssertEqual(VimLayerReference.symbols(for: "up M-right ret"), "↑ ⌘→ ↩")
        XCTAssertEqual(VimLayerReference.symbols(for: "del"), "⌦")
    }

    func testTypedCharactersMatchLayoutKeyNames() {
        XCTAssertEqual(VimLayerKeyboardMap.keyName(forInput: "/"), "slash")
        XCTAssertEqual(VimLayerKeyboardMap.keyName(forInput: "4"), "4")
        XCTAssertEqual(VimLayerKeyboardMap.keyName(forInput: "h"), "h")
    }

    func testEveryShippedVimMappingHasACuratedTitleAndCategory() throws {
        let vim = try XCTUnwrap(RuleCollectionCatalog().defaultCollections().first { $0.id == RuleCollectionIdentifier.vimNavigation })
        for entry in VimLayerReference.entries(from: vim.mappings) {
            XCTAssertNotNil(entry.category, "\(entry.input) has no category")
            XCTAssertFalse(entry.title.contains(" — "), "\(entry.input) shows the raw catalog description")
        }
    }

    func testKeycapsUseShortTitlesThatFitAOneUnitKey() {
        XCTAssertEqual(VimLayerReference.capTitle(for: "Delete previous word"), "Del ←")
        XCTAssertEqual(VimLayerReference.capTitle(for: "Copy"), "Copy")
        let vim = RuleCollectionCatalog().defaultCollections().first { $0.id == RuleCollectionIdentifier.vimNavigation }
        for entry in VimLayerReference.entries(from: vim?.mappings ?? []) {
            for title in [entry.title, entry.shift?.title, entry.ctrl?.title].compactMap(\.self) {
                XCTAssertLessThanOrEqual(VimLayerReference.capTitle(for: title).count, 6, title)
            }
        }
    }
}
