import Foundation
import SwiftUI

@MainActor
extension KanataManager {
    // MARK: - Configuration File Watching

    /// Start watching the configuration file for external changes
    func startConfigFileWatching() {
        guard let fileWatcher = self.configFileWatcher else {
            AppLogger.shared.log("⚠️ [FileWatcher] ConfigFileWatcher not initialized")
            return
        }

        let configPath = configPath
        AppLogger.shared.log("📁 [FileWatcher] Starting to watch config file: \(configPath)")

        fileWatcher.startWatching(path: configPath) { [weak self] in
            await self?.handleExternalConfigChange()
        }
    }

    /// Stop watching the configuration file
    func stopConfigFileWatching() {
        self.configFileWatcher?.stopWatching()
        AppLogger.shared.log("📁 [FileWatcher] Stopped watching config file")
    }

    /// Handle external configuration file changes
    func handleExternalConfigChange() async {
        AppLogger.shared.log("📝 [FileWatcher] External config file change detected")

        // Play the initial sound to indicate detection
        Task { @MainActor in SoundManager.shared.playTinkSound() }

        // Show initial status message
        await MainActor.run {
            saveStatus = .saving
        }

        // Read the updated configuration
        let configPath = configPath
        guard FileManager.default.fileExists(atPath: configPath) else {
            AppLogger.shared.log("❌ [FileWatcher] Config file no longer exists: \(configPath)")
            Task { @MainActor in SoundManager.shared.playErrorSound() }
            await MainActor.run {
                saveStatus = .failed("Config file was deleted")
            }
            return
        }

        do {
            let currentConfig = try String(contentsOfFile: configPath, encoding: .utf8)
            AppLogger.shared.log("📝 [FileWatcher] Read updated config: \(currentConfig.count) chars")

            // Parse + validate via existing flow
            let validation = await validateConfigFile()
            if !validation.isValid {
                AppLogger.shared.log("❌ [FileWatcher] Updated config is invalid: \(validation.errors.joined(separator: ", "))")
                Task { @MainActor in SoundManager.shared.playErrorSound() }
                await MainActor.run {
                    saveStatus = .failed(validation.errors.first ?? "Invalid configuration")
                }
                return
            }

            // Trigger reload (best-effort)
            let reloadResult = await triggerTCPReload()
            if reloadResult.isSuccess {
                AppLogger.shared.log("✅ [FileWatcher] Reloaded config after external change")
                Task { @MainActor in SoundManager.shared.playTinkSound() }
                await MainActor.run { saveStatus = .success }
            } else {
                AppLogger.shared.log("⚠️ [FileWatcher] Failed to hot-reload after external change: \(reloadResult.errorMessage ?? "Unknown error")")
                Task { @MainActor in SoundManager.shared.playErrorSound() }
                await MainActor.run { saveStatus = .failed("Hot reload failed") }
            }
        } catch {
            AppLogger.shared.log("❌ [FileWatcher] Failed to read updated config: \(error)")
            Task { @MainActor in SoundManager.shared.playErrorSound() }
            await MainActor.run { saveStatus = .failed("Failed to read updated config") }
        }
    }
}
