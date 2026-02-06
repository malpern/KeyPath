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

        // Start with only macOS Function Keys (simulate post-reset subset)
        let catalog = RuleCollectionCatalog()
        let macOnly = try XCTUnwrap(catalog.defaultCollections().first {
            $0.id == RuleCollectionIdentifier.macFunctionKeys
        })
        await manager.replaceCollections([macOnly])
        XCTAssertFalse(manager.ruleCollections.contains { $0.id == RuleCollectionIdentifier.vimNavigation })

        // Toggling Vim when missing should rehydrate from catalog and enable it
        await manager.toggleCollection(id: RuleCollectionIdentifier.vimNavigation, isEnabled: true)

        XCTAssertTrue(manager.ruleCollections.contains { $0.id == RuleCollectionIdentifier.vimNavigation && $0.isEnabled })

        // Persisted store should also include the rehydrated collection
        let persisted = await collectionStore.loadCollections()
        XCTAssertTrue(persisted.contains { $0.id == RuleCollectionIdentifier.vimNavigation && $0.isEnabled })
    }

    func testGenerateConfigIncludesMomentaryActivatorAlias() throws {
        let catalog = RuleCollectionCatalog()
        let vim = try XCTUnwrap(catalog.defaultCollections().first { $0.id == RuleCollectionIdentifier.vimNavigation })

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
        for i in 1 ... 12 {
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

        var conflictContext: RuleConflictContext?
        manager.onConflictResolution = { context in
            conflictContext = context
            return .keepNew
        }

        // Create first custom rule mapping caps -> esc
        let rule1 = CustomRule(input: "caps", output: "esc", isEnabled: true)
        let saved1 = await manager.saveCustomRule(rule1)
        XCTAssertTrue(saved1, "First rule should save successfully")

        // Create second custom rule with same input (conflict!)
        let rule2 = CustomRule(input: "caps", output: "tab", isEnabled: true)
        let saved2 = await manager.saveCustomRule(rule2)

        // Should resolve via conflict handler and still save
        XCTAssertTrue(saved2, "Second rule should save after conflict resolution")
        XCTAssertNotNil(conflictContext, "Conflict resolution should be requested")
        XCTAssertTrue(
            conflictContext?.conflictingKeys.contains("caps") ?? false,
            "Conflict should include the conflicting key"
        )

        // Both rules should exist, but the original should be disabled
        XCTAssertEqual(manager.customRules.count, 2, "Both rules should be saved")
        XCTAssertFalse(
            manager.customRules.contains { $0.input == "caps" && $0.output == "esc" && $0.isEnabled },
            "Original conflicting rule should be disabled"
        )
    }

    @MainActor
    func testCustomRuleConflictWithCollection_WarnsButAllows() async throws {
        let (manager, _) = try await createTestManager()
        defer { TestEnvironment.forceTestMode = false }

        var conflictContext: RuleConflictContext?
        manager.onConflictResolution = { context in
            conflictContext = context
            return .keepNew
        }

        // Enable Caps Lock remap collection (maps caps -> something)
        await manager.toggleCollection(id: RuleCollectionIdentifier.capsLockRemap, isEnabled: true)
        XCTAssertTrue(manager.ruleCollections.contains { $0.id == RuleCollectionIdentifier.capsLockRemap && $0.isEnabled })

        // Create custom rule with same input (caps)
        let rule = CustomRule(input: "caps", output: "esc", isEnabled: true)
        let saved = await manager.saveCustomRule(rule)

        // Should resolve via conflict handler and still save
        XCTAssertTrue(saved, "Rule should save after conflict resolution")
        XCTAssertNotNil(conflictContext, "Conflict resolution should be requested")
        XCTAssertTrue(
            conflictContext?.conflictingKeys.contains("caps") ?? false,
            "Conflict should include the conflicting key"
        )
        XCTAssertFalse(
            manager.ruleCollections.contains { $0.id == RuleCollectionIdentifier.capsLockRemap && $0.isEnabled },
            "Conflicting collection should be disabled"
        )
    }

    @MainActor
    func testCustomRuleConflictWithCollectionOnCustomLayer_WarnsButAllows() async throws {
        let (manager, _) = try await createTestManager()
        defer { TestEnvironment.forceTestMode = false }

        var conflictContext: RuleConflictContext?
        manager.onConflictResolution = { context in
            conflictContext = context
            return .keepNew
        }

        let launcherCollection = RuleCollection(
            id: UUID(),
            name: "Quick Launcher",
            summary: "Launcher layer mappings",
            category: .productivity,
            mappings: [KeyMapping(input: "a", output: "b")],
            isEnabled: true,
            targetLayer: .custom("launcher")
        )

        await manager.replaceCollections([launcherCollection])

        let systemActionRule = CustomRule(
            input: "a",
            output: #"(push-msg "system:spotlight")"#,
            isEnabled: true,
            targetLayer: .custom("launcher")
        )
        let saved = await manager.saveCustomRule(systemActionRule)

        XCTAssertTrue(saved, "Rule should save after conflict resolution on custom layer")
        XCTAssertNotNil(conflictContext, "Conflict resolution should be requested")
        XCTAssertTrue(
            conflictContext?.conflictingKeys.contains("a") ?? false,
            "Conflict should include the conflicting key"
        )
        XCTAssertFalse(
            manager.ruleCollections.contains { $0.id == launcherCollection.id && $0.isEnabled },
            "Conflicting collection should be disabled"
        )
    }

    @MainActor
    func testToggleCustomRule_ConflictWarnsButEnables() async throws {
        let (manager, _) = try await createTestManager()
        defer { TestEnvironment.forceTestMode = false }

        var conflictContext: RuleConflictContext?
        manager.onConflictResolution = { context in
            conflictContext = context
            return .keepNew
        }

        // Create two rules with same input, both initially disabled
        var rule1 = CustomRule(input: "caps", output: "esc", isEnabled: false)
        var rule2 = CustomRule(input: "caps", output: "tab", isEnabled: false)

        // Save both (no conflict since both disabled)
        await manager.saveCustomRule(rule1)
        await manager.saveCustomRule(rule2)
        rule1 = try XCTUnwrap(manager.customRules.first { $0.output == "esc" })
        rule2 = try XCTUnwrap(manager.customRules.first { $0.output == "tab" })

        // Enable first - no warning
        await manager.toggleCustomRule(id: rule1.id, isEnabled: true)
        XCTAssertNil(conflictContext, "No conflict for first enable")

        // Enable second - should warn
        await manager.toggleCustomRule(id: rule2.id, isEnabled: true)
        XCTAssertNotNil(conflictContext, "Conflict resolution should be requested")

        // Only the new rule should be enabled
        let enabledRules = manager.customRules.filter(\.isEnabled)
        XCTAssertEqual(enabledRules.count, 1, "Only one rule should remain enabled")
        XCTAssertTrue(enabledRules.contains { $0.id == rule2.id }, "New rule should be enabled")
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

        var conflictContext: RuleConflictContext?
        manager.onConflictResolution = { context in
            conflictContext = context
            return .keepNew
        }

        // Create conflicting rules
        let rule1 = CustomRule(input: "caps", output: "esc", isEnabled: true)
        await manager.saveCustomRule(rule1)

        let rule2 = CustomRule(input: "caps", output: "tab", isEnabled: true)
        await manager.saveCustomRule(rule2)

        // Conflict context should contain the key name
        XCTAssertNotNil(conflictContext)
        XCTAssertTrue(conflictContext?.conflictingKeys.contains("caps") ?? false, "Conflict should mention the key")
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

    // MARK: - Layer Deletion Tests

    @MainActor
    func testRemoveLayer_deletesCollectionsAndRules() async throws {
        let (manager, _) = try await createTestManager()
        defer { TestEnvironment.forceTestMode = false }

        // Create collections and rules on custom "window" layer
        let windowCollection = RuleCollection(
            id: UUID(),
            name: "Window Nav",
            summary: "Window navigation",
            category: .custom,
            mappings: [KeyMapping(input: "h", output: "left")],
            isEnabled: true,
            targetLayer: .custom("window")
        )

        let vimCollection = RuleCollection(
            id: UUID(),
            name: "Vim Nav",
            summary: "Vim navigation",
            category: .navigation,
            mappings: [KeyMapping(input: "j", output: "down")],
            isEnabled: true,
            targetLayer: .custom("vim")
        )

        let baseCollection = RuleCollection(
            id: UUID(),
            name: "Base Nav",
            summary: "Base layer nav",
            category: .custom,
            mappings: [KeyMapping(input: "k", output: "up")],
            isEnabled: true,
            targetLayer: .base
        )

        await manager.replaceCollections([windowCollection, vimCollection, baseCollection])

        // Create custom rules on window layer
        let windowRule1 = CustomRule(input: "a", output: "b", isEnabled: true, targetLayer: .custom("window"))
        let windowRule2 = CustomRule(input: "c", output: "d", isEnabled: true, targetLayer: .custom("window"))
        let vimRule = CustomRule(input: "e", output: "f", isEnabled: true, targetLayer: .custom("vim"))

        await manager.saveCustomRule(windowRule1)
        await manager.saveCustomRule(windowRule2)
        await manager.saveCustomRule(vimRule)

        // Verify initial state
        XCTAssertEqual(manager.ruleCollections.count, 3)
        XCTAssertEqual(manager.customRules.count, 3)

        // Remove window layer
        await manager.removeLayer("window")

        // Verify collections targeting window layer are removed
        XCTAssertEqual(manager.ruleCollections.count, 2)
        XCTAssertFalse(manager.ruleCollections.contains { $0.targetLayer.kanataName == "window" })
        XCTAssertTrue(manager.ruleCollections.contains { $0.name == "Vim Nav" })
        XCTAssertTrue(manager.ruleCollections.contains { $0.name == "Base Nav" })

        // Verify custom rules targeting window layer are removed
        XCTAssertEqual(manager.customRules.count, 1)
        XCTAssertFalse(manager.customRules.contains { $0.targetLayer.kanataName == "window" })
        XCTAssertTrue(manager.customRules.contains { $0.input == "e" && $0.output == "f" })
    }

    @MainActor
    func testRemoveLayer_persistsChangesToDisk() async throws {
        let (manager, tempDir) = try await createTestManager()
        defer { TestEnvironment.forceTestMode = false }

        // Create a custom rule on a custom layer
        let customRule = CustomRule(input: "a", output: "b", isEnabled: true, targetLayer: .custom("test"))
        await manager.saveCustomRule(customRule)

        XCTAssertEqual(manager.customRules.count, 1)

        // Remove the layer
        await manager.removeLayer("test")

        XCTAssertEqual(manager.customRules.count, 0)

        // Create a new store and verify persistence
        let customStore = CustomRulesStore(fileURL: tempDir.appendingPathComponent("CustomRules.json"))
        let loadedRules = await customStore.loadRules()

        XCTAssertEqual(loadedRules.count, 0, "Rules should be persisted to disk after layer removal")
    }

    @MainActor
    func testRemoveLayer_caseInsensitive() async throws {
        let (manager, _) = try await createTestManager()
        defer { TestEnvironment.forceTestMode = false }

        // Create collection with lowercase layer name
        let collection = RuleCollection(
            id: UUID(),
            name: "Test",
            summary: "Test collection",
            category: .custom,
            mappings: [KeyMapping(input: "h", output: "left")],
            isEnabled: true,
            targetLayer: .custom("window")
        )

        await manager.replaceCollections([collection])
        XCTAssertEqual(manager.ruleCollections.count, 1)

        // Remove with different case
        await manager.removeLayer("WINDOW")

        XCTAssertEqual(manager.ruleCollections.count, 0, "Layer removal should be case-insensitive")
    }

    @MainActor
    func testRemoveLayer_doesNotAffectOtherLayers() async throws {
        let (manager, _) = try await createTestManager()
        defer { TestEnvironment.forceTestMode = false }

        // Create collections on different layers
        let collection1 = RuleCollection(
            id: UUID(),
            name: "Window",
            summary: "Window layer",
            category: .custom,
            mappings: [KeyMapping(input: "h", output: "left")],
            isEnabled: true,
            targetLayer: .custom("window")
        )

        let collection2 = RuleCollection(
            id: UUID(),
            name: "Vim",
            summary: "Vim layer",
            category: .custom,
            mappings: [KeyMapping(input: "j", output: "down")],
            isEnabled: true,
            targetLayer: .custom("vim")
        )

        await manager.replaceCollections([collection1, collection2])

        // Remove window layer
        await manager.removeLayer("window")

        // Vim layer should remain
        XCTAssertEqual(manager.ruleCollections.count, 1)
        XCTAssertTrue(manager.ruleCollections.contains { $0.name == "Vim" })
    }
}
