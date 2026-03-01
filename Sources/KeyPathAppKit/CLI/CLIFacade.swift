import Foundation
import KeyPathCore
import KeyPathWizardCore

/// Public facade exposing KeyPathAppKit internals for the CLI binary.
/// This is the stable API boundary between the CLI and the app library.
public struct CLIFacade: Sendable {
    public init() {}

    // MARK: - Custom Rules

    public func loadCustomRules() async -> [CLICustomRule] {
        let rules = await CustomRulesStore.shared.loadRules()
        return rules.map { CLICustomRule(input: $0.input, output: $0.output, behavior: $0.behavior.map { String(describing: $0) }) }
    }

    public func addSimpleRemap(input: String, output: String) async throws {
        var rules = await CustomRulesStore.shared.loadRules()
        rules.removeAll { $0.input == input }
        let rule = CustomRule(input: input, output: output)
        rules.append(rule)
        try await CustomRulesStore.shared.saveRules(rules)
    }

    public func addTapHoldRemap(input: String, tap: String, hold: String, timeout: Int = 200) async throws {
        var rules = await CustomRulesStore.shared.loadRules()
        rules.removeAll { $0.input == input }
        let rule = CustomRule(
            input: input,
            output: tap,
            behavior: .dualRole(DualRoleBehavior(
                tapAction: tap,
                holdAction: hold,
                tapTimeout: timeout
            ))
        )
        rules.append(rule)
        try await CustomRulesStore.shared.saveRules(rules)
    }

    public func removeRemap(input: String) async throws -> Bool {
        var rules = await CustomRulesStore.shared.loadRules()
        let before = rules.count
        rules.removeAll { $0.input == input }
        if rules.count == before { return false }
        try await CustomRulesStore.shared.saveRules(rules)
        return true
    }

    // MARK: - Rule Collections

    public func loadRuleCollections() async -> [CLIRuleCollection] {
        let collections = await RuleCollectionStore.shared.loadCollections()
        return collections.map { CLIRuleCollection(from: $0) }
    }

    public func enableCollection(nameOrId: String) async throws -> String? {
        var collections = await RuleCollectionStore.shared.loadCollections()
        guard let index = findCollectionIndex(nameOrId: nameOrId, in: collections) else {
            return nil
        }
        collections[index].isEnabled = true
        try await RuleCollectionStore.shared.saveCollections(collections)
        return collections[index].name
    }

    public func disableCollection(nameOrId: String) async throws -> String? {
        var collections = await RuleCollectionStore.shared.loadCollections()
        guard let index = findCollectionIndex(nameOrId: nameOrId, in: collections) else {
            return nil
        }
        collections[index].isEnabled = false
        try await RuleCollectionStore.shared.saveCollections(collections)
        return collections[index].name
    }

    public func showCollection(nameOrId: String) async -> CLIRuleCollection? {
        let collections = await RuleCollectionStore.shared.loadCollections()
        guard let index = findCollectionIndex(nameOrId: nameOrId, in: collections) else {
            return nil
        }
        return CLIRuleCollection(from: collections[index])
    }

    // MARK: - Configuration

    @MainActor
    public func currentConfig() async -> String {
        let service = ConfigurationService()
        let config = await service.current()
        return config.content
    }

    @MainActor
    public func configPath() -> String {
        ConfigurationService().configurationPath
    }

    // MARK: - Apply Pipeline

    @MainActor
    public func applyConfiguration() async throws -> CLIApplyResult {
        let collections = await RuleCollectionStore.shared.loadCollections()
        let customRules = await CustomRulesStore.shared.loadRules()
        let enabledCount = collections.filter(\.isEnabled).count

        let service = ConfigurationService()
        try await service.saveConfiguration(
            ruleCollections: collections,
            customRules: customRules
        )

        let client = KanataTCPClient(port: 37001)
        let result = await client.reloadConfig()
        let reloadSuccess: Bool
        if case .success = result {
            reloadSuccess = true
        } else {
            reloadSuccess = false
        }

        return CLIApplyResult(
            collectionsCount: collections.count,
            enabledCount: enabledCount,
            customRulesCount: customRules.count,
            reloadSuccess: reloadSuccess
        )
    }

    // MARK: - TCP

    public func tcpCheckHealth() async -> Bool {
        let client = KanataTCPClient(port: 37001)
        return await client.checkServerStatus()
    }

    public func tcpGetLayers() async throws -> [String] {
        let client = KanataTCPClient(port: 37001)
        return try await client.requestLayerNames()
    }

    public func tcpReload() async -> Bool {
        let client = KanataTCPClient(port: 37001)
        let result = await client.reloadConfig()
        if case .success = result { return true }
        return false
    }

    public func tcpGetHrmStats() async throws -> CLIHrmStats {
        let client = KanataTCPClient(port: 37001)
        let stats = try await client.requestHrmStats()
        return CLIHrmStats(
            totalDecisions: stats.decisionsTotal,
            tapCount: stats.tapCount,
            holdCount: stats.holdCount
        )
    }

    public func tcpResetHrmStats() async throws {
        let client = KanataTCPClient(port: 37001)
        try await client.resetHrmStats()
    }

    // MARK: - Status (delegates to existing KeyPathCLI)

    @MainActor
    public func runStatus() async -> Int32 {
        let cli = KeyPathCLI()
        return await cli.run(arguments: ["keypath", "status"])
    }

    // MARK: - Helpers

    private func findCollectionIndex(nameOrId: String, in collections: [RuleCollection]) -> Int? {
        collections.firstIndex {
            $0.id.uuidString == nameOrId || $0.name.localizedCaseInsensitiveContains(nameOrId)
        }
    }
}

// MARK: - Public CLI Types

public struct CLICustomRule: Codable, Sendable {
    public let input: String
    public let output: String
    public let behavior: String?
}

public struct CLIRuleCollection: Codable, Sendable {
    public let id: String
    public let name: String
    public let isEnabled: Bool
    public let mappingCount: Int
    public let summary: String

    init(from internal_: RuleCollection) {
        id = internal_.id.uuidString
        name = internal_.name
        isEnabled = internal_.isEnabled
        mappingCount = internal_.mappings.count
        summary = internal_.summary
    }
}

public struct CLIApplyResult: Sendable {
    public let collectionsCount: Int
    public let enabledCount: Int
    public let customRulesCount: Int
    public let reloadSuccess: Bool
}

public struct CLIHrmStats: Sendable {
    public let totalDecisions: Int
    public let tapCount: Int
    public let holdCount: Int
}
