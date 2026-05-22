@testable import KeyPathAppKit
import KeyPathCore
import XCTest

@MainActor
final class RuleCollectionConflictDetectionTests: XCTestCase {

    private func makeManager() -> RuleCollectionsManager {
        RuleCollectionsManager(
            ruleCollectionStore: .shared,
            customRulesStore: .shared,
            configurationService: ConfigurationService()
        )
    }

    // MARK: - normalizedKeys

    func testNormalizedKeys_ExtractsInputKeys() {
        let manager = makeManager()
        let collection = RuleCollection(
            id: UUID(),
            name: "Test",
            summary: "Test",
            category: .custom,
            mappings: [
                KeyMapping(input: "caps", action: .keystroke(key: "esc"), description: ""),
                KeyMapping(input: "a", action: .keystroke(key: "lctl"), description: ""),
            ],
            isEnabled: true,
            icon: "star",
            tags: [],
            targetLayer: .base,
            configuration: .list
        )

        let keys = manager.normalizedKeys(for: collection)
        XCTAssertTrue(keys.contains("caps"))
        XCTAssertTrue(keys.contains("a"))
        XCTAssertEqual(keys.count, 2)
    }

    // MARK: - conflictInfo(for collection:)

    func testConflictInfo_NoConflict_WhenNoOverlap() {
        let manager = makeManager()
        let collection1 = RuleCollection(
            id: UUID(),
            name: "A",
            summary: "",
            category: .custom,
            mappings: [KeyMapping(input: "a", action: .keystroke(key: "b"), description: "")],
            isEnabled: true,
            icon: "star",
            tags: [],
            targetLayer: .base,
            configuration: .list
        )
        let collection2 = RuleCollection(
            id: UUID(),
            name: "B",
            summary: "",
            category: .custom,
            mappings: [KeyMapping(input: "c", action: .keystroke(key: "d"), description: "")],
            isEnabled: false,
            icon: "star",
            tags: [],
            targetLayer: .base,
            configuration: .list
        )

        manager.ruleCollections = [collection1]
        let conflict = manager.conflictInfo(for: collection2)
        XCTAssertNil(conflict)
    }

    func testConflictInfo_DetectsOverlap_SameLayer() {
        let manager = makeManager()
        let collection1 = RuleCollection(
            id: UUID(),
            name: "First",
            summary: "",
            category: .custom,
            mappings: [KeyMapping(input: "a", action: .keystroke(key: "x"), description: "")],
            isEnabled: true,
            icon: "star",
            tags: [],
            targetLayer: .base,
            configuration: .list
        )
        let collection2 = RuleCollection(
            id: UUID(),
            name: "Second",
            summary: "",
            category: .custom,
            mappings: [KeyMapping(input: "a", action: .keystroke(key: "y"), description: "")],
            isEnabled: true,
            icon: "star",
            tags: [],
            targetLayer: .base,
            configuration: .list
        )

        manager.ruleCollections = [collection1]
        let conflict = manager.conflictInfo(for: collection2)
        XCTAssertNotNil(conflict)
        XCTAssertTrue(conflict!.keys.contains("a"))
    }

    func testConflictInfo_NoConflict_DifferentLayers() {
        let manager = makeManager()
        let collection1 = RuleCollection(
            id: UUID(),
            name: "Base",
            summary: "",
            category: .custom,
            mappings: [KeyMapping(input: "a", action: .keystroke(key: "x"), description: "")],
            isEnabled: true,
            icon: "star",
            tags: [],
            targetLayer: .base,
            configuration: .list
        )
        let collection2 = RuleCollection(
            id: UUID(),
            name: "Nav",
            summary: "",
            category: .custom,
            mappings: [KeyMapping(input: "a", action: .keystroke(key: "y"), description: "")],
            isEnabled: true,
            icon: "star",
            tags: [],
            targetLayer: .navigation,
            configuration: .list
        )

        manager.ruleCollections = [collection1]
        let conflict = manager.conflictInfo(for: collection2)
        XCTAssertNil(conflict)
    }

    func testConflictInfo_IgnoresDisabledCollections() {
        let manager = makeManager()
        let collection1 = RuleCollection(
            id: UUID(),
            name: "Disabled",
            summary: "",
            category: .custom,
            mappings: [KeyMapping(input: "a", action: .keystroke(key: "x"), description: "")],
            isEnabled: false,
            icon: "star",
            tags: [],
            targetLayer: .base,
            configuration: .list
        )
        let collection2 = RuleCollection(
            id: UUID(),
            name: "New",
            summary: "",
            category: .custom,
            mappings: [KeyMapping(input: "a", action: .keystroke(key: "y"), description: "")],
            isEnabled: true,
            icon: "star",
            tags: [],
            targetLayer: .base,
            configuration: .list
        )

        manager.ruleCollections = [collection1]
        let conflict = manager.conflictInfo(for: collection2)
        XCTAssertNil(conflict)
    }

    // MARK: - conflictInfo(for customRule:)

    func testConflictInfo_CustomRule_DetectsCollectionConflict() {
        let manager = makeManager()
        let collection = RuleCollection(
            id: UUID(),
            name: "Caps Remap",
            summary: "",
            category: .custom,
            mappings: [KeyMapping(input: "caps", action: .keystroke(key: "esc"), description: "")],
            isEnabled: true,
            icon: "star",
            tags: [],
            targetLayer: .base,
            configuration: .list
        )
        manager.ruleCollections = [collection]

        let rule = CustomRule(input: "caps", action: .keystroke(key: "backspace"))
        let conflict = manager.conflictInfo(for: rule)
        XCTAssertNotNil(conflict)
    }

    func testConflictInfo_CustomRule_DetectsOtherCustomRuleConflict() {
        let manager = makeManager()
        manager.ruleCollections = []

        let existing = CustomRule(input: "a", action: .keystroke(key: "b"))
        var existingEnabled = existing
        existingEnabled.isEnabled = true
        manager.customRules = [existingEnabled]

        let newRule = CustomRule(input: "a", action: .keystroke(key: "c"))
        let conflict = manager.conflictInfo(for: newRule)
        XCTAssertNotNil(conflict)
    }

    // MARK: - conflictWithCustomRules

    func testConflictWithCustomRules_FindsMatchingKey() {
        let manager = makeManager()
        var rule = CustomRule(input: "x", action: .keystroke(key: "y"))
        rule.isEnabled = true
        manager.customRules = [rule]

        let conflict = manager.conflictWithCustomRules(Set(["x"]), layer: .base)
        XCTAssertNotNil(conflict)
    }

    func testConflictWithCustomRules_NoMatchWhenDifferentLayer() {
        let manager = makeManager()
        var rule = CustomRule(input: "x", action: .keystroke(key: "y"))
        rule.isEnabled = true
        rule.targetLayer = .base
        manager.customRules = [rule]

        let conflict = manager.conflictWithCustomRules(Set(["x"]), layer: .navigation)
        XCTAssertNil(conflict)
    }

    func testConflictWithCustomRules_NoMatchWhenDisabled() {
        let manager = makeManager()
        var rule = CustomRule(input: "x", action: .keystroke(key: "y"))
        rule.isEnabled = false
        manager.customRules = [rule]

        let conflict = manager.conflictWithCustomRules(Set(["x"]), layer: .base)
        XCTAssertNil(conflict)
    }

    // MARK: - RuleConflictInfo

    func testRuleConflictInfo_DisplayName_Collection() {
        let collection = RuleCollection(
            id: UUID(),
            name: "My Collection",
            summary: "",
            category: .custom,
            mappings: [],
            isEnabled: true,
            icon: "star",
            tags: [],
            targetLayer: .base,
            configuration: .list
        )
        let info = RuleConflictInfo(source: .collection(collection), keys: ["a"])
        XCTAssertEqual(info.displayName, "My Collection")
    }

    func testRuleConflictInfo_DisplayName_CustomRule() {
        let rule = CustomRule(input: "a", action: .keystroke(key: "b"))
        let info = RuleConflictInfo(source: .customRule(rule), keys: ["a"])
        XCTAssertFalse(info.displayName.isEmpty)
    }
}
