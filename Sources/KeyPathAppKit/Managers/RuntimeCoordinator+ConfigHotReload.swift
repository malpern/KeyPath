import Foundation
import KeyPathCore

extension RuntimeCoordinator {
    // MARK: - Configuration File Watching (delegates to ConfigHotReloadService)

    /// Start watching the configuration file for external changes
    func startConfigFileWatching() {
        guard let fileWatcher = configFileWatcher else {
            AppLogger.shared.warn("⚠️ [FileWatcher] ConfigFileWatcher not initialized")
            return
        }

        // Configure the hot reload service
        configHotReloadService.configure(
            configurationService: configurationService,
            reloadHandler: { [weak self] in
                guard let self else { return false }
                let result = await triggerConfigReload()
                return result.isSuccess
            },
            configParser: { [weak self] content in
                guard let self else { return [] }
                let parsed = try configurationService.parseConfigurationFromString(content)
                return parsed.keyMappings
            }
        )

        // Set up UI callbacks
        configHotReloadService.callbacks = ConfigHotReloadService.Callbacks(
            onDetected: {
                SoundManager.shared.playTinkSound()
            },
            onValidating: { [weak self] in
                self?.saveStatus = .saving
            },
            onSuccess: { [weak self] content in
                SoundManager.shared.playGlassSound()
                self?.saveStatus = .success
                // Update in-memory config
                if let mappings = self?.configHotReloadService.parseKeyMappings(from: content) {
                    self?.applyKeyMappings(mappings)
                }
            },
            onFailure: { [weak self] message in
                SoundManager.shared.playErrorSound()
                self?.saveStatus = .failed(message)
            },
            onReset: { [weak self] in
                self?.saveStatus = .idle
            }
        )

        let configPath = configPath
        AppLogger.shared.log("📁 [FileWatcher] Starting to watch config file: \(configPath)")

        fileWatcher.startWatching(path: configPath) { [weak self] in
            guard let self else { return }
            _ = await configHotReloadService.handleExternalChange(configPath: configPath)
        }
    }

    /// Stop watching the configuration file
    func stopConfigFileWatching() {
        configFileWatcher?.stopWatching()
        AppLogger.shared.log("📁 [FileWatcher] Stopped watching config file")
    }
}
