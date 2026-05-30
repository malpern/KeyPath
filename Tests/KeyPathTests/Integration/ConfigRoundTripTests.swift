@testable import KeyPathAppKit
import KeyPathCore
import XCTest

/// Round-trip tests: save collections → load → regenerate config → compare.
/// Detects serialization bugs where data is lost or mutated during persistence.
final class ConfigRoundTripTests: XCTestCase {
    @MainActor
    func testRuleCollections_SaveLoadRoundTrip_ProducesIdenticalConfig() async throws {
        TestEnvironment.forceTestMode = true
        defer { TestEnvironment.forceTestMode = false }

        let tempDir = FileManager.default.temporaryDirectory
            .appendingPathComponent("roundtrip-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: tempDir, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: tempDir) }

        let store = RuleCollectionStore(
            fileURL: tempDir.appendingPathComponent("RuleCollections.json")
        )

        // Get default collections with some enabled
        var collections = RuleCollectionCatalog().defaultCollections()
        if let idx = collections.firstIndex(where: { $0.id == RuleCollectionIdentifier.capsLockRemap }) {
            collections[idx].isEnabled = true
        }

        // Generate config BEFORE save
        let configBefore = KanataConfiguration.generateFromCollections(collections)

        // Save → Load
        try await store.saveCollections(collections)
        let loaded = await store.loadCollections()

        // Generate config AFTER load
        let configAfter = KanataConfiguration.generateFromCollections(loaded)

        XCTAssertEqual(
            configBefore, configAfter,
            "Config generated from loaded collections should match config from original collections"
        )
    }

    @MainActor
    func testCustomRules_SaveLoadRoundTrip_PreservesAllFields() async throws {
        TestEnvironment.forceTestMode = true
        defer { TestEnvironment.forceTestMode = false }

        let tempDir = FileManager.default.temporaryDirectory
            .appendingPathComponent("roundtrip-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: tempDir, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: tempDir) }

        let store = CustomRulesStore(
            fileURL: tempDir.appendingPathComponent("CustomRules.json")
        )

        let rules = [
            CustomRule(input: "a", action: .keystroke(key: "b"), shiftedOutput: "c"),
            CustomRule(input: "caps", action: .keystroke(key: "esc"), isEnabled: true),
            CustomRule(input: "1", action: .keystroke(key: "2"), shiftedOutput: "at", isEnabled: false),
        ]

        try await store.saveRules(rules)
        let loaded = await store.loadRules()

        XCTAssertEqual(loaded.count, rules.count, "Should load same number of rules")

        for (original, roundTripped) in zip(rules, loaded) {
            XCTAssertEqual(roundTripped.input, original.input)
            XCTAssertEqual(roundTripped.action, original.action)
            XCTAssertEqual(roundTripped.shiftedOutput, original.shiftedOutput)
            XCTAssertEqual(roundTripped.isEnabled, original.isEnabled)
        }
    }

    @MainActor
    func testFullPipeline_SaveLoadSave_ProducesIdenticalFile() async throws {
        TestEnvironment.forceTestMode = true
        defer { TestEnvironment.forceTestMode = false }

        let tempDir = FileManager.default.temporaryDirectory
            .appendingPathComponent("roundtrip-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: tempDir, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: tempDir) }

        let collectionStore = RuleCollectionStore(
            fileURL: tempDir.appendingPathComponent("RuleCollections.json")
        )
        let customStore = CustomRulesStore(
            fileURL: tempDir.appendingPathComponent("CustomRules.json")
        )
        let configService = ConfigurationService(configDirectory: tempDir.path)
        let manager = RuleCollectionsManager(
            ruleCollectionStore: collectionStore,
            customRulesStore: customStore,
            configurationService: configService,
            eventListener: KanataEventListener()
        )

        // Enable a pack and add a custom rule
        _ = await manager.toggleCollection(
            id: RuleCollectionIdentifier.capsLockRemap,
            isEnabled: true,
            autoResolveConflicts: true
        )
        await manager.saveCustomRule(
            CustomRule(input: "s", action: .keystroke(key: "d")),
            skipReload: true,
            autoResolveConflicts: true
        )

        // Read first config
        let configPath = tempDir.appendingPathComponent("keypath.kbd")
        let config1 = try String(contentsOf: configPath, encoding: .utf8)

        // Force regeneration (simulates app restart loading from persisted state)
        _ = await manager.regenerateConfigFromCollections(skipReload: true)
        let config2 = try String(contentsOf: configPath, encoding: .utf8)

        XCTAssertEqual(config1, config2, "Regenerated config should be identical to first generation")
    }
}
