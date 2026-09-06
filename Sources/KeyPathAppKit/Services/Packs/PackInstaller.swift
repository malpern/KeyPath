// M1 Gallery MVP — install/uninstall packs by converting their binding
// templates into CustomRule entries on RuleCollectionsManager, tagged with
// the pack id so uninstall can find and remove them.
//
// PackInstaller is the only place pack state changes; the Gallery/Pack Detail
// UI calls these methods and does not mutate CustomRules or config directly.

import AppKit
import Foundation
import KeyPathCore
import KeyPathRulesCore

@MainActor
public final class PackInstaller {
    public static let shared = PackInstaller()

    enum ManagedDefaultInstallPolicy: Equatable, Sendable {
        case promptWhenCustomized
        case useRecommended
    }

    #if DEBUG
        /// Test-only overrides for dialog responses. When set, bypasses NSAlert
        /// and returns this value instead.
        static var testOverrideApplyDefault: Bool?
        static var testOverrideRestore: Bool?
    #endif

    private init() {}

    // MARK: - Errors

    public enum InstallError: LocalizedError {
        case noRuleCollectionsManager
        case saveFailed(String)
        /// One or more other packs the user has installed are mutually
        /// exclusive with this one. Carries conflicting pack IDs and names
        /// so the UI can auto-resolve or display them in a dialog.
        case mutuallyExclusive(conflicts: [(id: String, name: String)])
        /// A required external app/dependency isn't installed. Carries
        /// the dependency display name and a website URL the UI can
        /// surface as a "Get it →" CTA.
        case dependencyMissing(name: String, websiteURL: URL)

        public var errorDescription: String? {
            switch self {
            case .noRuleCollectionsManager:
                return "RuleCollectionsManager is not available. The app may not be fully initialised."
            case let .saveFailed(reason):
                return "Could not save pack rules: \(reason)"
            case let .mutuallyExclusive(conflicts):
                let names = conflicts.map(\.name).joined(separator: ", ")
                return "Conflicts with \(names). Turn that pack off first to enable this one."
            case let .dependencyMissing(name, _):
                return "\(name) isn't installed."
            }
        }
    }

    // MARK: - Public API

    /// Recover before reading installed state, including metadata-only operations
    /// that would otherwise overwrite the pending transaction's record revision.
    func recoverAndValidateState(manager: RuleCollectionsManager, tracker: InstalledPackTracker,
                                 permit: ConfigurationOperationGate.Permit) async throws
    {
        let recovered = try await manager.configurationService.recoverPendingRuleWrite(
            collectionStore: manager.ruleCollectionStore, customStore: manager.customRulesStore,
            mutationPermit: permit, installedPackTracker: tracker
        )
        do {
            try await manager.refreshRecoveredRuleStateIfNeeded(recovered)
        } catch let error as KeyPathError {
            if case let .configuration(.loadFailed(reason)) = error {
                throw InstallError.saveFailed(reason)
            }
            throw error
        }
        try await tracker.validateForMutation()
    }

    /// Change only a visual capability's installed record. Legacy Rules toggles
    /// use this narrower operation; catalog installation still enforces its
    /// dependency/conflict gates before entering here. Nonvisual packs must use install/uninstall.
    @discardableResult
    func setVisualPackEnabled(
        _ pack: Pack, enabled: Bool, quickSettingValues: [String: Int]? = nil,
        manager: RuleCollectionsManager, installedPackTracker: InstalledPackTracker = .shared,
        mutationPermit: ConfigurationOperationGate.Permit? = nil
    ) async throws -> InstalledPackRecord? {
        try await manager.configurationService.operationGate.withOperation(using: mutationPermit) { @MainActor [self] permit in
            guard pack.visualOnly else { throw InstallError.saveFailed("This operation requires a visual-only pack") }
            try await recoverAndValidateState(manager: manager, tracker: installedPackTracker, permit: permit)
            let previous = await installedPackTracker.record(for: pack.id)
            let record: InstalledPackRecord?
            if enabled {
                let next = InstalledPackRecord(packID: pack.id, version: pack.version, installedAt: Date(),
                                               quickSettingValues: quickSettingValues ?? previous?.quickSettingValues ?? [:])
                do { try await installedPackTracker.upsert(next) }
                catch {
                    guard await restoreInstallRecord(previous, packID: pack.id, installedPackTracker: installedPackTracker) else {
                        throw InstallError.saveFailed("visual-only installed-pack record could not be saved and the previous state could not be fully restored")
                    }
                    throw error
                }
                record = next
            } else {
                try await installedPackTracker.remove(packID: pack.id)
                record = nil
            }
            // Settle the capability only after its record commits, before releasing admission.
            if installedPackTracker === InstalledPackTracker.shared, pack.id == PackRegistry.keystrokeHistory.id {
                KeystrokeHistoryService.shared.applyPackState(enabled)
            }
            return record
        }
    }

    /// Repair the existing enabled-collection/missing-record case using persisted
    /// sources under admission. Never turn a failed write into an installed result.
    func reconcileInstallRecord(
        for pack: Pack, manager: RuleCollectionsManager,
        installedPackTracker: InstalledPackTracker = .shared
    ) async throws -> InstalledPackRecord? {
        try await manager.configurationService.operationGate.withOperation { @MainActor permit in
            try await self.recoverAndValidateState(manager: manager, tracker: installedPackTracker, permit: permit)
            if let existing = await installedPackTracker.record(for: pack.id) { return existing }
            guard let collectionID = pack.associatedCollectionID else { return nil }
            let loaded = await manager.ruleCollectionStore.loadCollectionsDetailed()
            guard !loaded.wasFullReset, loaded.failedCollectionNames.isEmpty else {
                throw InstallError.saveFailed("Rule collections could not be read completely")
            }
            guard loaded.collections.contains(where: { $0.id == collectionID && $0.isEnabled }) else { return nil }
            let record = InstalledPackRecord(packID: pack.id, version: pack.version, installedAt: Date(), quickSettingValues: [:])
            try await installedPackTracker.upsert(record)
            return record
        }
    }

    /// Install a pack. Expands its binding templates into `CustomRule`s
    /// tagged with the pack's id, adds them to the user's rules, and
    /// regenerates the kanata config (which hot-reloads kanata).
    ///
    /// - Parameter pack: the pack to install.
    /// - Parameter quickSettingValues: user-chosen values for the pack's
    ///   quick settings. Missing keys fall back to the pack's defaults.
    /// - Parameter collectionConfiguration: An explicit configuration for the
    ///   pack's associated collection. Collection-backed and system packs apply
    ///   it atomically with enabling the collection.
    /// - Parameter managedDefaultPolicy: Controls whether a system pack asks
    ///   before replacing a customized managed collection. Onboarding can use
    ///   `.useRecommended` after the user has explicitly approved the change.
    /// - Parameter autoResolveCollectionConflicts: Whether a collection-backed
    ///   pack may automatically disable conflicting rules while it is enabled.
    /// - Parameter additionalCollectionIDsToDisable: Related catalog
    ///   collections to turn off in the same collection-backed transaction.
    /// - Parameter manager: the app's RuleCollectionsManager. Required.
    /// - Parameter skipFinalReload: Persist and validate the resulting config
    ///   without notifying the runtime; the caller owns the live reload.
    /// - Returns: the install record persisted for this pack.
    @discardableResult
    func install(
        _ pack: Pack,
        quickSettingValues: [String: Int] = [:],
        collectionConfiguration: RuleCollectionConfiguration? = nil,
        managedDefaultPolicy: ManagedDefaultInstallPolicy = .promptWhenCustomized,
        autoResolveCollectionConflicts: Bool = true,
        additionalCollectionIDsToDisable: Set<UUID> = [],
        manager: RuleCollectionsManager,
        skipFinalReload: Bool = false,
        installedPackTracker: InstalledPackTracker = .shared,
        mutationPermit: ConfigurationOperationGate.Permit? = nil
    ) async throws -> InstalledPackRecord {
        try await manager.configurationService.operationGate.withOperation(using: mutationPermit) { @MainActor [self] permit in
            try await recoverAndValidateState(manager: manager, tracker: installedPackTracker, permit: permit)
            AppLogger.shared.log(
                "📦 [PackInstaller] Installing pack '\(pack.name)' (id=\(pack.id), v\(pack.version))"
            )

            try await enforcePreInstallGates(
                for: pack,
                manager: manager,
                installedPackTracker: installedPackTracker
            )

            // Resolve effective quick-setting values (user-provided ∪ defaults).
            let resolvedSettings = resolveQuickSettings(pack: pack, overrides: quickSettingValues)

            // Visual-only packs (e.g. KindaVim Mode Display) don't touch the
            // kanata config at all — install just persists the tracker record
            // so other parts of the app (overlay, mode monitor) can react to
            // "this pack is active". No collection toggle, no reload.
            if pack.visualOnly {
                guard let record = try await setVisualPackEnabled(pack, enabled: true, quickSettingValues: resolvedSettings,
                                                                  manager: manager, installedPackTracker: installedPackTracker,
                                                                  mutationPermit: permit)
                else { throw InstallError.saveFailed("Visual pack activation returned no installed record") }
                return record
            }

            // System packs batch all collection changes into a single config regen.
            if pack.isSystemPack {
                let ruleStateSnapshot = manager.snapshotRuleState()
                let previousInstallRecord = await installedPackTracker.record(for: pack.id)
                let previousCollectionSnapshot = PackCollectionSnapshot.load(for: pack.id)
                let record = InstalledPackRecord(
                    packID: pack.id,
                    version: pack.version,
                    installedAt: Date(),
                    quickSettingValues: resolvedSettings
                )
                do {
                    try await applyManagedDefaults(
                        pack: pack,
                        manager: manager,
                        policy: managedDefaultPolicy,
                        associatedCollectionConfiguration: collectionConfiguration,
                        skipReload: skipFinalReload,
                        mutationPermit: permit
                    )
                } catch {
                    AppLogger.shared.errorUnlessQuietTest(
                        "❌ [PackInstaller] Could not apply system-pack defaults for '\(pack.name)'; restoring previous state"
                    )
                    let installRecordRestored = await restoreInstallRecord(
                        previousInstallRecord,
                        packID: pack.id,
                        installedPackTracker: installedPackTracker
                    )
                    let collectionSnapshotRestored = restoreManagedCollectionSnapshot(
                        previousCollectionSnapshot,
                        packID: pack.id
                    )
                    let rollbackApplied = await manager.rollbackToSnapshot(
                        ruleStateSnapshot,
                        userMessage: "Could not apply this system pack. Your previous rule state was restored.",
                        mutationPermit: permit
                    )
                    guard rollbackApplied, collectionSnapshotRestored, installRecordRestored else {
                        throw InstallError.saveFailed(
                            "system-pack defaults could not be applied and the previous state could not be fully restored"
                        )
                    }
                    throw error
                }
                do {
                    try await installedPackTracker.upsert(record)
                } catch {
                    AppLogger.shared.errorUnlessQuietTest(
                        "❌ [PackInstaller] Could not persist system-pack record for '\(pack.name)'; restoring previous state"
                    )
                    let installRecordRestored = await restoreInstallRecord(
                        previousInstallRecord,
                        packID: pack.id,
                        installedPackTracker: installedPackTracker
                    )
                    let collectionSnapshotRestored = restoreManagedCollectionSnapshot(
                        previousCollectionSnapshot,
                        packID: pack.id
                    )
                    let rollbackApplied = await manager.rollbackToSnapshot(
                        ruleStateSnapshot,
                        userMessage: "Could not record this system pack installation. Your previous rule state was restored.",
                        mutationPermit: permit
                    )
                    guard rollbackApplied, collectionSnapshotRestored, installRecordRestored else {
                        throw InstallError.saveFailed(
                            "installed-pack record could not be saved and the previous system-pack state could not be fully restored"
                        )
                    }
                    throw error
                }
                AppLogger.shared.log(
                    "✅ [PackInstaller] Installed system pack '\(pack.name)'"
                )
                return record
            }

            // Collection-backed packs (e.g. Home Row Mods) don't generate custom
            // rules — they just toggle the built-in RuleCollection on.
            if let collectionID = pack.associatedCollectionID {
                let ruleStateSnapshot = manager.snapshotRuleState()
                let previousInstallRecord = await installedPackTracker.record(for: pack.id)
                let ok = await manager.toggleCollection(
                    id: collectionID,
                    isEnabled: true,
                    autoResolveConflicts: autoResolveCollectionConflicts,
                    bypassOwnershipCheck: true,
                    configurationOverride: collectionConfiguration,
                    additionalCollectionIDsToDisable: additionalCollectionIDsToDisable,
                    skipReload: skipFinalReload,
                    mutationPermit: permit
                )
                if !ok {
                    throw InstallError.saveFailed("could not enable associated rule collection")
                }

                let record = InstalledPackRecord(
                    packID: pack.id,
                    version: pack.version,
                    installedAt: Date(),
                    quickSettingValues: resolvedSettings
                )
                do {
                    try await installedPackTracker.upsert(record)
                } catch {
                    AppLogger.shared.errorUnlessQuietTest(
                        "❌ [PackInstaller] Could not persist install record for '\(pack.name)'; restoring previous rule state"
                    )
                    let installRecordRestored = await restoreInstallRecord(
                        previousInstallRecord,
                        packID: pack.id,
                        installedPackTracker: installedPackTracker
                    )
                    let rollbackApplied = await manager.rollbackToSnapshot(
                        ruleStateSnapshot,
                        userMessage: "Could not record this pack installation. Your previous rule state was restored.",
                        mutationPermit: permit
                    )
                    guard rollbackApplied, installRecordRestored else {
                        throw InstallError.saveFailed(
                            "installed-pack record could not be saved and the previous state could not be fully restored"
                        )
                    }
                    throw error
                }
                AppLogger.shared.log(
                    "✅ [PackInstaller] Installed pack '\(pack.name)' via collection toggle (id=\(collectionID))"
                )
                return record
            }

            // Prepare the entire custom-rule pack before writing. The metadata and
            // all rules remain one recoverable revision through runtime application.
            let ruleStateSnapshot = manager.snapshotRuleState()
            let rules = renderBindings(for: pack, quickSettings: resolvedSettings)
            for (index, rule) in rules.enumerated() {
                guard await manager.updateCustomRuleInMemory(rule, mutationPermit: permit) else {
                    manager.ruleCollections = ruleStateSnapshot.collections
                    manager.customRules = ruleStateSnapshot.customRules
                    manager.refreshLayerIndicatorState()
                    throw InstallError.saveFailed("rule \(index + 1) of \(rules.count) could not be prepared")
                }
            }
            let record = InstalledPackRecord(packID: pack.id, version: pack.version,
                                             installedAt: Date(), quickSettingValues: resolvedSettings)
            try await commitPreparedPackRules(manager: manager, snapshot: ruleStateSnapshot,
                                              record: .init(tracker: installedPackTracker, record: record),
                                              skipReload: skipFinalReload, permit: permit)

            AppLogger.shared.log(
                "✅ [PackInstaller] Installed pack '\(pack.name)': \(rules.count) binding(s)"
            )
            return record
        }
    }

    /// Uninstall a pack. Removes every `CustomRule` tagged with this pack's
    /// id, regenerates the config, and drops the install record.
    func uninstall(
        packID: String,
        manager: RuleCollectionsManager,
        installedPackTracker: InstalledPackTracker = .shared,
        mutationPermit: ConfigurationOperationGate.Permit? = nil
    ) async throws {
        try await manager.configurationService.operationGate.withOperation(using: mutationPermit) { @MainActor [self] permit in
            try await recoverAndValidateState(manager: manager, tracker: installedPackTracker, permit: permit)
            AppLogger.shared.log("📦 [PackInstaller] Uninstalling pack '\(packID)'")

            // Visual-only packs just clear the tracker record; no kanata
            // changes to revert.
            if let pack = PackRegistry.pack(id: packID), pack.visualOnly {
                try await setVisualPackEnabled(pack, enabled: false, manager: manager,
                                               installedPackTracker: installedPackTracker, mutationPermit: permit)
                return
            }

            // System packs batch all collection changes into a single config regen.
            if let pack = PackRegistry.pack(id: packID), pack.isSystemPack {
                let originalCollections = manager.ruleCollections
                let didRestore = await restoreOrKeepOnUninstall(pack: pack, manager: manager)
                if let collectionID = pack.associatedCollectionID,
                   let i = manager.ruleCollections.firstIndex(where: { $0.id == collectionID })
                {
                    manager.ruleCollections[i].isEnabled = false
                }

                var applied = await manager.regenerateConfigFromCollections(mutationPermit: permit)
                if !applied, didRestore, disableRestoreConflictCollections(for: pack, manager: manager) {
                    AppLogger.shared.log(
                        "⚠️ [PackInstaller] Retrying managed restore for '\(packID)' after disabling install-conflict collections"
                    )
                    applied = await manager.regenerateConfigFromCollections(mutationPermit: permit)
                }

                guard applied else {
                    manager.ruleCollections = originalCollections
                    throw InstallError.saveFailed("could not apply managed collection restore")
                }
                removeManagedSnapshot(for: pack)
                try await installedPackTracker.remove(packID: packID)
                AppLogger.shared.log(
                    "✅ [PackInstaller] Uninstalled system pack '\(packID)' (restored=\(didRestore))"
                )
                return
            }

            // Collection-backed packs uninstall by disabling the associated
            // built-in collection; they don't have their own CustomRules to
            // remove.
            if let pack = PackRegistry.pack(id: packID),
               let collectionID = pack.associatedCollectionID
            {
                let ok = await manager.toggleCollection(id: collectionID, isEnabled: false, bypassOwnershipCheck: true, mutationPermit: permit)
                guard ok else {
                    throw InstallError.saveFailed("could not disable associated rule collection")
                }
                try await installedPackTracker.remove(packID: packID)
                AppLogger.shared.log(
                    "✅ [PackInstaller] Uninstalled pack '\(packID)' via collection toggle off (id=\(collectionID))"
                )
                return
            }

            let snapshot = manager.snapshotRuleState()
            let packRules = snapshot.customRules.filter { $0.packSource == packID }
            guard !packRules.isEmpty else {
                try await installedPackTracker.remove(packID: packID)
                return
            }
            manager.customRules.removeAll { $0.packSource == packID }
            try await commitPreparedPackRules(manager: manager, snapshot: snapshot,
                                              record: .init(tracker: installedPackTracker, removing: packID),
                                              permit: permit)

            AppLogger.shared.log(
                "✅ [PackInstaller] Uninstalled pack '\(packID)': removed \(packRules.count) rule(s)"
            )
        }
    }

    /// Update the tap/hold outputs on an installed pack binding. Used by
    /// Pack Detail's embedded picker so changing the Tap or Hold preset
    /// immediately rewrites the underlying `CustomRule` and triggers a
    /// Kanata config reload.
    ///
    /// If `tap` / `hold` is nil that side is left unchanged. If the rule is
    /// currently a simple remap (no dual-role behavior) but a `hold` value
    /// is supplied, it gets upgraded to a dual-role binding.
    ///
    /// Returns true if a rule was found, updated, and saved.
    @discardableResult
    func updateTapHold(
        packID: String,
        input: String,
        tap: String? = nil,
        hold: String? = nil,
        manager: RuleCollectionsManager
    ) async -> Bool {
        await manager.withRuleMutation(failure: false) { @MainActor permit in
            guard let recovered = await manager.recoverAndSnapshotRuleState(mutationPermit: permit) else { return false }
            let snapshot = recovered.customRules
            let normalizedInput = input.lowercased()
            guard var rule = snapshot.first(where: {
                $0.packSource == packID && $0.input.lowercased() == normalizedInput
            }) else {
                AppLogger.shared.log(
                    "⚠️ [PackInstaller] updateTapHold: no rule found for pack '\(packID)' input '\(input)'"
                )
                return false
            }

            let existingDual: DualRoleBehavior? = {
                if case let .dualRole(dr) = rule.behavior { return dr }
                return nil
            }()

            let newTap = tap ?? existingDual?.tapActionString ?? rule.action.outputString
            let newHold = hold ?? existingDual?.holdActionString

            if let newHold, !newHold.isEmpty {
                rule.action = .keystroke(key: newTap)
                rule.behavior = .dualRole(
                    DualRoleBehavior(
                        tapAction: KanataBehaviorRenderer.parseActionString(newTap),
                        holdAction: KanataBehaviorRenderer.parseActionString(newHold),
                        tapTimeout: existingDual?.tapTimeout ?? 200,
                        holdTimeout: existingDual?.holdTimeout ?? 200,
                        activateHoldOnOtherKey: existingDual?.activateHoldOnOtherKey ?? true,
                        quickTap: existingDual?.quickTap ?? false,
                        customTapKeys: existingDual?.customTapKeys ?? [],
                        useOppositeHand: existingDual?.useOppositeHand ?? false,
                        useOppositeHandRelease: existingDual?.useOppositeHandRelease ?? false,
                        useReleaseOrder: existingDual?.useReleaseOrder ?? false,
                        requirePriorIdleOverrideMs: existingDual?.requirePriorIdleOverrideMs
                    )
                )
            } else {
                // Simple remap (no hold).
                rule.action = .keystroke(key: newTap)
                rule.behavior = nil
            }

            let ok = await manager.saveCustomRule(rule, skipReload: false, mutationPermit: permit)
            if ok {
                AppLogger.shared.log(
                    "✅ [PackInstaller] updateTapHold: pack '\(packID)' input '\(input)' tap='\(newTap)' hold='\(newHold ?? "—")'"
                )
            } else {
                AppLogger.shared.log(
                    "❌ [PackInstaller] updateTapHold: save failed for pack '\(packID)' input '\(input)'"
                )
            }
            return ok
        }
    }

    /// Is this pack currently installed?
    public func isInstalled(packID: String) async -> Bool {
        await InstalledPackTracker.shared.isInstalled(packID: packID)
    }

    /// Current quick-setting values for an installed pack.
    public func quickSettings(for packID: String) async -> [String: Int] {
        let rec = await InstalledPackTracker.shared.record(for: packID)
        return rec?.quickSettingValues ?? [:]
    }

    /// Update quick settings on an already-installed pack. Re-applies the
    /// settings to the underlying config/rules and persists the new values.
    ///
    /// For **rule-based packs**: removes old CustomRules and re-renders with new settings.
    /// For **collection-backed packs**: updates the collection's timing config directly.
    func updateQuickSettings(
        packID: String,
        newValues: [String: Int],
        manager: RuleCollectionsManager,
        installedPackTracker: InstalledPackTracker = .shared,
        mutationPermit: ConfigurationOperationGate.Permit? = nil
    ) async throws {
        try await manager.configurationService.operationGate.withOperation(using: mutationPermit) { @MainActor [self] permit in
            try await recoverAndValidateState(manager: manager, tracker: installedPackTracker, permit: permit)
            guard let pack = PackRegistry.pack(id: packID) else {
                throw InstallError.saveFailed("pack not found in registry: \(packID)")
            }
            guard var record = await installedPackTracker.record(for: packID) else {
                throw InstallError.saveFailed("pack is not installed: \(packID)")
            }

            // Merge new values into existing settings
            var mergedSettings = record.quickSettingValues
            for (key, value) in newValues {
                mergedSettings[key] = value
            }

            // Clamp to valid ranges
            let resolved = resolveQuickSettings(pack: pack, overrides: mergedSettings)

            let snapshot = manager.snapshotRuleState()
            var hasRuleChanges = false
            if let collectionID = pack.associatedCollectionID {
                if let holdTimeout = resolved["holdTimeout"] {
                    guard let index = manager.ruleCollections.firstIndex(where: { $0.id == collectionID }),
                          case var .homeRowMods(config) = manager.ruleCollections[index].configuration
                    else {
                        throw InstallError.saveFailed("The pack's timing collection is missing or cannot be edited. Your settings were not changed.")
                    }
                    config.timing.tapWindow = holdTimeout
                    config.timing.holdDelay = holdTimeout
                    manager.ruleCollections[index].configuration = .homeRowMods(config)
                    hasRuleChanges = true
                }
            } else if !pack.bindings.isEmpty {
                manager.customRules.removeAll { $0.packSource == packID }
                for rule in renderBindings(for: pack, quickSettings: resolved) {
                    guard await manager.updateCustomRuleInMemory(rule, mutationPermit: permit) else {
                        restorePreparedRuleState(snapshot, manager: manager)
                        throw InstallError.saveFailed("updated pack rules could not be prepared")
                    }
                }
                hasRuleChanges = true
            }

            record.quickSettingValues = resolved
            if hasRuleChanges {
                try await commitPreparedPackRules(manager: manager, snapshot: snapshot,
                                                  record: .init(tracker: installedPackTracker, record: record),
                                                  permit: permit)
            } else {
                try await installedPackTracker.upsert(record)
            }

            AppLogger.shared.log(
                "✅ [PackInstaller] Updated quick settings for '\(pack.name)': \(resolved)"
            )
        }
    }

    /// One application/recovery boundary for prepared pack rule mutations.
    private func commitPreparedPackRules(
        manager: RuleCollectionsManager, snapshot: RuleCollectionsManager.RuleStateSnapshot,
        record: InstalledPackTracker.RecordChange, skipReload: Bool = false,
        permit: ConfigurationOperationGate.Permit
    ) async throws {
        let result = await SaveCoordinator(configurationService: manager.configurationService).saveRuleState(
            manager: manager, mutationPermit: permit, packRecord: record,
            reloadHandler: skipReload ? nil : manager.onRulesChanged
        )
        guard result.success else {
            restorePreparedRuleState(snapshot, manager: manager)
            if result.error is CancellationError { throw CancellationError() }
            throw InstallError.saveFailed(result.error?.localizedDescription ?? "Pack change could not be committed")
        }
        NotificationCenter.default.post(name: .ruleCollectionsChanged, object: nil)
    }

    private func restorePreparedRuleState(_ snapshot: RuleCollectionsManager.RuleStateSnapshot,
                                          manager: RuleCollectionsManager)
    {
        manager.ruleCollections = snapshot.collections
        manager.customRules = snapshot.customRules
        manager.refreshLayerIndicatorState()
    }

    // MARK: - Rendering

    /// Convert a pack's binding templates into concrete CustomRules tagged
    /// with the pack's id.
    func renderBindings(
        for pack: Pack,
        quickSettings: [String: Int]
    ) -> [CustomRule] {
        // Hold timeout from quick settings, falling back to home-row-mod
        // friendly default. Only used by templates that have a hold output.
        let holdMs = quickSettings["holdTimeout"] ?? 200

        return pack.bindings.map { template in
            let title = template.title
                ?? "\(pack.name) · \(template.input.uppercased())"

            // If the template has a hold output, attach a dual-role behavior
            // (tap-hold with `activateHoldOnOtherKey`, matching the
            // Kanata tap-hold-press variant used by the Home-Row Mods
            // convenience factory). Otherwise this is a simple remap.
            let behavior: MappingBehavior? = template.holdOutput.map { holdOutput in
                .dualRole(
                    DualRoleBehavior(
                        tapAction: KanataBehaviorRenderer.parseActionString(template.output),
                        holdAction: KanataBehaviorRenderer.parseActionString(holdOutput),
                        tapTimeout: holdMs,
                        holdTimeout: holdMs,
                        activateHoldOnOtherKey: true,
                        quickTap: false
                    )
                )
            }

            return CustomRule(
                id: UUID(),
                title: title,
                input: template.input,
                action: .keystroke(key: template.output),
                shiftedOutput: nil,
                isEnabled: true,
                notes: template.notes,
                createdAt: Date(),
                behavior: behavior,
                targetLayer: .base,
                deviceOverrides: nil,
                packSource: pack.id
            )
        }
    }

    // MARK: - Pre-install gates

    /// Pack-specific install gates. Right now only the KindaVim Mode
    /// Display pack has any: it conflicts with Vim Navigation (both want
    /// to own the h/j/k/l story) and requires kindaVim.app to be present.
    private func enforcePreInstallGates(
        for pack: Pack,
        manager: RuleCollectionsManager,
        installedPackTracker: InstalledPackTracker
    ) async throws {
        if pack.id == PackRegistry.kindaVim.id {
            // Mutex: refuse if any conflicting pack is installed.
            var conflicts: [(id: String, name: String)] = []
            if await installedPackTracker.isInstalled(packID: "com.keypath.pack.vim-navigation"),
               let conflict = PackRegistry.pack(id: "com.keypath.pack.vim-navigation")
            {
                conflicts.append((id: conflict.id, name: conflict.name))
            }
            // Also block on the legacy KindaVim rule collection (retired
            // in this release but preserved on disk for upgraders until the
            // migration runs). If it's still enabled, kindaVim.app would be
            // fighting our old h/j/k/l remaps — refuse and surface it as
            // a conflict the user can resolve from Rules.
            if manager.ruleCollections.contains(where: {
                $0.id == RuleCollectionIdentifier.kindaVim && $0.isEnabled
            }) {
                conflicts.append((id: RuleCollectionIdentifier.kindaVim.uuidString, name: "Legacy KindaVim rules"))
            }
            if !conflicts.isEmpty {
                throw InstallError.mutuallyExclusive(conflicts: conflicts)
            }

            // Dependency: kindaVim.app must be installed.
            if !FileManager.default.fileExists(atPath: "/Applications/kindaVim.app") {
                throw InstallError.dependencyMissing(
                    name: "KindaVim",
                    websiteURL: URL(string: "https://kindavim.app")!
                )
            }
        }

        if pack.id == "com.keypath.pack.vim-navigation",
           await installedPackTracker.isInstalled(packID: PackRegistry.kindaVim.id)
        {
            throw InstallError.mutuallyExclusive(conflicts: [(id: PackRegistry.kindaVim.id, name: PackRegistry.kindaVim.name)])
        }
    }

    // MARK: - Helpers

    private func restoreInstallRecord(
        _ previousRecord: InstalledPackRecord?,
        packID: String,
        installedPackTracker: InstalledPackTracker
    ) async -> Bool {
        do {
            if let previousRecord {
                try await installedPackTracker.upsert(previousRecord)
            } else {
                try await installedPackTracker.remove(packID: packID)
            }
            return true
        } catch {
            // A failed atomic write leaves the prior on-disk record intact.
            // The tracker reads committed disk state, so no speculative cache
            // can claim the compensating write succeeded.
            AppLogger.shared.errorUnlessQuietTest(
                "❌ [PackInstaller] Could not persist tracker rollback for '\(packID)': \(error)"
            )
            return false
        }
    }

    private func restoreManagedCollectionSnapshot(
        _ previousSnapshot: PackCollectionSnapshot?,
        packID: String
    ) -> Bool {
        do {
            if let previousSnapshot {
                try PackCollectionSnapshot.save(previousSnapshot)
            } else {
                let snapshotURL = PackCollectionSnapshot.snapshotURL(for: packID)
                if FileManager.default.fileExists(atPath: snapshotURL.path) {
                    try FileManager.default.removeItem(at: snapshotURL)
                }
            }
            // Preserve the Vallack rollback contract from the original managed
            // install path: a failed modern install supersedes and removes the
            // legacy migration file. Any modern snapshot that predated this
            // attempt has already been restored above.
            if packID == PackRegistry.vallackSystem.id {
                try PackCollectionSnapshot.removeLegacyVallackIfPresent()
            }
            return true
        } catch {
            AppLogger.shared.errorUnlessQuietTest(
                "❌ [PackInstaller] Could not restore managed-collection snapshot for '\(packID)': \(error)"
            )
            return false
        }
    }

    private func resolveQuickSettings(
        pack: Pack,
        overrides: [String: Int]
    ) -> [String: Int] {
        var resolved: [String: Int] = [:]
        for setting in pack.quickSettings {
            if let override = overrides[setting.id] {
                // Clamp to the pack-defined slider bounds so a malformed
                // override (negative, out-of-range, serialized garbage) can't
                // produce a kanata config with nonsense timing values.
                resolved[setting.id] = clamp(override, to: setting.kind)
            } else if let defaultVal = setting.defaultSliderValue {
                resolved[setting.id] = defaultVal
            }
        }
        return resolved
    }

    private func clamp(_ value: Int, to kind: PackQuickSetting.Kind) -> Int {
        switch kind {
        case let .slider(_, minValue, maxValue, _, _):
            min(max(value, minValue), maxValue)
        }
    }

    // MARK: - Generic Managed Collection Lifecycle

    private func snapshotManagedCollections(
        pack: Pack,
        manager: RuleCollectionsManager
    ) -> PackCollectionSnapshot {
        let encoder = JSONEncoder()
        var entries: [PackCollectionSnapshot.Entry] = []

        for managed in pack.managedDefaults {
            let collection = manager.ruleCollections.first { $0.id == managed.collectionID }
            let configJSON = (try? encoder.encode(collection?.configuration ?? .list)) ?? Data()
            entries.append(PackCollectionSnapshot.Entry(
                collectionID: managed.collectionID,
                wasEnabled: collection?.isEnabled ?? false,
                configurationJSON: configJSON
            ))
        }

        return PackCollectionSnapshot(packID: pack.id, entries: entries)
    }

    private func applyManagedDefaults(
        pack: Pack,
        manager: RuleCollectionsManager,
        policy: ManagedDefaultInstallPolicy,
        associatedCollectionConfiguration: RuleCollectionConfiguration?,
        skipReload: Bool,
        mutationPermit: ConfigurationOperationGate.Permit
    ) async throws {
        let snapshot = snapshotManagedCollections(pack: pack, manager: manager)
        let catalog = RuleCollectionCatalog().defaultCollections()

        // Ensure the pack's own associated collection exists too
        if let associated = pack.associatedCollectionID {
            ensureCollectionExists(id: associated, catalog: catalog, manager: manager)
            if let i = manager.ruleCollections.firstIndex(where: { $0.id == associated }) {
                if let associatedCollectionConfiguration {
                    manager.ruleCollections[i].configuration = associatedCollectionConfiguration
                }
                manager.ruleCollections[i].isEnabled = true
            }
        }

        for managed in pack.managedDefaults {
            ensureCollectionExists(id: managed.collectionID, catalog: catalog, manager: manager)

            guard let i = manager.ruleCollections.firstIndex(where: { $0.id == managed.collectionID }) else {
                continue
            }

            if let defaultConfig = managed.defaultConfiguration {
                let shouldApply = await shouldApplyManagedDefault(
                    managed: managed,
                    existingCollection: manager.ruleCollections[i],
                    packName: pack.name,
                    policy: policy
                )
                if shouldApply {
                    manager.ruleCollections[i].configuration = defaultConfig
                }
            }

            if managed.disableOnInstall {
                manager.ruleCollections[i].isEnabled = false
            } else if managed.enableOnInstall {
                manager.ruleCollections[i].isEnabled = true
            }
        }

        try PackCollectionSnapshot.save(snapshot)

        let applied = await manager.regenerateConfigFromCollections(skipReload: skipReload, mutationPermit: mutationPermit)
        guard applied else {
            throw InstallError.saveFailed("could not apply managed collection defaults")
        }
        AppLogger.shared.log("📦 [PackInstaller] Applied managed defaults for '\(pack.name)'")
    }

    private func shouldApplyManagedDefault(
        managed: ManagedCollectionDefault,
        existingCollection: RuleCollection,
        packName: String,
        policy: ManagedDefaultInstallPolicy
    ) async -> Bool {
        guard existingCollection.isEnabled,
              let defaultConfig = managed.defaultConfiguration,
              existingCollection.configuration != defaultConfig
        else {
            return true
        }

        // If the collection still has its catalog default config, the user
        // never customized it — apply the pack's config silently.
        let catalogDefault = RuleCollectionCatalog().defaultCollections()
            .first { $0.id == managed.collectionID }
        if let catalogDefault, existingCollection.configuration == catalogDefault.configuration {
            return true
        }

        if policy == .useRecommended {
            return true
        }

        if TestEnvironment.isRunningTests {
            #if DEBUG
                if let override = Self.testOverrideApplyDefault { return override }
            #endif
            return true
        }

        let diffs = RuleCollectionConfiguration.diffSettings(
            current: existingCollection.configuration,
            proposed: defaultConfig
        )

        return await withCheckedContinuation { continuation in
            let alert = NSAlert()
            alert.messageText = "\(packName) will configure \(managed.displayName)"
            alert.alertStyle = .informational
            alert.addButton(withTitle: "Use Recommended")
            alert.addButton(withTitle: "Keep My Settings")

            if !diffs.isEmpty {
                alert.informativeText = "Your current settings will be saved and can be restored when you uninstall \(packName)."
                alert.accessoryView = Self.buildComparisonView(
                    diffs: diffs,
                    currentLabel: "Current",
                    proposedLabel: "Recommended"
                )
            } else {
                alert.informativeText = "Your current \(managed.displayName) settings will be changed. Your current settings will be saved and can be restored when you uninstall \(packName)."
            }

            let response = alert.runModal()
            continuation.resume(returning: response == .alertFirstButtonReturn)
        }
    }

    @discardableResult
    private func restoreOrKeepOnUninstall(
        pack: Pack,
        manager: RuleCollectionsManager
    ) async -> Bool {
        var snapshot = PackCollectionSnapshot.load(for: pack.id)

        // Legacy migration for Vallack System
        if snapshot == nil, pack.id == "com.keypath.pack.vallack-system" {
            snapshot = PackCollectionSnapshot.loadLegacyVallack()
        }

        guard let snapshot else {
            AppLogger.shared.log("⚠️ [PackInstaller] No snapshot found for '\(pack.id)' — skipping restore")
            return false
        }

        let decoder = JSONDecoder()
        var userModified = false

        for entry in snapshot.entries {
            guard let i = manager.ruleCollections.firstIndex(where: { $0.id == entry.collectionID }) else {
                continue
            }

            let managed = pack.managedDefaults.first { $0.collectionID == entry.collectionID }
            if let appliedConfig = managed?.defaultConfiguration,
               manager.ruleCollections[i].configuration != appliedConfig
            {
                userModified = true
            }
        }

        // Build diffs for the restore dialog: current config vs previous (snapshot) config
        var allDiffs: [RuleCollectionConfiguration.SettingDiff] = []
        if userModified {
            for entry in snapshot.entries {
                guard let i = manager.ruleCollections.firstIndex(where: { $0.id == entry.collectionID }),
                      let previousConfig = try? decoder.decode(
                          RuleCollectionConfiguration.self, from: entry.configurationJSON
                      )
                else { continue }
                let diffs = RuleCollectionConfiguration.diffSettings(
                    current: manager.ruleCollections[i].configuration,
                    proposed: previousConfig
                )
                allDiffs.append(contentsOf: diffs)
            }
        }

        let shouldRestore: Bool
        if !userModified {
            shouldRestore = true
        } else if TestEnvironment.isRunningTests {
            #if DEBUG
                shouldRestore = Self.testOverrideRestore ?? true
            #else
                shouldRestore = true
            #endif
        } else {
            shouldRestore =
                await withCheckedContinuation { continuation in
                    let alert = NSAlert()
                    alert.messageText = "Restore Previous Settings?"
                    alert.alertStyle = .informational
                    alert.addButton(withTitle: "Restore Previous")
                    alert.addButton(withTitle: "Keep Current")

                    if !allDiffs.isEmpty {
                        alert.informativeText = "You modified settings after installing \(pack.name). Restore your previous configuration?"
                        alert.accessoryView = Self.buildComparisonView(
                            diffs: allDiffs,
                            currentLabel: "Current",
                            proposedLabel: "Previous"
                        )
                    } else {
                        alert.informativeText = "You modified settings after installing \(pack.name). Restore your previous configuration, or keep the current settings?"
                    }

                    let response = alert.runModal()
                    continuation.resume(returning: response == .alertFirstButtonReturn)
                }
        }

        if shouldRestore {
            for entry in snapshot.entries {
                guard let i = manager.ruleCollections.firstIndex(where: { $0.id == entry.collectionID }) else {
                    continue
                }
                if let restoredConfig = try? decoder.decode(
                    RuleCollectionConfiguration.self, from: entry.configurationJSON
                ) {
                    manager.ruleCollections[i].configuration = restoredConfig
                }
                manager.ruleCollections[i].isEnabled = entry.wasEnabled
            }
        }

        AppLogger.shared.log("📦 [PackInstaller] Uninstall restore for '\(pack.id)': restored=\(shouldRestore)")
        return shouldRestore
    }

    private func removeManagedSnapshot(for pack: Pack) {
        PackCollectionSnapshot.remove(for: pack.id)
        if pack.id == "com.keypath.pack.vallack-system" {
            PackCollectionSnapshot.removeLegacyVallack()
        }
    }

    private func disableRestoreConflictCollections(
        for pack: Pack,
        manager: RuleCollectionsManager
    ) -> Bool {
        var changed = false

        for managed in pack.managedDefaults where managed.disableOnInstall {
            guard let i = manager.ruleCollections.firstIndex(where: { $0.id == managed.collectionID }),
                  manager.ruleCollections[i].isEnabled
            else {
                continue
            }

            manager.ruleCollections[i].isEnabled = false
            changed = true
            AppLogger.shared.log(
                "⚠️ [PackInstaller] Leaving '\(managed.displayName)' disabled because restored settings conflicted during uninstall"
            )
        }

        return changed
    }

    private static func buildComparisonView(
        diffs: [RuleCollectionConfiguration.SettingDiff],
        currentLabel: String,
        proposedLabel: String
    ) -> NSView {
        let grid = NSGridView(numberOfColumns: 3, rows: 0)
        grid.translatesAutoresizingMaskIntoConstraints = false
        grid.columnSpacing = 12
        grid.rowSpacing = 4

        func headerCell(_ text: String) -> NSTextField {
            let field = NSTextField(labelWithString: text)
            field.font = .systemFont(ofSize: 11, weight: .semibold)
            field.textColor = .secondaryLabelColor
            return field
        }

        func cell(_ text: String, bold: Bool = false) -> NSTextField {
            let field = NSTextField(labelWithString: text)
            field.font = bold
                ? .systemFont(ofSize: 12, weight: .medium)
                : .systemFont(ofSize: 12)
            field.textColor = .labelColor
            field.lineBreakMode = .byTruncatingTail
            return field
        }

        grid.addRow(with: [
            headerCell(""),
            headerCell(currentLabel),
            headerCell(proposedLabel),
        ])

        for diff in diffs {
            grid.addRow(with: [
                cell(diff.label, bold: true),
                cell(diff.current),
                cell(diff.proposed),
            ])
        }

        grid.column(at: 0).width = 80
        grid.column(at: 1).width = 110
        grid.column(at: 2).width = 110

        let container = NSView(frame: NSRect(x: 0, y: 0, width: 320, height: CGFloat(diffs.count + 1) * 24 + 8))
        container.addSubview(grid)
        NSLayoutConstraint.activate([
            grid.leadingAnchor.constraint(equalTo: container.leadingAnchor),
            grid.trailingAnchor.constraint(equalTo: container.trailingAnchor),
            grid.topAnchor.constraint(equalTo: container.topAnchor, constant: 4),
            grid.bottomAnchor.constraint(equalTo: container.bottomAnchor, constant: -4),
        ])
        return container
    }

    private func ensureCollectionExists(id: UUID, catalog: [RuleCollection], manager: RuleCollectionsManager) {
        guard !manager.ruleCollections.contains(where: { $0.id == id }) else { return }
        if let catalogCollection = catalog.first(where: { $0.id == id }) {
            manager.ruleCollections.append(catalogCollection)
        }
    }
}

// MARK: - Bridge: expose the current CustomRules list as a read-only snapshot

extension RuleCollectionsManager {
    /// Read-only snapshot of the current custom rules. PackInstaller uses
    /// this to find rules by `packSource` tag without needing access to the
    /// full manager state.
    func snapshotCurrentRules() async -> [CustomRule] {
        customRules
    }
}
