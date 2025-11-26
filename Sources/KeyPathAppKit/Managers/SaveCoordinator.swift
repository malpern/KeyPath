import Foundation
import KeyPathCore

/// Callback interface for save status updates
@MainActor
protocol SaveCoordinatorDelegate: AnyObject {
    func saveStatusDidChange(_ status: SaveStatus)
    func configDidUpdate(mappings: [KeyMapping])
}

/// Result of a save operation
struct SaveResult {
    let success: Bool
    let error: Error?
    let mappings: [KeyMapping]?

    static func success(mappings: [KeyMapping]) -> SaveResult {
        SaveResult(success: true, error: nil, mappings: mappings)
    }

    static func failure(_ error: Error) -> SaveResult {
        SaveResult(success: false, error: error, mappings: nil)
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
    ///   - reloadHandler: Async handler to trigger config reload (returns success, error message)
    /// - Returns: SaveResult indicating success or failure with error details
    func saveMapping(
        input: String,
        output: String,
        ruleCollectionsManager: RuleCollectionsManager,
        reloadHandler: @escaping () async -> (success: Bool, errorMessage: String?)
    ) async -> SaveResult {
        // Suppress file watcher to prevent double reload
        configFileWatcher?.suppressEvents(for: 1.0, reason: "Internal saveConfiguration")
        saveStatus = .saving

        do {
            // Step 1: Validate input/output
            let (sanitizedInput, sanitizedOutput) = try validateInputOutput(
                input: input, output: output)

            // Step 2: Backup current config
            let currentConfig = await configurationService.current()
            backupCurrentConfig(currentConfig.content)

            // Step 3: Create and save custom rule
            let rule = ruleCollectionsManager.makeCustomRule(
                input: sanitizedInput, output: sanitizedOutput)
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
            let reloadResult = await reloadHandler()

            if reloadResult.success {
                // Success!
                AppLogger.shared.info("✅ [SaveCoordinator] Reload successful, config is valid")
                playSuccessSound()
                saveStatus = .success
                scheduleStatusReset()

                let mappings = ruleCollectionsManager.enabledMappings()
                return .success(mappings: mappings)
            } else {
                // Reload failed - restore backup
                let errorMessage = reloadResult.errorMessage ?? "TCP server unresponsive"
                AppLogger.shared.error("❌ [SaveCoordinator] TCP reload FAILED: \(errorMessage)")
                AppLogger.shared.error("❌ [SaveCoordinator] Restoring backup")

                playErrorSound()
                try await restoreLastGoodConfig()

                saveStatus = .failed("TCP server reload failed: \(errorMessage)")
                return .failure(
                    KeyPathError.configuration(
                        .loadFailed(
                            reason:
                                "TCP server required for validation-on-demand failed: \(errorMessage)"
                        )))
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
    ///   - reloadHandler: Async handler to trigger config reload
    /// - Returns: SaveResult indicating success or failure
    func saveGeneratedConfig(
        content: String,
        reloadHandler: @escaping () async -> (success: Bool, errorMessage: String?)
    ) async -> SaveResult {
        // Suppress file watcher to prevent double reload
        configFileWatcher?.suppressEvents(for: 1.0, reason: "Internal saveGeneratedConfiguration")
        saveStatus = .saving

        do {
            // Step 1: Validate generated config before saving
            AppLogger.shared.debug(
                "🔍 [SaveCoordinator] Validating generated config before save...")
            let validation = await configurationService.validateConfiguration(content)

            if !validation.isValid {
                AppLogger.shared.error(
                    "❌ [SaveCoordinator] Generated config validation failed: \(validation.errors.joined(separator: ", "))"
                )
                saveStatus = .failed(
                    "Invalid config: \(validation.errors.first ?? "Unknown error")")
                return .failure(
                    KeyPathError.configuration(.validationFailed(errors: validation.errors)))
            }

            AppLogger.shared.info("✅ [SaveCoordinator] Generated config validation passed")

            // Step 2: Backup current config
            let currentConfig = await configurationService.current()
            backupCurrentConfig(currentConfig.content)

            // Step 3: Write the configuration file
            let configPath = configurationService.configurationPath
            let configDir = configurationService.configDirectory

            let configDirURL = URL(fileURLWithPath: configDir)
            try FileManager.default.createDirectory(
                at: configDirURL, withIntermediateDirectories: true)

            let configURL = URL(fileURLWithPath: configPath)
            try content.write(to: configURL, atomically: true, encoding: .utf8)

            AppLogger.shared.info(
                "✅ [SaveCoordinator] Generated configuration saved to \(configPath)")

            // Step 4: Parse saved config to extract mappings
            let parsedMappings = parseConfig(content)

            // Step 5: Play write sound
            playWriteSound()

            // Step 6: Trigger reload for validation
            let reloadResult = await reloadHandler()

            if reloadResult.success {
                AppLogger.shared.info(
                    "✅ [SaveCoordinator] TCP reload successful, config is active")
                playSuccessSound()
                saveStatus = .success
                scheduleStatusReset()
                return .success(mappings: parsedMappings)
            } else {
                // TCP reload failed - restore backup
                let errorMessage = reloadResult.errorMessage ?? "TCP server unresponsive"
                AppLogger.shared.error("❌ [SaveCoordinator] TCP reload FAILED: \(errorMessage)")

                playErrorSound()
                try await restoreLastGoodConfig()

                saveStatus = .failed("Config reload failed: \(errorMessage)")
                return .failure(
                    KeyPathError.configuration(
                        .loadFailed(reason: "Hot reload failed: \(errorMessage)")))
            }

        } catch {
            saveStatus = .failed(
                "Failed to save generated configuration: \(error.localizedDescription)")
            return .failure(error)
        }
    }

    // MARK: - Backup/Restore

    func backupCurrentConfig(_ content: String) {
        lastGoodConfig = content
        AppLogger.shared.log("💾 [SaveCoordinator] Current config backed up to memory")
    }

    func restoreLastGoodConfig() async throws {
        guard let backup = lastGoodConfig else {
            throw KeyPathError.configuration(.backupNotFound)
        }
        AppLogger.shared.info("🔄 [SaveCoordinator] Restoring last good config")
        try await configurationService.writeConfigurationContent(backup)
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
                .validationFailed(errors: ["Input and output are required."]))
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

    private func scheduleStatusReset() {
        DispatchQueue.main.asyncAfter(deadline: .now() + 2.0) { [weak self] in
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
