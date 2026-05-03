import SwiftUI

// MARK: - Binding list & embedded editors

extension PackDetailView {
    /// Wraps embedded editors in `InsetBackPlane` with the same padding the
    /// Rules tab uses, so Pack Detail editors visually match their Rules
    /// counterparts (subtle inner-shadow container, consistent insets).
    @ViewBuilder
    func embeddedEditor<Content: View>(
        horizontalPadding: CGFloat = 16,
        @ViewBuilder content: () -> Content
    ) -> some View {
        InsetBackPlane {
            content()
                .padding(.top, 8)
                .padding(.bottom, 12)
                .padding(.horizontal, horizontalPadding)
        }
        .opacity(isInstalled ? 1.0 : 0.55)
        .animation(.easeInOut(duration: 0.2), value: isInstalled)
    }

    @ViewBuilder
    var bindingsBlock: some View {
        if isHomeRowModsPack, let collectionID = pack.associatedCollectionID {
            // Home Row Mods uses a different configuration shape than the
            // tap-hold picker — interactive keyboard + layered mods —
            // so we embed the same view the Rules tab uses. All layer-
            // aware callbacks delegate into the same `kanataManager`
            // methods Rules uses so hold-to-layer bindings work here too.
            embeddedEditor {
                HomeRowModsCollectionView(
                    config: $homeRowModsConfig,
                    availableLayers: availableHomeRowLayers(),
                    onConfigChanged: { newConfig in
                        Task { await applyHomeRowEdit(newConfig, collectionID: collectionID) }
                    },
                    onEnsureLayersExist: { layerNames in
                        for name in layerNames {
                            await kanataManager.underlyingManager.rulesManager.createLayer(name)
                        }
                    },
                    onEnableLayerCollections: { collectionIds in
                        await kanataManager.batchEnableCollections(collectionIds)
                    }
                )
            }
        } else if let singleKeyCollection = associatedSingleKeyCollection {
            // Single-key remap with preset pills (Escape Remap, Delete
            // Enhancement, Backup Caps Lock). Reuses Rules' view directly.
            embeddedEditor {
                SingleKeyPickerContent(
                    collection: singleKeyCollection,
                    onSelectOutput: { output in
                        Task { await applySingleKeyEdit(output: output) }
                    }
                )
            }
        } else if let pickerConfig = associatedPickerConfig {
            // Phase 2: for packs that map onto an existing RuleCollection's
            // tap-hold picker (e.g. Caps Lock Remap), embed the same picker
            // component the Rules tab uses.
            //
            // When the pack is OFF the picker reads as disabled (dimmed)
            // but clicks are still live: picking any preset installs the
            // pack, the user's click registers in the picker's internal
            // selection state, and the dim lifts. Phase 3 will persist the
            // selected preset through to the installed CustomRule.
            embeddedEditor {
                TapHoldPickerContent(
                    config: pickerConfig,
                    isEditable: true,
                    onSelectTapOutput: { output in
                        pickerTapSelection = output
                        Task { await applyPickerEdit(tap: output, hold: nil) }
                    },
                    onSelectHoldOutput: { output in
                        pickerHoldSelection = output
                        Task { await applyPickerEdit(tap: nil, hold: output) }
                    }
                )
                // Picker seeds its selection state at init. Re-id whenever
                // the live selection flips (e.g. on appear, after refresh
                // from the live rule) so SwiftUI re-creates it with the
                // fresh seed.
                .id("\(pickerTapSelection ?? "")-\(pickerHoldSelection ?? "")")
            }
        } else if let autoShiftCollection = associatedAutoShiftCollection {
            // Auto Shift Symbols: enabled-keys toggles + timing slider + fast-
            // typing protection. Same view the Rules tab uses.
            embeddedEditor {
                AutoShiftCollectionView(
                    config: autoShiftConfig,
                    onConfigChanged: { newConfig in
                        Task { await applyAutoShiftEdit(newConfig, collectionID: autoShiftCollection.id) }
                    }
                )
                .id(autoShiftCollection.id)
            }
        } else if let layerPresetCollection = associatedLayerPresetCollection {
            // Layer preset picker — Symbol/Fun layers. Users choose a preset
            // (e.g. Mirrored, Alphabetical) that redefines the layer's
            // mappings. Reuses the Rules-tab picker directly.
            embeddedEditor {
                LayerPresetPickerContent(
                    collection: layerPresetCollection,
                    onSelectPreset: { presetId in
                        selectedLayerPresetId = presetId
                        Task { await applyLayerPresetEdit(presetId: presetId, collectionID: layerPresetCollection.id) }
                    }
                )
                .id(selectedLayerPresetId ?? "")
            }
        } else if let launcherCollection = associatedLauncherCollection {
            // Quick Launcher — keyboard visualization + drawer of mappings,
            // activation-mode picker. Same view Rules tab uses; edits flow
            // through the same `updateLauncherConfig` VM hook.
            embeddedEditor(horizontalPadding: 12) {
                LauncherCollectionView(
                    config: $launcherConfig,
                    onConfigChanged: { newConfig in
                        Task { await applyLauncherEdit(newConfig, collectionID: launcherCollection.id) }
                    }
                )
            }
        } else if let collection = liveAssociatedCollection,
                  collection.id == RuleCollectionIdentifier.windowSnapping {
            // Window Snapping has a custom visual editor in Rules — convention
            // picker + monitor canvas + floating action cards. Pack Detail
            // embeds the same view so the experience is identical.
            // Rules uses horizontal padding of 12 for this particular editor.
            embeddedEditor(horizontalPadding: 12) {
                WindowSnappingView(
                    mappings: collection.mappings,
                    convention: collection.windowKeyConvention ?? .standard,
                    onConventionChange: { convention in
                        Task { await applyWindowConventionEdit(convention, collectionID: collection.id) }
                    }
                )
            }
        } else if pack.bindings.isEmpty, let collection = liveAssociatedCollection,
                  !collection.mappings.isEmpty {
            // Collection-backed pack with no explicit bindings and a plain
            // `.table` config (Vim Navigation, Mission Control, Numpad).
            // Uses the same MappingTableContent view Rules uses so the
            // table styling matches exactly.
            embeddedEditor {
                VStack(alignment: .leading, spacing: 8) {
                    if let hint = collection.activationHint, !hint.isEmpty {
                        Text(hint)
                            .font(.system(size: 12, weight: .medium))
                            .foregroundStyle(.secondary)
                    }
                    MappingTableContent(
                        mappings: collection.mappings.map {
                            ($0.input, $0.output, $0.shiftedOutput, $0.ctrlOutput,
                             $0.description, $0.sectionBreak, isInstalled, $0.id, nil)
                        }
                    )
                }
            }
        } else if pack.id == PackRegistry.kindaVim.id {
            embeddedEditor { KindaVimStatusBlock() }
        } else {
            VStack(alignment: .leading, spacing: 8) {
                Divider()
                Text("What this will change")
                    .font(.system(size: 12, weight: .semibold))
                    .foregroundStyle(.secondary)
                ForEach(Array(pack.bindings.enumerated()), id: \.offset) { _, template in
                    bindingRow(template)
                }
            }
        }
    }

    /// Renders a pack binding in the same visual vocabulary as Rules:
    /// input keycap → output keycap, with a behavior summary ("Hold: ⌘")
    /// inline when the binding has a hold component. Reuses `KeyCapChip`
    /// and `RuleBehaviorSummaryView` so this stays consistent with the
    /// Rules tab as that evolves.
    func bindingRow(_ template: PackBindingTemplate) -> some View {
        HStack(alignment: .center, spacing: 10) {
            KeyCapChip(text: RuleBehaviorSummaryView.formatKeyForBehavior(template.input))
            Image(systemName: "arrow.right")
                .font(.caption)
                .foregroundStyle(.secondary)
            KeyCapChip(text: RuleBehaviorSummaryView.formatKeyForBehavior(template.output))

            if let hold = template.holdOutput, !hold.isEmpty {
                Text("·")
                    .font(.caption)
                    .foregroundStyle(.tertiary)
                RuleBehaviorSummaryView(
                    behavior: .dualRole(
                        DualRoleBehavior(
                            tapAction: template.output,
                            holdAction: hold
                        )
                    )
                )
            }

            Spacer(minLength: 0)
        }
        .padding(.vertical, 2)
    }
}
