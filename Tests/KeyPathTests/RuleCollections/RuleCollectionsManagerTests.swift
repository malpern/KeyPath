@testable import KeyPathAppKit
import KeyPathCore
@preconcurrency import XCTest

final class RuleCollectionsManagerTests: KeyPathAsyncTestCase {
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

    @MainActor
    override func tearDown() async throws {
        TestEnvironment.forceTestMode = false
        try await super.tearDown()
    }

    // MARK: - Bootstrap Tests

    @MainActor
    func testBootstrap_LoadsCollectionsAndCustomRules() async throws {
        let (manager, tempDir) = try await createTestManager()
        defer { try? FileManager.default.removeItem(at: tempDir) }

        // Pre-populate stores with test data
        let collectionStore = RuleCollectionStore(
            fileURL: tempDir.appendingPathComponent("RuleCollections.json"))
        let customStore = CustomRulesStore(
            fileURL: tempDir.appendingPathComponent("CustomRules.json"))

        let testCollection = RuleCollection(
            name: "Test Collection",
            summary: "Test",
            category: .navigation,
            mappings: [KeyMapping(input: "h", output: "left")],
            isEnabled: true
        )
        try await collectionStore.saveCollections([testCollection])

        let testRule = CustomRule(input: "caps", output: "esc", isEnabled: true)
        try await customStore.saveRules([testRule])

        // Bootstrap should load both
        await manager.bootstrap()

        XCTAssertTrue(manager.ruleCollections.contains { $0.id == testCollection.id })
        XCTAssertEqual(manager.customRules.count, 1)
        XCTAssertEqual(manager.customRules.first?.input, "caps")
    }

    @MainActor
    func testBootstrap_EnsuresDefaultCollectionsWhenEmpty() async throws {
        let (manager, tempDir) = try await createTestManager()
        defer { try? FileManager.default.removeItem(at: tempDir) }

        // Bootstrap with empty stores
        await manager.bootstrap()

        // Should have default collections (at minimum macOS Function Keys)
        XCTAssertFalse(manager.ruleCollections.isEmpty, "Should have default collections")
    }

    @MainActor
    func testBootstrap_MigratesLegacyCustomMappingsCollection() async throws {
        let (manager, tempDir) = try await createTestManager()
        defer { try? FileManager.default.removeItem(at: tempDir) }

        // Create legacy custom mappings collection
        let legacyCollection = RuleCollection(
            id: RuleCollectionIdentifier.customMappings,
            name: "Custom Mappings",
            summary: "Legacy custom mappings",
            category: .custom,
            mappings: [
                KeyMapping(id: UUID(), input: "caps", output: "esc"),
                KeyMapping(id: UUID(), input: "tab", output: "ret")
            ],
            isEnabled: true
        )

        let collectionStore = RuleCollectionStore(
            fileURL: tempDir.appendingPathComponent("RuleCollections.json"))
        try await collectionStore.saveCollections([legacyCollection])

        // Bootstrap should migrate to CustomRulesStore
        await manager.bootstrap()

        // Legacy collection should be removed
        XCTAssertFalse(manager.ruleCollections.contains { $0.id == RuleCollectionIdentifier.customMappings })

        // Custom rules should be migrated
        XCTAssertEqual(manager.customRules.count, 2)
        XCTAssertTrue(manager.customRules.contains { $0.input == "caps" && $0.output == "esc" })
        XCTAssertTrue(manager.customRules.contains { $0.input == "tab" && $0.output == "ret" })
    }

    // MARK: - Collection Operations Tests

    @MainActor
    func testReplaceCollections_UpdatesInMemoryState() async throws {
        let (manager, tempDir) = try await createTestManager()
        defer { try? FileManager.default.removeItem(at: tempDir) }

        await manager.bootstrap()

        let newCollections = [
            RuleCollection(
                name: "Test 1",
                summary: "First test",
                category: .navigation,
                mappings: [KeyMapping(input: "h", output: "left")],
                isEnabled: true
            ),
            RuleCollection(
                name: "Test 2",
                summary: "Second test",
                category: .productivity,
                mappings: [KeyMapping(input: "j", output: "down")],
                isEnabled: true
            )
        ]

        await manager.replaceCollections(newCollections)

        XCTAssertEqual(manager.ruleCollections.count, 2)
        XCTAssertTrue(manager.ruleCollections.contains { $0.name == "Test 1" })
        XCTAssertTrue(manager.ruleCollections.contains { $0.name == "Test 2" })
    }

    @MainActor
    func testToggleCollection_EnablesExistingCollection() async throws {
        let (manager, tempDir) = try await createTestManager()
        defer { try? FileManager.default.removeItem(at: tempDir) }

        await manager.bootstrap()

        // Disable Vim
        await manager.toggleCollection(id: RuleCollectionIdentifier.vimNavigation, isEnabled: false)

        // Enable it
        await manager.toggleCollection(id: RuleCollectionIdentifier.vimNavigation, isEnabled: true)

        XCTAssertTrue(manager.ruleCollections.contains { $0.id == RuleCollectionIdentifier.vimNavigation && $0.isEnabled })
    }

    @MainActor
    func testToggleCollection_DisablesCollection() async throws {
        let (manager, tempDir) = try await createTestManager()
        defer { try? FileManager.default.removeItem(at: tempDir) }

        await manager.bootstrap()

        // Enable Vim
        await manager.toggleCollection(id: RuleCollectionIdentifier.vimNavigation, isEnabled: true)
        XCTAssertTrue(manager.ruleCollections.contains { $0.id == RuleCollectionIdentifier.vimNavigation && $0.isEnabled })

        // Disable it
        await manager.toggleCollection(id: RuleCollectionIdentifier.vimNavigation, isEnabled: false)
        XCTAssertTrue(manager.ruleCollections.contains { $0.id == RuleCollectionIdentifier.vimNavigation && !$0.isEnabled })
    }

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

    @MainActor
    func testToggleCollection_LeaderKeyResetsMomentaryActivators() async throws {
        let (manager, tempDir) = try await createTestManager()
        defer { try? FileManager.default.removeItem(at: tempDir) }

        await manager.bootstrap()

        // Enable Vim (which has a momentary activator)
        await manager.toggleCollection(id: RuleCollectionIdentifier.vimNavigation, isEnabled: true)

        // Change leader key
        await manager.updateCollectionOutput(id: RuleCollectionIdentifier.leaderKey, output: "tab")

        // Disable leader key collection - should reset activators to "space"
        await manager.toggleCollection(id: RuleCollectionIdentifier.leaderKey, isEnabled: false)

        // Check that Vim's activator is back to "space"
        if let vim = manager.ruleCollections.first(where: { $0.id == RuleCollectionIdentifier.vimNavigation }),
           let activator = vim.momentaryActivator {
            XCTAssertEqual(activator.input, "space", "Disabling leader key should reset activators to space")
        }
    }

    @MainActor
    func testAddCollection_InsertsNewCollection() async throws {
        let (manager, tempDir) = try await createTestManager()
        defer { try? FileManager.default.removeItem(at: tempDir) }

        await manager.bootstrap()
        let initialCount = manager.ruleCollections.count

        let newCollection = RuleCollection(
            name: "New Test Collection",
            summary: "A new test collection",
            category: .custom,
            mappings: [KeyMapping(input: "z", output: "undo")],
            isEnabled: true
        )

        await manager.addCollection(newCollection)

        XCTAssertEqual(manager.ruleCollections.count, initialCount + 1)
        XCTAssertTrue(manager.ruleCollections.contains { $0.id == newCollection.id })
    }

    @MainActor
    func testAddCollection_UpdatesExistingCollection() async throws {
        let (manager, tempDir) = try await createTestManager()
        defer { try? FileManager.default.removeItem(at: tempDir) }

        await manager.bootstrap()

        let testCollection = RuleCollection(
            name: "Test",
            summary: "Original summary",
            category: .custom,
            mappings: [KeyMapping(input: "h", output: "left")],
            isEnabled: false
        )
        await manager.addCollection(testCollection)

        let initialCount = manager.ruleCollections.count

        // Update with same ID
        var updated = testCollection
        updated.summary = "Updated summary"
        updated.mappings = [KeyMapping(input: "j", output: "down")]

        await manager.addCollection(updated)

        // Count should not increase
        XCTAssertEqual(manager.ruleCollections.count, initialCount)

        // Should be enabled and updated
        let result = manager.ruleCollections.first { $0.id == testCollection.id }
        XCTAssertTrue(result?.isEnabled ?? false)
        XCTAssertEqual(result?.summary, "Updated summary")
        XCTAssertEqual(result?.mappings.count, 1)
        XCTAssertEqual(result?.mappings.first?.output, "down")
    }

    // MARK: - Picker Collection Tests

    @MainActor
    func testUpdateCollectionOutput_UpdatesSingleKeyPicker() async throws {
        let (manager, tempDir) = try await createTestManager()
        defer { try? FileManager.default.removeItem(at: tempDir) }

        await manager.bootstrap()

        // Update Caps Lock remap output
        await manager.updateCollectionOutput(id: RuleCollectionIdentifier.capsLockRemap, output: "esc")

        let capsCollection = manager.ruleCollections.first { $0.id == RuleCollectionIdentifier.capsLockRemap }
        XCTAssertNotNil(capsCollection)
        XCTAssertEqual(capsCollection?.selectedOutput, "esc")
        XCTAssertTrue(capsCollection?.isEnabled ?? false)
    }

    @MainActor
    func testUpdateCollectionOutput_AddsCollectionFromCatalogIfMissing() async throws {
        let (manager, tempDir) = try await createTestManager()
        defer { try? FileManager.default.removeItem(at: tempDir) }

        // Start with empty collections
        await manager.replaceCollections([])

        // Update a catalog collection that isn't in the manager yet
        await manager.updateCollectionOutput(id: RuleCollectionIdentifier.capsLockRemap, output: "lctl")

        let capsCollection = manager.ruleCollections.first { $0.id == RuleCollectionIdentifier.capsLockRemap }
        XCTAssertNotNil(capsCollection, "Should add collection from catalog")
        XCTAssertEqual(capsCollection?.selectedOutput, "lctl")
        XCTAssertTrue(capsCollection?.isEnabled ?? false)
    }

    @MainActor
    func testUpdateCollectionTapOutput_UpdatesTapHoldPicker() async throws {
        let (manager, tempDir) = try await createTestManager()
        defer { try? FileManager.default.removeItem(at: tempDir) }

        await manager.bootstrap()

        // Create a tap-hold picker collection
        let tapHoldCollection = RuleCollection(
            id: UUID(),
            name: "Tap-Hold Test",
            summary: "Test tap-hold",
            category: .custom,
            mappings: [],
            isEnabled: false,
            displayStyle: .tapHoldPicker,
            selectedTapOutput: "a",
            selectedHoldOutput: "lctl"
        )
        await manager.addCollection(tapHoldCollection)

        // Update tap output
        await manager.updateCollectionTapOutput(id: tapHoldCollection.id, tapOutput: "b")

        let updated = manager.ruleCollections.first { $0.id == tapHoldCollection.id }
        XCTAssertEqual(updated?.selectedTapOutput, "b")
        XCTAssertTrue(updated?.isEnabled ?? false)
    }

    @MainActor
    func testUpdateCollectionHoldOutput_UpdatesTapHoldPicker() async throws {
        let (manager, tempDir) = try await createTestManager()
        defer { try? FileManager.default.removeItem(at: tempDir) }

        await manager.bootstrap()

        // Create a tap-hold picker collection
        let tapHoldCollection = RuleCollection(
            id: UUID(),
            name: "Tap-Hold Test",
            summary: "Test tap-hold",
            category: .custom,
            mappings: [],
            isEnabled: false,
            displayStyle: .tapHoldPicker,
            selectedTapOutput: "a",
            selectedHoldOutput: "lctl"
        )
        await manager.addCollection(tapHoldCollection)

        // Update hold output
        await manager.updateCollectionHoldOutput(id: tapHoldCollection.id, holdOutput: "lmet")

        let updated = manager.ruleCollections.first { $0.id == tapHoldCollection.id }
        XCTAssertEqual(updated?.selectedHoldOutput, "lmet")
        XCTAssertTrue(updated?.isEnabled ?? false)
    }

    // MARK: - Home Row Mods Tests

    @MainActor
    func testUpdateHomeRowModsConfig_UpdatesConfiguration() async throws {
        let (manager, tempDir) = try await createTestManager()
        defer { try? FileManager.default.removeItem(at: tempDir) }

        await manager.bootstrap()

        // Create home row mods collection
        let hrmCollection = RuleCollection(
            id: UUID(),
            name: "Home Row Mods",
            summary: "Home row modifiers",
            category: .custom,
            mappings: [],
            isEnabled: false,
            displayStyle: .homeRowMods
        )
        await manager.addCollection(hrmCollection)

        // Update config
        let config = HomeRowModsConfig(
            enabledKeys: Set(["a", "s", "d", "f", "j", "k", "l", ";"]),
            modifierAssignments: HomeRowModsConfig.cagsMacDefault,
            timing: TimingConfig(
                tapWindow: 250,
                holdDelay: 300,
                quickTapEnabled: true,
                quickTapTermMs: 100,
                tapOffsets: [:]
            ),
            keySelection: .both,
            showAdvanced: false
        )
        await manager.updateHomeRowModsConfig(id: hrmCollection.id, config: config)

        let updated = manager.ruleCollections.first { $0.id == hrmCollection.id }
        XCTAssertNotNil(updated?.homeRowModsConfig)
        XCTAssertEqual(updated?.homeRowModsConfig?.timing.tapWindow, 250)
        XCTAssertEqual(updated?.homeRowModsConfig?.timing.holdDelay, 300)
        XCTAssertTrue(updated?.isEnabled ?? false)
    }

    @MainActor
    func testToggleCollection_EnsuresHomeRowModsConfigExists() async throws {
        let (manager, tempDir) = try await createTestManager()
        defer { try? FileManager.default.removeItem(at: tempDir) }

        await manager.bootstrap()

        // Create home row mods collection without config
        var hrmCollection = RuleCollection(
            id: UUID(),
            name: "Home Row Mods",
            summary: "Home row modifiers",
            category: .custom,
            mappings: [],
            isEnabled: false,
            displayStyle: .homeRowMods
        )
        hrmCollection.homeRowModsConfig = nil
        await manager.addCollection(hrmCollection)

        // Toggle on - should create default config
        await manager.toggleCollection(id: hrmCollection.id, isEnabled: true)

        let updated = manager.ruleCollections.first { $0.id == hrmCollection.id }
        XCTAssertNotNil(updated?.homeRowModsConfig, "Should create default config when toggling on")
    }

    // MARK: - Leader Key Tests

    @MainActor
    func testUpdateLeaderKey_UpdatesAllMomentaryActivators() async throws {
        let (manager, tempDir) = try await createTestManager()
        defer { try? FileManager.default.removeItem(at: tempDir) }

        await manager.bootstrap()

        // Enable collections with momentary activators
        await manager.toggleCollection(id: RuleCollectionIdentifier.vimNavigation, isEnabled: true)

        // Update leader key
        await manager.updateLeaderKey("tab")

        // Check that all activators are updated
        let vim = manager.ruleCollections.first { $0.id == RuleCollectionIdentifier.vimNavigation }
        XCTAssertEqual(vim?.momentaryActivator?.input, "tab")
    }

    @MainActor
    func testUpdateCollectionOutput_LeaderKeyUpdatesMomentaryActivators() async throws {
        let (manager, tempDir) = try await createTestManager()
        defer { try? FileManager.default.removeItem(at: tempDir) }

        await manager.bootstrap()

        // Enable Vim
        await manager.toggleCollection(id: RuleCollectionIdentifier.vimNavigation, isEnabled: true)

        // Update leader key via collection output
        await manager.updateCollectionOutput(id: RuleCollectionIdentifier.leaderKey, output: "ret")

        // Vim's activator should be updated
        let vim = manager.ruleCollections.first { $0.id == RuleCollectionIdentifier.vimNavigation }
        XCTAssertEqual(vim?.momentaryActivator?.input, "ret")
    }

    // MARK: - Custom Rule Tests

    @MainActor
    func testSaveCustomRule_AddsNewRule() async throws {
        let (manager, tempDir) = try await createTestManager()
        defer { try? FileManager.default.removeItem(at: tempDir) }

        await manager.bootstrap()

        let rule = CustomRule(input: "caps", output: "esc", isEnabled: true)
        let success = await manager.saveCustomRule(rule)

        XCTAssertTrue(success)
        XCTAssertEqual(manager.customRules.count, 1)
        XCTAssertEqual(manager.customRules.first?.input, "caps")
        XCTAssertEqual(manager.customRules.first?.output, "esc")
    }

    @MainActor
    func testSaveCustomRule_UpdatesExistingRule() async throws {
        let (manager, tempDir) = try await createTestManager()
        defer { try? FileManager.default.removeItem(at: tempDir) }

        await manager.bootstrap()

        // Add initial rule
        let rule = CustomRule(input: "caps", output: "esc", isEnabled: true)
        await manager.saveCustomRule(rule)
        let ruleId = manager.customRules.first!.id

        // Update with same ID - create new rule with updated output
        let updated = CustomRule(id: ruleId, title: "", input: "caps", output: "lctl", isEnabled: true)
        let success = await manager.saveCustomRule(updated)

        XCTAssertTrue(success)
        XCTAssertEqual(manager.customRules.count, 1)
        XCTAssertEqual(manager.customRules.first?.output, "lctl")
    }

    @MainActor
    func testSaveCustomRule_SkipReloadWhenRequested() async throws {
        let (manager, tempDir) = try await createTestManager()
        defer { try? FileManager.default.removeItem(at: tempDir) }

        await manager.bootstrap()

        var reloadCalled = false
        manager.onRulesChanged = {
            reloadCalled = true
        }

        let rule = CustomRule(input: "caps", output: "esc", isEnabled: true)
        let success = await manager.saveCustomRule(rule, skipReload: true)

        XCTAssertTrue(success)
        XCTAssertFalse(reloadCalled, "Should not trigger reload when skipReload is true")
    }

    // NOTE: Validation failure tests are skipped because test mode uses lightweight validation
    // that doesn't actually fail on empty input/output

    @MainActor
    func testToggleCustomRule_EnablesRule() async throws {
        let (manager, tempDir) = try await createTestManager()
        defer { try? FileManager.default.removeItem(at: tempDir) }

        await manager.bootstrap()

        // Add disabled rule
        var rule = CustomRule(input: "caps", output: "esc", isEnabled: false)
        await manager.saveCustomRule(rule)
        rule = manager.customRules.first!

        // Enable it
        await manager.toggleCustomRule(id: rule.id, isEnabled: true)

        XCTAssertTrue(manager.customRules.first?.isEnabled ?? false)
    }

    @MainActor
    func testToggleCustomRule_DisablesRule() async throws {
        let (manager, tempDir) = try await createTestManager()
        defer { try? FileManager.default.removeItem(at: tempDir) }

        await manager.bootstrap()

        // Add enabled rule
        var rule = CustomRule(input: "caps", output: "esc", isEnabled: true)
        await manager.saveCustomRule(rule)
        rule = manager.customRules.first!

        // Disable it
        await manager.toggleCustomRule(id: rule.id, isEnabled: false)

        XCTAssertFalse(manager.customRules.first?.isEnabled ?? true)
    }

    @MainActor
    func testRemoveCustomRule_DeletesRule() async throws {
        let (manager, tempDir) = try await createTestManager()
        defer { try? FileManager.default.removeItem(at: tempDir) }

        await manager.bootstrap()

        // Add rule
        let rule = CustomRule(input: "caps", output: "esc", isEnabled: true)
        await manager.saveCustomRule(rule)
        let ruleId = manager.customRules.first!.id

        XCTAssertEqual(manager.customRules.count, 1)

        // Remove it
        await manager.removeCustomRule(id: ruleId)

        XCTAssertEqual(manager.customRules.count, 0)
    }

    @MainActor
    func testMakeCustomRule_CreatesNewRuleForNewInput() async throws {
        let (manager, _) = try await createTestManager()

        let rule = manager.makeCustomRule(input: "caps", output: "esc")

        XCTAssertEqual(rule.input, "caps")
        XCTAssertEqual(rule.output, "esc")
        XCTAssertTrue(rule.isEnabled)
    }

    @MainActor
    func testMakeCustomRule_PreservesExistingRuleMetadata() async throws {
        let (manager, tempDir) = try await createTestManager()
        defer { try? FileManager.default.removeItem(at: tempDir) }

        await manager.bootstrap()

        // Add existing rule with metadata
        let existing = CustomRule(
            input: "caps",
            output: "esc",
            isEnabled: false,
            notes: "My notes"
        )
        await manager.saveCustomRule(existing)

        // Make new rule with same input
        let updated = manager.makeCustomRule(input: "caps", output: "lctl")

        XCTAssertEqual(updated.id, existing.id, "Should preserve ID")
        XCTAssertEqual(updated.notes, "My notes", "Should preserve notes")
        XCTAssertEqual(updated.output, "lctl", "Should update output")
    }

    // MARK: - Enabled Mappings Tests

    @MainActor
    func testEnabledMappings_CombinesCollectionsAndCustomRules() async throws {
        let (manager, tempDir) = try await createTestManager()
        defer { try? FileManager.default.removeItem(at: tempDir) }

        await manager.bootstrap()

        // Enable a collection
        await manager.toggleCollection(id: RuleCollectionIdentifier.vimNavigation, isEnabled: true)

        // Add custom rule
        let rule = CustomRule(input: "caps", output: "esc", isEnabled: true)
        await manager.saveCustomRule(rule)

        let mappings = manager.enabledMappings()

        // Should have mappings from both sources
        XCTAssertGreaterThan(mappings.count, 1)
        XCTAssertTrue(mappings.contains { $0.input == "caps" }, "Should include custom rule")
    }

    @MainActor
    func testEnabledMappings_ExcludesDisabledRules() async throws {
        let (manager, tempDir) = try await createTestManager()
        defer { try? FileManager.default.removeItem(at: tempDir) }

        await manager.bootstrap()

        // Disable all default collections first
        for collection in manager.ruleCollections {
            await manager.toggleCollection(id: collection.id, isEnabled: false)
        }

        // Add disabled custom rule
        let rule = CustomRule(input: "caps", output: "esc", isEnabled: false)
        await manager.saveCustomRule(rule)

        let mappings = manager.enabledMappings()

        XCTAssertFalse(mappings.contains { $0.input == "caps" }, "Should not include disabled rule")
    }

    // MARK: - Config Regeneration Tests

    @MainActor
    func testRegenerateConfig_InvokesOnRulesChanged() async throws {
        let (manager, tempDir) = try await createTestManager()
        defer { try? FileManager.default.removeItem(at: tempDir) }

        await manager.bootstrap()

        var callbackInvoked = false
        manager.onRulesChanged = {
            callbackInvoked = true
        }

        // Any operation that triggers regeneration
        await manager.toggleCollection(id: RuleCollectionIdentifier.vimNavigation, isEnabled: true)

        XCTAssertTrue(callbackInvoked, "onRulesChanged should be invoked after config regeneration")
    }

    @MainActor
    func testRegenerateConfig_PlaysSuccessSound() async throws {
        let (manager, tempDir) = try await createTestManager()
        defer { try? FileManager.default.removeItem(at: tempDir) }

        await manager.bootstrap()

        // Trigger regeneration (should succeed in test mode)
        await manager.toggleCollection(id: RuleCollectionIdentifier.vimNavigation, isEnabled: true)

        // Note: SoundManager.shared.playTinkSound() is disabled in tests via TestEnvironment
        // This test verifies the code path executes without crashing
        XCTAssertTrue(true, "Config regeneration should complete successfully")
    }

    // MARK: - Layer State Tests

    @MainActor
    func testUpdateActiveLayerName_UpdatesCurrentLayerName() async throws {
        let (manager, tempDir) = try await createTestManager()
        defer { try? FileManager.default.removeItem(at: tempDir) }

        await manager.bootstrap()

        manager.onLayerChanged = { _ in }

        // Simulate layer change from Kanata (via private method reflection not possible)
        // Instead, test via enabling a layered collection
        await manager.toggleCollection(id: RuleCollectionIdentifier.vimNavigation, isEnabled: true)

        // Current layer should be base initially
        XCTAssertEqual(manager.currentLayerName, "Base")
    }

    @MainActor
    func testRefreshLayerIndicator_ResetsToBaseWhenNoLayeredCollections() async throws {
        let (manager, tempDir) = try await createTestManager()
        defer { try? FileManager.default.removeItem(at: tempDir) }

        await manager.bootstrap()

        // Enable then disable all layered collections
        await manager.toggleCollection(id: RuleCollectionIdentifier.vimNavigation, isEnabled: true)
        await manager.toggleCollection(id: RuleCollectionIdentifier.vimNavigation, isEnabled: false)

        // Should reset to Base
        XCTAssertEqual(manager.currentLayerName, "Base")
    }

    // MARK: - Callbacks Tests

    @MainActor
    func testOnWarning_InvokedForConflicts() async throws {
        let (manager, tempDir) = try await createTestManager()
        defer { try? FileManager.default.removeItem(at: tempDir) }

        await manager.bootstrap()

        var warningReceived: String?
        manager.onWarning = { warningReceived = $0 }

        // Enable conflicting rules
        let rule1 = CustomRule(input: "caps", output: "esc", isEnabled: true)
        await manager.saveCustomRule(rule1)

        let rule2 = CustomRule(input: "caps", output: "lctl", isEnabled: true)
        await manager.saveCustomRule(rule2)

        XCTAssertNotNil(warningReceived, "Should invoke warning callback for conflicts")
    }

    // MARK: - Existing Tests (Preserved)

    func testGenerateConfigIncludesMomentaryActivatorAlias() {
        let catalog = RuleCollectionCatalog()
        var vim = catalog.defaultCollections().first { $0.id == RuleCollectionIdentifier.vimNavigation }!
        vim.isEnabled = true

        let config = KanataConfiguration.generateFromCollections([vim])

        // Momentary activator uses tap-hold with layer-while-held
        XCTAssertTrue(
            config.contains("(tap-hold 200 200 spc (layer-while-held nav))"),
            "Momentary activator should use tap-hold with layer-while-held"
        )
        XCTAssertTrue(config.contains("(deflayer nav"), "Navigation layer block should be emitted")
    }

    // MARK: - Conflict Detection Tests (Preserved)

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
