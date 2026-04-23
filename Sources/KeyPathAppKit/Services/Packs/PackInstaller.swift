// M1 Gallery MVP — install/uninstall packs by converting their binding
// templates into CustomRule entries on RuleCollectionsManager, tagged with
// the pack id so uninstall can find and remove them.
//
// PackInstaller is the only place pack state changes; the Gallery/Pack Detail
// UI calls these methods and does not mutate CustomRules or config directly.

import Foundation
import KeyPathCore

@MainActor
public final class PackInstaller {
    public static let shared = PackInstaller()

    private init() {}

    // MARK: - Errors

    public enum InstallError: LocalizedError {
        case noRuleCollectionsManager
        case saveFailed(String)

        public var errorDescription: String? {
            switch self {
            case .noRuleCollectionsManager:
                "RuleCollectionsManager is not available. The app may not be fully initialised."
            case let .saveFailed(reason):
                "Could not save pack rules: \(reason)"
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

        // Resolve effective quick-setting values (user-provided ∪ defaults).
        let resolvedSettings = resolveQuickSettings(pack: pack, overrides: quickSettingValues)

        // Collection-backed packs (e.g. Home Row Mods) don't generate custom
        // rules — they just toggle the built-in RuleCollection on.
        if let collectionID = pack.associatedCollectionID {
            let ok = await manager.toggleCollection(id: collectionID, isEnabled: true)
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

        // Collection-backed packs uninstall by disabling the associated
        // built-in collection; they don't have their own CustomRules to
        // remove.
        if let pack = PackRegistry.pack(id: packID),
           let collectionID = pack.associatedCollectionID
        {
            _ = await manager.toggleCollection(id: collectionID, isEnabled: false)
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

        let newTap = tap ?? existingDual?.tapAction ?? rule.output
        let newHold = hold ?? existingDual?.holdAction

        if let newHold, !newHold.isEmpty {
            rule.output = newTap
            rule.behavior = .dualRole(
                DualRoleBehavior(
                    tapAction: newTap,
                    holdAction: newHold,
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
            rule.output = newTap
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
                        tapAction: template.output,
                        holdAction: holdOutput,
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
                output: template.output,
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

    // MARK: - Helpers

    private func resolveQuickSettings(
        pack: Pack,
        overrides: [String: Int]
    ) -> [String: Int] {
        var resolved: [String: Int] = [:]
        for setting in pack.quickSettings {
            if let override = overrides[setting.id] {
                resolved[setting.id] = override
            } else if let defaultVal = setting.defaultSliderValue {
                resolved[setting.id] = defaultVal
            }
        }
        return resolved
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
