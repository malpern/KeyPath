import Foundation
import KeyPathCore
import KeyPathPermissions
import KeyPathRulesCore

extension RuleCollectionsManager {
    // MARK: - Keymap Layout Management

    /// Set the active keyboard layout and regenerate the config.
    ///
    /// When a non-QWERTY layout is selected, this generates Kanata rules that
    /// remap physical QWERTY keys to output the target layout's characters.
    ///
    /// - Parameters:
    ///   - keymapId: The layout ID (e.g., "colemak-dh", "dvorak", or "qwerty-us" for none)
    ///   - includePunctuation: Whether to remap punctuation keys (relevant for Dvorak)
    /// - Returns: Array of conflicting custom rules, if any
    @discardableResult
    func setActiveKeymap(_ keymapId: String, includePunctuation: Bool) async -> [RuleConflictInfo] {
        await withRuleMutation(failure: []) { [self] permit in
            AppLogger.shared.log("⌨️ [RuleCollections] Setting active keymap to '\(keymapId)' (punctuation: \(includePunctuation))")

            let keymapBefore = (id: activeKeymapId, includePunctuation: keymapIncludesPunctuation)
            do {
                try await recoverRuleState(mutationPermit: permit)
            } catch {
                KeymapPreferences.restoreFailedSelection(
                    attemptedID: keymapId, attemptedPunctuation: includePunctuation,
                    previousID: keymapBefore.id, previousPunctuation: keymapBefore.includePunctuation,
                    userDefaults: keymapPreferences
                )
                if !(error is CancellationError) { onError?(error.localizedDescription) }
                return []
            }
            let snapshot = snapshotRuleState()
            activeKeymapId = keymapId
            keymapIncludesPunctuation = includePunctuation

            // Check for conflicts with custom rules
            let conflicts = detectKeymapConflicts(keymapId: keymapId, includePunctuation: includePunctuation)

            if !conflicts.isEmpty {
                let conflictKeys = conflicts.flatMap(\.keys).joined(separator: ", ")
                onWarning?(
                    "⚠️ Layout change affects custom rules on: \(conflictKeys). Custom rules will override layout mappings for those keys."
                )
                AppLogger.shared.log("⚠️ [RuleCollections] Keymap conflicts with custom rules on: \(conflictKeys)")
            }

            // Remove any existing keymap collection
            ruleCollections.removeAll { $0.id == RuleCollectionIdentifier.keymapLayout }

            // Add new keymap collection if not QWERTY
            if let keymapCollection = KeymapMappingGenerator.generateCollection(
                for: keymapId,
                includePunctuation: includePunctuation
            ) {
                // Insert at the beginning so custom rules take priority
                ruleCollections.insert(keymapCollection, at: 0)
                AppLogger.shared.log("⌨️ [RuleCollections] Added keymap collection with \(keymapCollection.mappings.count) mappings")
            } else if keymapId == LogicalKeymap.defaultId {
                AppLogger.shared.log("⌨️ [RuleCollections] QWERTY selected - no keymap collection needed")
            }

            refreshLayerIndicatorState()
            if await commitRuleMutation(snapshot: snapshot, failureContext: "keyboard layout", keymapBefore: keymapBefore, mutationPermit: permit) {
                await persistKeymapState()
            }

            return conflicts
        }
    }

    /// Detect conflicts between the keymap layout and existing custom rules.
    ///
    /// Returns information about which custom rules target keys that the keymap will remap.
    func detectKeymapConflicts(keymapId: String, includePunctuation: Bool) -> [RuleConflictInfo] {
        guard let keymap = LogicalKeymap.find(id: keymapId),
              keymapId != LogicalKeymap.qwertyUSId,
              keymapId != LogicalKeymap.systemId
        else {
            return []
        }

        let keymapMappings = KeymapMappingGenerator.generateMappings(
            to: keymap,
            includePunctuation: includePunctuation
        )

        let keymapKeys = Set(keymapMappings.map { KanataKeyConverter.convertToKanataKey($0.input) })

        var conflicts: [RuleConflictInfo] = []

        for rule in customRules where rule.isEnabled {
            let normalizedInput = KanataKeyConverter.convertToKanataKey(rule.input)
            if keymapKeys.contains(normalizedInput) {
                conflicts.append(RuleConflictInfo(source: .customRule(rule), keys: [normalizedInput]))
            }
        }

        return conflicts
    }

    /// Persist the current keymap state to UserDefaults
    func persistKeymapState() async {
        keymapPreferences.set(activeKeymapId, forKey: "activeKeymapId")
        keymapPreferences.set(keymapIncludesPunctuation, forKey: "keymapIncludesPunctuation")
        AppLogger.shared.log("💾 [RuleCollections] Persisted keymap state: \(activeKeymapId)")
    }

    /// Restore keymap state from UserDefaults (called during bootstrap)
    func restoreKeymapState() {
        if let storedKeymapId = keymapPreferences.string(forKey: "activeKeymapId") {
            activeKeymapId = storedKeymapId
        }
        keymapIncludesPunctuation = keymapPreferences.bool(forKey: "keymapIncludesPunctuation")
        AppLogger.shared.log("📂 [RuleCollections] Restored keymap state: \(activeKeymapId) (punctuation: \(keymapIncludesPunctuation))")
    }
}
