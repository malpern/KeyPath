import Foundation
import KeyPathCore
import KeyPathPermissions

extension RuleCollectionsManager {
    // MARK: - Migrations

    private enum MigrationKey {
        static let launcherEnabledByDefault = "RuleCollections.Migration.LauncherEnabledByDefault"
    }

    /// Run one-time migrations for collection state changes
    func runMigrations() {
        // Migration: Enable Quick Launcher by default (added in 1.1)
        // This runs once for existing users who had launcher disabled by old default
        if !UserDefaults.standard.bool(forKey: MigrationKey.launcherEnabledByDefault) {
            if let index = ruleCollections.firstIndex(where: { $0.id == RuleCollectionIdentifier.launcher }) {
                if !ruleCollections[index].isEnabled {
                    ruleCollections[index].isEnabled = true
                    AppLogger.shared.log("♻️ [RuleCollections] Migration: Enabled Quick Launcher by default")
                }
            }
            UserDefaults.standard.set(true, forKey: MigrationKey.launcherEnabledByDefault)
        }
    }

    func dedupeRuleCollectionsInPlace() {
        ruleCollections = RuleCollectionDeduplicator.dedupe(ruleCollections)
    }

    func refreshLayerIndicatorState() {
        let hasLayered = ruleCollections.contains { $0.isEnabled && $0.targetLayer != .base }
        if !hasLayered {
            updateActiveLayerName(RuleCollectionLayer.base.kanataName)
        }
    }

    func updateActiveLayerName(_ rawName: String) {
        let normalized = rawName.isEmpty ? RuleCollectionLayer.base.kanataName : rawName
        let display = normalized.capitalized

        // Heartbeat: any layer poll result means TCP is alive, even if layer is unchanged.
        NotificationCenter.default.post(name: .kanataTcpHeartbeat, object: nil)

        if currentLayerName == display {
            return
        }

        currentLayerName = display
        onLayerChanged?(display)

        // Show visual layer indicator
        AppLogger.shared.log("🎯 [RuleCollectionsManager] Calling LayerIndicatorManager.showLayer('\(display)')")
        LayerIndicatorManager.shared.showLayer(display)
    }

    /// Regenerates the Kanata configuration from collections and custom rules.
    /// Returns `true` on success, `false` if validation or saving fails.
    @discardableResult
    func regenerateConfigFromCollections(skipReload: Bool = false) async -> Bool {
        dedupeRuleCollectionsInPlace()

        AppLogger.shared.log("🔄 [RuleCollections] regenerateConfigFromCollections: \(ruleCollections.count) collections, \(customRules.count) custom rules")

        // INVARIANT: In production, ruleCollections should never be empty (at minimum, macOS Function Keys)
        // Tests may create isolated scenarios with empty collections, so only warn in debug builds
        if ruleCollections.isEmpty {
            AppLogger.shared.log("⚠️ [RuleCollections] regenerateConfigFromCollections called with empty collections")
        }

        // INVARIANT: At least one collection should be enabled (macOS Function Keys is system default)
        // Log warning instead of assert to avoid crashing in edge cases
        if !ruleCollections.contains(where: \.isEnabled), !ruleCollections.isEmpty {
            AppLogger.shared.log("⚠️ [RuleCollections] No enabled collections - config will only have defaults")
        }

        do {
            // Suppress file watcher before saving to prevent double-reload race condition
            // Without this, the file watcher detects our write and tries to reload,
            // which can race with onRulesChanged reload and cause an error beep
            onBeforeSave?()

            AppLogger.shared.log("🔄 [RuleCollections] Calling configurationService.saveConfiguration...")
            AppLogger.shared.log("🔄 [RuleCollections] Custom rules to save: \(customRules.map { "'\($0.input)' → '\($0.output)'" }.joined(separator: ", "))")
            // IMPORTANT: Save config FIRST (validates before writing)
            // Only persist to stores AFTER config is successfully written
            // This prevents store/config mismatch if validation fails
            try await configurationService.saveConfiguration(
                ruleCollections: ruleCollections,
                customRules: customRules
            )
            AppLogger.shared.log("✅ [RuleCollections] configurationService.saveConfiguration succeeded")

            // Config write succeeded - now persist to stores
            try await ruleCollectionStore.saveCollections(ruleCollections)
            try await customRulesStore.saveRules(customRules)
            AppLogger.shared.log("✅ [RuleCollections] Stores persisted")

            // Notify observers and play success sound
            await MainActor.run {
                NotificationCenter.default.post(name: .ruleCollectionsChanged, object: nil)
                SoundManager.shared.playTinkSound()
            }

            if !skipReload {
                await onRulesChanged?()
            }

            return true
        } catch {
            AppLogger.shared.log("❌ [RuleCollections] Failed to regenerate config: \(error)")
            AppLogger.shared.log("❌ [RuleCollections] Error details: \(String(describing: error))")

            // Extract user-friendly error message
            let userMessage = if let keyPathError = error as? KeyPathError,
                                 case let .configuration(configError) = keyPathError,
                                 case let .validationFailed(errors) = configError {
                "Configuration validation failed:\n\n" + errors.joined(separator: "\n")
            } else {
                "Failed to save configuration: \(error.localizedDescription)"
            }

            // Notify user via callback
            AppLogger.shared.debug("🚨 [RuleCollectionsManager] About to call onError, callback is \(onError == nil ? "nil" : "set"): \(userMessage)")
            onError?(userMessage)

            await MainActor.run {
                SoundManager.shared.playErrorSound()
            }

            return false
        }
    }
}
