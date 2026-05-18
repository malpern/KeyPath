import Foundation
import KeyPathCore
import KeyPathPermissions

extension RuleCollectionsManager {
    // MARK: - Bootstrap

    /// Load rule collections and custom rules from persistent storage
    func bootstrap() async {
        // Restore keymap state first (before loading collections)
        restoreKeymapState()

        async let storedCollectionsTask = ruleCollectionStore.loadCollections()
        async let storedCustomRulesTask = customRulesStore.loadRules()

        let storedCollections = await storedCollectionsTask
        let storedCustomRules = await storedCustomRulesTask

        ruleCollections = RuleCollectionDeduplicator.dedupe(storedCollections)
        customRules = storedCustomRules
        AppLogger.shared.log("📊 [RuleCollectionsManager] bootstrap: loaded \(customRules.count) custom rules from store")

        ensureDefaultCollectionsIfNeeded()

        // Restore keymap collection if a non-identity layout was active
        if activeKeymapId != LogicalKeymap.qwertyUSId, activeKeymapId != LogicalKeymap.systemId {
            if let keymapCollection = KeymapMappingGenerator.generateCollection(
                for: activeKeymapId,
                includePunctuation: keymapIncludesPunctuation
            ) {
                // Remove any stale keymap collection first
                ruleCollections.removeAll { $0.id == RuleCollectionIdentifier.keymapLayout }
                // Insert at beginning so custom rules take priority
                ruleCollections.insert(keymapCollection, at: 0)
                AppLogger.shared.log("⌨️ [RuleCollections] Restored keymap collection for \(activeKeymapId)")
            }
        }

        dedupeRuleCollectionsInPlace()
        refreshLayerIndicatorState()

        await regenerateConfigFromCollections()
    }
}
