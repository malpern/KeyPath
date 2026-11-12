import AppKit
import Foundation
import KeyPathCore
import KeyPathRulesCore

/// Manages Kanata configuration files and operations
@MainActor
final class ConfigurationManager {
    let configPath: String

    private let configurationService: ConfigurationService

    init(configurationService: ConfigurationService) {
        self.configurationService = configurationService

        configPath = configurationService.configurationPath
    }

    func buildKanataArguments(checkOnly: Bool = false) -> [String] {
        var arguments = ["--cfg", configPath]

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
            return (false, [String(localized: "Config file does not exist at: \(configPath)")])
        }

        // Use CLI validation (TCP-only mode)
        AppLogger.shared.log("📄 [ConfigManager] Using file-based validation")
        return await configurationService.validateConfigViaFile()
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
                    try await DefaultTextEditor.open(filePath)
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
