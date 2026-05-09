import SwiftUI

// MARK: - Live state queries

extension PackDetailView {
    func refreshInstallState() async {
        let installed = await PackInstaller.shared.isInstalled(packID: pack.id)
        let saved = await PackInstaller.shared.quickSettings(for: pack.id)
        // Pick up whatever tap/hold the installed rule currently has — the
        // user might have edited it from the Rules tab since the last time
        // this sheet opened. Reading it here keeps the embedded picker and
        // the "Tap: X · Hold: Y" summary in sync with the live rule.
        let liveSelection = await liveTapHoldFromInstalledRule()
        let liveSingleKey = await liveSingleKeySelection()
        let liveHomeRow = await liveHomeRowModsConfig()
        await MainActor.run {
            isInstalled = installed
            if installed, !saved.isEmpty {
                quickSettingValues = saved
            }
            if let liveSelection {
                pickerTapSelection = liveSelection.tap
                pickerHoldSelection = liveSelection.hold
            }
            if let liveSingleKey {
                singleKeySelection = liveSingleKey
            }
            if let liveHomeRow {
                homeRowModsConfig = liveHomeRow
            }
            if let liveAutoShift = liveAutoShiftConfig() {
                autoShiftConfig = liveAutoShift
            }
            if let livePreset = liveLayerPresetId() {
                selectedLayerPresetId = livePreset
            }
            if let liveLauncher = liveLauncherConfig() {
                launcherConfig = liveLauncher
            }
        }
    }

    func liveAutoShiftConfig() -> AutoShiftSymbolsConfig? {
        guard let collection = associatedAutoShiftCollection,
              case let .autoShiftSymbols(cfg) = collection.configuration
        else { return nil }
        return cfg
    }

    func liveLayerPresetId() -> String? {
        guard let collection = associatedLayerPresetCollection,
              case let .layerPresetPicker(cfg) = collection.configuration
        else { return nil }
        return cfg.selectedPresetId
    }

    func liveLauncherConfig() -> LauncherGridConfig? {
        guard let collection = associatedLauncherCollection,
              case let .launcherGrid(cfg) = collection.configuration
        else { return nil }
        return cfg
    }

    func liveSingleKeySelection() async -> String? {
        guard let collectionID = pack.associatedCollectionID else { return nil }
        let collections = await kanataManager.underlyingManager
            .ruleCollectionsManager.ruleCollections
        if let match = collections.first(where: { $0.id == collectionID }),
           let cfg = match.configuration.singleKeyPickerConfig
        {
            return cfg.selectedOutput
        }
        return nil
    }

    func liveTapHoldFromInstalledRule() async -> (tap: String?, hold: String?)? {
        // Collection-backed pack: read live selection from the associated
        // collection's TapHoldPickerConfig (this is what Rules persists to).
        if let collectionID = pack.associatedCollectionID {
            let collections = await kanataManager.underlyingManager
                .ruleCollectionsManager.ruleCollections
            if let match = collections.first(where: { $0.id == collectionID }),
               let cfg = match.configuration.tapHoldPickerConfig
            {
                return (tap: cfg.selectedTapOutput, hold: cfg.selectedHoldOutput)
            }
            return nil
        }

        // Rule-based pack: read from the tagged CustomRule.
        guard let input = pack.bindings.first?.input.lowercased() else { return nil }
        let rules = await kanataManager.underlyingManager
            .ruleCollectionsManager.snapshotCurrentRules()
        guard let rule = rules.first(where: {
            $0.packSource == pack.id && $0.input.lowercased() == input
        }) else {
            return nil
        }
        if case let .dualRole(dr) = rule.behavior {
            return (tap: dr.tapAction, hold: dr.holdAction)
        }
        return (tap: rule.output, hold: nil)
    }

    /// Read the current persisted Home Row Mods config so the embedded
    /// editor opens matching live state (not catalog defaults).
    func liveHomeRowModsConfig() async -> HomeRowModsConfig? {
        guard isHomeRowModsPack, let collectionID = pack.associatedCollectionID else {
            return nil
        }
        let collections = await kanataManager.underlyingManager
            .ruleCollectionsManager.ruleCollections
        if let match = collections.first(where: { $0.id == collectionID }),
           case let .homeRowMods(config) = match.configuration
        {
            return config
        }
        return nil
    }

    /// Supplies the same layer list Rules uses when rendering the Home Row
    /// Mods editor, so hold-to-layer bindings resolve correctly inside
    /// Pack Detail.
    func availableHomeRowLayers() -> [String] {
        let names = Set(
            kanataManager.ruleCollections
                .map(\.targetLayer.kanataName)
                .filter { $0.lowercased() != "base" }
        )
        return Array(names).sorted()
    }
}
