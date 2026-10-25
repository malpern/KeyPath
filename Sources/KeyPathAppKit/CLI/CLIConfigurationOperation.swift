import Foundation
import KeyPathCore

/// A command-scoped view of the existing configuration operation gate.
/// Scoped facades may compose writes and apply without releasing ownership.
/// They cannot be used to mutate after the command returns.
public struct CLIConfigurationOperation: Sendable {
    let service: ConfigurationService
    let permit: ConfigurationOperationGate.Permit
    let directory: String
    let installedPackTracker: InstalledPackTracker

    public var rules: RulesFacade {
        RulesFacade(operation: self)
    }

    public var collections: CollectionsFacade {
        CollectionsFacade(operation: self)
    }

    public var packs: PacksFacade {
        PacksFacade(operation: self)
    }

    public var config: ConfigFacade {
        ConfigFacade(operation: self)
    }

    public static func run<Result: Sendable>(
        _ body: @escaping @Sendable (CLIConfigurationOperation) async throws -> Result
    ) async throws -> Result {
        try await run(configDirectory: KeyPathConstants.Config.directory, body)
    }

    /// Test seam for isolated rule/config operations. Pack uninstall snapshots
    /// still use the standard user directory, so this is not a public workspace API.
    static func run<Result: Sendable>(
        configDirectory: String,
        _ body: @escaping @Sendable (CLIConfigurationOperation) async throws -> Result
    ) async throws -> Result {
        let directory = URL(fileURLWithPath: configDirectory, isDirectory: true)
        let service = await MainActor.run {
            ConfigurationService(
                configDirectory: configDirectory,
                ruleCollectionStore: RuleCollectionStore(fileURL: directory.appendingPathComponent("RuleCollections.json")),
                customRulesStore: CustomRulesStore(fileURL: directory.appendingPathComponent("CustomRules.json"))
            )
        }
        return try await service.operationGate.withOperation { permit in
            try await body(Self(service: service, permit: permit, directory: configDirectory,
                                installedPackTracker: InstalledPackTracker(fileURL: directory.appendingPathComponent("installed-packs.json"))))
        }
    }
}
