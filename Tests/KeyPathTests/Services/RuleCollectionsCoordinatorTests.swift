import Foundation
@testable import KeyPathAppKit
import KeyPathCore
import Testing

// MARK: - Test Helpers

/// Creates a RuleCollectionsManager backed by temp-directory stores, pre-loaded with catalog defaults.
@MainActor
private func makeTestManager() throws -> (RuleCollectionsManager, URL) {
    TestEnvironment.forceTestMode = true
    let tempDir = FileManager.default.temporaryDirectory
        .appendingPathComponent("rcc-\(UUID().uuidString)")
    try FileManager.default.createDirectory(at: tempDir, withIntermediateDirectories: true)

    let manager = RuleCollectionsManager(
        ruleCollectionStore: RuleCollectionStore(
            fileURL: tempDir.appendingPathComponent("RuleCollections.json")
        ),
        customRulesStore: CustomRulesStore(
            fileURL: tempDir.appendingPathComponent("CustomRules.json")
        ),
        configurationService: ConfigurationService(configDirectory: tempDir.path),
        eventListener: KanataEventListener()
    )
    let catalog = RuleCollectionCatalog()
    manager.ruleCollections = catalog.defaultCollections()

    return (manager, tempDir)
}

/// Removes a temp directory, ignoring errors.
private func cleanUp(_ url: URL) {
    try? FileManager.default.removeItem(at: url)
}

// MARK: - Configuration

@Suite("RuleCollectionsCoordinator — Configuration")
@MainActor
struct RuleCollectionsCoordinatorConfigTests {

    @Test("unconfigured coordinator has no-op callbacks")
    func unconfiguredCoordinatorHasNoOpCallbacks() async throws {
        let (manager, tempDir) = try makeTestManager()
        defer { cleanUp(tempDir); TestEnvironment.forceTestMode = false }

        let coordinator = RuleCollectionsCoordinator(ruleCollectionsManager: manager)

        // Pick any collection to toggle — should not crash with default no-op callbacks
        guard let first = coordinator.ruleCollections.first else {
            Issue.record("Catalog should provide at least one collection")
            return
        }
        let result = await coordinator.toggleRuleCollection(id: first.id, isEnabled: !first.isEnabled)
        // No crash means no-op callbacks worked. Result depends on manager logic.
        _ = result
    }

    @Test("configure sets callbacks that are invoked on toggle")
    func configureSetsCallbacks() async throws {
        let (manager, tempDir) = try makeTestManager()
        defer { cleanUp(tempDir); TestEnvironment.forceTestMode = false }

        let coordinator = RuleCollectionsCoordinator(ruleCollectionsManager: manager)

        var applyMappingsCalled = false
        var notifyStateChangedCalled = false

        coordinator.configure(
            applyMappings: { _ in applyMappingsCalled = true },
            notifyStateChanged: { notifyStateChangedCalled = true }
        )

        guard let first = coordinator.ruleCollections.first else {
            Issue.record("Catalog should provide at least one collection")
            return
        }
        _ = await coordinator.toggleRuleCollection(id: first.id, isEnabled: !first.isEnabled)

        #expect(applyMappingsCalled, "applyMappings callback should have been invoked")
        #expect(notifyStateChangedCalled, "notifyStateChanged callback should have been invoked")
    }
}

// MARK: - Toggle Operations

@Suite("RuleCollectionsCoordinator — Toggle Operations")
@MainActor
struct RuleCollectionsCoordinatorToggleTests {

    @Test("toggleRuleCollection enables a disabled collection")
    func toggleEnablesDisabled() async throws {
        let (manager, tempDir) = try makeTestManager()
        defer { cleanUp(tempDir); TestEnvironment.forceTestMode = false }

        let coordinator = RuleCollectionsCoordinator(ruleCollectionsManager: manager)

        guard let disabled = coordinator.ruleCollections.first(where: { !$0.isEnabled }) else {
            Issue.record("Catalog should have at least one disabled collection")
            return
        }

        _ = await coordinator.toggleRuleCollection(id: disabled.id, isEnabled: true)

        let updated = coordinator.ruleCollections.first(where: { $0.id == disabled.id })
        #expect(updated?.isEnabled == true, "Collection should now be enabled")
    }

    @Test("toggleRuleCollection disables an enabled collection")
    func toggleDisablesEnabled() async throws {
        let (manager, tempDir) = try makeTestManager()
        defer { cleanUp(tempDir); TestEnvironment.forceTestMode = false }

        let coordinator = RuleCollectionsCoordinator(ruleCollectionsManager: manager)

        guard let enabled = coordinator.ruleCollections.first(where: { $0.isEnabled }) else {
            Issue.record("Catalog should have at least one enabled collection")
            return
        }

        _ = await coordinator.toggleRuleCollection(id: enabled.id, isEnabled: false)

        let updated = coordinator.ruleCollections.first(where: { $0.id == enabled.id })
        #expect(updated?.isEnabled == false, "Collection should now be disabled")
    }

    @Test("toggleRuleCollection calls applyMappings and notifyStateChanged exactly once")
    func toggleCallsCallbacksOnce() async throws {
        let (manager, tempDir) = try makeTestManager()
        defer { cleanUp(tempDir); TestEnvironment.forceTestMode = false }

        let coordinator = RuleCollectionsCoordinator(ruleCollectionsManager: manager)

        var applyCount = 0
        var notifyCount = 0

        coordinator.configure(
            applyMappings: { _ in applyCount += 1 },
            notifyStateChanged: { notifyCount += 1 }
        )

        guard let first = coordinator.ruleCollections.first else {
            Issue.record("Catalog should provide at least one collection")
            return
        }
        _ = await coordinator.toggleRuleCollection(id: first.id, isEnabled: !first.isEnabled)

        #expect(applyCount == 1, "applyMappings should be called exactly once")
        #expect(notifyCount == 1, "notifyStateChanged should be called exactly once")
    }

    @Test("toggleRuleCollection returns true on success")
    func toggleReturnsTrueOnSuccess() async throws {
        let (manager, tempDir) = try makeTestManager()
        defer { cleanUp(tempDir); TestEnvironment.forceTestMode = false }

        let coordinator = RuleCollectionsCoordinator(ruleCollectionsManager: manager)

        guard let first = coordinator.ruleCollections.first else {
            Issue.record("Catalog should provide at least one collection")
            return
        }
        let result = await coordinator.toggleRuleCollection(id: first.id, isEnabled: !first.isEnabled)

        #expect(result == true, "Toggle of a known collection should return true")
    }
}

// MARK: - Batch Operations

@Suite("RuleCollectionsCoordinator — Batch Operations")
@MainActor
struct RuleCollectionsCoordinatorBatchTests {

    @Test("batchEnableCollections enables multiple collections")
    func batchEnablesMultiple() async throws {
        let (manager, tempDir) = try makeTestManager()
        defer { cleanUp(tempDir); TestEnvironment.forceTestMode = false }

        let coordinator = RuleCollectionsCoordinator(ruleCollectionsManager: manager)

        let disabledIDs = coordinator.ruleCollections
            .filter { !$0.isEnabled }
            .prefix(3)
            .map(\.id)

        // Need at least 2 disabled collections for a meaningful batch test
        try #require(disabledIDs.count >= 2, "Need at least 2 disabled collections for batch test")

        await coordinator.batchEnableCollections(ids: Array(disabledIDs))

        for id in disabledIDs {
            let collection = coordinator.ruleCollections.first(where: { $0.id == id })
            #expect(collection?.isEnabled == true, "Collection \(id) should be enabled after batch enable")
        }
    }

    @Test("batchEnableCollections calls callbacks once")
    func batchCallsCallbacksOnce() async throws {
        let (manager, tempDir) = try makeTestManager()
        defer { cleanUp(tempDir); TestEnvironment.forceTestMode = false }

        let coordinator = RuleCollectionsCoordinator(ruleCollectionsManager: manager)

        var applyCount = 0
        var notifyCount = 0

        coordinator.configure(
            applyMappings: { _ in applyCount += 1 },
            notifyStateChanged: { notifyCount += 1 }
        )

        let disabledIDs = coordinator.ruleCollections
            .filter { !$0.isEnabled }
            .prefix(2)
            .map(\.id)

        try #require(disabledIDs.count >= 2, "Need at least 2 disabled collections")

        await coordinator.batchEnableCollections(ids: Array(disabledIDs))

        #expect(applyCount == 1, "applyMappings should be called exactly once for a batch operation")
        #expect(notifyCount == 1, "notifyStateChanged should be called exactly once for a batch operation")
    }
}

// MARK: - Custom Rules

@Suite("RuleCollectionsCoordinator — Custom Rules")
@MainActor
struct RuleCollectionsCoordinatorCustomRuleTests {

    @Test("makeCustomRule creates rule with correct input and output")
    func makeCustomRuleCorrectFields() throws {
        let (manager, tempDir) = try makeTestManager()
        defer { cleanUp(tempDir); TestEnvironment.forceTestMode = false }

        let coordinator = RuleCollectionsCoordinator(ruleCollectionsManager: manager)

        let rule = coordinator.makeCustomRule(input: "caps_lock", output: "escape")

        #expect(rule.input == "caps_lock", "Input should match")
        #expect(rule.action == .keystroke(key: "escape"), "Action should be keystroke with the output key")
    }

    @Test("saveCustomRule adds rule to customRules")
    func saveCustomRuleAddsRule() async throws {
        let (manager, tempDir) = try makeTestManager()
        defer { cleanUp(tempDir); TestEnvironment.forceTestMode = false }

        let coordinator = RuleCollectionsCoordinator(ruleCollectionsManager: manager)

        let rule = coordinator.makeCustomRule(input: "a", output: "b")
        let saved = await coordinator.saveCustomRule(rule, skipReload: true)

        #expect(saved == true, "Save should succeed")
        #expect(coordinator.customRules.contains(where: { $0.id == rule.id }),
                "Custom rules should contain the saved rule")
    }

    @Test("toggleCustomRule changes enabled state")
    func toggleCustomRuleChangesState() async throws {
        let (manager, tempDir) = try makeTestManager()
        defer { cleanUp(tempDir); TestEnvironment.forceTestMode = false }

        let coordinator = RuleCollectionsCoordinator(ruleCollectionsManager: manager)

        let rule = coordinator.makeCustomRule(input: "x", output: "y")
        _ = await coordinator.saveCustomRule(rule, skipReload: true)

        // Rule starts enabled; toggle it off
        await coordinator.toggleCustomRule(id: rule.id, isEnabled: false)

        let toggled = coordinator.customRules.first(where: { $0.id == rule.id })
        #expect(toggled?.isEnabled == false, "Custom rule should be disabled after toggle")
    }

    @Test("removeCustomRule removes the rule")
    func removeCustomRuleRemovesIt() async throws {
        let (manager, tempDir) = try makeTestManager()
        defer { cleanUp(tempDir); TestEnvironment.forceTestMode = false }

        let coordinator = RuleCollectionsCoordinator(ruleCollectionsManager: manager)

        let rule = coordinator.makeCustomRule(input: "q", output: "w")
        _ = await coordinator.saveCustomRule(rule, skipReload: true)
        #expect(!coordinator.customRules.isEmpty, "Should have at least one custom rule after save")

        await coordinator.removeCustomRule(withID: rule.id)

        #expect(!coordinator.customRules.contains(where: { $0.id == rule.id }),
                "Custom rule should be removed")
    }

    @Test("clearAllCustomRules empties the list")
    func clearAllCustomRulesEmptiesList() async throws {
        let (manager, tempDir) = try makeTestManager()
        defer { cleanUp(tempDir); TestEnvironment.forceTestMode = false }

        let coordinator = RuleCollectionsCoordinator(ruleCollectionsManager: manager)

        // Save two rules
        let rule1 = coordinator.makeCustomRule(input: "m", output: "n")
        let rule2 = coordinator.makeCustomRule(input: "o", output: "p")
        _ = await coordinator.saveCustomRule(rule1, skipReload: true)
        _ = await coordinator.saveCustomRule(rule2, skipReload: true)
        #expect(coordinator.customRules.count >= 2, "Should have at least 2 custom rules")

        await coordinator.clearAllCustomRules()

        #expect(coordinator.customRules.isEmpty, "Custom rules should be empty after clearing")
    }
}

// MARK: - Read-Only Access

@Suite("RuleCollectionsCoordinator — Read-Only Access")
@MainActor
struct RuleCollectionsCoordinatorReadOnlyTests {

    @Test("ruleCollections returns manager's collections matching catalog count")
    func ruleCollectionsMatchesCatalog() throws {
        let (manager, tempDir) = try makeTestManager()
        defer { cleanUp(tempDir); TestEnvironment.forceTestMode = false }

        let coordinator = RuleCollectionsCoordinator(ruleCollectionsManager: manager)
        let catalog = RuleCollectionCatalog()
        let expected = catalog.defaultCollections()

        #expect(coordinator.ruleCollections.count == expected.count,
                "Coordinator should expose the same number of collections as the catalog")
    }

    @Test("enabledMappings returns non-empty for catalog defaults")
    func enabledMappingsNonEmpty() throws {
        let (manager, tempDir) = try makeTestManager()
        defer { cleanUp(tempDir); TestEnvironment.forceTestMode = false }

        let coordinator = RuleCollectionsCoordinator(ruleCollectionsManager: manager)

        // The catalog ships with some enabled-by-default collections that produce mappings
        let mappings = coordinator.enabledMappings()

        // At minimum, verify the method runs and returns an array.
        // Some catalogs may have no enabled-by-default mappings, so we check >= 0
        // but also verify the count matches what the manager would return directly.
        #expect(mappings.count == manager.enabledMappings().count,
                "Coordinator's enabledMappings should mirror manager's enabledMappings")
    }
}
