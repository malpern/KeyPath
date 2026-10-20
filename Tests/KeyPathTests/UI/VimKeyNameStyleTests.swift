@testable import KeyPathAppKit
import KeyPathRulesCore
import XCTest

@MainActor
final class VimKeyNameStyleTests: XCTestCase {
    private var defaults: UserDefaults!
    private let suite = "VimKeyNameStyleTests"
    private var savedStandard: Any?

    override func setUp() async throws {
        try await super.setUp()
        defaults = UserDefaults(suiteName: suite)
        defaults.removePersistentDomain(forName: suite)
        savedStandard = UserDefaults.standard.object(forKey: VimKeyNameStyle.defaultsKey)
    }

    override func tearDown() async throws {
        defaults.removePersistentDomain(forName: suite)
        UserDefaults.standard.set(savedStandard, forKey: VimKeyNameStyle.defaultsKey)
        try await super.tearDown()
    }

    func testDefaultsArePlainForVimAndVimTermsForNeovim() {
        XCTAssertEqual(VimKeyNameStyle.current(for: RuleCollectionIdentifier.vimNavigation, defaults: defaults), .plain)
        XCTAssertEqual(VimKeyNameStyle.current(for: RuleCollectionIdentifier.neovimTerminal, defaults: defaults), .vim)
    }

    func testEachPackKeepsItsOwnChoice() {
        VimKeyNameStyle.set(.vim, for: RuleCollectionIdentifier.vimNavigation, defaults: defaults)
        XCTAssertEqual(VimKeyNameStyle.current(for: RuleCollectionIdentifier.vimNavigation, defaults: defaults), .vim)
        XCTAssertEqual(VimKeyNameStyle.current(for: RuleCollectionIdentifier.neovimTerminal, defaults: defaults), .vim,
                       "changing Vim leaves Neovim at its own default")
        VimKeyNameStyle.set(.plain, for: RuleCollectionIdentifier.neovimTerminal, defaults: defaults)
        XCTAssertEqual(VimKeyNameStyle.current(for: RuleCollectionIdentifier.neovimTerminal, defaults: defaults), .plain)
    }

    func testCacheSignatureChangesWithEitherPack() {
        let before = VimKeyNameStyle.cacheSignature(defaults: defaults)
        VimKeyNameStyle.set(.vim, for: RuleCollectionIdentifier.vimNavigation, defaults: defaults)
        XCTAssertNotEqual(VimKeyNameStyle.cacheSignature(defaults: defaults), before)
    }

    func testBothColumnsNameEveryShippedKey() throws {
        let vim = try XCTUnwrap(RuleCollectionCatalog().defaultCollections().first { $0.id == RuleCollectionIdentifier.neovimTerminal })
        for mapping in vim.mappings {
            let plain = try XCTUnwrap(VimLayerReference.presentation(forInput: mapping.input, style: .plain), mapping.input)
            let terms = try XCTUnwrap(VimLayerReference.presentation(forInput: mapping.input, style: .vim), mapping.input)
            XCTAssertLessThanOrEqual(terms.keycapLabel.count, 6, "\(mapping.input) fits a keycap")
            XCTAssertEqual(plain.category, terms.category, "\(mapping.input) stays in the same group")
        }
        let y = try XCTUnwrap(VimLayerReference.presentation(forInput: "y", style: .vim))
        XCTAssertEqual([y.keycapLabel, y.title], ["yank", "Yank"])
        let g = try XCTUnwrap(VimLayerReference.presentation(forInput: "g", style: .vim))
        XCTAssertEqual(g.keycapLabel, "gg")
        let h = try XCTUnwrap(VimLayerReference.presentation(forInput: "h", style: .vim))
        XCTAssertEqual(h.keycapLabel, "←", "arrows stay arrows in both styles")
    }

    func testVariantsUseVimNotationInVimTerms() {
        let g = KeyMapping(input: "g", action: .keystroke(key: "M-up"), shiftedOutput: "M-down")
        XCTAssertEqual(VimLayerReference.entry(for: g, style: .vim).shift?.title, "Go to last line")
        XCTAssertEqual(VimLayerReference.entry(for: g, style: .plain).shift?.title, "Bottom of document")
    }

    func testShortcutListFollowsEachPacksStyle() throws {
        let catalog = RuleCollectionCatalog().defaultCollections()
        let vim = try XCTUnwrap(catalog.first { $0.id == RuleCollectionIdentifier.vimNavigation })
        let keyMap: [UInt16: LayerKeyInfo] = [
            16: .mapped(displayLabel: "C⌘", outputKey: "c", outputKeyCode: nil, collectionId: vim.id) // y
        ]
        let vm = ContextHUDViewModel()

        VimKeyNameStyle.set(.plain, for: vim.id)
        vm.update(layerName: "nav", keyMap: keyMap, collections: [vim], style: .defaultList)
        XCTAssertEqual(vm.groups.flatMap(\.entries).map(\.action), ["Copy"])

        VimKeyNameStyle.set(.vim, for: vim.id)
        vm.update(layerName: "nav", keyMap: keyMap, collections: [vim], style: .defaultList)
        XCTAssertEqual(vm.groups.flatMap(\.entries).map(\.action), ["Yank"])
    }
}
