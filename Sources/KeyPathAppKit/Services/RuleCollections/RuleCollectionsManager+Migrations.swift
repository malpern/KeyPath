import Foundation
import KeyPathCore
import KeyPathPermissions
import KeyPathRulesCore

extension RuleCollectionsManager {
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
    /// Compatibility API: `true` means persistence completed, not engine application.
    /// Keep this meaning until callers participate in the multi-store transaction.
    @discardableResult
    func regenerateConfigFromCollections(skipReload: Bool = false, conflictResolutionDepth: Int = 0) async -> Bool {
        await persistRules(skipReload: skipReload, conflictResolutionDepth: conflictResolutionDepth).didPersist
    }

    /// Returns persistence failure or the actual reload result after persistence.
    /// Nil reload means explicitly skipped or no callback, never presumed applied.
    func persistRules(skipReload: Bool = false, conflictResolutionDepth: Int = 0) async -> RulePersistenceResult {
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
            AppLogger.shared.log("🔄 [RuleCollections] Custom rules to save: \(customRules.map { "'\($0.input)' → '\($0.action.displayName)'" }.joined(separator: ", "))")
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

            let reloadResult = skipReload ? nil : await onRulesChanged?()
            return .persisted(reloadResult: reloadResult)
        } catch let error as CancellationError {
            // Task was cancelled (e.g., view disappeared mid-save) — silently ignore
            // rather than showing a misleading "validation failed" dialog
            AppLogger.shared.log("⚠️ [RuleCollections] Config save cancelled (task cancellation)")
            return .failed(error)
        } catch {
            // #460: if the failure is a mapping conflict between real collections,
            // offer to disable one inline and retry, instead of just showing an error.
            if let resolved = await tryResolveMappingConflict(
                error, skipReload: skipReload, depth: conflictResolutionDepth
            ) {
                return resolved
            }

            AppLogger.shared.log("❌ [RuleCollections] Failed to regenerate config: \(error)")
            AppLogger.shared.log("❌ [RuleCollections] Error details: \(String(describing: error))")

            // Detect validation cancellation (propagated through KeyPathError wrapper)
            if let keyPathError = error as? KeyPathError,
               case let .configuration(configError) = keyPathError,
               case let .validationFailed(errors) = configError,
               errors.contains(where: { $0.contains("cancelled") })
            {
                AppLogger.shared.log("⚠️ [RuleCollections] Config validation was cancelled — not showing error dialog")
                return .failed(error)
            }

            // Extract user-friendly error message
            let userMessage: String = if let keyPathError = error as? KeyPathError,
                                         case let .configuration(configError) = keyPathError,
                                         case let .validationFailed(errors) = configError
            {
                "Configuration validation failed:\n\n" + errors.joined(separator: "\n")
            } else if let keyPathError = error as? KeyPathError,
                      case let .configuration(configError) = keyPathError,
                      case let .mappingConflicts(conflicts) = configError
            {
                // Non-actionable (or cancelled) mapping conflict — explain it (#460).
                conflicts.map(\.userExplanation).joined(separator: "\n\n")
            } else {
                "Failed to save configuration: \(error.localizedDescription)"
            }

            // Notify user via callback
            AppLogger.shared.debug("🚨 [RuleCollectionsManager] About to call onError, callback is \(onError == nil ? "nil" : "set"): \(userMessage)")
            onError?(userMessage)

            await MainActor.run {
                SoundManager.shared.playErrorSound()
            }

            return .failed(error)
        }
    }
}
