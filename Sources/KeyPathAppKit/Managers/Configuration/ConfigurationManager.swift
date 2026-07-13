import AppKit
import Foundation
import KeyPathCore
import KeyPathRulesCore

/// Manages Kanata configuration files and operations
@MainActor
final class ConfigurationManager {
    let configPath: String
    let configDirectory: String

    private let configurationService: ConfigurationService

    init(configurationService: ConfigurationService) {
        self.configurationService = configurationService

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
                AppLogger.shared.log("📊 [ConfigManager] Production logging enabled (layer changes only)")
            }
            arguments.append("--log-layer-changes")
        }

        AppLogger.shared.log("🔧 [ConfigManager] Built arguments: \(arguments.joined(separator: " "))")
        return arguments
    }

    func validateConfigFile() async -> (isValid: Bool, errors: [String]) {
        guard Foundation.FileManager().fileExists(atPath: configPath) else {
            return (false, ["Config file does not exist at: \(configPath)"])
        }

        // Use CLI validation (TCP-only mode)
        AppLogger.shared.log("📄 [ConfigManager] Using file-based validation")
        return await configurationService.validateConfigViaFile()
    }

    /// Ensures a valid configuration exists on startup, handling invalid configs by backing them up and resetting to default
    func ensureValidStartupConfig() async -> (mappings: [KeyMapping], validationError: ConfigValidationError?) {
        AppLogger.shared.log("📂 [ConfigManager] Ensuring valid startup configuration")

        guard Foundation.FileManager().fileExists(atPath: configPath) else {
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
            let cli = await configurationService.validateConfigViaFile()
            if cli.isValid {
                AppLogger.shared.log("✅ [ConfigManager] CLI validation PASSED")
                let config = try await configurationService.reload()
                AppLogger.shared.log(
                    "✅ [ConfigManager] Successfully loaded \(config.keyMappings.count) existing mappings"
                )
                return (config.keyMappings, nil)
            } else {
                AppLogger.shared.log(
                    "❌ [ConfigManager] CLI validation FAILED with \(cli.errors.count) errors"
                )

                // Handle invalid startup config
                let backupPath = await handleInvalidStartupConfig(configContent: configContent, errors: cli.errors)

                // Return default mapping (caps->esc) and the validation error for UI
                let defaultMapping = KeyMapping(input: "caps", action: .keystroke(key: "esc"))
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
        let defaultMapping = KeyMapping(input: "caps", action: .keystroke(key: "esc"))
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

    func backupFailedConfigAndApplySafe(failedConfig: String, mappings: [KeyMapping]) async throws -> String {
        // Delegate to ConfigurationService for backup and safe config application
        try await configurationService.backupFailedConfigAndApplySafe(
            failedConfig: failedConfig,
            mappings: mappings
        )
    }

    func createDefaultIfMissing() async -> Bool {
        AppLogger.shared.log("🛠️ [ConfigManager] Ensuring default user config at \(configPath)")

        do {
            try await configurationService.createInitialConfigIfNeeded()
        } catch {
            AppLogger.shared.log(
                "❌ [ConfigManager] Failed to create initial config via ConfigurationService: \(error)"
            )
            return false
        }

        let exists = Foundation.FileManager().fileExists(atPath: configPath)
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

    func generateConfig(mappings: [KeyMapping]) -> String {
        guard !mappings.isEmpty else {
            // Return default config with caps->esc if no mappings
            let defaultMapping = KeyMapping(input: "caps", action: .keystroke(key: "escape"))
            return KanataConfiguration.generateFromMappings([defaultMapping])
        }

        return KanataConfiguration.generateFromMappings(mappings)
    }
}
