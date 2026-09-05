import Foundation
import KeyPathCore
import KeyPathRulesCore

/// Callback interface for save status updates
@MainActor
protocol SaveCoordinatorDelegate: AnyObject {
    func saveStatusDidChange(_ status: SaveStatus)
    func configDidUpdate(mappings: [KeyMapping])
}

/// Rule and app-keymap recovery include source files and an explicit reload result.
/// Legacy config-only recovery does not claim source or runtime restoration.
enum SaveRecoveryResult {
    case notAttempted
    case restoredPreviousAppKeymapState(reloadResult: ReloadResult?)
    case appKeymapRecoveryFailed(Error)
    case restoredPreviousRuleState(reloadResult: ReloadResult?)
    case ruleStateRecoveryFailed(Error)
    case restoredPreviousConfig
    case wroteMinimalSafeConfig(backupError: Error?)
    case failed(backupError: Error?, fallbackError: Error)
}

/// Keeps both causes available to explicit-restore callers while retaining the
/// fallback error's existing user-facing description.
struct SaveRecoveryError: LocalizedError {
    let backupError: Error?
    let fallbackError: Error

    var errorDescription: String? {
        fallbackError.localizedDescription
    }
}

/// Result of a save operation
struct SaveResult {
    /// A pending application is still a successful save. Consult `reloadResult`
    /// when the caller needs to distinguish persisted content from active content.
    let success: Bool
    let error: Error?
    let mappings: [KeyMapping]?
    /// Nil when validation or persistence failed before the reload was attempted.
    let reloadResult: ReloadResult?

    let recoveryResult: SaveRecoveryResult

    static func success(mappings: [KeyMapping], reloadResult: ReloadResult) -> SaveResult {
        SaveResult(success: true, error: nil, mappings: mappings, reloadResult: reloadResult, recoveryResult: .notAttempted)
    }

    static func failure(
        _ error: Error,
        reloadResult: ReloadResult? = nil,
        recoveryResult: SaveRecoveryResult = .notAttempted
    ) -> SaveResult {
        SaveResult(success: false, error: error, mappings: nil, reloadResult: reloadResult, recoveryResult: recoveryResult)
    }
}

/// Coordinates save operations with validation, backup, and hot-reload
///
/// This coordinator handles the entire save pipeline:
/// 1. Input validation
/// 2. Config backup
/// 3. Rule persistence
/// 4. Config writing
/// 5. TCP reload for live validation
/// 6. Rollback on failure
@MainActor
final class SaveCoordinator {
    // MARK: - Dependencies

    private let configurationService: ConfigurationService
    private weak var configFileWatcher: ConfigFileWatcher?

    // MARK: - Properties

    private(set) var saveStatus: SaveStatus = .idle {
        didSet {
            delegate?.saveStatusDidChange(saveStatus)
        }
    }

    weak var delegate: SaveCoordinatorDelegate?

    /// In-memory backup of last known good config
    private var lastGoodConfig: String?

    // MARK: - Initialization

    init(
        configurationService: ConfigurationService,
        configFileWatcher: ConfigFileWatcher? = nil
    ) {
        self.configurationService = configurationService
        self.configFileWatcher = configFileWatcher
    }

    /// Convenience initializer for legacy code (will be deprecated)
    convenience init() {
        let configService = ConfigurationService(configDirectory: KeyPathConstants.Config.directory)
        self.init(configurationService: configService, configFileWatcher: nil)
    }

    // MARK: - Public Save API

    /// Persist app metadata, its include, and the main config as one revision.
    /// Keep the journal open through reload; rejected/cancelled edits restore all
    /// three files. Restoration gets an explicit reload attempt when necessary.
    func saveAppKeymaps(
        store: AppKeymapStore = .shared,
        mutate: @escaping @MainActor @Sendable (inout [AppKeymap]) throws -> Void,
        runtimeDidApply: @escaping @MainActor @Sendable () async -> Void = {},
        reloadHandler: @escaping @MainActor @Sendable () async -> ReloadResult
    ) async -> SaveResult {
        do {
            return try await configurationService.operationGate.withOperation { @MainActor [self] permit in
                saveStatus = .saving
                var staged: ConfigurationService.AppKeymapWrite?
                var reload: ReloadResult?
                do {
                    configFileWatcher?.suppressEvents(for: 1.0, reason: "Internal app-specific save")
                    staged = try await configurationService.stageAppKeymapChange(store: store, mutationPermit: permit, mutate: mutate)
                    try Task.checkCancellation()
                    let result = await reloadHandler()
                    reload = result
                    try Task.checkCancellation()
                    guard result.disposition == .applied || result.disposition == .pending else {
                        throw KeyPathError.configuration(.loadFailed(reason: result.errorMessage ?? "App-specific configuration could not be applied"))
                    }
                    guard let staged else { throw AppConfigError.validationUnavailable }
                    try await configurationService.settleAppKeymapWrite(staged, commit: true, mutationPermit: permit)
                    if result.disposition == .applied {
                        await Task { @MainActor in await runtimeDidApply() }.value
                    }
                    saveStatus = .success
                    scheduleStatusReset()
                    return .success(mappings: staged.configuration.keyMappings, reloadResult: result)
                } catch {
                    var recovery: SaveRecoveryResult = .notAttempted
                    var reportedError: Error = error
                    if let staged {
                        do {
                            try await configurationService.settleAppKeymapWrite(staged, commit: false, mutationPermit: permit)
                            // Unstructured recovery deliberately does not inherit cancellation.
                            // Await it while retaining admission; TCP must be allowed to finish.
                            let recoveryReload = reload == nil ? nil : await Task { @MainActor in
                                let result = await reloadHandler()
                                if result.disposition == .applied { await runtimeDidApply() }
                                return result
                            }.value
                            recovery = .restoredPreviousAppKeymapState(reloadResult: recoveryReload)
                            if let recoveryReload, recoveryReload.disposition == .failed || recoveryReload.disposition == .rejected {
                                reportedError = SaveApplicationError(cause: error, recovery: recoveryReload.errorMessage ?? "The prior files were restored, but runtime recovery failed")
                            }
                        } catch let recoveryError {
                            recovery = .appKeymapRecoveryFailed(recoveryError)
                            reportedError = SaveApplicationError(cause: error, recovery: recoveryError.localizedDescription)
                        }
                    }
                    saveStatus = .failed(reportedError.localizedDescription)
                    return .failure(reportedError, reloadResult: reload, recoveryResult: recovery)
                }
            }
        } catch {
            return .failure(error)
        }
    }

    /// Save a custom rule with input/output mapping
    ///
    /// This is the main entry point for saving key mappings created via the UI.
    /// - Parameters:
    ///   - input: The input key/sequence
    ///   - output: The output key/sequence
    ///   - ruleCollectionsManager: Manager to persist the custom rule
    ///   - reloadHandler: Async handler to trigger config reload and classify the result
    /// - Returns: SaveResult indicating success or failure with error details
    func saveMapping(
        input: String,
        output: String,
        ruleCollectionsManager: RuleCollectionsManager,
        reloadHandler: @escaping () async -> ReloadResult
    ) async -> SaveResult {
        do {
            return try await configurationService.operationGate.withOperation { @MainActor [self] permit in
                // Suppress file watcher to prevent double reload
                configFileWatcher?.suppressEvents(for: 1.0, reason: "Internal saveConfiguration")
                saveStatus = .saving

                let snapshot = ruleCollectionsManager.snapshotRuleState()
                do {
                    let (sanitizedInput, sanitizedOutput) = try validateInputOutput(input: input, output: output)
                    let rule = ruleCollectionsManager.makeCustomRule(input: sanitizedInput, output: sanitizedOutput)
                    guard await ruleCollectionsManager.updateCustomRuleInMemory(rule, mutationPermit: permit) else {
                        let error = KeyPathError.configuration(.validationFailed(errors: ["The rule change was cancelled or conflicts with an existing mapping."]))
                        saveStatus = .failed(error.localizedDescription)
                        return .failure(error)
                    }
                    let result = await saveRuleState(manager: ruleCollectionsManager, mutationPermit: permit, reloadHandler: reloadHandler)
                    if result.success {
                        NotificationCenter.default.post(name: .ruleCollectionsChanged, object: nil)
                        playSuccessSound()
                    } else {
                        // The transaction already restored (or preserved) the files.
                        // Never regenerate here: that could overwrite an external edit.
                        ruleCollectionsManager.ruleCollections = snapshot.collections
                        ruleCollectionsManager.customRules = snapshot.customRules
                        ruleCollectionsManager.refreshLayerIndicatorState()
                    }
                    return result
                } catch {
                    saveStatus = .failed(error.localizedDescription)
                    return .failure(error)
                }
            }
        } catch {
            return .failure(error)
        }
    }

    /// Keep all rule files recoverable until the engine accepts or defers them.
    /// The manager owns its optimistic in-memory snapshot; this owner settles disk
    /// and runtime before the caller restores that snapshot on failure.
    func saveRuleState(
        manager: RuleCollectionsManager,
        mutationPermit: ConfigurationOperationGate.Permit,
        packRecord: InstalledPackTracker.RecordChange? = nil,
        reloadHandler: (() async -> ReloadResult)?
    ) async -> SaveResult {
        do {
            return try await configurationService.operationGate.withOperation(using: mutationPermit) { @MainActor [self] permit in
                saveStatus = .saving
                var conflictDepth = 0
                while true {
                    var staged: ConfigurationService.RuleWrite?
                    var reload: ReloadResult?
                    do {
                        manager.dedupeRuleCollectionsInPlace()
                        manager.onBeforeSave?()
                        staged = try await configurationService.stageRuleState(
                            ruleCollections: manager.ruleCollections, customRules: manager.customRules,
                            collectionStore: manager.ruleCollectionStore, customStore: manager.customRulesStore,
                            mutationPermit: permit, packRecord: packRecord
                        )
                        try Task.checkCancellation()
                        playWriteSound()
                        let result = await reloadHandler?()
                        reload = result
                        try Task.checkCancellation()
                        if let result, result.disposition != .applied, result.disposition != .pending {
                            throw KeyPathError.configuration(.loadFailed(reason: result.errorMessage ?? "The rule configuration could not be applied"))
                        }
                        guard let staged else { throw AppConfigError.validationUnavailable }
                        try await configurationService.settleRuleWrite(staged, commit: true, mutationPermit: permit)
                        saveStatus = .success
                        scheduleStatusReset()
                        return SaveResult(success: true, error: nil, mappings: manager.enabledMappings(),
                                          reloadResult: result, recoveryResult: .notAttempted)
                    } catch {
                        if staged == nil, reload == nil,
                           await manager.resolveMappingConflictInMemory(error, depth: conflictDepth, mutationPermit: permit)
                        {
                            conflictDepth += 1
                            continue
                        }
                        var recovery: SaveRecoveryResult = .notAttempted
                        var reportedError: Error = error
                        if let staged {
                            do {
                                try await configurationService.settleRuleWrite(staged, commit: false, mutationPermit: permit)
                                let recoveryReload = reload == nil ? nil : await Task { @MainActor in await reloadHandler?() }.value
                                recovery = .restoredPreviousRuleState(reloadResult: recoveryReload)
                                if let recoveryReload, recoveryReload.disposition == .failed || recoveryReload.disposition == .rejected {
                                    reportedError = SaveApplicationError(cause: error, recovery: recoveryReload.errorMessage ?? "Prior rule files were restored, but runtime recovery failed")
                                }
                            } catch let recoveryError {
                                recovery = .ruleStateRecoveryFailed(recoveryError)
                                reportedError = SaveApplicationError(cause: error, recovery: recoveryError.localizedDescription)
                            }
                        }
                        saveStatus = .failed(reportedError.localizedDescription)
                        return .failure(reportedError, reloadResult: reload, recoveryResult: recovery)
                    }
                }
            }
        } catch { return .failure(error) }
    }

    /// Capture and transform raw content under the same admission as its save.
    func editConfiguration(
        transform: @escaping @MainActor @Sendable (String) throws -> String,
        runtimeDidApply: @escaping @MainActor @Sendable () async -> Void = {},
        reloadHandler: @escaping @MainActor @Sendable () async -> ReloadResult
    ) async -> SaveResult {
        do {
            return try await configurationService.operationGate.withOperation { @MainActor [self] permit in
                let original = try await snapshotCurrentConfig(mutationPermit: permit)
                let content = try transform(original)
                return await saveGeneratedConfig(content: content, mutationPermit: permit, expectedContent: original,
                                                 runtimeDidApply: runtimeDidApply, reloadHandler: reloadHandler)
            }
        } catch { return .failure(error) }
    }

    /// Save a complete generated configuration (e.g., from AI)
    ///
    /// - Parameters:
    ///   - content: The full Kanata configuration content
    ///   - reloadHandler: Async handler to trigger config reload and classify the result
    /// - Returns: SaveResult indicating success or failure
    func saveGeneratedConfig(
        content: String,
        mutationPermit: ConfigurationOperationGate.Permit? = nil,
        expectedContent: String? = nil,
        runtimeDidApply: @escaping @MainActor @Sendable () async -> Void = {},
        reloadHandler: @escaping () async -> ReloadResult
    ) async -> SaveResult {
        do {
            return try await configurationService.operationGate.withOperation(using: mutationPermit) { @MainActor [self] permit in
                // Suppress file watcher to prevent double reload
                configFileWatcher?.suppressEvents(for: 1.0, reason: "Internal saveGeneratedConfiguration")
                saveStatus = .saving

                do {
                    // Step 1: Validate generated config before saving
                    AppLogger.shared.debug(
                        "🔍 [SaveCoordinator] Validating generated config before save..."
                    )
                    let validation = await configurationService.validateConfiguration(content)

                    if !validation.isValid {
                        AppLogger.shared.error(
                            "❌ [SaveCoordinator] Generated config validation failed: \(validation.errors.joined(separator: ", "))"
                        )
                        saveStatus = .failed(
                            "Invalid config: \(validation.errors.first ?? "Unknown error")"
                        )
                        return .failure(
                            KeyPathError.configuration(.validationFailed(errors: validation.errors))
                        )
                    }

                    AppLogger.shared.info("✅ [SaveCoordinator] Generated config validation passed")

                    // Step 2: Backup current config
                    let previousContent = try await snapshotCurrentConfig(mutationPermit: permit)
                    if let expectedContent, previousContent != expectedContent {
                        throw KeyPathError.configuration(.loadFailed(reason: "The configuration changed while this edit was being prepared. Reload mappings and try again."))
                    }
                    try Task.checkCancellation()
                    backupCurrentConfig(previousContent)

                    // Step 3: Write the configuration file
                    let configPath = configurationService.configurationPath
                    let configDir = configurationService.configDirectory

                    let configDirURL = URL(fileURLWithPath: configDir)
                    try Foundation.FileManager().createDirectory(
                        at: configDirURL, withIntermediateDirectories: true
                    )

                    let configURL = URL(fileURLWithPath: configPath)
                    try content.write(to: configURL, atomically: true, encoding: .utf8)

                    AppLogger.shared.info(
                        "✅ [SaveCoordinator] Generated configuration saved to \(configPath)"
                    )

                    // Step 4: Parse saved config to extract mappings
                    let parsedMappings = parseConfig(content)

                    // Step 5: Play write sound
                    playWriteSound()

                    // Step 6: Trigger reload for validation
                    let reloadResult = await reloadHandler()

                    if reloadResult.disposition == .applied || reloadResult.disposition == .pending {
                        if reloadResult.disposition == .applied {
                            AppLogger.shared.info(
                                "✅ [SaveCoordinator] TCP reload successful, config is active"
                            )
                        } else {
                            AppLogger.shared.info(
                                "ℹ️ [SaveCoordinator] Config saved; reload pending: \(reloadResult.errorMessage ?? "service unavailable")"
                            )
                        }
                        if reloadResult.disposition == .applied {
                            // Settle applied runtime state even if a newer edit cancelled this task.
                            await Task { @MainActor in await runtimeDidApply() }.value
                        }
                        playSuccessSound()
                        saveStatus = .success
                        scheduleStatusReset()
                        return .success(mappings: parsedMappings, reloadResult: reloadResult)
                    } else {
                        // TCP reload failed - restore backup
                        let errorMessage = reloadResult.errorMessage ?? "TCP server unresponsive"
                        AppLogger.shared.error("❌ [SaveCoordinator] TCP reload FAILED: \(errorMessage)")

                        playErrorSound()
                        let recoveryResult = await restoreConfig(previousContent, mutationPermit: permit)

                        saveStatus = .failed("Config reload failed: \(errorMessage)")
                        return .failure(
                            KeyPathError.configuration(
                                .loadFailed(reason: "Hot reload failed: \(errorMessage)")
                            ),
                            reloadResult: reloadResult,
                            recoveryResult: recoveryResult
                        )
                    }

                } catch {
                    saveStatus = .failed(
                        "Failed to save generated configuration: \(error.localizedDescription)"
                    )
                    return .failure(error)
                }
            }
        } catch {
            return .failure(error)
        }
    }

    // MARK: - Backup/Restore

    func backupCurrentConfig(_ content: String) {
        lastGoodConfig = content
        AppLogger.shared.log("💾 [SaveCoordinator] Current config backed up to memory")
    }

    /// Ensure we have a backup by loading the current config if none exists.
    /// Call this early in the app lifecycle so rollback always has a fallback.
    func ensureBackupExists() async {
        guard lastGoodConfig == nil else { return }
        let current = await configurationService.current()
        if !current.content.isEmpty {
            lastGoodConfig = current.content
            AppLogger.shared.log("💾 [SaveCoordinator] Initialized backup from current config on disk")
        }
    }

    @discardableResult
    func restoreLastGoodConfig() async throws -> SaveRecoveryResult {
        try await configurationService.operationGate.withOperation { @MainActor [self] permit in
            let result = await restoreConfig(lastGoodConfig, mutationPermit: permit)
            // Preserve the throwing contract for existing explicit-restore callers.
            if case let .failed(backupError, fallbackError) = result {
                throw SaveRecoveryError(backupError: backupError, fallbackError: fallbackError)
            }
            return result
        }
    }

    private func restoreConfig(_ content: String?, mutationPermit: ConfigurationOperationGate.Permit) async -> SaveRecoveryResult {
        var backupError: Error?
        if let backup = content {
            AppLogger.shared.info("🔄 [SaveCoordinator] Restoring last good config")
            do {
                try await configurationService.writeConfigurationContent(backup, mutationPermit: mutationPermit)
                return .restoredPreviousConfig
            } catch {
                backupError = error
                AppLogger.shared.error("❌ [SaveCoordinator] Failed to restore backup: \(error) - writing minimal safe config")
            }
        } else {
            AppLogger.shared.warnUnlessQuietTest("⚠️ [SaveCoordinator] No backup available - writing minimal safe config")
        }
        do {
            try await writeMinimalSafeConfig()
            return .wroteMinimalSafeConfig(backupError: backupError)
        } catch {
            AppLogger.shared.error("❌ [SaveCoordinator] Minimal safe config recovery failed: \(error)")
            return .failed(backupError: backupError, fallbackError: error)
        }
    }

    /// Write a minimal safe config that kanata can load without crashing.
    /// This prevents persistent crash loops when both the broken config and the backup fail.
    private func writeMinimalSafeConfig() async throws {
        let safeConfig = """
        ;; Minimal safe config written by SaveCoordinator after rollback failure
        \(KanataDefcfg.minimalSafe.render())
        (defsrc)
        (deflayer base)
        """
        let configPath = configurationService.configurationPath
        let configURL = URL(fileURLWithPath: configPath)
        let configDir = URL(fileURLWithPath: configurationService.configDirectory)
        try Foundation.FileManager().createDirectory(at: configDir, withIntermediateDirectories: true)
        try safeConfig.write(to: configURL, atomically: true, encoding: .utf8)
        AppLogger.shared.warnUnlessQuietTest("🛡️ [SaveCoordinator] Wrote minimal safe config to \(configPath)")
    }

    func hasBackup() -> Bool {
        lastGoodConfig != nil
    }

    // MARK: - Save Status Management

    func setSaving() {
        saveStatus = .saving
    }

    func setValidating() {
        saveStatus = .validating
    }

    func setSuccess() {
        saveStatus = .success
        scheduleStatusReset()
    }

    func setFailed(_ message: String) {
        saveStatus = .failed(message)
    }

    func setIdle() {
        saveStatus = .idle
    }

    // MARK: - Validation Helpers

    /// Validate input/output before saving
    func validateInputOutput(input: String, output: String) throws -> (
        sanitizedInput: String, sanitizedOutput: String
    ) {
        let sanitizedInput = input.trimmingCharacters(in: .whitespacesAndNewlines)
        let sanitizedOutput = output.trimmingCharacters(in: .whitespacesAndNewlines)

        guard !sanitizedInput.isEmpty, !sanitizedOutput.isEmpty else {
            throw KeyPathError.configuration(
                .validationFailed(errors: ["Input and output are required."])
            )
        }

        return (sanitizedInput, sanitizedOutput)
    }

    // MARK: - Sound Effects

    func playWriteSound() {
        Task { @MainActor in SoundManager.shared.playTinkSound() }
    }

    func playSuccessSound() {
        Task { @MainActor in SoundManager.shared.playGlassSound() }
    }

    func playErrorSound() {
        Task { @MainActor in SoundManager.shared.playErrorSound() }
    }

    // MARK: - Private Helpers

    private func snapshotCurrentConfig(mutationPermit: ConfigurationOperationGate.Permit) async throws -> String {
        let path = configurationService.configurationPath
        if await !(configurationService.fileExistsAsync(path: path)) {
            return await configurationService.current(mutationPermit: mutationPermit).content
        }
        // Generated saves write raw content without refreshing the parsed cache.
        // Back up the actual file, never a possibly older cached configuration.
        return try await configurationService.readCurrentConfig()
    }

    private func scheduleStatusReset() {
        Task { @MainActor [weak self] in
            try? await Task.sleep(for: .seconds(2))
            self?.saveStatus = .idle
        }
    }

    private func parseConfig(_ content: String) -> [KeyMapping] {
        do {
            let config = try configurationService.parseConfigurationFromString(content)
            return config.keyMappings
        } catch {
            AppLogger.shared.warn("⚠️ [SaveCoordinator] Failed to parse config: \(error)")
            return []
        }
    }
}

private struct SaveApplicationError: LocalizedError {
    let cause: Error
    let recovery: String
    var errorDescription: String? {
        "\(cause.localizedDescription). Recovery needs attention: \(recovery)"
    }
}
