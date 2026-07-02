import Foundation
import KeyPathCore
import KeyPathPermissions

extension RuleCollectionsManager {
    // MARK: - Bootstrap

    /// Load rule collections and custom rules from persistent storage
    func bootstrap() async {
        // Restore keymap state first (before loading collections)
        restoreKeymapState()

        async let storedCollectionsTask = ruleCollectionStore.loadCollectionsDetailed()
        async let storedCustomRulesTask = customRulesStore.loadRules()

        let loadResult = await storedCollectionsTask
        let storedCustomRules = await storedCustomRulesTask

        ruleCollections = RuleCollectionDeduplicator.dedupe(loadResult.collections)
        customRules = storedCustomRules
        AppLogger.shared.log("📊 [RuleCollectionsManager] bootstrap: loaded \(customRules.count) custom rules from store")

        if !loadResult.failedCollectionNames.isEmpty || loadResult.wasFullReset {
            notifyConfigRecovery(loadResult)
        }

        ensureDefaultCollectionsIfNeeded()

        // Re-enable collections that installed packs expect to be active.
        // Handles drift when RuleCollections.json is reset independently of installed-packs.json.
        await reconcilePackCollectionState()

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

        let leaderSnapshot = PreferencesService.shared.leaderKeyPreference
        let collectionsSnapshot = ruleCollections
        let didReconcileLeader = reconcileLeaderKeyFromCollection()

        let applied = await regenerateConfigFromCollections()
        if didReconcileLeader, !applied {
            rollbackLeaderReconcile(preference: leaderSnapshot, collections: collectionsSnapshot)
        }
    }

    // MARK: - Pack Reconciliation

    /// Cross-reference installed packs against loaded collections and re-enable
    /// any collection that an installed pack manages but that was loaded as disabled.
    private func reconcilePackCollectionState() async {
        let installedRecords = await InstalledPackTracker.shared.allInstalled()
        guard !installedRecords.isEmpty else { return }

        var fixedCount = 0

        for record in installedRecords {
            guard let pack = PackRegistry.pack(id: record.packID) else { continue }

            for collectionID in pack.managedCollectionIDs {
                guard let index = ruleCollections.firstIndex(where: { $0.id == collectionID }) else {
                    continue
                }
                if !ruleCollections[index].isEnabled {
                    ruleCollections[index].isEnabled = true
                    fixedCount += 1
                    AppLogger.shared.log(
                        "🔧 [Bootstrap] Reconciled: re-enabled '\(ruleCollections[index].name)' for installed pack '\(pack.name)'"
                    )
                }
            }
        }

        if fixedCount > 0 {
            AppLogger.shared.log("🔧 [Bootstrap] Pack reconciliation fixed \(fixedCount) collection(s)")
        }
    }

    // MARK: - Config Recovery Notification

    private func notifyConfigRecovery(_ result: RuleCollectionStore.LoadResult) {
        let backupNote = result.backupPath != nil ? " Your previous config was backed up." : ""

        if result.wasFullReset {
            let body = "All rule configurations were reset to defaults.\(backupNote)"
            AppLogger.shared.log("⚠️ [Bootstrap] Full config reset. Backup: \(result.backupPath ?? "none")")
            Task { @MainActor in
                UserNotificationService.shared.notifyConfigEvent(
                    "Configuration Reset",
                    body: body,
                    key: "config.reset.full"
                )
            }
        } else {
            let names = result.failedCollectionNames
            let summary = names.count <= 3
                ? names.joined(separator: ", ")
                : "\(names.prefix(3).joined(separator: ", ")) and \(names.count - 3) more"
            let body = "\(summary) reset to defaults after an update.\(backupNote)"
            AppLogger.shared.log("⚠️ [Bootstrap] Partial config recovery: \(names.joined(separator: ", "))")
            Task { @MainActor in
                UserNotificationService.shared.notifyConfigEvent(
                    "\(names.count) Rule\(names.count == 1 ? "" : "s") Reset",
                    body: body,
                    key: "config.reset.partial"
                )
            }
        }
    }
}
