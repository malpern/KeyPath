@testable import KeyPathAppKit
import KeyPathCore
@preconcurrency import XCTest

final class RuleCollectionsManagerTests: XCTestCase {
    // MARK: - Helper Methods

    @MainActor
    private func createTestManager() async throws -> (RuleCollectionsManager, URL) {
        TestEnvironment.forceTestMode = true

        let tempDir = FileManager.default.temporaryDirectory
            .appendingPathComponent("rule-manager-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: tempDir, withIntermediateDirectories: true)

        let collectionStore = RuleCollectionStore(
            fileURL: tempDir.appendingPathComponent("RuleCollections.json"))
        let customStore = CustomRulesStore(
            fileURL: tempDir.appendingPathComponent("CustomRules.json"))
        let configService = ConfigurationService(configDirectory: tempDir.path)
        let manager = RuleCollectionsManager(
            ruleCollectionStore: collectionStore,
            customRulesStore: customStore,
            configurationService: configService,
            eventListener: KanataEventListener()
        )

        return (manager, tempDir)
    }

    // MARK: - Existing Tests

    @MainActor
    func testToggleRehydratesMissingCatalogCollection() async throws {
        TestEnvironment.forceTestMode = true
        defer { TestEnvironment.forceTestMode = false }

        let tempDir = FileManager.default.temporaryDirectory
            .appendingPathComponent("rule-manager-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: tempDir, withIntermediateDirectories: true)

        let collectionStore = RuleCollectionStore(
            fileURL: tempDir.appendingPathComponent("RuleCollections.json"))
        let customStore = CustomRulesStore(
            fileURL: tempDir.appendingPathComponent("CustomRules.json"))
        let configService = ConfigurationService(configDirectory: tempDir.path)
        let manager = RuleCollectionsManager(
            ruleCollectionStore: collectionStore,
            customRulesStore: customStore,
            configurationService: configService,
            eventListener: KanataEventListener()
        )

        // Start with only macOS Function Keys (simulate post-reset subset)
        let catalog = RuleCollectionCatalog()
        let macOnly = catalog.defaultCollections().first {
            $0.id == RuleCollectionIdentifier.macFunctionKeys
        }!
        await manager.replaceCollections([macOnly])
        XCTAssertFalse(manager.ruleCollections.contains { $0.id == RuleCollectionIdentifier.vimNavigation })

        // Toggling Vim when missing should rehydrate from catalog and enable it
        await manager.toggleCollection(id: RuleCollectionIdentifier.vimNavigation, isEnabled: true)

        XCTAssertTrue(manager.ruleCollections.contains { $0.id == RuleCollectionIdentifier.vimNavigation && $0.isEnabled })

        // Persisted store should also include the rehydrated collection
        let persisted = await collectionStore.loadCollections()
        XCTAssertTrue(persisted.contains { $0.id == RuleCollectionIdentifier.vimNavigation && $0.isEnabled })
    }

    func testGenerateConfigIncludesMomentaryActivatorAlias() {
        let catalog = RuleCollectionCatalog()
        let vim = catalog.defaultCollections().first { $0.id == RuleCollectionIdentifier.vimNavigation }!

        let config = KanataConfiguration.generateFromCollections([vim])

        // Momentary activator exposes layer-while-held navigation
        XCTAssertTrue(
            config.contains("(layer-while-held nav)"),
            "Momentary activator should activate the nav layer via layer-while-held"
        )
        XCTAssertTrue(config.contains("(deflayer nav"), "Navigation layer block should be emitted")
    }

    // MARK: - Function Key Mode Tests

    func testFunctionKeyMappingsMediaMode() {
        let mappings = RuleCollectionCatalog.functionKeyMappings(for: .media)

        XCTAssertEqual(mappings.count, 12, "Should have 12 function key mappings")

        // Verify media key outputs
        XCTAssertTrue(mappings.contains { $0.input == "f1" && $0.output == "brdn" }, "F1 should map to brightness down")
        XCTAssertTrue(mappings.contains { $0.input == "f2" && $0.output == "brup" }, "F2 should map to brightness up")
        XCTAssertTrue(mappings.contains { $0.input == "f7" && $0.output == "prev" }, "F7 should map to previous track")
        XCTAssertTrue(mappings.contains { $0.input == "f8" && $0.output == "pp" }, "F8 should map to play/pause")
        XCTAssertTrue(mappings.contains { $0.input == "f10" && $0.output == "mute" }, "F10 should map to mute")
        XCTAssertTrue(mappings.contains { $0.input == "f12" && $0.output == "volu" }, "F12 should map to volume up")
    }

    func testFunctionKeyMappingsFunctionMode() {
        let mappings = RuleCollectionCatalog.functionKeyMappings(for: .function)

        XCTAssertEqual(mappings.count, 12, "Should have 12 function key mappings")

        // Verify passthrough outputs (each F-key maps to itself)
        for i in 1...12 {
            let key = "f\(i)"
            XCTAssertTrue(
                mappings.contains { $0.input == key && $0.output == key },
                "\(key.uppercased()) should pass through as \(key)"
            )
        }
    }

    func testFunctionKeyModeConversion() {
        // Test Bool -> FunctionKeyMode conversion
        XCTAssertEqual(FunctionKeyMode(preferMediaKeys: true), .media)
        XCTAssertEqual(FunctionKeyMode(preferMediaKeys: false), .function)

        // Test FunctionKeyMode -> Bool conversion
        XCTAssertTrue(FunctionKeyMode.media.preferMediaKeys)
        XCTAssertFalse(FunctionKeyMode.function.preferMediaKeys)
    }

    // MARK: - Conflict Detection Tests

    @MainActor
    func testCustomRuleConflictWithCustomRule_WarnsButAllows() async throws {
        let (manager, _) = try await createTestManager()
        defer { TestEnvironment.forceTestMode = false }

        var warningReceived: String?
        var errorReceived: String?
        manager.onWarning = { warningReceived = $0 }
        manager.onError = { errorReceived = $0 }

        // Create first custom rule mapping caps -> esc
        let rule1 = CustomRule(input: "caps", output: "esc", isEnabled: true)
        let saved1 = await manager.saveCustomRule(rule1)
        XCTAssertTrue(saved1, "First rule should save successfully")

        // Create second custom rule with same input (conflict!)
        let rule2 = CustomRule(input: "caps", output: "tab", isEnabled: true)
        let saved2 = await manager.saveCustomRule(rule2)

        // Should warn but still save
        XCTAssertTrue(saved2, "Second rule should save despite conflict (warning-only)")
        XCTAssertNotNil(warningReceived, "Warning should be received for conflict")
        XCTAssertNil(errorReceived, "Error should NOT be received (warning-only behavior)")
        XCTAssertTrue(warningReceived?.contains("conflicts") ?? false, "Warning message should mention conflict")
        XCTAssertTrue(warningReceived?.contains("caps") ?? false, "Warning should mention the conflicting key")

        // Both rules should exist
        XCTAssertEqual(manager.customRules.count, 2, "Both rules should be saved")
    }

    @MainActor
    func testCustomRuleConflictWithCollection_WarnsButAllows() async throws {
        let (manager, _) = try await createTestManager()
        defer { TestEnvironment.forceTestMode = false }

        var warningReceived: String?
        manager.onWarning = { warningReceived = $0 }

        // Enable Caps Lock remap collection (maps caps -> something)
        await manager.toggleCollection(id: RuleCollectionIdentifier.capsLockRemap, isEnabled: true)
        XCTAssertTrue(manager.ruleCollections.contains { $0.id == RuleCollectionIdentifier.capsLockRemap && $0.isEnabled })

        // Create custom rule with same input (caps)
        let rule = CustomRule(input: "caps", output: "esc", isEnabled: true)
        let saved = await manager.saveCustomRule(rule)

        // Should warn but still save
        XCTAssertTrue(saved, "Rule should save despite conflict with collection")
        XCTAssertNotNil(warningReceived, "Warning should be received")
        XCTAssertTrue(warningReceived?.contains("conflicts") ?? false)
    }

    @MainActor
    func testToggleCustomRule_ConflictWarnsButEnables() async throws {
        let (manager, _) = try await createTestManager()
        defer { TestEnvironment.forceTestMode = false }

        var warningReceived: String?
        manager.onWarning = { warningReceived = $0 }

        // Create two rules with same input, both initially disabled
        var rule1 = CustomRule(input: "caps", output: "esc", isEnabled: false)
        var rule2 = CustomRule(input: "caps", output: "tab", isEnabled: false)

        // Save both (no conflict since both disabled)
        await manager.saveCustomRule(rule1)
        await manager.saveCustomRule(rule2)
        rule1 = manager.customRules.first { $0.output == "esc" }!
        rule2 = manager.customRules.first { $0.output == "tab" }!

        // Enable first - no warning
        await manager.toggleCustomRule(id: rule1.id, isEnabled: true)
        XCTAssertNil(warningReceived, "No warning for first enable")

        // Enable second - should warn
        await manager.toggleCustomRule(id: rule2.id, isEnabled: true)
        XCTAssertNotNil(warningReceived, "Warning should be received for conflict")

        // Both should be enabled
        let enabledRules = manager.customRules.filter(\.isEnabled)
        XCTAssertEqual(enabledRules.count, 2, "Both rules should be enabled despite conflict")
    }

    @MainActor
    func testNoConflictWarning_WhenNoOverlap() async throws {
        let (manager, _) = try await createTestManager()
        defer { TestEnvironment.forceTestMode = false }

        var warningReceived: String?
        manager.onWarning = { warningReceived = $0 }

        // Create two rules with different inputs
        let rule1 = CustomRule(input: "caps", output: "esc", isEnabled: true)
        let rule2 = CustomRule(input: "tab", output: "ret", isEnabled: true)

        await manager.saveCustomRule(rule1)
        await manager.saveCustomRule(rule2)

        // No warnings should occur
        XCTAssertNil(warningReceived, "No warning should occur when rules don't conflict")
        XCTAssertEqual(manager.customRules.count, 2)
    }

    @MainActor
    func testDisabledRuleDoesNotConflict() async throws {
        let (manager, _) = try await createTestManager()
        defer { TestEnvironment.forceTestMode = false }

        var warningReceived: String?
        manager.onWarning = { warningReceived = $0 }

        // Create disabled rule
        let rule1 = CustomRule(input: "caps", output: "esc", isEnabled: false)
        await manager.saveCustomRule(rule1)

        // Create enabled rule with same input - should NOT conflict (first is disabled)
        let rule2 = CustomRule(input: "caps", output: "tab", isEnabled: true)
        await manager.saveCustomRule(rule2)

        XCTAssertNil(warningReceived, "Disabled rules should not trigger conflict warnings")
    }

    @MainActor
    func testConflictInfo_ContainsCorrectKeys() async throws {
        let (manager, _) = try await createTestManager()
        defer { TestEnvironment.forceTestMode = false }

        var warningMessage: String?
        manager.onWarning = { warningMessage = $0 }

        // Create conflicting rules
        let rule1 = CustomRule(input: "caps", output: "esc", isEnabled: true)
        await manager.saveCustomRule(rule1)

        let rule2 = CustomRule(input: "caps", output: "tab", isEnabled: true)
        await manager.saveCustomRule(rule2)

        // Warning should contain the key name
        XCTAssertNotNil(warningMessage)
        XCTAssertTrue(warningMessage?.contains("caps") ?? false, "Warning should mention the conflicting key")
        XCTAssertTrue(warningMessage?.contains("Last enabled rule wins") ?? false, "Warning should explain behavior")
    }

    @MainActor
    func testIdenticalMomentaryActivatorsDoNotWarn() async throws {
        let (manager, _) = try await createTestManager()
        defer { TestEnvironment.forceTestMode = false }

        var warningReceived: String?
        manager.onWarning = { warningReceived = $0 }

        let first = RuleCollection(
            name: "Nav",
            summary: "Navigation layer",
            category: .navigation,
            mappings: [KeyMapping(input: "h", output: "left")],
            isEnabled: true,
            targetLayer: .navigation,
            momentaryActivator: MomentaryActivator(input: "space", targetLayer: .navigation)
        )

        let second = RuleCollection(
            name: "Delete Enh",
            summary: "Delete tweaks",
            category: .navigation,
            mappings: [KeyMapping(input: "d", output: "del")],
            isEnabled: false,
            targetLayer: .navigation,
            momentaryActivator: MomentaryActivator(input: "space", targetLayer: .navigation)
        )

        await manager.replaceCollections([first, second])
        await manager.toggleCollection(id: second.id, isEnabled: true)

        XCTAssertNil(warningReceived, "Identical activators should not trigger a conflict warning")
        let updated = manager.ruleCollections
        XCTAssertNotNil(updated.first(where: { $0.id == first.id })?.momentaryActivator)
        XCTAssertNil(updated.first(where: { $0.id == second.id })?.momentaryActivator)
    }
}
