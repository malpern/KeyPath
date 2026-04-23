@testable import KeyPathAppKit
import XCTest

final class PackSummaryProviderTests: XCTestCase {
    private func makeInput(
        pack: Pack,
        collection: RuleCollection? = nil,
        tapOverride: String? = nil,
        holdOverride: String? = nil,
        singleKeyOverride: String? = nil
    ) -> PackSummaryProvider.Input {
        .init(
            pack: pack,
            collection: collection,
            tapOverride: tapOverride,
            holdOverride: holdOverride,
            singleKeyOverride: singleKeyOverride
        )
    }

    // MARK: - Tap/Hold picker

    func testTapHoldUsesCollectionDefaultMapping() {
        // Caps Lock Remap's catalog collection has a dual-role mapping
        // defaulting to Hyper / Hyper — the summary should reflect that
        // when there are no live selections.
        let pack = PackRegistry.capsLockToEscape
        let catalog = RuleCollectionCatalog().defaultCollections()
        let collection = catalog.first { $0.id == pack.associatedCollectionID }
        XCTAssertNotNil(collection)

        let summary = PackSummaryProvider.summary(for: makeInput(pack: pack, collection: collection))
        XCTAssertEqual(summary, "Tap: ✦ Hyper  ·  Hold: ✦ Hyper")
    }

    func testTapHoldOverrideWinsOverCollectionDefault() {
        let pack = PackRegistry.capsLockToEscape
        let collection = RuleCollectionCatalog().defaultCollections()
            .first { $0.id == pack.associatedCollectionID }!

        let summary = PackSummaryProvider.summary(for: makeInput(
            pack: pack,
            collection: collection,
            tapOverride: "esc"
        ))
        XCTAssertEqual(summary, "Tap: ⎋ Escape  ·  Hold: ✦ Hyper")
    }

    func testTapHoldOverrideSwapsOnlyTouchedSide() {
        let pack = PackRegistry.capsLockToEscape
        let collection = RuleCollectionCatalog().defaultCollections()
            .first { $0.id == pack.associatedCollectionID }!

        let summary = PackSummaryProvider.summary(for: makeInput(
            pack: pack,
            collection: collection,
            holdOverride: "meh"
        ))
        XCTAssertEqual(summary, "Tap: ✦ Hyper  ·  Hold: ◇ Meh")
    }

    // MARK: - Single-key picker

    func testSingleKeyUsesPresetLabel() {
        let pack = PackRegistry.escapeRemap
        let collection = RuleCollectionCatalog().defaultCollections()
            .first { $0.id == pack.associatedCollectionID }!

        let summary = PackSummaryProvider.summary(for: makeInput(pack: pack, collection: collection))
        // Default is "caps" with label "⇪ Caps Lock"; input is "esc".
        XCTAssertEqual(summary, "⎋ Escape → ⇪ Caps Lock")
    }

    func testSingleKeyOverrideWins() {
        let pack = PackRegistry.escapeRemap
        let collection = RuleCollectionCatalog().defaultCollections()
            .first { $0.id == pack.associatedCollectionID }!

        let summary = PackSummaryProvider.summary(for: makeInput(
            pack: pack,
            collection: collection,
            singleKeyOverride: "tab"
        ))
        XCTAssertEqual(summary, "⎋ Escape → ⇥ Tab")
    }

    // MARK: - Multi-binding / complex

    func testHomeRowModsReturnsNil() {
        let pack = PackRegistry.homeRowMods
        let collection = RuleCollectionCatalog().defaultCollections()
            .first { $0.id == pack.associatedCollectionID }!
        let summary = PackSummaryProvider.summary(for: makeInput(pack: pack, collection: collection))
        // Multi-binding — the inline summary misrepresents the state, so
        // the provider returns nil and the header simply hides the line.
        XCTAssertNil(summary)
    }

    // MARK: - Fallback: rule-based pack

    func testFallsBackToPackTemplateWhenNoCollection() {
        // Synthesize a rule-based pack (no associated collection).
        let pack = Pack(
            id: "test.pack",
            version: "1.0.0",
            name: "Test",
            tagline: "t",
            shortDescription: "s",
            longDescription: "",
            category: "Productivity",
            iconSymbol: "star",
            bindings: [
                PackBindingTemplate(input: "a", output: "b", holdOutput: "lsft", title: nil)
            ]
        )
        let summary = PackSummaryProvider.summary(for: makeInput(pack: pack, collection: nil))
        XCTAssertEqual(summary, "Tap: b  ·  Hold: ⇧ Shift")
    }

    // MARK: - Formatter

    func testFormatKeyCoversCommonTokens() {
        XCTAssertEqual(PackSummaryProvider.formatKey("hyper"), "✦ Hyper")
        XCTAssertEqual(PackSummaryProvider.formatKey("HYPER"), "✦ Hyper") // case-insensitive
        XCTAssertEqual(PackSummaryProvider.formatKey("caps"), "⇪ Caps")
        XCTAssertEqual(PackSummaryProvider.formatKey("esc"), "⎋ Escape")
        XCTAssertEqual(PackSummaryProvider.formatKey("someCustomThing"), "someCustomThing")
    }
}
