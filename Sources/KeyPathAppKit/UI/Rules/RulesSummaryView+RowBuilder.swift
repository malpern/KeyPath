import KeyPathCore
import SwiftUI

// MARK: - Collection Row Builder

extension RulesTabView {
    func packForCollection(_ collection: RuleCollection) -> Pack? {
        PackRegistry.starterKit.first { $0.associatedCollectionID == collection.id }
    }

    @ViewBuilder
    func collectionRow(for collection: RuleCollection, scrollProxy: ScrollViewProxy) -> some View {
        let style = collection.displayStyle
        let isSpecializedTable = style == .table && (
            collection.id == RuleCollectionIdentifier.numpadLayer ||
                collection.id == RuleCollectionIdentifier.vimNavigation ||
                collection.id == RuleCollectionIdentifier.windowSnapping ||
                collection.id == RuleCollectionIdentifier.macFunctionKeys
        )
        let needsCollection = style == .singleKeyPicker || style == .homeRowMods || style == .homeRowLayerToggles || style == .tapHoldPicker || style == .layerPresetPicker || style == .launcherGrid ||
            style == .chordGroups ||
            style ==
            .sequences || style == .autoShiftSymbols || isSpecializedTable
        ExpandableCollectionRow(
            collectionId: collection.id.uuidString,
            name: dynamicCollectionName(for: collection),
            icon: collection.icon ?? "circle",
            count: style == .singleKeyPicker || style == .tapHoldPicker ? 1 :
                (style == .layerPresetPicker ? (collection.configuration.layerPresetPickerConfig?.selectedMappings.count ?? 0) : collection.mappings.count),
            isEnabled: pendingToggles[collection.id] ?? collection.isEnabled,
            mappings: collection.mappings.map {
                ($0.input, $0.action.outputString, $0.shiftedOutput, $0.ctrlOutput, $0.description, $0.sectionBreak, $0.sectionLabel, collection.isEnabled, $0.id, nil)
            },
            onToggle: { isOn in
                handleCollectionToggle(collection: collection, isOn: isOn)
            },
            onEditMapping: nil,
            onDeleteMapping: nil,
            onTapRow: packForCollection(collection).map { pack in
                { PackDetailWindowController.shared.showWindow(pack: pack, kanataManager: kanataManager) }
            },
            description: dynamicCollectionDescription(for: collection),
            layerActivator: collection.momentaryActivator,
            leaderKeyDisplay: currentLeaderKeyDisplay,
            activationHint: dynamicActivationHint(for: collection),
            managingPackName: collectionOwnershipMap[collection.id]?.packName,
            onManagedToggleTapped: collectionOwnershipMap[collection.id] != nil ? {
                managedToggleCollection = collection
            } : nil,
            defaultExpanded: recommendationFocusCollectionId == collection.id,
            displayStyle: style,
            collection: needsCollection ? collection : nil,
            onSelectOutput: style == .singleKeyPicker ? { output in
                pendingSelections[collection.id] = output
                Task { await kanataManager.updateCollectionOutput(collection.id, output: output) }
            } : nil,
            onSelectTapOutput: style == .tapHoldPicker ? { tap in
                Task { await kanataManager.updateCollectionTapOutput(collection.id, tapOutput: tap) }
            } : nil,
            onSelectHoldOutput: style == .tapHoldPicker ? { hold in
                Task { await kanataManager.updateCollectionHoldOutput(collection.id, holdOutput: hold) }
            } : nil,
            onUpdateHomeRowModsConfig: style == .homeRowMods ? { config in
                pendingToggles[collection.id] = true
                Task { await kanataManager.updateHomeRowModsConfig(collectionId: collection.id, config: config) }
            } : nil,
            homeRowAvailableLayers: style == .homeRowMods ? availableHomeRowLayers(for: collection) : [],
            onEnsureHomeRowLayersExist: style == .homeRowMods ? { layerNames in
                for layerName in layerNames {
                    await kanataManager.underlyingManager.rulesManager.createLayer(layerName)
                }
            } : nil,
            onEnableLayerCollections: style == .homeRowMods ? { collectionIds in
                await kanataManager.batchEnableCollections(collectionIds)
            } : nil,
            onOpenHomeRowModsModal: style == .homeRowMods ? {
                homeRowModsEditState = HomeRowModsEditState(collection: collection, selectedKey: nil)
            } : nil,
            onOpenHomeRowModsModalWithKey: style == .homeRowMods ? { key in
                homeRowModsEditState = HomeRowModsEditState(collection: collection, selectedKey: key)
            } : nil,
            onUpdateHomeRowLayerTogglesConfig: style == .homeRowLayerToggles ? { config in
                pendingToggles[collection.id] = true
                Task { await kanataManager.updateHomeRowLayerTogglesConfig(collectionId: collection.id, config: config) }
            } : nil,
            onOpenHomeRowLayerTogglesModal: style == .homeRowLayerToggles ? {
                homeRowLayerTogglesEditState = HomeRowLayerTogglesEditState(collection: collection, selectedKey: nil)
            } : nil,
            onOpenHomeRowLayerTogglesModalWithKey: style == .homeRowLayerToggles ? { key in
                homeRowLayerTogglesEditState = HomeRowLayerTogglesEditState(collection: collection, selectedKey: key)
            } : nil,
            onUpdateChordGroupsConfig: style == .chordGroups ? { config in
                pendingToggles[collection.id] = true
                Task { await kanataManager.updateChordGroupsConfig(collectionId: collection.id, config: config) }
            } : nil,
            onOpenChordGroupsModal: style == .chordGroups ? {
                chordGroupsEditState = ChordGroupsEditState(collection: collection)
            } : nil,
            onUpdateSequencesConfig: style == .sequences ? { config in
                pendingToggles[collection.id] = true
                Task { await kanataManager.updateSequencesConfig(collectionId: collection.id, config: config) }
            } : nil,
            onOpenSequencesModal: style == .sequences ? {
                sequencesEditState = SequencesEditState(collection: collection)
            } : nil,
            onSelectLayerPreset: style == .layerPresetPicker ? { presetId in
                Task { await kanataManager.updateCollectionLayerPreset(collection.id, presetId: presetId) }
            } : nil,
            onSelectWindowConvention: collection.id == RuleCollectionIdentifier.windowSnapping ? { convention in
                Task { await kanataManager.updateWindowKeyConvention(collection.id, convention: convention) }
            } : nil,
            onWindowSnappingActivationModeChange: collection.id == RuleCollectionIdentifier.windowSnapping ? { mode in
                Task {
                    if let autoEnabled = await kanataManager.updateWindowSnappingActivationMode(collectionId: collection.id, mode: mode) {
                        settingsToastManager.showSuccess("Also enabled \(autoEnabled)")
                    }
                }
            } : nil,
            onSelectFunctionKeyMode: collection.id == RuleCollectionIdentifier.macFunctionKeys ? { mode in
                Task { await kanataManager.updateFunctionKeyMode(collection.id, mode: mode) }
            } : nil,
            onLauncherConfigChanged: collection.id == RuleCollectionIdentifier.launcher ? { config in
                Task { await kanataManager.updateLauncherConfig(collection.id, config: config) }
            } : nil,
            windowSnappingActive: isWindowSnappingOnLauncher,
            onAutoShiftConfigChanged: collection.id == RuleCollectionIdentifier.autoShiftSymbols ? { config in
                pendingToggles[collection.id] = true
                Task { await kanataManager.updateAutoShiftSymbolsConfig(collectionId: collection.id, config: config) }
            } : nil,
            onHelpTapped: collection.id == RuleCollectionIdentifier.homeRowMods ? {
                showingHomeRowModsHelp = true
            } : nil,
            scrollID: "collection-\(collection.id.uuidString)",
            scrollProxy: scrollProxy
        )
        .overlay(
            packForCollection(collection) == nil && !collection.isSystemDefault
                ? RoundedRectangle(cornerRadius: 10)
                .strokeBorder(Color.orange.opacity(0.35), lineWidth: 1.5)
                : nil
        )
    }
}
