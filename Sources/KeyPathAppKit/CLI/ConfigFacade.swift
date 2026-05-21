import Foundation
import KeyPathCore

public struct ConfigFacade: Sendable {
    public init() {}

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

    @MainActor
    public func validateConfig() async -> CLIValidationResult {
        let service = ConfigurationService()
        let config = await service.current()
        if config.content.isEmpty {
            return CLIValidationResult(isValid: false, errors: ["No configuration generated yet. Run 'keypath apply' first."])
        }
        let result = await service.validateConfiguration(config.content)
        return CLIValidationResult(isValid: result.isValid, errors: result.errors)
    }

    // MARK: - Apply

    public func applyConfiguration() async throws -> CLIApplyResult {
        let collections = await RuleCollectionStore.shared.loadCollections()
        let customRules = await CustomRulesStore.shared.loadRules()
        let enabledCount = collections.filter(\.isEnabled).count

        let service = await MainActor.run { ConfigurationService() }
        try await service.saveConfiguration(
            ruleCollections: collections,
            customRules: customRules
        )

        let port = await MainActor.run { PreferencesService.shared.tcpServerPort }
        let client = KanataTCPClient(port: port)
        let result = await client.reloadConfig()
        let reloadSuccess = if case .success = result {
            true
        } else {
            false
        }

        let changeset = CLIApplyChangeset(
            enabledCollections: collections.filter(\.isEnabled).map(\.name),
            disabledCollections: collections.filter { !$0.isEnabled }.map(\.name),
            customRules: customRules.filter(\.isEnabled).map { "\($0.input) → \($0.action.outputString)" }
        )

        return CLIApplyResult(
            collectionsCount: collections.count,
            enabledCount: enabledCount,
            customRulesCount: customRules.count,
            reloadSuccess: reloadSuccess,
            changeset: changeset
        )
    }

    // MARK: - TCP

    func tcpClient() async -> KanataTCPClient {
        let port = await MainActor.run { PreferencesService.shared.tcpServerPort }
        return KanataTCPClient(port: port)
    }

    public func tcpCheckHealth() async -> Bool {
        let client = await tcpClient()
        return await client.checkServerStatus()
    }

    public func tcpGetLayers() async throws -> [String] {
        let client = await tcpClient()
        return try await client.requestLayerNames()
    }

    public func tcpReload() async -> Bool {
        let client = await tcpClient()
        let result = await client.reloadConfig()
        if case .success = result { return true }
        return false
    }

    public func tcpGetHrmStats() async throws -> CLIHrmStats {
        let client = await tcpClient()
        let stats = try await client.requestHrmStats()
        return CLIHrmStats(
            totalDecisions: stats.decisionsTotal,
            tapCount: stats.tapCount,
            holdCount: stats.holdCount
        )
    }

    public func tcpResetHrmStats() async throws {
        let client = await tcpClient()
        try await client.resetHrmStats()
    }

    public func tcpChangeLayer(_ layerName: String) async -> Bool {
        let client = await tcpClient()
        let result = await client.changeLayer(layerName)
        if case .success = result { return true }
        return false
    }
}

// MARK: - Config Types

public struct CLIApplyResult: Codable, Sendable {
    public let collectionsCount: Int
    public let enabledCount: Int
    public let customRulesCount: Int
    public let reloadSuccess: Bool
    public let changeset: CLIApplyChangeset?
}

public struct CLIApplyChangeset: Codable, Sendable {
    public let enabledCollections: [String]
    public let disabledCollections: [String]
    public let customRules: [String]
}

public struct CLIValidationResult: Codable, Sendable {
    public let isValid: Bool
    public let errors: [String]
    public let configPath: String?
    public let configBytes: Int?
    public let collectionsCount: Int?
    public let customRulesCount: Int?

    public init(isValid: Bool, errors: [String], configPath: String? = nil, configBytes: Int? = nil, collectionsCount: Int? = nil, customRulesCount: Int? = nil) {
        self.isValid = isValid
        self.errors = errors
        self.configPath = configPath
        self.configBytes = configBytes
        self.collectionsCount = collectionsCount
        self.customRulesCount = customRulesCount
    }
}

public struct CLIHrmStats: Codable, Sendable {
    public let totalDecisions: Int
    public let tapCount: Int
    public let holdCount: Int
}
