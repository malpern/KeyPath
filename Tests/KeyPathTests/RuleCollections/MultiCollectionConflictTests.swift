@testable import KeyPathAppKit
@testable import KeyPathCore
@preconcurrency import XCTest

@MainActor
final class MultiCollectionConflictTests: XCTestCase {
    private func makeManager() -> RuleCollectionsManager {
        RuleCollectionsManager(
            ruleCollectionStore: .shared,
            customRulesStore: .shared,
            configurationService: ConfigurationService()
        )
    }

    private func collection(
        name: String,
        mappings: [(String, String)],
        layer: RuleCollectionLayer = .base,
        enabled: Bool = true,
        activator: MomentaryActivator? = nil
    ) -> RuleCollection {
        RuleCollection(
            id: UUID(),
            name: name,
            summary: name,
            category: .custom,
            mappings: mappings.map { KeyMapping(input: $0.0, action: .keystroke(key: $0.1)) },
            isEnabled: enabled,
            icon: "star",
            tags: [],
            targetLayer: layer,
            momentaryActivator: activator,
            configuration: .list
        )
    }

    // MARK: - 3-Way Conflict Detection (Deduplicator)

    func testDeduplicator_ThreeWayConflict() {
        let a = collection(name: "A", mappings: [("a", "1")])
        let b = collection(name: "B", mappings: [("a", "2")])
        let c = collection(name: "C", mappings: [("a", "3")])

        let conflicts = RuleCollectionDeduplicator.detectConflicts(in: [a, b, c])
        XCTAssertEqual(conflicts.count, 1)
        XCTAssertEqual(conflicts.first?.inputKey, "a")
        XCTAssertEqual(conflicts.first?.conflictingCollections.count, 3)
        XCTAssertTrue(conflicts.first?.conflictingCollections.contains("A") ?? false)
        XCTAssertTrue(conflicts.first?.conflictingCollections.contains("B") ?? false)
        XCTAssertTrue(conflicts.first?.conflictingCollections.contains("C") ?? false)
    }

    func testDeduplicator_ThreeWayConflict_MultipleKeys() {
        let a = collection(name: "A", mappings: [("a", "1"), ("b", "2")])
        let b = collection(name: "B", mappings: [("a", "3"), ("b", "4")])
        let c = collection(name: "C", mappings: [("a", "5")])

        let conflicts = RuleCollectionDeduplicator.detectConflicts(in: [a, b, c])
        let conflictKeys = Set(conflicts.map(\.inputKey))
        XCTAssertTrue(conflictKeys.contains("a"))
        XCTAssertTrue(conflictKeys.contains("b"))

        let aConflict = conflicts.first(where: { $0.inputKey == "a" })
        XCTAssertEqual(aConflict?.conflictingCollections.count, 3)

        let bConflict = conflicts.first(where: { $0.inputKey == "b" })
        XCTAssertEqual(bConflict?.conflictingCollections.count, 2)
    }

    func testDeduplicator_ThreeWayConflict_OneDisabled() {
        let a = collection(name: "A", mappings: [("a", "1")])
        let b = collection(name: "B", mappings: [("a", "2")], enabled: false)
        let c = collection(name: "C", mappings: [("a", "3")])

        let conflicts = RuleCollectionDeduplicator.detectConflicts(in: [a, b, c])
        XCTAssertEqual(conflicts.count, 1)
        XCTAssertEqual(conflicts.first?.conflictingCollections.count, 2)
        XCTAssertFalse(
            conflicts.first?.conflictingCollections.contains("B") ?? true,
            "Disabled collection should not be in conflict list"
        )
    }

    // MARK: - Conflict Resolution Cascade

    func testConflictInfo_RevealedConflictAfterDisabling() {
        let manager = makeManager()
        let first = collection(name: "First", mappings: [("a", "1")])
        let second = collection(name: "Second", mappings: [("a", "2")])
        let third = collection(name: "Third", mappings: [("a", "3")])

        manager.ruleCollections = [first, second]
        let conflictWithSecond = manager.conflictInfo(for: third)
        XCTAssertNotNil(conflictWithSecond, "Third conflicts with existing enabled collections")

        var disabledSecond = second
        disabledSecond.isEnabled = false
        manager.ruleCollections = [first, disabledSecond]
        let conflictWithFirst = manager.conflictInfo(for: third)
        XCTAssertNotNil(conflictWithFirst, "Third still conflicts with First even after Second disabled")
        XCTAssertTrue(conflictWithFirst?.keys.contains("a") ?? false)
    }

    func testConflictInfo_NoConflictAfterAllDisabled() {
        let manager = makeManager()
        var first = collection(name: "First", mappings: [("a", "1")])
        first.isEnabled = false
        var second = collection(name: "Second", mappings: [("a", "2")])
        second.isEnabled = false

        manager.ruleCollections = [first, second]
        let third = collection(name: "Third", mappings: [("a", "3")])
        let conflict = manager.conflictInfo(for: third)
        XCTAssertNil(conflict, "No conflict when all existing collections are disabled")
    }

    // MARK: - Activator Conflicts

    func testConflictInfo_DifferentActivatorsSameKey() {
        let manager = makeManager()
        let navA = collection(
            name: "Nav A",
            mappings: [("h", "left")],
            layer: .navigation,
            activator: MomentaryActivator(input: "space", targetLayer: .navigation)
        )
        let navB = collection(
            name: "Nav B",
            mappings: [("j", "down")],
            layer: .custom("symbols"),
            activator: MomentaryActivator(input: "space", targetLayer: .custom("symbols"))
        )

        manager.ruleCollections = [navA]
        let conflict = manager.conflictInfo(for: navB)
        XCTAssertNotNil(
            conflict,
            "Same key ('space') with different target layers should conflict"
        )
    }

    func testConflictInfo_IdenticalActivatorsNoConflict() {
        let manager = makeManager()
        let navA = collection(
            name: "Nav A",
            mappings: [("h", "left")],
            layer: .navigation,
            activator: MomentaryActivator(input: "space", targetLayer: .navigation)
        )
        let navB = collection(
            name: "Nav B",
            mappings: [("j", "down")],
            layer: .navigation,
            activator: MomentaryActivator(input: "space", targetLayer: .navigation)
        )

        manager.ruleCollections = [navA]
        let conflict = manager.conflictInfo(for: navB)
        XCTAssertNil(
            conflict,
            "Identical activators are redundant (not conflicts) and non-overlapping keys should pass"
        )
    }

    func testConflictInfo_DifferentActivatorKeys() {
        let manager = makeManager()
        let navA = collection(
            name: "Nav A",
            mappings: [("h", "left")],
            layer: .navigation,
            activator: MomentaryActivator(input: "space", targetLayer: .navigation)
        )
        let navB = collection(
            name: "Nav B",
            mappings: [("j", "down")],
            layer: .custom("symbols"),
            activator: MomentaryActivator(input: "tab", targetLayer: .custom("symbols"))
        )

        manager.ruleCollections = [navA]
        let conflict = manager.conflictInfo(for: navB)
        XCTAssertNil(
            conflict,
            "Different activator keys on different layers should not conflict"
        )
    }

    // MARK: - Cross-Layer Edge Cases

    func testConflictInfo_SameKeyDifferentLayersNoConflict() {
        let manager = makeManager()
        let base = collection(name: "Base", mappings: [("h", "h")], layer: .base)
        let nav = collection(name: "Nav", mappings: [("h", "left")], layer: .navigation)

        manager.ruleCollections = [base]
        let conflict = manager.conflictInfo(for: nav)
        XCTAssertNil(conflict, "Same key on different layers should not conflict")
    }

    func testConflictInfo_CustomLayerConflict() {
        let manager = makeManager()
        let window1 = collection(name: "Window A", mappings: [("h", "left")], layer: .custom("window"))
        let window2 = collection(name: "Window B", mappings: [("h", "right")], layer: .custom("window"))

        manager.ruleCollections = [window1]
        let conflict = manager.conflictInfo(for: window2)
        XCTAssertNotNil(conflict, "Same key on same custom layer should conflict")
    }

    func testConflictInfo_DifferentCustomLayersNoConflict() {
        let manager = makeManager()
        let window = collection(name: "Window", mappings: [("h", "left")], layer: .custom("window"))
        let symbols = collection(name: "Symbols", mappings: [("h", "!")])

        var symbolsOnCustom = symbols
        symbolsOnCustom = collection(name: "Symbols", mappings: [("h", "!")], layer: .custom("symbols"))

        manager.ruleCollections = [window]
        let conflict = manager.conflictInfo(for: symbolsOnCustom)
        XCTAssertNil(conflict, "Same key on different custom layers should not conflict")
    }

    // MARK: - Deduplicator Multi-Collection Ordering

    func testDeduplicator_FirstCollectionWins() {
        let a = collection(name: "A", mappings: [("caps", "esc")])
        let b = collection(name: "B", mappings: [("caps", "tab")])
        let c = collection(name: "C", mappings: [("caps", "ret")])

        let deduped = RuleCollectionDeduplicator.dedupe([a, b, c])
        XCTAssertEqual(deduped[0].mappings.count, 1, "First collection keeps its mapping")
        XCTAssertEqual(deduped[1].mappings.count, 0, "Second collection's duplicate removed")
        XCTAssertEqual(deduped[2].mappings.count, 0, "Third collection's duplicate removed")
    }

    func testDeduplicator_MixedLayersNotDeduped() {
        let base = collection(name: "Base", mappings: [("h", "h")], layer: .base)
        let nav = collection(name: "Nav", mappings: [("h", "left")], layer: .navigation)

        let deduped = RuleCollectionDeduplicator.dedupe([base, nav])
        XCTAssertEqual(deduped[0].mappings.count, 1)
        XCTAssertEqual(deduped[1].mappings.count, 1, "Different layers should not deduplicate")
    }

    func testDeduplicator_DisabledCollectionNotCounted() {
        let enabled = collection(name: "Enabled", mappings: [("a", "x")])
        let disabled = collection(name: "Disabled", mappings: [("a", "y")], enabled: false)
        let another = collection(name: "Another", mappings: [("a", "z")])

        let deduped = RuleCollectionDeduplicator.dedupe([enabled, disabled, another])
        XCTAssertEqual(deduped[0].mappings.count, 1, "First enabled keeps mapping")
        XCTAssertEqual(deduped[1].mappings.count, 1, "Disabled collection untouched")
        XCTAssertEqual(deduped[2].mappings.count, 0, "Third enabled loses to first")
    }

    // MARK: - Deduplicator Activator Conflicts

    func testDeduplicator_DuplicateActivatorRemoved() {
        let a = collection(
            name: "A", mappings: [("h", "left")], layer: .navigation,
            activator: MomentaryActivator(input: "space", targetLayer: .navigation)
        )
        let b = collection(
            name: "B", mappings: [("j", "down")], layer: .navigation,
            activator: MomentaryActivator(input: "space", targetLayer: .navigation)
        )

        let deduped = RuleCollectionDeduplicator.dedupe([a, b])
        XCTAssertNotNil(deduped[0].momentaryActivator, "First keeps activator")
        XCTAssertNil(deduped[1].momentaryActivator, "Second's duplicate activator removed")
    }

    // MARK: - Neovim Terminal Exclusion

    func testConflictInfo_NeovimTerminalNeverConflicts() {
        let manager = makeManager()
        let nav = collection(name: "Nav", mappings: [("h", "left")], layer: .navigation)
        manager.ruleCollections = [nav]

        let neovim = RuleCollection(
            id: RuleCollectionIdentifier.neovimTerminal,
            name: "Neovim Terminal",
            summary: "Reference",
            category: .custom,
            mappings: [KeyMapping(input: "h", action: .keystroke(key: "left"))],
            isEnabled: true,
            targetLayer: .navigation
        )
        let conflict = manager.conflictInfo(for: neovim)
        XCTAssertNil(conflict, "Neovim Terminal should never conflict")
    }

    func testConflictInfo_ExistingNeovimDoesNotBlockNew() {
        let manager = makeManager()
        let neovim = RuleCollection(
            id: RuleCollectionIdentifier.neovimTerminal,
            name: "Neovim Terminal",
            summary: "Reference",
            category: .custom,
            mappings: [KeyMapping(input: "h", action: .keystroke(key: "left"))],
            isEnabled: true,
            targetLayer: .navigation
        )
        manager.ruleCollections = [neovim]

        let nav = collection(name: "Nav", mappings: [("h", "left")], layer: .navigation)
        let conflict = manager.conflictInfo(for: nav)
        XCTAssertNil(conflict, "Neovim Terminal in collections should not block new collections")
    }

    // MARK: - Custom Rule vs Collection Conflicts

    func testConflictInfo_CustomRuleConflictsWithMultipleCollections() {
        let manager = makeManager()
        let collA = collection(name: "A", mappings: [("caps", "esc")])
        manager.ruleCollections = [collA]

        let rule = CustomRule(input: "caps", action: .keystroke(key: "tab"))
        let conflict = manager.conflictInfo(for: rule)
        XCTAssertNotNil(conflict, "Custom rule should detect collection conflict")
    }

    func testConflictInfo_CustomRuleNoConflictDifferentLayer() {
        let manager = makeManager()
        let nav = collection(name: "Nav", mappings: [("h", "left")], layer: .navigation)
        manager.ruleCollections = [nav]

        var rule = CustomRule(input: "h", action: .keystroke(key: "right"))
        rule.targetLayer = .base
        let conflict = manager.conflictInfo(for: rule)
        XCTAssertNil(conflict, "Custom rule on different layer should not conflict")
    }

    func testConflictInfo_CustomRuleConflictsWithOtherCustomRule() {
        let manager = makeManager()
        manager.ruleCollections = []

        var existing = CustomRule(input: "caps", action: .keystroke(key: "esc"))
        existing.isEnabled = true
        manager.customRules = [existing]

        let newRule = CustomRule(input: "caps", action: .keystroke(key: "tab"))
        let conflict = manager.conflictInfo(for: newRule)
        XCTAssertNotNil(conflict)
    }

    func testConflictInfo_DisabledCustomRuleNoConflict() {
        let manager = makeManager()
        manager.ruleCollections = []

        var existing = CustomRule(input: "caps", action: .keystroke(key: "esc"))
        existing.isEnabled = false
        manager.customRules = [existing]

        let newRule = CustomRule(input: "caps", action: .keystroke(key: "tab"))
        let conflict = manager.conflictInfo(for: newRule)
        XCTAssertNil(conflict, "Disabled custom rule should not conflict")
    }

    // MARK: - Key Normalization in Conflicts

    func testConflictInfo_NormalizesKeyNames() {
        let manager = makeManager()
        let collWithCaps = collection(name: "Caps", mappings: [("caps", "esc")])
        manager.ruleCollections = [collWithCaps]

        let collWithCapslock = collection(name: "CapsLock", mappings: [("capslock", "tab")])
        let conflict = manager.conflictInfo(for: collWithCapslock)
        XCTAssertNotNil(conflict, "'caps' and 'capslock' should normalize to same key")
    }

    func testConflictInfo_NormalizesModifierNames() {
        let manager = makeManager()
        let collA = collection(name: "A", mappings: [("left shift", "x")])
        manager.ruleCollections = [collA]

        let collB = collection(name: "B", mappings: [("lshift", "y")])
        let conflict = manager.conflictInfo(for: collB)
        XCTAssertNotNil(conflict, "'left shift' and 'lshift' should normalize to same key")
    }

    // MARK: - Conflict Description

    func testMappingConflictInfo_Description() {
        let info = KeyPathError.MappingConflictInfo(
            inputKey: "a",
            layer: "Base",
            conflictingCollections: ["HRM", "Layer Toggles", "Custom Rule"]
        )
        let desc = info.description
        XCTAssertTrue(desc.contains("a"))
        XCTAssertTrue(desc.contains("HRM"))
        XCTAssertTrue(desc.contains("Base"))
    }

    func testMappingConflictInfo_HoldDescriptions() {
        let info = KeyPathError.MappingConflictInfo(
            inputKey: "a",
            layer: "Base",
            conflictingCollections: ["HRM", "Toggles"],
            holdDescriptions: ["HRM: hold → lsft", "Toggles: hold → nav"]
        )
        XCTAssertEqual(info.holdDescriptions.count, 2)
        XCTAssertTrue(info.holdDescriptions[0].contains("lsft"))
    }
}
