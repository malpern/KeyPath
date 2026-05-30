@testable import KeyPathAppKit
import KeyPathCore
import XCTest

@MainActor
final class RuleCollectionsManagerAPITests: XCTestCase {
    private func makeManager() -> RuleCollectionsManager {
        RuleCollectionsManager(
            ruleCollectionStore: .shared,
            customRulesStore: .shared,
            configurationService: ConfigurationService()
        )
    }

    // MARK: - enabledMappings

    func testEnabledMappings_IncludesEnabledCollections() {
        let manager = makeManager()
        manager.ruleCollections = [
            RuleCollection(
                id: UUID(),
                name: "Enabled",
                summary: "",
                category: .custom,
                mappings: [KeyMapping(input: "a", action: .keystroke(key: "b"), description: "")],
                isEnabled: true,
                icon: "star",
                tags: [],
                targetLayer: .base,
                configuration: .list
            )
        ]
        manager.customRules = []

        let mappings = manager.enabledMappings()
        XCTAssertEqual(mappings.count, 1)
        XCTAssertEqual(mappings[0].input, "a")
    }

    func testEnabledMappings_ExcludesDisabledCollections() {
        let manager = makeManager()
        manager.ruleCollections = [
            RuleCollection(
                id: UUID(),
                name: "Disabled",
                summary: "",
                category: .custom,
                mappings: [KeyMapping(input: "a", action: .keystroke(key: "b"), description: "")],
                isEnabled: false,
                icon: "star",
                tags: [],
                targetLayer: .base,
                configuration: .list
            )
        ]
        manager.customRules = []

        let mappings = manager.enabledMappings()
        XCTAssertTrue(mappings.isEmpty)
    }

    func testEnabledMappings_IncludesEnabledCustomRules() {
        let manager = makeManager()
        manager.ruleCollections = []
        var rule = CustomRule(input: "x", action: .keystroke(key: "y"))
        rule.isEnabled = true
        manager.customRules = [rule]

        let mappings = manager.enabledMappings()
        XCTAssertEqual(mappings.count, 1)
        XCTAssertEqual(mappings[0].input, "x")
    }

    func testEnabledMappings_ExcludesDisabledCustomRules() {
        let manager = makeManager()
        manager.ruleCollections = []
        var rule = CustomRule(input: "x", action: .keystroke(key: "y"))
        rule.isEnabled = false
        manager.customRules = [rule]

        let mappings = manager.enabledMappings()
        XCTAssertTrue(mappings.isEmpty)
    }

    func testEnabledMappings_CombinesCollectionsAndCustomRules() {
        let manager = makeManager()
        manager.ruleCollections = [
            RuleCollection(
                id: UUID(),
                name: "Col",
                summary: "",
                category: .custom,
                mappings: [KeyMapping(input: "a", action: .keystroke(key: "b"), description: "")],
                isEnabled: true,
                icon: "star",
                tags: [],
                targetLayer: .base,
                configuration: .list
            )
        ]
        var rule = CustomRule(input: "c", action: .keystroke(key: "d"))
        rule.isEnabled = true
        manager.customRules = [rule]

        let mappings = manager.enabledMappings()
        XCTAssertEqual(mappings.count, 2)
    }

    // MARK: - makeCustomRule

    func testMakeCustomRule_NewInput_CreatesNew() {
        let manager = makeManager()
        manager.customRules = []

        let rule = manager.makeCustomRule(input: "caps", output: "esc")
        XCTAssertEqual(rule.input, "caps")
        XCTAssertEqual(rule.action, .keystroke(key: "esc"))
        XCTAssertTrue(rule.isEnabled)
    }

    func testMakeCustomRule_ExistingInput_PreservesID() {
        let manager = makeManager()
        let existing = CustomRule(input: "caps", action: .keystroke(key: "tab"))
        manager.customRules = [existing]

        let rule = manager.makeCustomRule(input: "caps", output: "esc")
        XCTAssertEqual(rule.id, existing.id)
        XCTAssertEqual(rule.action, .keystroke(key: "esc"))
    }

    func testMakeCustomRule_CaseInsensitiveMatch() {
        let manager = makeManager()
        let existing = CustomRule(input: "Caps", action: .keystroke(key: "tab"))
        manager.customRules = [existing]

        let rule = manager.makeCustomRule(input: "caps", output: "esc")
        XCTAssertEqual(rule.id, existing.id)
    }

    func testMakeCustomRule_RawKanataOutput() {
        let manager = makeManager()
        manager.customRules = []

        let rule = manager.makeCustomRule(input: "a", output: "(multi lctl lsft)")
        XCTAssertEqual(rule.action, .rawKanata("(multi lctl lsft)"))
    }

    // MARK: - getCustomRule

    func testGetCustomRule_Found() {
        let manager = makeManager()
        let existing = CustomRule(input: "caps", action: .keystroke(key: "esc"))
        manager.customRules = [existing]

        let found = manager.getCustomRule(forInput: "caps")
        XCTAssertNotNil(found)
        XCTAssertEqual(found?.id, existing.id)
    }

    func testGetCustomRule_CaseInsensitive() {
        let manager = makeManager()
        let existing = CustomRule(input: "Caps", action: .keystroke(key: "esc"))
        manager.customRules = [existing]

        let found = manager.getCustomRule(forInput: "CAPS")
        XCTAssertNotNil(found)
    }

    func testGetCustomRule_NotFound() {
        let manager = makeManager()
        manager.customRules = []

        let found = manager.getCustomRule(forInput: "nonexistent")
        XCTAssertNil(found)
    }

    // MARK: - normalizedActivator

    func testNormalizedActivator_WithActivator() {
        let manager = makeManager()
        let collection = RuleCollection(
            id: UUID(),
            name: "Nav",
            summary: "",
            category: .custom,
            mappings: [],
            isEnabled: true,
            icon: "star",
            tags: [],
            targetLayer: .navigation,
            momentaryActivator: MomentaryActivator(input: "space", targetLayer: .navigation),
            configuration: .list
        )

        let result = manager.normalizedActivator(for: collection)
        XCTAssertNotNil(result)
        XCTAssertEqual(result?.layer, .navigation)
    }

    func testNormalizedActivator_WithoutActivator() {
        let manager = makeManager()
        let collection = RuleCollection(
            id: UUID(),
            name: "Base",
            summary: "",
            category: .custom,
            mappings: [],
            isEnabled: true,
            icon: "star",
            tags: [],
            targetLayer: .base,
            configuration: .list
        )

        let result = manager.normalizedActivator(for: collection)
        XCTAssertNil(result)
    }

    // MARK: - updateActiveLayerName

    func testUpdateActiveLayerName_SetsCurrentLayerName() {
        let manager = makeManager()
        manager.updateActiveLayerName("nav")
        XCTAssertEqual(manager.currentLayerName, "Nav")
    }

    func testUpdateActiveLayerName_EmptyString_DefaultsToBase() {
        let manager = makeManager()
        manager.updateActiveLayerName("nav")
        manager.updateActiveLayerName("")
        XCTAssertEqual(manager.currentLayerName, "Base")
    }

    func testUpdateActiveLayerName_CallsOnLayerChanged() {
        let manager = makeManager()
        var changedTo: String?
        manager.onLayerChanged = { changedTo = $0 }

        manager.updateActiveLayerName("nav")
        XCTAssertEqual(changedTo, "Nav")
    }

    func testUpdateActiveLayerName_SameValue_DoesNotCallCallback() {
        let manager = makeManager()
        manager.updateActiveLayerName("nav")

        var called = false
        manager.onLayerChanged = { _ in called = true }
        manager.updateActiveLayerName("nav")
        XCTAssertFalse(called)
    }
}
