// M1 Gallery MVP — install/uninstall packs by converting their binding
// templates into CustomRule entries on RuleCollectionsManager, tagged with
// the pack id so uninstall can find and remove them.
//
// PackInstaller is the only place pack state changes; the Gallery/Pack Detail
// UI calls these methods and does not mutate CustomRules or config directly.

import AppKit
import Foundation
import KeyPathCore

@MainActor
public final class PackInstaller {
    public static let shared = PackInstaller()

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

    /// Install a pack. Expands its binding templates into `CustomRule`s
    /// tagged with the pack's id, adds them to the user's rules, and
    /// regenerates the kanata config (which hot-reloads kanata).
    ///
    /// - Parameter pack: the pack to install.
    /// - Parameter quickSettingValues: user-chosen values for the pack's
    ///   quick settings. Missing keys fall back to the pack's defaults.
    /// - Parameter manager: the app's RuleCollectionsManager. Required.
    /// - Returns: the install record persisted for this pack.
    @discardableResult
    func install(
        _ pack: Pack,
        quickSettingValues: [String: Int] = [:],
        manager: RuleCollectionsManager,
        skipFinalReload: Bool = false
    ) async throws -> InstalledPackRecord {
        AppLogger.shared.log(
            "📦 [PackInstaller] Installing pack '\(pack.name)' (id=\(pack.id), v\(pack.version))"
        )

        try await enforcePreInstallGates(for: pack, manager: manager)

        // Resolve effective quick-setting values (user-provided ∪ defaults).
        let resolvedSettings = resolveQuickSettings(pack: pack, overrides: quickSettingValues)

        // Visual-only packs (e.g. KindaVim Mode Display) don't touch the
        // kanata config at all — install just persists the tracker record
        // so other parts of the app (overlay, mode monitor) can react to
        // "this pack is active". No collection toggle, no reload.
        if pack.visualOnly {
            let record = InstalledPackRecord(
                packID: pack.id,
                version: pack.version,
                installedAt: Date(),
                quickSettingValues: resolvedSettings
            )
            try await InstalledPackTracker.shared.upsert(record)
            AppLogger.shared.log(
                "✅ [PackInstaller] Installed visual-only pack '\(pack.name)' (no kanata side effects)"
            )
            return record
        }

        // System packs batch all collection changes into a single config regen.
        if pack.isSystemPack {
            // Record the install BEFORE applying configs so that when
            // regenerateConfigFromCollections posts .ruleCollectionsChanged,
            // any listener querying packManagingCollection already finds
            // the ownership record.
            let record = InstalledPackRecord(
                packID: pack.id,
                version: pack.version,
                installedAt: Date(),
                quickSettingValues: resolvedSettings
            )
            try await InstalledPackTracker.shared.upsert(record)
            do {
                try await applyManagedDefaults(pack: pack, manager: manager)
            } catch {
                try? await InstalledPackTracker.shared.remove(packID: pack.id)
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
            let ok = await manager.toggleCollection(id: collectionID, isEnabled: true, autoResolveConflicts: true, bypassOwnershipCheck: true)
            if !ok {
                throw InstallError.saveFailed("could not enable associated rule collection")
            }

            let record = InstalledPackRecord(
                packID: pack.id,
                version: pack.version,
                installedAt: Date(),
                quickSettingValues: resolvedSettings
            )
            try await InstalledPackTracker.shared.upsert(record)
            AppLogger.shared.log(
                "✅ [PackInstaller] Installed pack '\(pack.name)' via collection toggle (id=\(collectionID))"
            )
            return record
        }

        // Build CustomRule entries from templates.
        let rules = renderBindings(for: pack, quickSettings: resolvedSettings)

        // Append rules in one batch: use skipReload=true for all but the
        // last, so we only regenerate the config file once at the end.
        // Callers that chain an immediate edit after install can pass
        // `skipFinalReload: true` to suppress even the last reload, so a
        // followup `updateTapHold` fires exactly one reload for the
        // combined result (and doesn't trip the TCP reload cooldown).
        for (index, rule) in rules.enumerated() {
            let isLast = (index == rules.count - 1)
            let suppressReload = !isLast || skipFinalReload
            let ok = await manager.saveCustomRule(rule, skipReload: suppressReload)
            if !ok {
                AppLogger.shared.log(
                    "❌ [PackInstaller] Failed to save rule \(index + 1)/\(rules.count) for pack '\(pack.id)'"
                )
                // Roll back: remove whatever got added so far.
                await rollbackPartialInstall(packID: pack.id, manager: manager)
                throw InstallError.saveFailed("rule \(index + 1) of \(rules.count) could not be saved")
            }
        }

        // Record the install.
        let record = InstalledPackRecord(
            packID: pack.id,
            version: pack.version,
            installedAt: Date(),
            quickSettingValues: resolvedSettings
        )
        try await InstalledPackTracker.shared.upsert(record)

        AppLogger.shared.log(
            "✅ [PackInstaller] Installed pack '\(pack.name)': \(rules.count) binding(s)"
        )
        return record
    }

    /// Uninstall a pack. Removes every `CustomRule` tagged with this pack's
    /// id, regenerates the config, and drops the install record.
    func uninstall(
        packID: String,
        manager: RuleCollectionsManager
    ) async throws {
        AppLogger.shared.log("📦 [PackInstaller] Uninstalling pack '\(packID)'")

        // Visual-only packs just clear the tracker record; no kanata
        // changes to revert.
        if let pack = PackRegistry.pack(id: packID), pack.visualOnly {
            try await InstalledPackTracker.shared.remove(packID: packID)
            AppLogger.shared.log(
                "✅ [PackInstaller] Uninstalled visual-only pack '\(packID)'"
            )
            return
        }

        // System packs batch all collection changes into a single config regen.
        if let pack = PackRegistry.pack(id: packID), pack.isSystemPack {
            let didRestore = await restoreOrKeepOnUninstall(pack: pack, manager: manager)
            if let collectionID = pack.associatedCollectionID,
               let i = manager.ruleCollections.firstIndex(where: { $0.id == collectionID })
            {
                manager.ruleCollections[i].isEnabled = false
            }
            await manager.regenerateConfigFromCollections()
            try await InstalledPackTracker.shared.remove(packID: packID)
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
            let ok = await manager.toggleCollection(id: collectionID, isEnabled: false, bypassOwnershipCheck: true)
            guard ok else {
                throw InstallError.saveFailed("could not disable associated rule collection")
            }
            try await InstalledPackTracker.shared.remove(packID: packID)
            AppLogger.shared.log(
                "✅ [PackInstaller] Uninstalled pack '\(packID)' via collection toggle off (id=\(collectionID))"
            )
            return
        }

        // Snapshot current rule set, drop those owned by this pack.
        let before = await manager.snapshotCurrentRules()
        let packRules = before.filter { $0.packSource == packID }

        guard !packRules.isEmpty else {
            // Nothing to remove from rules, but still clear the tracker
            // record in case it drifted out of sync.
            try await InstalledPackTracker.shared.remove(packID: packID)
            AppLogger.shared.log(
                "ℹ️ [PackInstaller] No rules tagged with pack '\(packID)'; cleared tracker record"
            )
            return
        }

        for (index, rule) in packRules.enumerated() {
            let isLast = (index == packRules.count - 1)
            // We remove directly — skipReload avoided here since
            // removeCustomRule regenerates on each call. For M1 we accept
            // N regenerations; M2 will batch.
            _ = isLast // reserved for future batching
            await manager.removeCustomRule(id: rule.id)
        }

        try await InstalledPackTracker.shared.remove(packID: packID)

        AppLogger.shared.log(
            "✅ [PackInstaller] Uninstalled pack '\(packID)': removed \(packRules.count) rule(s)"
        )
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
        let snapshot = await manager.snapshotCurrentRules()
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

        let ok = await manager.saveCustomRule(rule, skipReload: false)
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
        manager: RuleCollectionsManager
    ) async throws {
        guard let pack = PackRegistry.pack(id: packID) else {
            throw InstallError.saveFailed("pack not found in registry: \(packID)")
        }
        guard var record = await InstalledPackTracker.shared.record(for: packID) else {
            throw InstallError.saveFailed("pack is not installed: \(packID)")
        }

        // Merge new values into existing settings
        var mergedSettings = record.quickSettingValues
        for (key, value) in newValues {
            mergedSettings[key] = value
        }

        // Clamp to valid ranges
        let resolved = resolveQuickSettings(pack: pack, overrides: mergedSettings)

        if let collectionID = pack.associatedCollectionID {
            // Collection-backed pack: update timing config
            if let holdTimeout = resolved["holdTimeout"],
               let index = manager.ruleCollections.firstIndex(where: { $0.id == collectionID })
            {
                if case var .homeRowMods(config) = manager.ruleCollections[index].configuration {
                    config.timing.tapWindow = holdTimeout
                    config.timing.holdDelay = holdTimeout
                    manager.ruleCollections[index].configuration = .homeRowMods(config)
                    await manager.regenerateConfigFromCollections()
                }
            }
        } else if !pack.bindings.isEmpty {
            // Rule-based pack: re-render bindings with new settings
            let oldRules = await manager.snapshotCurrentRules().filter { $0.packSource == packID }
            for rule in oldRules {
                await manager.removeCustomRule(id: rule.id)
            }
            let newRules = renderBindings(for: pack, quickSettings: resolved)
            for (index, rule) in newRules.enumerated() {
                let isLast = (index == newRules.count - 1)
                _ = await manager.saveCustomRule(rule, skipReload: !isLast)
            }
        }

        // Persist updated record
        record.quickSettingValues = resolved
        try await InstalledPackTracker.shared.upsert(record)

        AppLogger.shared.log(
            "✅ [PackInstaller] Updated quick settings for '\(pack.name)': \(resolved)"
        )
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
        manager: RuleCollectionsManager
    ) async throws {
        if pack.id == PackRegistry.kindaVim.id {
            // Mutex: refuse if any conflicting pack is installed.
            var conflicts: [(id: String, name: String)] = []
            if await InstalledPackTracker.shared.isInstalled(packID: "com.keypath.pack.vim-navigation"),
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
           await InstalledPackTracker.shared.isInstalled(packID: PackRegistry.kindaVim.id)
        {
            throw InstallError.mutuallyExclusive(conflicts: [(id: PackRegistry.kindaVim.id, name: PackRegistry.kindaVim.name)])
        }
    }

    // MARK: - Helpers

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
        manager: RuleCollectionsManager
    ) async throws {
        let snapshot = snapshotManagedCollections(pack: pack, manager: manager)

        let catalog = RuleCollectionCatalog().defaultCollections()

        // Ensure the pack's own associated collection exists too
        if let associated = pack.associatedCollectionID {
            ensureCollectionExists(id: associated, catalog: catalog, manager: manager)
            if let i = manager.ruleCollections.firstIndex(where: { $0.id == associated }) {
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
                    packName: pack.name
                )
                if shouldApply {
                    manager.ruleCollections[i].configuration = defaultConfig
                }
            }

            if managed.enableOnInstall {
                manager.ruleCollections[i].isEnabled = true
            }
        }

        try PackCollectionSnapshot.save(snapshot)

        await manager.regenerateConfigFromCollections()
        AppLogger.shared.log("📦 [PackInstaller] Applied managed defaults for '\(pack.name)'")
    }

    private func shouldApplyManagedDefault(
        managed: ManagedCollectionDefault,
        existingCollection: RuleCollection,
        packName: String
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

        if TestEnvironment.isRunningTests {
            #if DEBUG
                if let override = Self.testOverrideApplyDefault { return override }
            #endif
            return true
        }

        return await withCheckedContinuation { continuation in
            let alert = NSAlert()
            alert.messageText = "\(packName) will configure \(managed.displayName)"
            alert.informativeText = "Your current \(managed.displayName) settings will be changed. Your current settings will be saved and can be restored when you uninstall \(packName)."
            alert.alertStyle = .informational
            alert.addButton(withTitle: "Use Recommended")
            alert.addButton(withTitle: "Keep My Settings")
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
                    alert.informativeText = "You modified settings after installing \(pack.name). Restore your previous configuration, or keep the current settings?"
                    alert.alertStyle = .informational
                    alert.addButton(withTitle: "Restore Previous")
                    alert.addButton(withTitle: "Keep Current")
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

        PackCollectionSnapshot.remove(for: pack.id)
        if pack.id == "com.keypath.pack.vallack-system" {
            PackCollectionSnapshot.removeLegacyVallack()
        }

        AppLogger.shared.log("📦 [PackInstaller] Uninstall restore for '\(pack.id)': restored=\(shouldRestore)")
        return shouldRestore
    }

    private func ensureCollectionExists(id: UUID, catalog: [RuleCollection], manager: RuleCollectionsManager) {
        guard !manager.ruleCollections.contains(where: { $0.id == id }) else { return }
        if let catalogCollection = catalog.first(where: { $0.id == id }) {
            manager.ruleCollections.append(catalogCollection)
        }
    }

    /// Remove any rules already committed for this pack id. Best-effort —
    /// used when an install fails partway through.
    private func rollbackPartialInstall(
        packID: String,
        manager: RuleCollectionsManager
    ) async {
        let current = await manager.snapshotCurrentRules()
        let partial = current.filter { $0.packSource == packID }
        AppLogger.shared.log(
            "↩️ [PackInstaller] Rolling back \(partial.count) rule(s) after failed install of '\(packID)'"
        )
        for rule in partial {
            await manager.removeCustomRule(id: rule.id)
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
