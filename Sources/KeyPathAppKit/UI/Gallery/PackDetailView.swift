// M1 Phase 3 — Pack Detail view, Direction-C flavored.
// Spec: docs/design/sprint-1/pack-detail-directions.md (Direction C).
//
// M1 scope: this ships as a sheet over the Gallery window. The full
// Direction-C behavior (real keyboard canvas dims behind the panel,
// affected keys glow with pending tint, install moment is a continuity
// transition) depends on having the main keyboard always visible behind
// Pack Detail — which KeyPath's current window model (main window is a
// splash) does not yet support. For M1 we approximate by:
//   - Presenting Pack Detail as a sheet with the Direction-C visual
//     vocabulary (affected-keys preview inside the sheet, animated
//     pending tint that transitions to installed state).
//   - Showing a confirmation toast after install/uninstall with Undo.
// The real in-place modification coupling is a follow-up once the main
// window grows a persistent keyboard canvas.

import AppKit
import SwiftUI

struct PackDetailView: View {
    let pack: Pack
    @Environment(\.dismiss) private var dismiss
    @Environment(KanataViewModel.self) private var kanataManager

    @State private var isInstalled = false
    @State private var isWorking = false
    @State private var toggleTask: Task<Void, Never>?
    @State private var justInstalled = false
    @State private var justUninstalled = false
    @State private var errorMessage: String?
    @State private var quickSettingValues: [String: Int] = [:]
    @State private var lastUndoSnapshot: UndoSnapshot?

    /// Live tap/hold selection mirrored from the embedded picker. Drives
    /// the blue "Tap: X · Hold: Y" status line so it updates the moment
    /// the user clicks a preset, without waiting for Phase 3's write-
    /// through to the installed CustomRule.
    @State private var pickerTapSelection: String?
    @State private var pickerHoldSelection: String?
    @State private var singleKeySelection: String?

    /// Local state for the embedded Home Row Mods editor. Mirrors the
    /// config shape Rules uses so we can drop `HomeRowModsCollectionView`
    /// in unchanged. Edits here are local for now — wiring them through
    /// to a persisted collection config is follow-up work.
    @State private var homeRowModsConfig: HomeRowModsConfig = .init()

    /// Local state for the embedded Auto Shift Symbols editor.
    @State private var autoShiftConfig: AutoShiftSymbolsConfig = .init()

    /// Currently-selected layer-preset id (for the Symbol/Fun packs).
    @State private var selectedLayerPresetId: String?

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            header
            ScrollView(showsIndicators: false) {
                VStack(alignment: .leading, spacing: 18) {
                    descriptionBlock
                    if !pack.quickSettings.isEmpty {
                        quickSettingsBlock
                    }
                    bindingsBlock
                }
                .padding(.horizontal, 24)
                .padding(.bottom, 20)
            }
        }
        .frame(width: 560, height: 640)
        .task {
            await refreshInstallState()
            loadDefaultQuickSettings()
        }
        .overlay(toastOverlay, alignment: .bottom)
    }

    // MARK: - Header

    private var header: some View {
        VStack(alignment: .leading, spacing: 12) {
            // Top controls: a breadcrumb-style "Gallery" back link on the
            // left (opens the full Gallery window) and a close ✕ on the
            // right. The back link matters when Pack Detail is opened from
            // somewhere other than the Gallery (e.g. the Suggested banner
            // in the overlay inspector) — it gives users a way to jump to
            // the full list instead of just dismissing the sheet.
            HStack {
                Button(action: { openGalleryWindow() }) {
                    HStack(spacing: 4) {
                        Image(systemName: "chevron.left")
                            .font(.system(size: 10, weight: .semibold))
                        Text("Gallery")
                            .font(.system(size: 12, weight: .medium))
                    }
                    .foregroundStyle(.secondary)
                }
                .buttonStyle(.plain)
                .focusable(false)
                .accessibilityLabel("Open Gallery")
                .accessibilityIdentifier("pack-detail-open-gallery")
                Spacer()
                Button(action: { dismiss() }) {
                    Image(systemName: "xmark")
                        .font(.system(size: 11, weight: .semibold))
                        .foregroundStyle(.secondary)
                        .frame(width: 24, height: 24)
                        .background(Circle().fill(.quaternary))
                }
                .buttonStyle(.plain)
                .focusable(false)
                .keyboardShortcut(.cancelAction)
                .accessibilityLabel("Close")
                .accessibilityIdentifier("pack-detail-close")
            }

            HStack(alignment: .center, spacing: 16) {
                heroIcon
                VStack(alignment: .leading, spacing: 4) {
                    Text(pack.name)
                        .font(.system(size: 20, weight: .semibold))
                    Text(pack.tagline)
                        .font(.system(size: 13))
                        .foregroundStyle(.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                    currentConfigRow
                }
                Spacer()
                // On/off toggle — aligned with the title block, vertically
                // centered with the hero icon.
                Toggle(
                    "",
                    isOn: Binding(
                        get: { isInstalled },
                        set: { handleToggle(to: $0) }
                    )
                )
                .labelsHidden()
                .toggleStyle(.switch)
                .scaleEffect(0.91, anchor: .trailing)
                .disabled(isWorking)
                .accessibilityLabel(isInstalled ? "Turn off pack" : "Turn on pack")
                .accessibilityIdentifier("pack-detail-toggle")
            }
        }
        .padding(.horizontal, 24)
        .padding(.top, 32)
        .padding(.bottom, 14)
    }

    /// Blue inline summary of what this pack does right now — mirrors the
    /// "Tap: X · Hold: Y" treatment used in the Rules list so users see the
    /// effective behavior without reading binding details.
    ///
    /// Reads from the associated `RuleCollection`'s mapping behavior when
    /// one exists (so Caps Lock Remap shows its real Hyper/Hyper default);
    /// falls back to the pack's own binding template otherwise.
    @ViewBuilder
    private var currentConfigRow: some View {
        if let summary = currentConfigSummary {
            HStack(spacing: 6) {
                Image(systemName: "hand.point.up.left.fill")
                    .font(.system(size: 10))
                    .foregroundStyle(Color.accentColor)
                Text(summary)
                    .font(.system(size: 11, weight: .medium))
                    .foregroundStyle(Color.accentColor)
            }
            .padding(.top, 2)
        }
    }

    private var currentConfigSummary: String? {
        PackSummaryProvider.summary(
            for: .init(
                pack: pack,
                collection: liveAssociatedCollection,
                tapOverride: pickerTapSelection,
                holdOverride: pickerHoldSelection,
                singleKeyOverride: singleKeySelection
            )
        )
    }

    /// Larger version of the pack card's hero icon, for Pack Detail's header.
    private var heroIcon: some View {
        ZStack {
            RoundedRectangle(cornerRadius: 14, style: .continuous)
                .fill(
                    LinearGradient(
                        colors: [
                            Color.accentColor.opacity(0.16),
                            Color.accentColor.opacity(0.06)
                        ],
                        startPoint: .topLeading,
                        endPoint: .bottomTrailing
                    )
                )
                .overlay(
                    RoundedRectangle(cornerRadius: 14, style: .continuous)
                        .strokeBorder(Color.accentColor.opacity(0.22), lineWidth: 0.5)
                )
                .frame(width: 72, height: 72)

            if let secondary = pack.iconSecondarySymbol {
                HStack(spacing: 3) {
                    Image(systemName: pack.iconSymbol)
                        .font(.system(size: 22, weight: .semibold))
                        .foregroundStyle(.tint)
                        .symbolRenderingMode(.hierarchical)
                    Image(systemName: "arrow.right")
                        .font(.system(size: 9, weight: .semibold))
                        .foregroundStyle(.secondary)
                    Image(systemName: secondary)
                        .font(.system(size: 22, weight: .semibold))
                        .foregroundStyle(.tint)
                        .symbolRenderingMode(.hierarchical)
                }
            } else {
                Image(systemName: pack.iconSymbol)
                    .font(.system(size: 30, weight: .semibold))
                    .foregroundStyle(.tint)
                    .symbolRenderingMode(.hierarchical)
            }
        }
    }

    private func handleToggle(to newValue: Bool) {
        guard newValue != isInstalled else { return }
        // Cancel any in-flight install/uninstall so two quick taps (install →
        // uninstall → install) don't interleave writes into the rules table.
        // `.disabled(isWorking)` guards the tap-through case, but SwiftUI
        // Toggles can re-fire before the disabled state propagates on a
        // rapid double-flick.
        toggleTask?.cancel()
        toggleTask = Task { newValue ? await install() : await uninstall() }
    }

    /// Dismiss this sheet and bring the Gallery window forward. Works
    /// whether Pack Detail was opened from the Gallery itself (no-op
    /// beyond dismiss) or from another surface like the Suggested banner.
    private func openGalleryWindow() {
        dismiss()
        GalleryWindowController.shared.showWindow(kanataManager: kanataManager)
    }

    /// Apply a picker-driven edit to the installed rule / collection. If
    /// the pack isn't installed yet, install it first (which for
    /// collection-backed packs toggles the collection, for rule-based
    /// packs creates tagged CustomRules). Install's reload is suppressed
    /// so the follow-up tap/hold update fires exactly one reload.
    private func applyPickerEdit(tap: String?, hold: String?) async {
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
    private func applySingleKeyEdit(output: String) async {
        singleKeySelection = output
        guard let collectionID = pack.associatedCollectionID else { return }
        if !isInstalled {
            await install(skipFinalReload: true)
        }
        await kanataManager.updateCollectionOutput(collectionID, output: output)
    }

    // MARK: - Description

    /// Single scannable paragraph that answers WHY (the problem this solves)
    /// and WHAT (how this pack solves it). Replaces the prior two-block
    /// short + long description — packs should front-load the pitch, not
    /// split it into a lede and a follow-up.
    private var descriptionBlock: some View {
        Text(pack.shortDescription)
            .font(.system(size: 13))
            .foregroundStyle(.primary)
            .fixedSize(horizontal: false, vertical: true)
            .lineSpacing(2)
    }

    // MARK: - Quick settings

    private var quickSettingsBlock: some View {
        VStack(alignment: .leading, spacing: 10) {
            Divider()
            Text("Quick settings")
                .font(.system(size: 12, weight: .semibold))
                .foregroundStyle(.secondary)
            ForEach(pack.quickSettings) { setting in
                quickSettingRow(setting)
            }
        }
    }

    @ViewBuilder
    private func quickSettingRow(_ setting: PackQuickSetting) -> some View {
        switch setting.kind {
        case let .slider(_, min: lo, max: hi, step: step, unitSuffix: suffix):
            HStack(spacing: 10) {
                Text(setting.label)
                    .font(.system(size: 12))
                    .frame(width: 110, alignment: .leading)
                Slider(
                    value: sliderBinding(for: setting.id),
                    in: Double(lo) ... Double(hi),
                    step: Double(step)
                )
                Text("\(quickSettingValues[setting.id] ?? 0)\(suffix)")
                    .font(.system(size: 11, design: .monospaced))
                    .foregroundStyle(.secondary)
                    .frame(width: 60, alignment: .trailing)
            }
        }
    }

    // MARK: - Binding list

    @ViewBuilder
    private var bindingsBlock: some View {
        if isHomeRowModsPack, let collectionID = pack.associatedCollectionID {
            // Home Row Mods uses a different configuration shape than the
            // tap-hold picker — interactive keyboard + layered mods —
            // so we embed the same view the Rules tab uses. All layer-
            // aware callbacks delegate into the same `kanataManager`
            // methods Rules uses so hold-to-layer bindings work here too.
            VStack(alignment: .leading, spacing: 0) {
                Divider()
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
                .opacity(isInstalled ? 1.0 : 0.55)
                .animation(.easeInOut(duration: 0.2), value: isInstalled)
            }
        } else if let singleKeyCollection = associatedSingleKeyCollection {
            // Single-key remap with preset pills (Escape Remap, Delete
            // Enhancement, Backup Caps Lock). Reuses Rules' view directly.
            VStack(alignment: .leading, spacing: 0) {
                Divider()
                SingleKeyPickerContent(
                    collection: singleKeyCollection,
                    onSelectOutput: { output in
                        Task { await applySingleKeyEdit(output: output) }
                    }
                )
                .opacity(isInstalled ? 1.0 : 0.55)
                .animation(.easeInOut(duration: 0.2), value: isInstalled)
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
            VStack(alignment: .leading, spacing: 0) {
                Divider()
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
                // fresh seed. User clicks update our local state, which
                // bumps the id, which re-seeds — harmless because the new
                // seed matches what the user just clicked.
                .id("\(pickerTapSelection ?? "")-\(pickerHoldSelection ?? "")")
                .opacity(isInstalled ? 1.0 : 0.55)
                .animation(.easeInOut(duration: 0.2), value: isInstalled)
            }
        } else if let autoShiftCollection = associatedAutoShiftCollection {
            // Auto Shift Symbols: enabled-keys toggles + timing slider + fast-
            // typing protection. Same view the Rules tab uses.
            VStack(alignment: .leading, spacing: 0) {
                Divider()
                AutoShiftCollectionView(
                    config: autoShiftConfig,
                    onConfigChanged: { newConfig in
                        Task { await applyAutoShiftEdit(newConfig, collectionID: autoShiftCollection.id) }
                    }
                )
                .id(autoShiftCollection.id) // re-mount when live config changes
                .opacity(isInstalled ? 1.0 : 0.55)
                .animation(.easeInOut(duration: 0.2), value: isInstalled)
            }
        } else if let layerPresetCollection = associatedLayerPresetCollection {
            // Layer preset picker — Symbol/Fun layers. Users choose a preset
            // (e.g. Mirrored, Alphabetical) that redefines the layer's
            // mappings. Reuses the Rules-tab picker directly.
            VStack(alignment: .leading, spacing: 0) {
                Divider()
                LayerPresetPickerContent(
                    collection: layerPresetCollection,
                    onSelectPreset: { presetId in
                        selectedLayerPresetId = presetId
                        Task { await applyLayerPresetEdit(presetId: presetId, collectionID: layerPresetCollection.id) }
                    }
                )
                .id(selectedLayerPresetId ?? "")
                .opacity(isInstalled ? 1.0 : 0.55)
                .animation(.easeInOut(duration: 0.2), value: isInstalled)
            }
        } else if let collection = liveAssociatedCollection,
                  collection.id == RuleCollectionIdentifier.windowSnapping {
            // Window Snapping has a custom visual editor in Rules — convention
            // picker + monitor canvas + floating action cards. Pack Detail
            // embeds the same view so the experience is identical.
            VStack(alignment: .leading, spacing: 0) {
                Divider()
                if let hint = collection.activationHint, !hint.isEmpty {
                    Text(hint)
                        .font(.system(size: 12, weight: .medium))
                        .foregroundStyle(.secondary)
                        .padding(.top, 8)
                }
                WindowSnappingView(
                    mappings: collection.mappings,
                    convention: collection.windowKeyConvention ?? .standard,
                    onConventionChange: { convention in
                        Task { await applyWindowConventionEdit(convention, collectionID: collection.id) }
                    }
                )
                .opacity(isInstalled ? 1.0 : 0.55)
                .animation(.easeInOut(duration: 0.2), value: isInstalled)
            }
        } else if pack.bindings.isEmpty, let collection = liveAssociatedCollection,
                  !collection.mappings.isEmpty {
            // Collection-backed pack with no explicit bindings and a plain
            // `.table` config (Vim Navigation, Mission Control, Numpad).
            // Uses the same MappingTableContent view Rules uses so the
            // table styling matches exactly.
            VStack(alignment: .leading, spacing: 8) {
                Divider()
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
                .opacity(isInstalled ? 1.0 : 0.6)
                .animation(.easeInOut(duration: 0.2), value: isInstalled)
            }
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

    /// Live `RuleCollection` this pack is associated with. Used to hand
    /// to Rules' view components (they take the whole collection so they
    /// can render the user's latest selections, not catalog defaults).
    private var liveAssociatedCollection: RuleCollection? {
        guard let collectionID = pack.associatedCollectionID else { return nil }
        let live = kanataManager.underlyingManager
            .ruleCollectionsManager.ruleCollections
            .first { $0.id == collectionID }
        if let live { return live }
        return RuleCollectionCatalog().defaultCollections()
            .first { $0.id == collectionID }
    }

    /// Collection with a `.singleKeyPicker` configuration — drives the
    /// SingleKeyPickerContent dispatch in Pack Detail.
    private var associatedSingleKeyCollection: RuleCollection? {
        guard let collection = liveAssociatedCollection,
              case .singleKeyPicker = collection.configuration
        else { return nil }
        return collection
    }

    /// Collection backing an Auto Shift-style pack (enabled-keys toggles +
    /// timing slider). Matches the `.autoShiftSymbols` configuration case.
    private var associatedAutoShiftCollection: RuleCollection? {
        guard let collection = liveAssociatedCollection,
              case .autoShiftSymbols = collection.configuration
        else { return nil }
        return collection
    }

    /// Collection backing a layer-preset pack (Symbol, Fun). Matches the
    /// `.layerPresetPicker` configuration case.
    private var associatedLayerPresetCollection: RuleCollection? {
        guard let collection = liveAssociatedCollection,
              case .layerPresetPicker = collection.configuration
        else { return nil }
        return collection
    }

    /// True if this pack's bindings line up with the Home Row Mods
    /// collection's input set — in which case we render that collection's
    /// interactive keyboard + modifier controls instead of the generic
    /// tap-hold picker.
    private var isHomeRowModsPack: Bool {
        let homeRowKeys: Set<String> = ["a", "s", "d", "f", "j", "k", "l", "scln", ";"]
        let inputs = Set(pack.bindings.map { $0.input.lowercased() })
        // Consider it a home-row pack if at least 4 of its bindings are on
        // the home row — covers light and full variants without listing
        // every combination.
        return inputs.intersection(homeRowKeys).count >= 4
    }

    /// Match the pack to an existing `RuleCollection` that carries a
    /// tap-hold picker config. Today this is keyed on the pack's first
    /// binding input matching the collection's picker `inputKey`. When we
    /// add a proper `associatedCollectionID` to Pack, switch to that.
    ///
    /// If the installed rule (or a refreshed live selection) has a value,
    /// we stamp it into the config's `selectedTapOutput`/`selectedHoldOutput`
    /// so the embedded picker opens highlighted on the real current state.
    private var associatedPickerConfig: TapHoldPickerConfig? {
        guard let firstInput = pack.bindings.first?.input.lowercased() else { return nil }
        let base = RuleCollectionCatalog().defaultCollections().lazy
            .compactMap { $0.configuration.tapHoldPickerConfig }
            .first(where: { $0.inputKey.lowercased() == firstInput })
        guard var config = base else { return nil }
        if let liveTap = pickerTapSelection {
            config.selectedTapOutput = liveTap
        }
        if let liveHold = pickerHoldSelection {
            config.selectedHoldOutput = liveHold
        }
        return config
    }

    /// Renders a pack binding in the same visual vocabulary as Rules:
    /// input keycap → output keycap, with a behavior summary ("Hold: ⌘")
    /// inline when the binding has a hold component. Reuses `KeyCapChip`
    /// and `RuleBehaviorSummaryView` so this stays consistent with the
    /// Rules tab as that evolves.
    private func bindingRow(_ template: PackBindingTemplate) -> some View {
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

    // MARK: - Toast overlay

    @ViewBuilder
    private var toastOverlay: some View {
        if let error = errorMessage {
            toastView(
                icon: "exclamationmark.triangle.fill",
                iconColor: .orange,
                message: error,
                action: nil
            )
            .transition(.move(edge: .bottom).combined(with: .opacity))
            .padding(.bottom, 72)
        } else if justInstalled {
            toastView(
                icon: "checkmark.circle.fill",
                iconColor: .green,
                message: installedToastMessage,
                action: ("Undo", { Task { await undoInstall() } })
            )
            .transition(.move(edge: .bottom).combined(with: .opacity))
            .padding(.bottom, 72)
        } else if justUninstalled {
            toastView(
                icon: "checkmark.circle.fill",
                iconColor: .green,
                message: "\(pack.name) turned off.",
                action: ("Undo", { Task { await undoUninstall() } })
            )
            .transition(.move(edge: .bottom).combined(with: .opacity))
            .padding(.bottom, 72)
        }
    }

    private var installedToastMessage: String {
        pack.bindings.count == 1
            ? "\(pack.name) turned on."
            : "\(pack.name) turned on · \(pack.bindings.count) bindings added."
    }

    private func toastView(
        icon: String,
        iconColor: Color,
        message: String,
        action: (label: String, handler: () -> Void)?
    ) -> some View {
        HStack(spacing: 10) {
            Image(systemName: icon)
                .foregroundStyle(iconColor)
            Text(message)
                .font(.system(size: 12))
                .foregroundStyle(.primary)
            if let action {
                Button(action.label, action: action.handler)
                    .buttonStyle(.link)
                    .foregroundStyle(.blue)
                    .accessibilityIdentifier("pack-detail-banner-action")
            }
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 10)
        .background(
            RoundedRectangle(cornerRadius: 10, style: .continuous)
                .fill(.regularMaterial)
                .shadow(color: .black.opacity(0.14), radius: 10, y: 3)
        )
        .overlay(
            RoundedRectangle(cornerRadius: 10, style: .continuous)
                .strokeBorder(Color.white.opacity(0.14), lineWidth: 0.5)
        )
    }

    // MARK: - State actions

    private func sliderBinding(for id: String) -> Binding<Double> {
        Binding(
            get: { Double(quickSettingValues[id] ?? 0) },
            set: { quickSettingValues[id] = Int($0) }
        )
    }

    private func loadDefaultQuickSettings() {
        for setting in pack.quickSettings {
            if quickSettingValues[setting.id] == nil,
               let defaultVal = setting.defaultSliderValue
            {
                quickSettingValues[setting.id] = defaultVal
            }
        }
    }

    private func refreshInstallState() async {
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
        }
    }

    private func liveAutoShiftConfig() -> AutoShiftSymbolsConfig? {
        guard let collection = associatedAutoShiftCollection,
              case let .autoShiftSymbols(cfg) = collection.configuration
        else { return nil }
        return cfg
    }

    private func liveLayerPresetId() -> String? {
        guard let collection = associatedLayerPresetCollection,
              case let .layerPresetPicker(cfg) = collection.configuration
        else { return nil }
        return cfg.selectedPresetId
    }

    private func liveSingleKeySelection() async -> String? {
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

    /// Apply a Home Row Mods edit — analogous to the tap-hold `updateTapHold`
    /// path: if the pack isn't installed yet, install it first (which
    /// toggles the collection on), then persist the new config. Install's
    /// reload is suppressed so the config save is the only reload.
    private func applyHomeRowEdit(_ newConfig: HomeRowModsConfig, collectionID: UUID) async {
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
    private func applyAutoShiftEdit(_ newConfig: AutoShiftSymbolsConfig, collectionID: UUID) async {
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
    private func applyWindowConventionEdit(_ convention: WindowKeyConvention, collectionID: UUID) async {
        if !isInstalled {
            await install(skipFinalReload: true)
        }
        await kanataManager.updateWindowKeyConvention(collectionID, convention: convention)
    }

    /// Mirror of `applyHomeRowEdit` for layer-preset packs (Symbol, Fun).
    /// Installs the pack on first touch, then switches the collection's
    /// selected preset so the generated kanata config rebinds the layer.
    private func applyLayerPresetEdit(presetId: String, collectionID: UUID) async {
        selectedLayerPresetId = presetId
        if !isInstalled {
            await install(skipFinalReload: true)
        }
        await kanataManager.updateCollectionLayerPreset(collectionID, presetId: presetId)
    }

    /// Supplies the same layer list Rules uses when rendering the Home Row
    /// Mods editor, so hold-to-layer bindings resolve correctly inside
    /// Pack Detail.
    private func availableHomeRowLayers() -> [String] {
        let names = Set(
            kanataManager.ruleCollections
                .map(\.targetLayer.kanataName)
                .filter { $0.lowercased() != "base" }
        )
        return Array(names).sorted()
    }

    /// Read the current persisted Home Row Mods config so the embedded
    /// editor opens matching live state (not catalog defaults).
    private func liveHomeRowModsConfig() async -> HomeRowModsConfig? {
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

    private func liveTapHoldFromInstalledRule() async -> (tap: String?, hold: String?)? {
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

    private func install(skipFinalReload: Bool = false) async {
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
        } catch {
            withAnimation { errorMessage = error.localizedDescription }
            Task {
                try? await Task.sleep(nanoseconds: 4_000_000_000)
                await MainActor.run {
                    withAnimation(.easeOut(duration: 0.3)) { errorMessage = nil }
                }
            }
        }
        isWorking = false
    }

    private func uninstall() async {
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

    private func undoInstall() async {
        withAnimation(.easeOut(duration: 0.2)) { justInstalled = false }
        await uninstall()
    }

    private func undoUninstall() async {
        withAnimation(.easeOut(duration: 0.2)) { justUninstalled = false }
        // Re-install with the saved settings from just before uninstall.
        if let snap = lastUndoSnapshot {
            quickSettingValues = snap.quickSettingValues
        }
        await install()
    }

    // MARK: - Helpers

    private func displayLabel(for kanataKey: String) -> String {
        switch kanataKey.lowercased() {
        case "caps": "⇪"
        case "lmet": "⌘"
        case "rmet": "⌘"
        case "lalt": "⌥"
        case "ralt": "⌥"
        case "lctl": "⌃"
        case "rctl": "⌃"
        case "lsft": "⇧"
        case "rsft": "⇧"
        case "spc": "Space"
        case "ret", "enter": "⏎"
        case "tab": "⇥"
        case "esc": "⎋"
        case "bspc", "backspace": "⌫"
        case "del": "⌦"
        case "minus": "-"
        case "equal": "="
        default: kanataKey
        }
    }
}

// MARK: - Keycap chip

/// Small keycap visual used in Pack Detail to represent affected keys.
/// Mirrors the chip style in PackCardView but renders larger.
struct KeycapChipView: View {
    enum KeyState {
        /// Default state — what the key does today, no pending change.
        case inert
        /// Pending state — this key will change if the user installs.
        case pending
        /// Installed state — the pack is active and this key is taking effect.
        case installed
    }

    let label: String
    let state: KeyState

    var body: some View {
        Text(label)
            .font(.system(size: 13, weight: .semibold, design: .monospaced))
            .foregroundStyle(foreground)
            .frame(minWidth: 36, minHeight: 36)
            .padding(.horizontal, 8)
            .background(background)
            .overlay(border)
            .animation(.easeInOut(duration: 0.24), value: state)
    }

    private var foreground: Color {
        switch state {
        case .inert: .primary.opacity(0.7)
        case .pending: .accentColor.opacity(0.85)
        case .installed: .accentColor
        }
    }

    private var background: some View {
        RoundedRectangle(cornerRadius: 6, style: .continuous)
            .fill(fillColor)
    }

    private var fillColor: Color {
        switch state {
        case .inert: Color(nsColor: .controlBackgroundColor)
        case .pending: Color.accentColor.opacity(0.08)
        case .installed: Color.accentColor.opacity(0.14)
        }
    }

    private var border: some View {
        RoundedRectangle(cornerRadius: 6, style: .continuous)
            .strokeBorder(borderColor, lineWidth: state == .inert ? 0.5 : 1)
    }

    private var borderColor: Color {
        switch state {
        case .inert: Color(nsColor: .separatorColor)
        case .pending: Color.accentColor.opacity(0.5)
        case .installed: Color.accentColor.opacity(0.7)
        }
    }
}

// MARK: - Undo snapshot

private struct UndoSnapshot {
    let quickSettingValues: [String: Int]
}
