import Foundation
import KeyPathCore

public struct ConfigFacade: Sendable {
    private let configDirectory: String
    private let ruleCollectionLoader: @Sendable () async -> [RuleCollection]
    private let customRuleLoader: @Sendable () async -> [CustomRule]
    private let reloadHandler: (@Sendable () async -> Bool)?

    public init(configDirectory: String = KeyPathConstants.Config.directory) {
        self.configDirectory = configDirectory
        ruleCollectionLoader = { await RuleCollectionStore.shared.loadCollections() }
        customRuleLoader = { await CustomRulesStore.shared.loadRules() }
        reloadHandler = nil
    }

    init(
        configDirectory: String,
        ruleCollectionLoader: @escaping @Sendable () async -> [RuleCollection],
        customRuleLoader: @escaping @Sendable () async -> [CustomRule],
        reloadHandler: (@Sendable () async -> Bool)? = nil
    ) {
        self.configDirectory = configDirectory
        self.ruleCollectionLoader = ruleCollectionLoader
        self.customRuleLoader = customRuleLoader
        self.reloadHandler = reloadHandler
    }

    // MARK: - Configuration

    @MainActor
    public func currentConfig() async -> String {
        let service = ConfigurationService(configDirectory: configDirectory)
        let config = await service.current()
        return config.content
    }

    @MainActor
    public func configPath() -> String {
        ConfigurationService(configDirectory: configDirectory).configurationPath
    }

    @MainActor
    public func validateConfig() async -> CLIValidationResult {
        let service = ConfigurationService(configDirectory: configDirectory)
        let config = await service.current()
        if config.content.isEmpty {
            return CLIValidationResult(isValid: false, errors: ["No configuration generated yet. Run 'keypath apply' first."])
        }
        let result = await service.validateConfiguration(config.content)
        return CLIValidationResult(isValid: result.isValid, errors: result.errors)
    }

    // MARK: - Apply

    public func applyConfiguration(dryRun: Bool = false) async throws -> CLIApplyResult {
        let collections = await ruleCollectionLoader()
        let customRules = await customRuleLoader()
        let enabledCount = collections.filter(\.isEnabled).count

        let service = await MainActor.run { ConfigurationService(configDirectory: configDirectory) }

        if dryRun {
            let previewConfig = try await service.generateConfiguration(
                ruleCollections: collections,
                customRules: customRules
            )
            try await validateDryRunConfig(previewConfig.content)

            return CLIApplyResult(
                collectionsCount: collections.count,
                enabledCount: enabledCount,
                customRulesCount: customRules.count,
                reloadSuccess: false,
                changeset: changeset(collections: collections, customRules: customRules),
                dryRun: true
            )
        }

        try await service.saveConfiguration(
            ruleCollections: collections,
            customRules: customRules
        )

        let reloadSuccess = if let reloadHandler {
            await reloadHandler()
        } else {
            await tcpReload()
        }

        return CLIApplyResult(
            collectionsCount: collections.count,
            enabledCount: enabledCount,
            customRulesCount: customRules.count,
            reloadSuccess: reloadSuccess,
            changeset: changeset(collections: collections, customRules: customRules)
        )
    }

    // MARK: - Backup / Restore

    public func backupConfig(outputPath: String? = nil) throws -> CLIConfigBackupResult {
        let fileManager = FileManager.default
        let sourceURL = URL(fileURLWithPath: configDirectory, isDirectory: true)
        let sourceCopyURL = try resolvedExistingDirectory(sourceURL, fileManager: fileManager)
        guard fileManager.fileExists(atPath: sourceCopyURL.path) else {
            throw Self.error("Config directory does not exist: \(sourceURL.path)")
        }

        let destinationURL = try outputPath.map {
            URL(fileURLWithPath: ($0 as NSString).expandingTildeInPath, isDirectory: true)
        } ?? defaultBackupURL()

        if fileManager.fileExists(atPath: destinationURL.path) {
            throw Self.error("Backup destination already exists: \(destinationURL.path)")
        }

        try fileManager.createDirectory(
            at: destinationURL.deletingLastPathComponent(),
            withIntermediateDirectories: true
        )
        try fileManager.createDirectory(at: destinationURL, withIntermediateDirectories: true)
        try copyDirectoryContents(from: sourceCopyURL, to: destinationURL, fileManager: fileManager)

        return try CLIConfigBackupResult(
            sourcePath: sourceURL.path,
            backupPath: destinationURL.path,
            copiedItems: copiedItemNames(in: destinationURL)
        )
    }

    public func restoreConfig(from backupPath: String, reload: Bool) async throws -> CLIConfigRestoreResult {
        let fileManager = FileManager.default
        let sourceURL = URL(fileURLWithPath: (backupPath as NSString).expandingTildeInPath, isDirectory: true)
        var isDirectory: ObjCBool = false
        guard fileManager.fileExists(atPath: sourceURL.path, isDirectory: &isDirectory), isDirectory.boolValue else {
            throw Self.error("Backup directory does not exist: \(sourceURL.path)")
        }

        let resolvedSourceURL = try resolvedExistingDirectory(sourceURL, fileManager: fileManager)
        let destinationURL = URL(fileURLWithPath: configDirectory, isDirectory: true)
        try fileManager.createDirectory(
            at: destinationURL.deletingLastPathComponent(),
            withIntermediateDirectories: true
        )

        let restoreTargetURL: URL
        if fileManager.fileExists(atPath: destinationURL.path) {
            restoreTargetURL = try resolvedExistingDirectory(destinationURL, fileManager: fileManager)
        } else {
            restoreTargetURL = destinationURL
            try fileManager.createDirectory(at: restoreTargetURL, withIntermediateDirectories: true)
        }

        if sameResolvedPath(resolvedSourceURL, restoreTargetURL) {
            throw Self.error("Backup path resolves to the active config directory: \(sourceURL.path)")
        }

        // Copy-over first, prune extras second: a failure at any point leaves the
        // user with a superset of their config, never a gutted directory. The
        // previous wipe-then-copy ordering lost data when a transient
        // temp_validation_*.kbd file vanished mid-wipe and aborted the restore
        // before anything was copied back (#881).
        try overwriteDirectoryContents(from: resolvedSourceURL, to: restoreTargetURL, fileManager: fileManager)
        try pruneExtraneousItems(
            at: restoreTargetURL,
            keeping: Set(fileManager.contentsOfDirectory(atPath: resolvedSourceURL.path)),
            fileManager: fileManager
        )

        let reloadSuccess = reload ? await tcpReload() : nil
        return try CLIConfigRestoreResult(
            sourcePath: sourceURL.path,
            restoredPath: destinationURL.path,
            restoredItems: copiedItemNames(in: restoreTargetURL),
            reloadRequested: reload,
            reloadSuccess: reloadSuccess
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

    public func tcpGetCurrentLayer() async throws -> String {
        let client = await tcpClient()
        return try await client.requestCurrentLayerName()
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

    private func defaultBackupURL() throws -> URL {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.dateFormat = "yyyyMMdd-HHmmss"
        let name = "keypath-config-\(formatter.string(from: Date()))"
        let supportDirectory = try FileManager.default.url(
            for: .applicationSupportDirectory,
            in: .userDomainMask,
            appropriateFor: nil,
            create: true
        )
        return supportDirectory
            .appendingPathComponent("KeyPath", isDirectory: true)
            .appendingPathComponent("QA Backups", isDirectory: true)
            .appendingPathComponent(name, isDirectory: true)
    }

    private func validateDryRunConfig(_ content: String) async throws {
        let tempDirectory = FileManager.default.temporaryDirectory
            .appendingPathComponent("keypath-cli-dry-run-\(UUID().uuidString)", isDirectory: true)
        defer {
            try? FileManager.default.removeItem(at: tempDirectory)
        }
        let service = await MainActor.run { ConfigurationService(configDirectory: tempDirectory.path) }
        let validation = await service.validateConfiguration(content)
        guard validation.isValid else {
            throw KeyPathError.configuration(.validationFailed(errors: validation.errors))
        }
    }

    private func changeset(
        collections: [RuleCollection],
        customRules: [CustomRule]
    ) -> CLIApplyChangeset {
        CLIApplyChangeset(
            enabledCollections: collections.filter(\.isEnabled).map(\.name),
            disabledCollections: collections.filter { !$0.isEnabled }.map(\.name),
            customRules: customRules.filter(\.isEnabled).map { "\($0.input) → \($0.action.outputString)" }
        )
    }

    private func resolvedExistingDirectory(_ url: URL, fileManager: FileManager) throws -> URL {
        var isDirectory: ObjCBool = false
        guard fileManager.fileExists(atPath: url.path, isDirectory: &isDirectory), isDirectory.boolValue else {
            throw Self.error("Directory does not exist: \(url.path)")
        }
        return url.resolvingSymlinksInPath()
    }

    private func copyDirectoryContents(from source: URL, to destination: URL, fileManager: FileManager) throws {
        let contents = try fileManager.contentsOfDirectory(
            at: source,
            includingPropertiesForKeys: nil
        )
        for item in contents {
            if isTransientValidationArtifact(item.lastPathComponent) { continue }
            do {
                try fileManager.copyItem(
                    at: item,
                    to: destination.appendingPathComponent(item.lastPathComponent)
                )
            } catch where isFileNotFound(error) {
                // Vanished between enumeration and copy — transient, skip.
            }
        }
    }

    /// Copy every backup item over the destination, replacing existing entries
    /// in place. Unlike wipe-then-copy, an interruption never leaves the
    /// destination with less data than it started with.
    private func overwriteDirectoryContents(from source: URL, to destination: URL, fileManager: FileManager) throws {
        let contents = try fileManager.contentsOfDirectory(
            at: source,
            includingPropertiesForKeys: nil
        )
        for item in contents {
            if isTransientValidationArtifact(item.lastPathComponent) { continue }
            let target = destination.appendingPathComponent(item.lastPathComponent)
            do {
                try fileManager.removeItem(at: target)
            } catch where isFileNotFound(error) {
                // Nothing to replace — fine.
            }
            try fileManager.copyItem(at: item, to: target)
        }
    }

    /// Remove destination items that aren't part of the backup. Tolerates
    /// files that vanish mid-iteration (their owner cleaned up — that's the
    /// goal state) and skips transient validation artifacts entirely.
    private func pruneExtraneousItems(at directory: URL, keeping names: Set<String>, fileManager: FileManager) throws {
        let contents = try fileManager.contentsOfDirectory(
            at: directory,
            includingPropertiesForKeys: nil
        )
        for item in contents {
            let name = item.lastPathComponent
            if names.contains(name) || isTransientValidationArtifact(name) { continue }
            do {
                try fileManager.removeItem(at: item)
            } catch where isFileNotFound(error) {
                // Already gone — pruning succeeded by other means.
            }
        }
    }

    /// `temp_validation_*.kbd` files (and their `.sb-*` safe-save shadows) are
    /// written into the config directory by ConfigurationService validation and
    /// cleaned up by their owner. Racing that cleanup aborted restores (#881).
    private func isTransientValidationArtifact(_ name: String) -> Bool {
        name.hasPrefix("temp_validation_")
    }

    private func isFileNotFound(_ error: Error) -> Bool {
        let nsError = error as NSError
        if nsError.domain == NSCocoaErrorDomain,
           nsError.code == NSFileNoSuchFileError || nsError.code == NSFileReadNoSuchFileError
        {
            return true
        }
        if nsError.domain == NSPOSIXErrorDomain, nsError.code == Int(ENOENT) {
            return true
        }
        return false
    }

    private func sameResolvedPath(_ lhs: URL, _ rhs: URL) -> Bool {
        lhs.resolvingSymlinksInPath().standardizedFileURL.path ==
            rhs.resolvingSymlinksInPath().standardizedFileURL.path
    }

    private func copiedItemNames(in directory: URL) throws -> [String] {
        try FileManager.default.contentsOfDirectory(atPath: directory.path).sorted()
    }

    private static func error(_ message: String) -> NSError {
        NSError(domain: "KeyPath.ConfigFacade", code: 1, userInfo: [NSLocalizedDescriptionKey: message])
    }
}

// MARK: - Config Types

public struct CLIApplyResult: Codable, Sendable {
    public let collectionsCount: Int
    public let enabledCount: Int
    public let customRulesCount: Int
    public let reloadSuccess: Bool
    public let changeset: CLIApplyChangeset?
    public let dryRun: Bool?

    public init(
        collectionsCount: Int,
        enabledCount: Int,
        customRulesCount: Int,
        reloadSuccess: Bool,
        changeset: CLIApplyChangeset?,
        dryRun: Bool? = nil
    ) {
        self.collectionsCount = collectionsCount
        self.enabledCount = enabledCount
        self.customRulesCount = customRulesCount
        self.reloadSuccess = reloadSuccess
        self.changeset = changeset
        self.dryRun = dryRun
    }
}

public struct CLIApplyChangeset: Codable, Sendable {
    public let enabledCollections: [String]
    public let disabledCollections: [String]
    public let customRules: [String]
}

public struct CLIConfigBackupResult: Codable, Sendable {
    public let sourcePath: String
    public let backupPath: String
    public let copiedItems: [String]
}

public struct CLIConfigRestoreResult: Codable, Sendable {
    public let sourcePath: String
    public let restoredPath: String
    public let restoredItems: [String]
    public let reloadRequested: Bool
    public let reloadSuccess: Bool?
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
