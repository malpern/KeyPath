import KeyPathCore
import SwiftUI

// MARK: - Rule Management

extension LiveKeyboardOverlayView {
    /// Load custom rules state (both global and app-specific)
    func loadCustomRulesState() {
        Task {
            let keymaps = await services.appKeymapStore.loadKeymaps()
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
            guard let manager = kanataViewModel?.underlyingManager else { return }
            do {
                try await manager.removeAppRule(
                    bundleIdentifier: keymap.mapping.bundleIdentifier,
                    overrideID: override.id,
                    store: services.appKeymapStore
                )
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

            do {
                try await manager.mutateAppKeymaps(store: services.appKeymapStore) { $0.removeAll() }
            } catch {
                AppLogger.shared.log("⚠️ [LiveKeyboardOverlay] Failed to clear app rules: \(error)")
                appRuleDeleteError = "Failed to clear app rules: \(error.localizedDescription)"
                return
            }

            // Reload UI state
            loadCustomRulesState()
            SoundPlayer.shared.playSuccessSound()
        }
    }
}
