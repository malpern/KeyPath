import Foundation
import KeyPathCore
import KeyPathRulesCore

/// Task-local scope is intentionally shared: nested callbacks can cross coordinator
/// instances. Unique rotating operation tokens distinguish their ownership, while
/// carrying the full set lets an A -> B -> A callback cycle fail instead of hang.
private enum SaveOperationContext {
    @TaskLocal static var activeOperations: Set<UUID> = []
}

/// Callback interface for save status updates
@MainActor
protocol SaveCoordinatorDelegate: AnyObject {
    func saveStatusDidChange(_ status: SaveStatus)
    func configDidUpdate(mappings: [KeyMapping])
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

    static func success(mappings: [KeyMapping], reloadResult: ReloadResult) -> SaveResult {
        SaveResult(success: true, error: nil, mappings: mappings, reloadResult: reloadResult)
    }

    static func failure(_ error: Error, reloadResult: ReloadResult? = nil) -> SaveResult {
        SaveResult(success: false, error: error, mappings: nil, reloadResult: reloadResult)
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
    private let engineClient: EngineClient
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

    // MainActor methods can interleave at every await. Keep the entire save,
    // including reload and recovery, exclusive within this coordinator.
    private var operationInProgress = false
    private var operationID = UUID()
    private var operationWaiters: [CheckedContinuation<Void, Never>] = []

    // MARK: - Initialization

    init(
        configurationService: ConfigurationService,
        engineClient: EngineClient,
        configFileWatcher: ConfigFileWatcher? = nil
    ) {
        self.configurationService = configurationService
        self.engineClient = engineClient
        self.configFileWatcher = configFileWatcher
    }

    /// Convenience initializer for legacy code (will be deprecated)
    convenience init() {
        let configService = ConfigurationService(configDirectory: KeyPathConstants.Config.directory)
        let engine = TCPEngineClient()
        self.init(configurationService: configService, engineClient: engine, configFileWatcher: nil)
    }

    // MARK: - Public Save API

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
            try await beginOperation()
        } catch {
            return .failure(error)
        }
        defer { endOperation() }

        // Suppress file watcher to prevent double reload
        configFileWatcher?.suppressEvents(for: 1.0, reason: "Internal saveConfiguration")
        saveStatus = .saving

        do {
            // Step 1: Validate input/output
            let (sanitizedInput, sanitizedOutput) = try validateInputOutput(
                input: input, output: output
            )

            // Step 2: Backup current config
            let previousContent = try await snapshotCurrentConfig()
            try Task.checkCancellation()
            backupCurrentConfig(previousContent)

            // Step 3: Create and save custom rule
            let rule = ruleCollectionsManager.makeCustomRule(
                input: sanitizedInput, output: sanitizedOutput
            )
            let didSave = await ruleCollectionsManager.saveCustomRule(rule, skipReload: true)

            guard didSave else {
                let message = "Failed to save custom rule (possible conflict)"
                saveStatus = .failed(message)
                return .failure(KeyPathError.configuration(.validationFailed(errors: [message])))
            }

            // Step 4: Play write sound
            playWriteSound()

            // Step 5: Trigger reload for validation
            AppLogger.shared.debug("📡 [SaveCoordinator] Triggering TCP reload for validation")
            let reloadResult = await reloadWithinOperation(reloadHandler)

            if reloadResult.disposition == .applied || reloadResult.disposition == .pending {
                // Success!
                if reloadResult.disposition == .applied {
                    AppLogger.shared.info("✅ [SaveCoordinator] Reload successful, config is valid")
                } else {
                    AppLogger.shared.info("ℹ️ [SaveCoordinator] Config saved; reload pending: \(reloadResult.errorMessage ?? "service unavailable")")
                }
                playSuccessSound()
                saveStatus = .success
                scheduleStatusReset()

                let mappings = ruleCollectionsManager.enabledMappings()
                return .success(mappings: mappings, reloadResult: reloadResult)
            } else {
                // Reload failed - restore backup
                let errorMessage = reloadResult.errorMessage ?? "TCP server unresponsive"
                AppLogger.shared.error("❌ [SaveCoordinator] TCP reload FAILED: \(errorMessage)")
                AppLogger.shared.error("❌ [SaveCoordinator] Restoring backup")

                playErrorSound()
                do {
                    try await restoreConfig(previousContent)
                } catch {
                    AppLogger.shared.error("❌ [SaveCoordinator] Rollback also failed: \(error)")
                }

                saveStatus = .failed("TCP server reload failed: \(errorMessage)")
                return .failure(
                    KeyPathError.configuration(
                        .loadFailed(
                            reason:
                            "TCP server required for validation-on-demand failed: \(errorMessage)"
                        )
                    ),
                    reloadResult: reloadResult
                )
            }

        } catch {
            saveStatus = .failed(error.localizedDescription)
            return .failure(error)
        }
    }

    /// Save a complete generated configuration (e.g., from AI)
    ///
    /// - Parameters:
    ///   - content: The full Kanata configuration content
    ///   - reloadHandler: Async handler to trigger config reload and classify the result
    /// - Returns: SaveResult indicating success or failure
    func saveGeneratedConfig(
        content: String,
        reloadHandler: @escaping () async -> ReloadResult
    ) async -> SaveResult {
        do {
            try await beginOperation()
        } catch {
            return .failure(error)
        }
        defer { endOperation() }

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
            let previousContent = try await snapshotCurrentConfig()
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
            let reloadResult = await reloadWithinOperation(reloadHandler)

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
                playSuccessSound()
                saveStatus = .success
                scheduleStatusReset()
                return .success(mappings: parsedMappings, reloadResult: reloadResult)
            } else {
                // TCP reload failed - restore backup
                let errorMessage = reloadResult.errorMessage ?? "TCP server unresponsive"
                AppLogger.shared.error("❌ [SaveCoordinator] TCP reload FAILED: \(errorMessage)")

                playErrorSound()
                do {
                    try await restoreConfig(previousContent)
                } catch {
                    AppLogger.shared.error("❌ [SaveCoordinator] Rollback also failed: \(error)")
                }

                saveStatus = .failed("Config reload failed: \(errorMessage)")
                return .failure(
                    KeyPathError.configuration(
                        .loadFailed(reason: "Hot reload failed: \(errorMessage)")
                    ),
                    reloadResult: reloadResult
                )
            }

        } catch {
            saveStatus = .failed(
                "Failed to save generated configuration: \(error.localizedDescription)"
            )
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

    func restoreLastGoodConfig() async throws {
        try await beginOperation()
        defer { endOperation() }
        try await restoreConfig(lastGoodConfig)
    }

    private func restoreConfig(_ content: String?) async throws {
        guard let backup = content else {
            AppLogger.shared.warnUnlessQuietTest("⚠️ [SaveCoordinator] No backup available - writing minimal safe config")
            try await writeMinimalSafeConfig()
            return
        }
        AppLogger.shared.info("🔄 [SaveCoordinator] Restoring last good config")
        do {
            try await configurationService.writeConfigurationContent(backup)
        } catch {
            AppLogger.shared.error("❌ [SaveCoordinator] Failed to restore backup: \(error) - writing minimal safe config")
            try await writeMinimalSafeConfig()
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

    /// Cancellation before admission never writes or changes the active status.
    /// A queued cancellation is observed when its FIFO turn arrives. Once a write
    /// starts, finish reload/recovery rather than abandoning a half-applied edit.
    private func beginOperation() async throws {
        try Task.checkCancellation()
        if operationInProgress, SaveOperationContext.activeOperations.contains(operationID) {
            throw KeyPathError.configuration(.loadFailed(
                reason: "A reload callback cannot recursively save or restore through the same coordinator."
            ))
        }
        if operationInProgress {
            await withCheckedContinuation { operationWaiters.append($0) }
        } else {
            operationInProgress = true
        }
        do {
            try Task.checkCancellation()
        } catch {
            endOperation()
            throw error
        }
    }

    private func endOperation() {
        // Inherited task-local context from a finished reload must not reject
        // a later independent operation (including child tasks that outlive it).
        operationID = UUID()
        if operationWaiters.isEmpty {
            operationInProgress = false
        } else {
            // Transfer ownership directly; do not leave a gap for a new caller
            // to overtake an already queued save.
            operationWaiters.removeFirst().resume()
        }
    }

    private func reloadWithinOperation(_ reloadHandler: () async -> ReloadResult) async -> ReloadResult {
        var activeOperations = SaveOperationContext.activeOperations
        activeOperations.insert(operationID)
        return await SaveOperationContext.$activeOperations.withValue(activeOperations) {
            await reloadHandler()
        }
    }

    private func snapshotCurrentConfig() async throws -> String {
        let path = configurationService.configurationPath
        if await !(configurationService.fileExistsAsync(path: path)) {
            return await configurationService.current().content
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
