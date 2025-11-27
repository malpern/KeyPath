import AppKit
import Foundation
import KeyPathCore

/// Protocol for managing Kanata configuration files
@preconcurrency
protocol ConfigurationManaging: Sendable {
    var configPath: String { get }
    var configDirectory: String { get }

    /// Build Kanata command line arguments
    func buildKanataArguments(checkOnly: Bool) -> [String]

    /// Validate configuration file
    func validateConfigFile() async -> (isValid: Bool, errors: [String])

    /// Validate configuration content string
    func validateConfiguration(_ content: String) async -> (isValid: Bool, errors: [String])

    /// Write generated configuration to disk
    func writeGeneratedConfig(_ content: String) async throws -> [KeyMapping]

    /// Write validated configuration to disk
    func writeValidatedConfig(_ content: String) async throws

    /// Load existing mappings from config file
    func loadExistingMappings() async -> [KeyMapping]

    /// Save configuration with mappings
    func saveConfiguration(mappings: [KeyMapping]) async throws

    /// Backup current config
    func backupCurrentConfig() async

    /// Restore last good config
    func restoreLastGoodConfig() async throws

    /// Create default config if missing
    func createDefaultIfMissing() async -> Bool

    /// Open config file in editor
    func openInEditor(_ path: String) async

    /// Parse config content to mappings
    func parseConfig(_ content: String) -> [KeyMapping]

    /// Generate config from mappings
    func generateConfig(mappings: [KeyMapping]) -> String

    /// Ensure valid startup config, handling invalid configs by backing them up and resetting to default
    func ensureValidStartupConfig() async -> (mappings: [KeyMapping], validationError: ConfigValidationError?)

    /// Backup failed config and apply safe default
    func backupFailedConfigAndApplySafe(failedConfig: String, mappings: [KeyMapping]) async throws -> String
}

/// Manages Kanata configuration files and operations
@MainActor
final class ConfigurationManager: @preconcurrency ConfigurationManaging {
    let configPath: String
    let configDirectory: String

    private let configurationService: ConfigurationService
    private let configBackupManager: ConfigBackupManager
    private let configFileWatcher: ConfigFileWatcher?

    init(
        configurationService: ConfigurationService,
        configBackupManager: ConfigBackupManager,
        configFileWatcher: ConfigFileWatcher?
    ) {
        self.configurationService = configurationService
        self.configBackupManager = configBackupManager
        self.configFileWatcher = configFileWatcher

        configPath = configurationService.configurationPath
        configDirectory = configurationService.configDirectory
    }

    func buildKanataArguments(checkOnly: Bool = false) -> [String] {
        var arguments = ["--cfg", configPath]

        // Add TCP port argument
        let tcpPort = PreferencesService.shared.tcpServerPort
        arguments.append(contentsOf: ["--port", "\(tcpPort)"])
        AppLogger.shared.log("📡 [ConfigManager] TCP server enabled on port \(tcpPort)")

        if checkOnly {
            arguments.append("--check")
        } else {
            // Add logging flags based on user preference
            let verboseLogging = PreferencesService.shared.verboseKanataLogging
            if verboseLogging {
                // Trace mode: comprehensive logging with event timing
                arguments.append("--trace")
                AppLogger.shared.log("📊 [ConfigManager] Verbose logging enabled (--trace)")
            } else {
                // Standard debug mode with layer changes
                arguments.append("--debug")
            }
            arguments.append("--log-layer-changes")
        }

        AppLogger.shared.log("🔧 [ConfigManager] Built arguments: \(arguments.joined(separator: " "))")
        return arguments
    }

    func validateConfigFile() async -> (isValid: Bool, errors: [String]) {
        guard FileManager.default.fileExists(atPath: configPath) else {
            return (false, ["Config file does not exist at: \(configPath)"])
        }

        // Use CLI validation (TCP-only mode)
        AppLogger.shared.log("📄 [ConfigManager] Using file-based validation")
        return configurationService.validateConfigViaFile()
    }

    func validateConfiguration(_ content: String) async -> (isValid: Bool, errors: [String]) {
        await configurationService.validateConfiguration(content)
    }

    func writeGeneratedConfig(_ content: String) async throws -> [KeyMapping] {
        AppLogger.shared.log("💾 [ConfigManager] Writing generated configuration")

        // Suppress file watcher to prevent double reload from our own write
        configFileWatcher?.suppressEvents(for: 1.0, reason: "Internal writeGeneratedConfig")

        // Validate before saving
        AppLogger.shared.log("🔍 [ConfigManager] Validating generated config before save...")
        let validation = await validateConfiguration(content)

        if !validation.isValid {
            AppLogger.shared.log(
                "❌ [ConfigManager] Generated config validation failed: \(validation.errors.joined(separator: ", "))"
            )
            throw KeyPathError.configuration(.validationFailed(errors: validation.errors))
        }

        AppLogger.shared.log("✅ [ConfigManager] Generated config validation passed")

        // Backup current config before making changes
        await backupCurrentConfig()

        // Ensure config directory exists
        let configDirectoryURL = URL(fileURLWithPath: configDirectory)
        try FileManager.default.createDirectory(
            at: configDirectoryURL, withIntermediateDirectories: true
        )

        // Write the configuration file
        let configURL = URL(fileURLWithPath: configPath)
        try content.write(to: configURL, atomically: true, encoding: .utf8)

        AppLogger.shared.log("✅ [ConfigManager] Generated configuration saved to \(configPath)")

        // Parse the saved config to return mappings
        return parseConfig(content)
    }

    func writeValidatedConfig(_ content: String) async throws {
        AppLogger.shared.log("📡 [ConfigManager] Saving validated config (TCP-only mode)")

        let configDir = URL(fileURLWithPath: configDirectory)
        try FileManager.default.createDirectory(at: configDir, withIntermediateDirectories: true)
        AppLogger.shared.log("🔍 [ConfigManager] Config directory created/verified: \(configDirectory)")

        let configURL = URL(fileURLWithPath: configPath)

        // Check if file exists before writing
        let fileExists = FileManager.default.fileExists(atPath: configPath)
        AppLogger.shared.log("🔍 [ConfigManager] Config file exists before write: \(fileExists)")

        // Write the config
        try content.write(to: configURL, atomically: true, encoding: .utf8)
        AppLogger.shared.log("✅ [ConfigManager] Config written to file successfully")

        // Get modification time after write
        let afterAttributes = try FileManager.default.attributesOfItem(atPath: configPath)
        let afterModTime = afterAttributes[.modificationDate] as? Date
        let fileSize = afterAttributes[.size] as? Int ?? 0
        AppLogger.shared.log(
            "🔍 [ConfigManager] Modification time after write: \(afterModTime?.description ?? "unknown")")
        AppLogger.shared.log("🔍 [ConfigManager] File size: \(fileSize) bytes")

        // Post-save validation: verify the file was saved correctly
        AppLogger.shared.log("🔍 [Validation-PostSave] ========== POST-SAVE VALIDATION BEGIN ==========")
        AppLogger.shared.log("🔍 [Validation-PostSave] Validating saved config at: \(configPath)")

        do {
            let savedContent = try String(contentsOfFile: configPath, encoding: .utf8)
            AppLogger.shared.log(
                "📖 [Validation-PostSave] Successfully read saved file (\(savedContent.count) characters)")

            let postSaveStart = Date()
            let postSaveValidation = await validateConfiguration(savedContent)
            let postSaveDuration = Date().timeIntervalSince(postSaveStart)
            AppLogger.shared.log(
                "⏱️ [Validation-PostSave] Validation completed in \(String(format: "%.3f", postSaveDuration)) seconds"
            )

            if postSaveValidation.isValid {
                AppLogger.shared.info("✅ [Validation-PostSave] Post-save validation PASSED")
                AppLogger.shared.info("✅ [Validation-PostSave] Config saved and verified successfully")
            } else {
                AppLogger.shared.error("❌ [Validation-PostSave] Post-save validation FAILED")
                AppLogger.shared.error(
                    "❌ [Validation-PostSave] Found \(postSaveValidation.errors.count) errors:")
                for (index, error) in postSaveValidation.errors.enumerated() {
                    AppLogger.shared.log("   Error \(index + 1): \(error)")
                }
                AppLogger.shared.debug(
                    "🔍 [Validation-PostSave] ========== POST-SAVE VALIDATION END ==========")
                throw KeyPathError.configuration(.validationFailed(errors: postSaveValidation.errors))
            }
        } catch {
            AppLogger.shared.error("❌ [Validation-PostSave] Failed to read saved config: \(error)")
            AppLogger.shared.error("❌ [Validation-PostSave] Error type: \(type(of: error))")
            AppLogger.shared.debug(
                "🔍 [Validation-PostSave] ========== POST-SAVE VALIDATION END ==========")
            throw error
        }

        AppLogger.shared.debug("🔍 [Validation-PostSave] ========== POST-SAVE VALIDATION END ==========")
    }

    func loadExistingMappings() async -> [KeyMapping] {
        // Deprecated: Use ensureValidStartupConfig instead
        let result = await ensureValidStartupConfig()
        return result.mappings
    }

    /// Ensures a valid configuration exists on startup, handling invalid configs by backing them up and resetting to default
    func ensureValidStartupConfig() async -> (mappings: [KeyMapping], validationError: ConfigValidationError?) {
        AppLogger.shared.log("📂 [ConfigManager] Ensuring valid startup configuration")

        guard FileManager.default.fileExists(atPath: configPath) else {
            AppLogger.shared.log("ℹ️ [ConfigManager] No existing config file found at: \(configPath)")
            AppLogger.shared.log("ℹ️ [ConfigManager] Starting with empty mappings")
            return ([], nil)
        }

        do {
            AppLogger.shared.log("📖 [ConfigManager] Reading config file from: \(configPath)")
            let configContent = try String(contentsOfFile: configPath, encoding: .utf8)
            AppLogger.shared.log("📖 [ConfigManager] Config file size: \(configContent.count) characters")

            // Strict CLI validation to match engine behavior on startup
            AppLogger.shared.log("🔍 [ConfigManager] Running CLI validation of existing configuration...")
            let cli = configurationService.validateConfigViaFile()
            if cli.isValid {
                AppLogger.shared.log("✅ [ConfigManager] CLI validation PASSED")
                let config = try await configurationService.reload()
                AppLogger.shared.log(
                    "✅ [ConfigManager] Successfully loaded \(config.keyMappings.count) existing mappings")
                return (config.keyMappings, nil)
            } else {
                AppLogger.shared.log(
                    "❌ [ConfigManager] CLI validation FAILED with \(cli.errors.count) errors")

                // Handle invalid startup config
                let backupPath = await handleInvalidStartupConfig(configContent: configContent, errors: cli.errors)

                // Return default mapping (caps->esc) and the validation error for UI
                let defaultMapping = KeyMapping(input: "caps", output: "esc")
                return ([defaultMapping], .invalidStartup(errors: cli.errors, backupPath: backupPath))
            }
        } catch {
            AppLogger.shared.log("❌ [ConfigManager] Failed to load existing config: \(error)")
            AppLogger.shared.log("❌ [ConfigManager] Error type: \(type(of: error))")
            return ([], nil)
        }
    }

    /// Handle invalid startup configuration with backup and fallback
    private func handleInvalidStartupConfig(configContent: String, errors _: [String]) async -> String {
        AppLogger.shared.log("🛡️ [ConfigManager] Handling invalid startup configuration...")

        // Create backup of invalid config
        let timestamp = ISO8601DateFormatter().string(from: Date()).replacingOccurrences(
            of: ":", with: "-"
        )
        let backupPath = "\(configDirectory)/invalid-config-backup-\(timestamp).kbd"

        AppLogger.shared.log("💾 [ConfigManager] Creating backup of invalid config...")
        do {
            try configContent.write(toFile: backupPath, atomically: true, encoding: .utf8)
            AppLogger.shared.log("💾 [ConfigManager] Successfully backed up invalid config to: \(backupPath)")
        } catch {
            AppLogger.shared.error("❌ [ConfigManager] Failed to backup invalid config: \(error)")
        }

        // Generate default configuration
        AppLogger.shared.log("🔧 [ConfigManager] Generating default fallback configuration...")
        let defaultMapping = KeyMapping(input: "caps", output: "esc")
        let defaultConfig = generateConfig(mappings: [defaultMapping])
        AppLogger.shared.log("🔧 [ConfigManager] Default config generated with mapping: caps → esc")

        do {
            AppLogger.shared.log("📝 [ConfigManager] Writing default config to: \(configPath)")
            try defaultConfig.write(toFile: configPath, atomically: true, encoding: .utf8)
            AppLogger.shared.info("✅ [ConfigManager] Successfully replaced invalid config with default")
        } catch {
            AppLogger.shared.error("❌ [ConfigManager] Failed to write default config: \(error)")
        }

        AppLogger.shared.log("🛡️ [ConfigManager] Invalid startup config handling complete")
        return backupPath
    }

    func saveConfiguration(mappings: [KeyMapping]) async throws {
        AppLogger.shared.log("💾 [ConfigManager] Saving configuration with \(mappings.count) mappings")

        // Suppress file watcher to prevent double reload from our own write
        configFileWatcher?.suppressEvents(for: 1.0, reason: "Internal saveConfiguration")

        // Backup current config before making changes
        await backupCurrentConfig()

        // Delegate to ConfigurationService for saving
        try await configurationService.saveConfiguration(keyMappings: mappings)
        AppLogger.shared.log(
            "💾 [ConfigManager] Config saved with \(mappings.count) mappings via ConfigurationService")
    }

    func backupCurrentConfig() async {
        AppLogger.shared.log("💾 [ConfigManager] Creating backup of current config")
        _ = configBackupManager.createPreEditBackup()
    }

    func backupFailedConfigAndApplySafe(failedConfig: String, mappings: [KeyMapping]) async throws -> String {
        // Delegate to ConfigurationService for backup and safe config application
        try await configurationService.backupFailedConfigAndApplySafe(
            failedConfig: failedConfig,
            mappings: mappings
        )
    }

    func restoreLastGoodConfig() async throws {
        AppLogger.shared.log("🔄 [ConfigManager] Restoring last good config")
        // The backup manager handles restoration internally
        // This would need to be implemented if not already available
        throw KeyPathError.configuration(.loadFailed(reason: "Restore not yet implemented"))
    }

    func createDefaultIfMissing() async -> Bool {
        AppLogger.shared.log("🛠️ [ConfigManager] Ensuring default user config at \(configPath)")

        do {
            try await configurationService.createInitialConfigIfNeeded()
        } catch {
            AppLogger.shared.log(
                "❌ [ConfigManager] Failed to create initial config via ConfigurationService: \(error)")
            return false
        }

        let exists = FileManager.default.fileExists(atPath: configPath)
        if exists {
            AppLogger.shared.log("✅ [ConfigManager] Verified user config exists at \(configPath)")
        } else {
            AppLogger.shared.log("❌ [ConfigManager] User config still missing at \(configPath)")
        }
        return exists
    }

    func openInEditor(_ path: String) async {
        let filePath = (path as NSString).expandingTildeInPath
        AppLogger.shared.log("📝 [ConfigManager] Opening file in editor: \(filePath)")

        if !TestEnvironment.isRunningTests {
            // Try to open with Zed editor first (if available)
            do {
                _ = try await SubprocessRunner.shared.run(
                    "/usr/local/bin/zed",
                    args: [filePath],
                    timeout: 5
                )
                AppLogger.shared.log("📝 [ConfigManager] Opened file in Zed: \(filePath)")
                return
            } catch {
                // Fallback: Try to open with default text editor
                do {
                    _ = try await SubprocessRunner.shared.run(
                        "/usr/bin/open",
                        args: ["-t", filePath],
                        timeout: 5
                    )
                    AppLogger.shared.log("📝 [ConfigManager] Opened file in default text editor: \(filePath)")
                } catch {
                    // Last resort: Open containing folder
                    let folderPath = URL(fileURLWithPath: filePath).deletingLastPathComponent().path
                    NSWorkspace.shared.open(URL(fileURLWithPath: folderPath))
                    AppLogger.shared.log("📁 [ConfigManager] Opened containing folder: \(folderPath)")
                }
            }
        }
    }

    func parseConfig(_ content: String) -> [KeyMapping] {
        // Delegate to ConfigurationService for parsing
        do {
            let config = try configurationService.parseConfigurationFromString(content)
            return config.keyMappings
        } catch {
            AppLogger.shared.log("⚠️ [ConfigManager] Failed to parse config: \(error)")
            return []
        }
    }

    func generateConfig(mappings: [KeyMapping]) -> String {
        guard !mappings.isEmpty else {
            // Return default config with caps->esc if no mappings
            let defaultMapping = KeyMapping(input: "caps", output: "escape")
            return KanataConfiguration.generateFromMappings([defaultMapping])
        }

        return KanataConfiguration.generateFromMappings(mappings)
    }

    func generateConfig(ruleCollections: [RuleCollection]) -> String {
        let mappings = ruleCollections.enabledMappings()
        if mappings.isEmpty {
            return generateConfig(mappings: [])
        }
        return KanataConfiguration.generateFromCollections(ruleCollections)
    }
}
