import Foundation
@testable import KeyPathAppKit
import KeyPathCore
import Testing

// MARK: - Test Helpers

/// Creates a runtime backed by temporary stores and a stub engine reload.
@MainActor
private func makeTestRuntime() throws -> (RuntimeCoordinator, URL) {
    let tempDir = FileManager.default.temporaryDirectory
        .appendingPathComponent("runtime-rule-mutation-\(UUID().uuidString)")
    try FileManager.default.createDirectory(at: tempDir, withIntermediateDirectories: true)

    let configuration = ConfigurationService(configDirectory: tempDir.path)
    let manager = RuleCollectionsManager(
        ruleCollectionStore: RuleCollectionStore(
            fileURL: tempDir.appendingPathComponent("RuleCollections.json")
        ),
        customRulesStore: CustomRulesStore(
            fileURL: tempDir.appendingPathComponent("CustomRules.json")
        ),
        configurationService: configuration,
        eventListener: KanataEventListener()
    )
    let catalog = RuleCollectionCatalog()
    manager.ruleCollections = catalog.defaultCollections()

    let runtime = RuntimeCoordinator(injectedConfigurationService: configuration,
                                     injectedRuleCollectionsManager: manager)
    manager.onRulesChanged = { .init(success: true, response: nil, errorMessage: nil, protocol: nil, disposition: .applied) }
    return (runtime, tempDir)
}

/// Removes a temp directory, ignoring errors.
private func cleanUp(_ url: URL) {
    try? FileManager.default.removeItem(at: url)
}

// MARK: - Batch Operations

@Suite("Runtime rule mutations — Batch Operations")
@MainActor
struct RuntimeRuleBatchTests {
    @Test("batchEnableCollections enables multiple collections")
    func batchEnablesMultiple() async throws {
        let (coordinator, tempDir) = try makeTestRuntime()
        defer { cleanUp(tempDir) }

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

    @Test("batchEnableCollections reloads once and refreshes the runtime mappings")
    func batchRefreshesMappingsAfterOneReload() async throws {
        let (coordinator, tempDir) = try makeTestRuntime()
        defer { cleanUp(tempDir) }

        let manager = coordinator.ruleCollectionsManager
        var reloadCount = 0
        manager.onRulesChanged = {
            reloadCount += 1
            return .init(success: true, response: nil, errorMessage: nil, protocol: nil, disposition: .applied)
        }

        let disabledIDs = coordinator.ruleCollections
            .filter { !$0.isEnabled }
            .prefix(2)
            .map(\.id)

        try #require(disabledIDs.count >= 2, "Need at least 2 disabled collections")

        await coordinator.batchEnableCollections(ids: Array(disabledIDs))

        #expect(reloadCount == 1)
        #expect(coordinator.keyMappings == manager.enabledMappings())
    }
}

// MARK: - Custom Rules

@Suite("Runtime rule mutations — Custom Rules")
@MainActor
struct RuntimeCustomRuleTests {
    @Test("makeCustomRule creates rule with correct input and output")
    func makeCustomRuleCorrectFields() throws {
        let (coordinator, tempDir) = try makeTestRuntime()
        defer { cleanUp(tempDir) }

        let rule = coordinator.makeCustomRule(input: "caps_lock", output: "escape")

        #expect(rule.input == "caps_lock", "Input should match")
        #expect(rule.action == .keystroke(key: "escape"), "Action should be keystroke with the output key")
    }

    @Test("saveCustomRule adds rule to customRules")
    func saveCustomRuleAddsRule() async throws {
        let (coordinator, tempDir) = try makeTestRuntime()
        defer { cleanUp(tempDir) }

        let rule = coordinator.makeCustomRule(input: "a", output: "b")
        let saved = await coordinator.saveCustomRule(rule, skipReload: true)

        #expect(saved == true, "Save should succeed")
        #expect(coordinator.customRules.contains(where: { $0.id == rule.id }),
                "Custom rules should contain the saved rule")
    }

    @Test("removeCustomRule removes the rule")
    func removeCustomRuleRemovesIt() async throws {
        let (coordinator, tempDir) = try makeTestRuntime()
        defer { cleanUp(tempDir) }

        let rule = coordinator.makeCustomRule(input: "q", output: "w")
        _ = await coordinator.saveCustomRule(rule, skipReload: true)
        #expect(!coordinator.customRules.isEmpty, "Should have at least one custom rule after save")

        await coordinator.removeCustomRule(withID: rule.id)

        #expect(!coordinator.customRules.contains(where: { $0.id == rule.id }),
                "Custom rule should be removed")
    }

    @Test("clearAllCustomRules empties the list")
    func clearAllCustomRulesEmptiesList() async throws {
        let (coordinator, tempDir) = try makeTestRuntime()
        defer { cleanUp(tempDir) }

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

@Suite("Runtime rule mutations — Read-Only Access")
@MainActor
struct RuntimeRuleReadOnlyTests {
    @Test("ruleCollections returns manager's collections matching catalog count")
    func ruleCollectionsMatchesCatalog() throws {
        let (coordinator, tempDir) = try makeTestRuntime()
        defer { cleanUp(tempDir) }
        let catalog = RuleCollectionCatalog()
        let expected = catalog.defaultCollections()

        #expect(coordinator.ruleCollections.count == expected.count,
                "Coordinator should expose the same number of collections as the catalog")
    }
}
