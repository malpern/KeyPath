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

    /// Add a simple key remap. Returns `true` if an existing mapping for the input key was replaced.
    @discardableResult
    public func addSimpleRemap(input: String, output: String) async throws -> Bool {
        var rules = await CustomRulesStore.shared.loadRules()
        let hadExisting = rules.contains { $0.input == input }
        rules.removeAll { $0.input == input }
        let rule = CustomRule(input: input, output: output)
        rules.append(rule)
        try await CustomRulesStore.shared.saveRules(rules)
        return hadExisting
    }

    /// Add a tap-hold remap. Returns `true` if an existing mapping for the input key was replaced.
    @discardableResult
    public func addTapHoldRemap(input: String, tap: String, hold: String, timeout: Int = 200) async throws -> Bool {
        var rules = await CustomRulesStore.shared.loadRules()
        let hadExisting = rules.contains { $0.input == input }
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
        return hadExisting
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

    /// Enable a collection by name or ID. Returns the name, or nil if not found. Throws on ambiguous match.
    public func enableCollection(nameOrId: String) async throws -> String? {
        var collections = await RuleCollectionStore.shared.loadCollections()
        guard let index = try resolveCollectionIndex(nameOrId: nameOrId, in: collections) else {
            return nil
        }
        collections[index].isEnabled = true
        try await RuleCollectionStore.shared.saveCollections(collections)
        return collections[index].name
    }

    /// Disable a collection by name or ID. Returns the name, or nil if not found. Throws on ambiguous match.
    public func disableCollection(nameOrId: String) async throws -> String? {
        var collections = await RuleCollectionStore.shared.loadCollections()
        guard let index = try resolveCollectionIndex(nameOrId: nameOrId, in: collections) else {
            return nil
        }
        collections[index].isEnabled = false
        try await RuleCollectionStore.shared.saveCollections(collections)
        return collections[index].name
    }

    /// Show a collection by name or ID. Returns nil if not found. Throws on ambiguous match.
    public func showCollection(nameOrId: String) async throws -> CLIRuleCollection? {
        let collections = await RuleCollectionStore.shared.loadCollections()
        guard let index = try resolveCollectionIndex(nameOrId: nameOrId, in: collections) else {
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

        let client = KanataTCPClient(port: PreferencesService.shared.tcpServerPort)
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
        let port = await MainActor.run { PreferencesService.shared.tcpServerPort }
        let client = KanataTCPClient(port: port)
        return await client.checkServerStatus()
    }

    public func tcpGetLayers() async throws -> [String] {
        let port = await MainActor.run { PreferencesService.shared.tcpServerPort }
        let client = KanataTCPClient(port: port)
        return try await client.requestLayerNames()
    }

    public func tcpReload() async -> Bool {
        let port = await MainActor.run { PreferencesService.shared.tcpServerPort }
        let client = KanataTCPClient(port: port)
        let result = await client.reloadConfig()
        if case .success = result { return true }
        return false
    }

    public func tcpGetHrmStats() async throws -> CLIHrmStats {
        let port = await MainActor.run { PreferencesService.shared.tcpServerPort }
        let client = KanataTCPClient(port: port)
        let stats = try await client.requestHrmStats()
        return CLIHrmStats(
            totalDecisions: stats.decisionsTotal,
            tapCount: stats.tapCount,
            holdCount: stats.holdCount
        )
    }

    public func tcpResetHrmStats() async throws {
        let port = await MainActor.run { PreferencesService.shared.tcpServerPort }
        let client = KanataTCPClient(port: port)
        try await client.resetHrmStats()
    }

    // MARK: - Status

    // ⚠️ inspectSystem() calls SMAppService.status which does synchronous IPC —
    // can take 10-30s under launchd load. Callers should be aware of potential latency.
    @MainActor
    public func runStatus() async -> CLIStatusResult {
        let engine = InstallerEngine()
        let context = await engine.inspectSystem()

        return CLIStatusResult(
            isOperational: context.permissions.isSystemReady
                && context.helper.isReady
                && context.components.hasAllRequired
                && context.services.isHealthy
                && !context.conflicts.hasConflicts,
            helperInstalled: context.helper.isInstalled,
            helperWorking: context.helper.isWorking,
            helperVersion: context.helper.version,
            keyPathAccessibility: context.permissions.keyPath.accessibility.isReady,
            keyPathInputMonitoring: context.permissions.keyPath.inputMonitoring.isReady,
            kanataAccessibility: context.permissions.kanata.accessibility.isReady,
            kanataInputMonitoring: context.permissions.kanata.inputMonitoring.isReady,
            kanataBinaryInstalled: context.components.kanataBinaryInstalled,
            karabinerDriverInstalled: context.components.karabinerDriverInstalled,
            vhidDeviceHealthy: context.components.vhidDeviceHealthy,
            kanataRunning: context.services.kanataRunning,
            karabinerDaemonRunning: context.services.karabinerDaemonRunning,
            vhidHealthy: context.services.vhidHealthy,
            hasConflicts: context.conflicts.hasConflicts,
            timestamp: context.timestamp
        )
    }

    // MARK: - Key Validation

    /// Validate a key name against the Kanata key set. Returns the canonical form, or nil if invalid.
    public func validateKey(_ key: String) -> String? {
        guard CustomRuleValidator.isValidKey(key) else { return nil }
        return CustomRuleValidator.normalizeKey(key)
    }

    // MARK: - Helpers

    /// Resolve a collection by name or UUID. Returns nil if not found. Throws `AmbiguousCollectionMatch` on multiple matches.
    private func resolveCollectionIndex(nameOrId: String, in collections: [RuleCollection]) throws -> Int? {
        // Exact UUID match
        if let index = collections.firstIndex(where: { $0.id.uuidString == nameOrId }) {
            return index
        }

        // Exact name match (case-insensitive)
        let exactMatches = collections.enumerated().filter {
            $0.element.name.caseInsensitiveCompare(nameOrId) == .orderedSame
        }
        if exactMatches.count == 1 {
            return exactMatches[0].offset
        }

        // Substring match as fallback
        let substringMatches = collections.enumerated().filter {
            $0.element.name.localizedCaseInsensitiveContains(nameOrId)
        }
        if substringMatches.count == 1 {
            return substringMatches[0].offset
        }
        if substringMatches.count > 1 {
            throw AmbiguousCollectionMatch(
                query: nameOrId,
                matches: substringMatches.map { .init(name: $0.element.name, id: $0.element.id.uuidString) }
            )
        }

        return nil
    }
}

/// Thrown when a collection name/ID query matches multiple collections.
public struct AmbiguousCollectionMatch: Error, CustomStringConvertible {
    public struct Match: Sendable {
        public let name: String
        public let id: String
    }

    public let query: String
    public let matches: [Match]

    public var description: String {
        var lines = ["Found \(matches.count) collections matching \"\(query)\":"]
        for match in matches {
            lines.append("  - \(match.name) (id: \(match.id))")
        }
        lines.append("Use the full name or ID to disambiguate.")
        return lines.joined(separator: "\n")
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

    public init(from collection: RuleCollection) {
        id = collection.id.uuidString
        name = collection.name
        isEnabled = collection.isEnabled
        mappingCount = collection.mappings.count
        summary = collection.summary
    }
}

public struct CLIApplyResult: Codable, Sendable {
    public let collectionsCount: Int
    public let enabledCount: Int
    public let customRulesCount: Int
    public let reloadSuccess: Bool
}

public struct CLIHrmStats: Codable, Sendable {
    public let totalDecisions: Int
    public let tapCount: Int
    public let holdCount: Int
}

public struct CLIStatusResult: Codable, Sendable {
    public let isOperational: Bool
    public let helperInstalled: Bool
    public let helperWorking: Bool
    public let helperVersion: String?
    public let keyPathAccessibility: Bool
    public let keyPathInputMonitoring: Bool
    public let kanataAccessibility: Bool
    public let kanataInputMonitoring: Bool
    public let kanataBinaryInstalled: Bool
    public let karabinerDriverInstalled: Bool
    public let vhidDeviceHealthy: Bool
    public let kanataRunning: Bool
    public let karabinerDaemonRunning: Bool
    public let vhidHealthy: Bool
    public let hasConflicts: Bool
    public let timestamp: Date
}
