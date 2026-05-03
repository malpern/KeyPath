import SwiftUI

// MARK: - Install / uninstall / apply actions

extension PackDetailView {
    func handleToggle(to newValue: Bool) {
        guard newValue != isInstalled else { return }
        // Cancel any in-flight install/uninstall so two quick taps (install →
        // uninstall → install) don't interleave writes into the rules table.
        // `.disabled(isWorking)` guards the tap-through case, but SwiftUI
        // Toggles can re-fire before the disabled state propagates on a
        // rapid double-flick.
        toggleTask?.cancel()
        toggleTask = Task { newValue ? await install() : await uninstall() }
    }

    func install(skipFinalReload: Bool = false) async {
        isWorking = true
        errorMessage = nil
        do {
            let manager = kanataManager.underlyingManager.ruleCollectionsManager
            _ = try await PackInstaller.shared.install(
                pack,
                quickSettingValues: quickSettingValues,
                manager: manager,
                skipFinalReload: skipFinalReload
            )
            lastUndoSnapshot = .init(quickSettingValues: quickSettingValues)
            await refreshInstallState()
            withAnimation(.spring(response: 0.4, dampingFraction: 0.85)) {
                justInstalled = true
            }
            Task {
                try? await Task.sleep(nanoseconds: 4_000_000_000)
                await MainActor.run {
                    withAnimation(.easeOut(duration: 0.3)) { justInstalled = false }
                }
            }
        } catch let error as PackInstaller.InstallError {
            if case let .mutuallyExclusive(conflicts) = error {
                packConflict = PackConflictState(
                    packToInstall: pack,
                    conflictingPacks: conflicts
                )
            } else {
                showTemporaryError(error.localizedDescription)
            }
        } catch {
            showTemporaryError(error.localizedDescription)
        }
        isWorking = false
    }

    func uninstall() async {
        isWorking = true
        errorMessage = nil
        do {
            let manager = kanataManager.underlyingManager.ruleCollectionsManager
            try await PackInstaller.shared.uninstall(packID: pack.id, manager: manager)
            await refreshInstallState()
            withAnimation(.spring(response: 0.4, dampingFraction: 0.85)) {
                justUninstalled = true
            }
            Task {
                try? await Task.sleep(nanoseconds: 4_000_000_000)
                await MainActor.run {
                    withAnimation(.easeOut(duration: 0.3)) { justUninstalled = false }
                }
            }
        } catch {
            withAnimation { errorMessage = error.localizedDescription }
        }
        isWorking = false
    }

    func undoInstall() async {
        withAnimation(.easeOut(duration: 0.2)) { justInstalled = false }
        await uninstall()
    }

    func undoUninstall() async {
        withAnimation(.easeOut(duration: 0.2)) { justUninstalled = false }
        // Re-install with the saved settings from just before uninstall.
        if let snap = lastUndoSnapshot {
            quickSettingValues = snap.quickSettingValues
        }
        await install()
    }

    func resolveConflictAndInstall(_ conflict: PackConflictState) async {
        let manager = kanataManager.underlyingManager.ruleCollectionsManager
        do {
            for conflicting in conflict.conflictingPacks {
                try await PackInstaller.shared.uninstall(packID: conflicting.id, manager: manager)
            }
            await install()
        } catch {
            showTemporaryError(error.localizedDescription)
        }
    }

    /// Apply a picker-driven edit to the installed rule / collection. If
    /// the pack isn't installed yet, install it first (which for
    /// collection-backed packs toggles the collection, for rule-based
    /// packs creates tagged CustomRules). Install's reload is suppressed
    /// so the follow-up tap/hold update fires exactly one reload.
    func applyPickerEdit(tap: String?, hold: String?) async {
        if !isInstalled {
            await install(skipFinalReload: true)
        }
        if let collectionID = pack.associatedCollectionID {
            // Collection-backed: edits go through the same API Rules uses,
            // modifying the collection's TapHoldPickerConfig selections.
            if let tap {
                await kanataManager.updateCollectionTapOutput(collectionID, tapOutput: tap)
            }
            if let hold {
                await kanataManager.updateCollectionHoldOutput(collectionID, holdOutput: hold)
            }
        } else {
            // Rule-based: the pack owns its own CustomRule tagged with
            // packSource; rewrite that rule's dual-role behavior.
            guard let input = pack.bindings.first?.input else { return }
            let manager = kanataManager.underlyingManager.ruleCollectionsManager
            let ok = await PackInstaller.shared.updateTapHold(
                packID: pack.id,
                input: input,
                tap: tap,
                hold: hold,
                manager: manager
            )
            if !ok {
                await MainActor.run {
                    withAnimation {
                        errorMessage = "Couldn't save the change. Another rule may be conflicting on \(input.uppercased())."
                    }
                }
                Task {
                    try? await Task.sleep(nanoseconds: 4_000_000_000)
                    await MainActor.run {
                        withAnimation(.easeOut(duration: 0.3)) { errorMessage = nil }
                    }
                }
            }
        }
    }

    /// Apply a single-key-picker edit. Collection-backed only — the
    /// collection's `selectedOutput` is persisted via the same VM API the
    /// Rules tab uses.
    func applySingleKeyEdit(output: String) async {
        singleKeySelection = output
        guard let collectionID = pack.associatedCollectionID else { return }
        if !isInstalled {
            await install(skipFinalReload: true)
        }
        await kanataManager.updateCollectionOutput(collectionID, output: output)
    }

    /// Apply a Home Row Mods edit — analogous to the tap-hold `updateTapHold`
    /// path: if the pack isn't installed yet, install it first (which
    /// toggles the collection on), then persist the new config. Install's
    /// reload is suppressed so the config save is the only reload.
    func applyHomeRowEdit(_ newConfig: HomeRowModsConfig, collectionID: UUID) async {
        homeRowModsConfig = newConfig
        if !isInstalled {
            await install(skipFinalReload: true)
        }
        // VM method returns Void (it's the manager layer underneath that
        // returns Bool-for-newly-enabled). Mirrors Rules' call site. If we
        // want surfaced error toasts here later, call the manager directly.
        await kanataManager.updateHomeRowModsConfig(
            collectionId: collectionID,
            config: newConfig
        )
    }

    /// Mirror of `applyHomeRowEdit` for Auto Shift Symbols.
    func applyAutoShiftEdit(_ newConfig: AutoShiftSymbolsConfig, collectionID: UUID) async {
        autoShiftConfig = newConfig
        if !isInstalled {
            await install(skipFinalReload: true)
        }
        await kanataManager.updateAutoShiftSymbolsConfig(
            collectionId: collectionID,
            config: newConfig
        )
    }

    /// Mirror of `applyHomeRowEdit` for Window Snapping's convention picker
    /// (Standard L/R/U/I/J/K vs Vim H/L/Y/U/B/N).
    func applyWindowConventionEdit(_ convention: WindowKeyConvention, collectionID: UUID) async {
        if !isInstalled {
            await install(skipFinalReload: true)
        }
        await kanataManager.updateWindowKeyConvention(collectionID, convention: convention)
    }

    /// Mirror of `applyHomeRowEdit` for layer-preset packs (Symbol, Fun).
    /// Installs the pack on first touch, then switches the collection's
    /// selected preset so the generated kanata config rebinds the layer.
    func applyLayerPresetEdit(presetId: String, collectionID: UUID) async {
        selectedLayerPresetId = presetId
        if !isInstalled {
            await install(skipFinalReload: true)
        }
        await kanataManager.updateCollectionLayerPreset(collectionID, presetId: presetId)
    }

    /// Mirror of `applyHomeRowEdit` for the Quick Launcher pack. Persists
    /// activation-mode + key mappings via the same VM hook Rules uses.
    func applyLauncherEdit(_ newConfig: LauncherGridConfig, collectionID: UUID) async {
        launcherConfig = newConfig
        if !isInstalled {
            await install(skipFinalReload: true)
        }
        await kanataManager.updateLauncherConfig(collectionID, config: newConfig)
    }
}
