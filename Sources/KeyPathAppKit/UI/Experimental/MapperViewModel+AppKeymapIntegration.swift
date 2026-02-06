import AppKit
import KeyPathCore

// MARK: - App Keymap Integration

/// Extension to integrate MapperViewModel with the per-app keymap system
extension MapperViewModel {
    /// Save a mapping that only applies when a specific app is active.
    /// Uses AppKeymapStore and AppConfigGenerator for virtual key-based app detection.
    ///
    /// - Returns: `true` if successful, `false` if failed. On failure, `statusMessage` is set with details.
    func saveAppSpecificMapping(
        inputKey: String,
        outputAction: String,
        appCondition: AppConditionInfo,
        kanataManager: RuntimeCoordinator
    ) async -> Bool {
        AppLogger.shared.log("🎯 [MapperViewModel] Saving app-specific mapping: \(inputKey) → \(outputAction) [only in \(appCondition.displayName)]")

        do {
            // 1. Load existing keymaps
            var existingKeymap = await AppKeymapStore.shared.getKeymap(bundleIdentifier: appCondition.bundleIdentifier)

            // 2. Create or update the keymap
            if existingKeymap == nil {
                // Create new keymap for this app
                existingKeymap = AppKeymap(
                    bundleIdentifier: appCondition.bundleIdentifier,
                    displayName: appCondition.displayName,
                    overrides: []
                )
                AppLogger.shared.log("🎯 [MapperViewModel] Created new app keymap for \(appCondition.displayName)")
            }

            guard var keymap = existingKeymap else {
                AppLogger.shared.error("❌ [MapperViewModel] Failed to create keymap")
                statusMessage = "Failed to create keymap"
                statusIsError = true
                return false
            }

            // 3. Add or update the override for this input key
            let newOverride = AppKeyOverride(
                inputKey: inputKey.lowercased(),
                outputAction: outputAction,
                description: "Created via Mapper"
            )

            // Remove existing override for same input key (if any)
            keymap.overrides.removeAll { $0.inputKey.lowercased() == inputKey.lowercased() }
            keymap.overrides.append(newOverride)

            // 4. Save to store
            try await AppKeymapStore.shared.upsertKeymap(keymap)

            // 5. Regenerate the app-specific config file (keypath-apps.kbd)
            try await AppConfigGenerator.regenerateFromStore()

            // 5.1. Regenerate the MAIN config to use @kp-* aliases for app-specific keys
            // Without this, the base layer uses plain 'a' instead of '@kp-a',
            // and the switch expression in keypath-apps.kbd is never reached.
            try await AppConfigGenerator.regenerateMainConfig()

            // 6. Ensure the include line is in the main config
            let migrationService = KanataConfigMigrationService()
            let mainConfigPath = WizardSystemPaths.userConfigPath
            if !migrationService.hasIncludeLine(configPath: mainConfigPath) {
                do {
                    try migrationService.prependIncludeLineIfMissing(to: mainConfigPath)
                    AppLogger.shared.log("✅ [MapperViewModel] Added include line for keypath-apps.kbd")
                } catch KanataConfigMigrationService.MigrationError.includeAlreadyPresent {
                    // Already present, ignore
                } catch {
                    AppLogger.shared.warn("⚠️ [MapperViewModel] Could not add include line: \(error)")
                    // Continue anyway - user may need to add it manually
                }
            }

            // 7. Update AppContextService with the new bundle-to-VK mapping
            await AppContextService.shared.reloadMappings()

            // 8. Reload Kanata to pick up the new config
            _ = await kanataManager.restartKanata(reason: "Per-app mapping saved")

            AppLogger.shared.log("✅ [MapperViewModel] App-specific mapping saved")
            return true
        } catch {
            AppLogger.shared.error("❌ [MapperViewModel] Failed to save app-specific mapping: \(error)")
            statusMessage = "Failed to save: \(error.localizedDescription)"
            statusIsError = true
            return false
        }
    }

    /// Remove the mapping for a specific app for the given input key.
    func removeAppSpecificMapping(
        inputKey: String,
        appCondition: AppConditionInfo
    ) async {
        do {
            guard var keymap = await AppKeymapStore.shared.getKeymap(bundleIdentifier: appCondition.bundleIdentifier) else {
                return
            }

            // Remove the override for this input key
            keymap.overrides.removeAll { $0.inputKey.lowercased() == inputKey.lowercased() }

            if keymap.overrides.isEmpty {
                // If no more overrides, remove the entire keymap
                try await AppKeymapStore.shared.removeKeymap(bundleIdentifier: appCondition.bundleIdentifier)
            } else {
                // Update with remaining overrides
                try await AppKeymapStore.shared.upsertKeymap(keymap)
            }

            // Regenerate config
            try await AppConfigGenerator.regenerateFromStore()
            await AppContextService.shared.reloadMappings()

            AppLogger.shared.log("✅ [MapperViewModel] Removed app-specific mapping")
        } catch {
            AppLogger.shared.error("❌ [MapperViewModel] Failed to remove app-specific mapping: \(error)")
        }
    }
}
