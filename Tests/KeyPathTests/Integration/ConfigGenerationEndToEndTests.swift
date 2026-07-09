@testable import KeyPathAppKit
import KeyPathCore
import KeyPathRulesCore
import XCTest

/// End-to-end tests for the Kanata config generation pipeline.
/// These test the full path from RuleCollections → KanataConfiguration.generateFromCollections → .kbd output,
/// verifying that critical kanata blocks appear correctly in generated configs.
@MainActor
final class ConfigGenerationEndToEndTests: XCTestCase {
    private func generateConfig(
        collections: [RuleCollection],
        customRules: [CustomRule] = []
    ) -> String {
        let customRuleCollections = customRules.asRuleCollections()
        let all = customRuleCollections + collections
        let deduped = RuleCollectionDeduplicator.dedupe(all)
        return KanataConfiguration.generateFromCollections(deduped)
    }

    // MARK: - Basic structure

    func testGeneratedConfig_ContainsDefcfg() {
        let collections = [RuleCollectionCatalog().defaultCollections().first!]
        let config = generateConfig(collections: collections)
        XCTAssertTrue(config.contains("(defcfg"), "Config must contain defcfg block")
    }

    func testGeneratedConfig_ContainsDefsrc() {
        let collections = [RuleCollectionCatalog().defaultCollections().first!]
        let config = generateConfig(collections: collections)
        XCTAssertTrue(config.contains("(defsrc"), "Config must contain defsrc block")
    }

    func testGeneratedConfig_ContainsDeflayer() {
        let collections = [RuleCollectionCatalog().defaultCollections().first!]
        let config = generateConfig(collections: collections)
        XCTAssertTrue(config.contains("(deflayer"), "Config must contain deflayer block")
    }

    func testGeneratedConfig_ContainsDefvar() {
        let collections = RuleCollectionCatalog().defaultCollections()
        let config = generateConfig(collections: collections)
        XCTAssertTrue(config.contains("(defvar"), "Config should contain defvar block for timing variables")
    }

    func testDefcfg_ContainsProcessUnmappedKeys() {
        let collections = [RuleCollectionCatalog().defaultCollections().first!]
        let config = generateConfig(collections: collections)
        XCTAssertTrue(config.contains("process-unmapped-keys"),
                      "defcfg should specify process-unmapped-keys for safety")
    }

    // MARK: - Custom rules

    func testCustomRule_SimpleRemap_AppearsInConfig() {
        let macFK = RuleCollectionCatalog().defaultCollections().first!
        let rule = CustomRule(input: "caps", action: .keystroke(key: "esc"))
        let config = generateConfig(collections: [macFK], customRules: [rule])
        XCTAssertTrue(config.contains("esc"), "Config should contain the remapped output 'esc'")
    }

    func testCustomRule_TapHold_ProducesTapHoldInConfig() {
        let macFK = RuleCollectionCatalog().defaultCollections().first!
        let rule = CustomRule(
            input: "a",
            action: .keystroke(key: "a"),
            behavior: .dualRole(DualRoleBehavior.homeRowMod(letter: "a", modifier: "lctl"))
        )
        let config = generateConfig(collections: [macFK], customRules: [rule])
        XCTAssertTrue(config.contains("tap-hold"), "Custom rule with dual-role should produce tap-hold")
        XCTAssertTrue(config.contains("lctl"), "Custom rule should contain the hold modifier")
    }

    // MARK: - Home Row Mods

    func testHRM_ProducesTapHoldInOutput() {
        var collections = RuleCollectionCatalog().defaultCollections()
        if let idx = collections.firstIndex(where: { $0.id == RuleCollectionIdentifier.homeRowMods }) {
            collections[idx].isEnabled = true
            collections[idx].configuration = .homeRowMods(HomeRowModsConfig())
        }
        let config = generateConfig(collections: collections)
        XCTAssertTrue(config.contains("tap-hold"), "HRM config should produce tap-hold expressions")
    }

    func testHRM_AllModifiers_PresentInConfig() {
        var collections = RuleCollectionCatalog().defaultCollections()
        var hrmConfig = HomeRowModsConfig()
        hrmConfig.enabledKeys = Set(["a", "s", "d", "f"])
        hrmConfig.modifierAssignments = ["a": "lctl", "s": "lalt", "d": "lsft", "f": "lmet"]
        if let idx = collections.firstIndex(where: { $0.id == RuleCollectionIdentifier.homeRowMods }) {
            collections[idx].isEnabled = true
            collections[idx].configuration = .homeRowMods(hrmConfig)
        }
        let config = generateConfig(collections: collections)
        XCTAssertTrue(config.contains("lctl"), "Config should contain lctl")
        XCTAssertTrue(config.contains("lalt"), "Config should contain lalt")
        XCTAssertTrue(config.contains("lsft"), "Config should contain lsft")
        XCTAssertTrue(config.contains("lmet"), "Config should contain lmet")
    }

    // MARK: - Caps Lock tap-hold picker

    func testCapsLockRemap_ProducesTapHold() {
        var collections = RuleCollectionCatalog().defaultCollections()
        if let idx = collections.firstIndex(where: { $0.id == RuleCollectionIdentifier.capsLockRemap }) {
            collections[idx].isEnabled = true
        }
        let config = generateConfig(collections: collections)
        XCTAssertTrue(config.contains("tap-hold"), "Caps Lock Remap should produce tap-hold")
    }

    // MARK: - Navigation layer

    func testVimNavigation_ProducesLayerDefinition() {
        var collections = RuleCollectionCatalog().defaultCollections()
        if let idx = collections.firstIndex(where: { $0.id == RuleCollectionIdentifier.vimNavigation }) {
            collections[idx].isEnabled = true
        }
        let config = generateConfig(collections: collections)
        XCTAssertTrue(config.contains("deflayer"), "Vim Navigation should produce a layer definition")
    }

    // MARK: - Function keys

    func testFunctionKeys_ProducesMediaKeyMappings() {
        var collections = RuleCollectionCatalog().defaultCollections()
        if let idx = collections.firstIndex(where: { $0.id == RuleCollectionIdentifier.macFunctionKeys }) {
            collections[idx].isEnabled = true
        }
        let config = generateConfig(collections: collections)
        XCTAssertTrue(config.contains("brdn") || config.contains("brup") || config.contains("pp"),
                      "Function keys should contain media key outputs")
    }

    // MARK: - Disabled collections

    func testDisabledCollection_ExcludedFromConfig() {
        var collections = RuleCollectionCatalog().defaultCollections()
        for i in collections.indices {
            collections[i].isEnabled = false
        }
        let config = generateConfig(collections: collections)
        XCTAssertFalse(config.contains("tap-hold-press"),
                       "Disabled HRM should not produce tap-hold-press in config")
    }

    // MARK: - Auto-shift symbols

    func testAutoShift_ProducesTapHoldWithShiftedOutputs() {
        var collections = RuleCollectionCatalog().defaultCollections()
        if let idx = collections.firstIndex(where: { $0.id == RuleCollectionIdentifier.autoShiftSymbols }) {
            var asConfig = AutoShiftSymbolsConfig()
            asConfig.enabledKeys = Set(["min", "eql"])
            collections[idx].isEnabled = true
            collections[idx].configuration = .autoShiftSymbols(asConfig)
        }
        let config = generateConfig(collections: collections)
        XCTAssertTrue(config.contains("tap-hold"), "Auto-shift should produce tap-hold")
        XCTAssertTrue(config.contains("S-min") || config.contains("S-eql"),
                      "Auto-shift should contain shifted outputs")
    }

    // MARK: - Balanced parentheses (critical safety check)

    func testGeneratedConfig_HasBalancedParentheses() {
        var collections = RuleCollectionCatalog().defaultCollections()
        for i in collections.indices where collections[i].id == RuleCollectionIdentifier.capsLockRemap
            || collections[i].id == RuleCollectionIdentifier.macFunctionKeys
        {
            collections[i].isEnabled = true
        }
        let config = generateConfig(collections: collections)
        let openCount = config.filter { $0 == "(" }.count
        let closeCount = config.filter { $0 == ")" }.count
        XCTAssertEqual(openCount, closeCount,
                       "Config must have balanced parens (\(openCount) open, \(closeCount) close)")
    }

    func testComplexConfig_HasBalancedParentheses() {
        var collections = RuleCollectionCatalog().defaultCollections()
        for i in collections.indices where collections[i].id == RuleCollectionIdentifier.capsLockRemap
            || collections[i].id == RuleCollectionIdentifier.macFunctionKeys
            || collections[i].id == RuleCollectionIdentifier.homeRowMods
            || collections[i].id == RuleCollectionIdentifier.vimNavigation
        {
            collections[i].isEnabled = true
            if collections[i].id == RuleCollectionIdentifier.homeRowMods {
                collections[i].configuration = .homeRowMods(HomeRowModsConfig())
            }
        }
        let rule = CustomRule(
            input: "caps",
            action: .keystroke(key: "esc"),
            behavior: .dualRole(DualRoleBehavior(
                tapAction: .keystroke(key: "esc"),
                holdAction: .hyper,
                activateHoldOnOtherKey: true
            ))
        )
        let config = generateConfig(collections: collections, customRules: [rule])
        let openCount = config.filter { $0 == "(" }.count
        let closeCount = config.filter { $0 == ")" }.count
        XCTAssertEqual(openCount, closeCount,
                       "Complex config must have balanced parens (\(openCount) open, \(closeCount) close)")
    }

    // MARK: - Defalias block

    func testHRM_ProducesDefaliasBlock() {
        var collections = RuleCollectionCatalog().defaultCollections()
        if let idx = collections.firstIndex(where: { $0.id == RuleCollectionIdentifier.homeRowMods }) {
            collections[idx].isEnabled = true
            collections[idx].configuration = .homeRowMods(HomeRowModsConfig())
        }
        let config = generateConfig(collections: collections)
        XCTAssertTrue(config.contains("(defalias"), "HRM should produce defalias block")
    }

    // MARK: - Non-empty output

    func testDefaultCollections_ProduceNonEmptyConfig() {
        let collections = RuleCollectionCatalog().defaultCollections()
        let config = generateConfig(collections: collections)
        XCTAssertGreaterThan(config.count, 100, "Default config should be substantial")
    }
}
