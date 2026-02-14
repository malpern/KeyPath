import KeyPathCore
import SwiftUI

// MARK: - Rule Management

extension LiveKeyboardOverlayView {
    /// Load custom rules state (both global and app-specific)
    func loadCustomRulesState() {
        Task {
            let keymaps = await AppKeymapStore.shared.loadKeymaps()
            await MainActor.run {
                appKeymaps = keymaps
                // Show custom rules tab if either global rules or app-specific rules exist
                // NOTE: We read underlyingManager.customRules directly to avoid race condition
                // where the notification arrives before KanataViewModel's async state update
                let globalRules = kanataViewModel?.underlyingManager.customRules ?? []
                cachedCustomRules = globalRules
                let hasGlobalRules = !globalRules.isEmpty
                let hasAppSpecificRules = !keymaps.isEmpty
                hasCustomRules = hasGlobalRules || hasAppSpecificRules
                // If we were on customRules tab but rules are gone, switch to mapper
                if !hasCustomRules, inspectorSection == .customRules {
                    inspectorSection = .mapper
                }
            }
        }
    }

    /// Delete an app-specific rule override
    func deleteAppRule(keymap: AppKeymap, override: AppKeyOverride) {
        Task {
            // Remove the override from the keymap
            var updatedKeymap = keymap
            updatedKeymap.overrides.removeAll { $0.id == override.id }

            do {
                if updatedKeymap.overrides.isEmpty {
                    // No more overrides - remove entire keymap
                    try await AppKeymapStore.shared.removeKeymap(bundleIdentifier: keymap.mapping.bundleIdentifier)
                } else {
                    // Update keymap with remaining overrides
                    try await AppKeymapStore.shared.upsertKeymap(updatedKeymap)
                }

                // Regenerate config and reload
                try await AppConfigGenerator.regenerateFromStore()
                await AppContextService.shared.reloadMappings()

                // Restart Kanata to pick up changes
                if let kanataVM = kanataViewModel {
                    _ = await kanataVM.underlyingManager.restartKanata(reason: "App rule deleted")
                }
            } catch {
                AppLogger.shared.log("⚠️ [Overlay] Failed to delete app rule: \(error)")
                await MainActor.run {
                    appRuleDeleteError = "Failed to delete rule: \(error.localizedDescription)"
                }
            }
        }
    }

    /// Reset all custom rules (global and app-specific)
    func resetAllCustomRules() {
        Task {
            guard let manager = kanataViewModel?.underlyingManager else { return }

            // Clear all global custom rules atomically (uses clearAllCustomRules which saves to disk)
            await manager.clearAllCustomRules()

            // Remove all app-specific keymaps
            let keymapsToRemove = appKeymaps
            for keymap in keymapsToRemove {
                try? await AppKeymapStore.shared.removeKeymap(bundleIdentifier: keymap.mapping.bundleIdentifier)
            }

            // Regenerate app config and restart Kanata to apply all changes
            do {
                try await AppConfigGenerator.regenerateFromStore()
                await AppContextService.shared.reloadMappings()
                _ = await manager.restartKanata(reason: "All custom rules reset")
            } catch {
                AppLogger.shared.log("⚠️ [LiveKeyboardOverlay] Failed to regenerate config after reset: \(error)")
            }

            // Reload UI state
            loadCustomRulesState()
            SoundPlayer.shared.playSuccessSound()
        }
    }
}
