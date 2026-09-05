import AppKit
import KeyPathCore
import KeyPathRulesCore

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
        let action: KeyAction = outputAction.contains("(") ? .rawKanata(outputAction) : .keystroke(key: outputAction)
        AppLogger.shared.log("🎯 [MapperViewModel] Saving app-specific mapping: \(inputKey) → \(outputAction) [only in \(appCondition.displayName)]")

        do {
            try await kanataManager.mutateAppKeymaps { keymaps in
                let index = keymaps.firstIndex { $0.mapping.bundleIdentifier == appCondition.bundleIdentifier }
                var keymap = index.map { keymaps[$0] } ?? AppKeymap(
                    bundleIdentifier: appCondition.bundleIdentifier,
                    displayName: appCondition.displayName,
                    overrides: []
                )
                keymap.overrides.removeAll { $0.inputKey.lowercased() == inputKey.lowercased() }
                keymap.overrides.append(AppKeyOverride(inputKey: inputKey.lowercased(), action: action, description: "Created via Mapper"))
                AppKeymapStore.upsert(keymap, in: &keymaps)
            }

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
            guard let kanataManager else { throw AppConfigError.validationUnavailable }
            try await kanataManager.mutateAppKeymaps { keymaps in
                guard let index = keymaps.firstIndex(where: { $0.mapping.bundleIdentifier == appCondition.bundleIdentifier }) else { return }
                keymaps[index].overrides.removeAll { $0.inputKey.lowercased() == inputKey.lowercased() }
                if keymaps[index].overrides.isEmpty { keymaps.remove(at: index) }
            }

            AppLogger.shared.log("✅ [MapperViewModel] Removed app-specific mapping")
        } catch {
            AppLogger.shared.error("❌ [MapperViewModel] Failed to remove app-specific mapping: \(error)")
            statusMessage = error.localizedDescription
            statusIsError = true
        }
    }
}
