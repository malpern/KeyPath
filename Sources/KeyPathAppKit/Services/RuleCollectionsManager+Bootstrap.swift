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

    var storedCollections = await storedCollectionsTask
    var storedCustomRules = await storedCustomRulesTask

    // Migrate legacy custom mappings if needed
    if storedCustomRules.isEmpty,
       let customIndex = storedCollections.firstIndex(where: {
           $0.id == RuleCollectionIdentifier.customMappings
       })
    {
        let legacy = storedCollections.remove(at: customIndex)
        storedCustomRules = legacy.mappings.map { mapping in
            CustomRule(
                id: mapping.id,
                title: "",
                input: mapping.input,
                output: mapping.output,
                isEnabled: legacy.isEnabled
            )
        }
        AppLogger.shared.log(
            "♻️ [RuleCollections] Migrated \(storedCustomRules.count) legacy custom mapping(s) into CustomRulesStore"
        )
        do {
            try await customRulesStore.saveRules(storedCustomRules)
        } catch {
            AppLogger.shared.log(
                "⚠️ [RuleCollections] Failed to persist migrated custom rules: \(error)")
        }
        do {
            try await ruleCollectionStore.saveCollections(storedCollections)
        } catch {
            AppLogger.shared.log(
                "⚠️ [RuleCollections] Failed to persist collections after migration: \(error)")
        }
    }

    ruleCollections = RuleCollectionDeduplicator.dedupe(storedCollections)
    customRules = storedCustomRules
    AppLogger.shared.log("📊 [RuleCollectionsManager] bootstrap: loaded \(customRules.count) custom rules from store")

    ensureDefaultCollectionsIfNeeded()
    runMigrations()

    // Restore keymap collection if a non-QWERTY layout was active
    if activeKeymapId != LogicalKeymap.defaultId {
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
