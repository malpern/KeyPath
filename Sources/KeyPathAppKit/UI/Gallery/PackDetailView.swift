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
    let showBackToRules: Bool
    @Environment(\.dismiss) var dismiss
    @Environment(KanataViewModel.self) var kanataManager

    init(pack: Pack, showBackToRules: Bool = false) {
        self.pack = pack
        self.showBackToRules = showBackToRules
    }

    @State var isInstalled = false
    @State var isWorking = false
    @State var toggleTask: Task<Void, Never>?
    @State var justInstalled = false
    @State var justUninstalled = false
    @State var errorMessage: String?
    @State var packConflict: PackConflictState?
    @State var quickSettingValues: [String: Int] = [:]
    @State var lastUndoSnapshot: UndoSnapshot?

    /// Live tap/hold selection mirrored from the embedded picker. Drives
    /// the blue "Tap: X · Hold: Y" status line so it updates the moment
    /// the user clicks a preset, without waiting for Phase 3's write-
    /// through to the installed CustomRule.
    @State var pickerTapSelection: String?
    @State var pickerHoldSelection: String?
    @State var singleKeySelection: String?

    /// Local state for the embedded Home Row Mods editor. Mirrors the
    /// config shape Rules uses so we can drop `HomeRowModsCollectionView`
    /// in unchanged. Edits here are local for now — wiring them through
    /// to a persisted collection config is follow-up work.
    @State var homeRowModsConfig: HomeRowModsConfig = .init()

    /// Local state for the embedded Auto Shift Symbols editor.
    @State var autoShiftConfig: AutoShiftSymbolsConfig = .init()

    /// Currently-selected layer-preset id (for the Symbol/Fun packs).
    @State var selectedLayerPresetId: String?

    /// Local state for the embedded Quick Launcher editor.
    @State var launcherConfig: LauncherGridConfig = .defaultConfig

    /// Local state for the embedded Key Repeat Control editor.
    @State var keyRepeatConfig: KeyRepeatControlConfig = .init()

    /// Help sheet presentation (Home Row Mods only — mirrors the Rules tab's
    /// `?` button that opens the HRM markdown help).
    @State var showingHomeRowModsHelp = false

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
                    dependencySection
                }
                .padding(.horizontal, 24)
                .padding(.bottom, 20)
            }
        }
        .frame(
            minWidth: pack.preferredDetailWidth,
            idealWidth: pack.preferredDetailWidth,
            maxWidth: .infinity,
            minHeight: 500,
            idealHeight: 640,
            maxHeight: .infinity
        )
        .task {
            await refreshInstallState()
            loadDefaultQuickSettings()
        }
        .overlay(toastOverlay, alignment: .bottom)
        .sheet(isPresented: $showingHomeRowModsHelp) {
            MarkdownHelpSheet(resource: "home-row-mods", title: "Home Row Mods")
        }
        .sheet(item: $packConflict) { conflict in
            PackConflictResolutionDialog(
                state: conflict,
                onChoice: { choice in
                    packConflict = nil
                    if choice == .switchToNew {
                        Task { await resolveConflictAndInstall(conflict) }
                    }
                },
                onCancel: { packConflict = nil }
            )
        }
    }

    // MARK: - Header

    var header: some View {
        VStack(alignment: .leading, spacing: 12) {
            // Top controls: a breadcrumb-style "Gallery" back link on the
            // left (opens the full Gallery window) and a close ✕ on the
            // right. The back link matters when Pack Detail is opened from
            // somewhere other than the Gallery (e.g. the Suggested banner
            // in the overlay inspector) — it gives users a way to jump to
            // the full list instead of just dismissing the sheet.
            HStack {
                if showBackToRules {
                    Button {
                        PackDetailWindowController.shared.closeWindow()
                    } label: {
                        HStack(spacing: 4) {
                            Image(systemName: "chevron.left")
                                .font(.system(size: 10, weight: .semibold))
                            Text("All Rules")
                                .font(.system(size: 12, weight: .medium))
                        }
                        .foregroundStyle(.secondary)
                        .padding(.vertical, 4)
                        .padding(.trailing, 8)
                        .contentShape(Rectangle())
                    }
                    .buttonStyle(.borderless)
                    .focusable(false)
                    .accessibilityLabel("Close and return to rules")
                    .accessibilityIdentifier("pack-detail-close")
                }
                Spacer()
                if showBackToRules {
                    Button(action: { PackDetailWindowController.shared.closeWindow() }) {
                        Image(systemName: "xmark.circle.fill")
                            .font(.system(size: 16))
                            .foregroundStyle(.secondary)
                    }
                    .buttonStyle(.plain)
                    .focusable(false)
                    .accessibilityLabel("Close")
                    .accessibilityIdentifier("pack-detail-dismiss")
                }
            }

            HStack(alignment: .center, spacing: 16) {
                heroIcon
                VStack(alignment: .leading, spacing: 4) {
                    HStack(alignment: .firstTextBaseline, spacing: 6) {
                        Text(pack.name)
                            .font(.system(size: 20, weight: .semibold))
                        // Help button — mirrors the `?` on the Rules tab's
                        // Home Row Mods row. Only present for packs that
                        // have curated help markdown.
                        if helpResourceName != nil {
                            Button {
                                if helpResourceName != nil {
                                    showingHomeRowModsHelp = true
                                }
                            } label: {
                                Image(systemName: "questionmark.circle")
                                    .font(.system(size: 14))
                                    .foregroundStyle(.secondary)
                            }
                            .buttonStyle(.plain)
                            .focusable(false)
                            .accessibilityLabel("\(pack.name) help")
                            .accessibilityIdentifier("pack-detail-help")
                        }
                    }
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
                .tint(.accentColor)
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
    var currentConfigRow: some View {
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

    var currentConfigSummary: String? {
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
    var heroIcon: some View {
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

    /// Help markdown resource name for packs that have curated help content.
    /// Returns nil for packs without — matches the Rules tab, where only
    /// Home Row Mods surfaces a `?` button today.
    var helpResourceName: String? {
        switch pack.associatedCollectionID {
        case RuleCollectionIdentifier.homeRowMods: "home-row-mods"
        default: nil
        }
    }

    /// Live `RuleCollection` this pack is associated with. Used to hand
    /// to Rules' view components (they take the whole collection so they
    /// can render the user's latest selections, not catalog defaults).
    var liveAssociatedCollection: RuleCollection? {
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
    var associatedSingleKeyCollection: RuleCollection? {
        guard let collection = liveAssociatedCollection,
              case .singleKeyPicker = collection.configuration
        else { return nil }
        return collection
    }

    /// Collection backing an Auto Shift-style pack (enabled-keys toggles +
    /// timing slider). Matches the `.autoShiftSymbols` configuration case.
    var associatedAutoShiftCollection: RuleCollection? {
        guard let collection = liveAssociatedCollection,
              case .autoShiftSymbols = collection.configuration
        else { return nil }
        return collection
    }

    /// Collection backing a layer-preset pack (Symbol, Fun). Matches the
    /// `.layerPresetPicker` configuration case.
    var associatedLayerPresetCollection: RuleCollection? {
        guard let collection = liveAssociatedCollection,
              case .layerPresetPicker = collection.configuration
        else { return nil }
        return collection
    }

    /// Collection backing a launcher pack (Quick Launcher). Matches the
    /// `.launcherGrid` configuration case.
    var associatedLauncherCollection: RuleCollection? {
        guard let collection = liveAssociatedCollection,
              case .launcherGrid = collection.configuration
        else { return nil }
        return collection
    }

    /// Collection backing a key repeat control pack. Matches the
    /// `.keyRepeatControl` configuration case.
    var associatedKeyRepeatCollection: RuleCollection? {
        guard let collection = liveAssociatedCollection,
              case .keyRepeatControl = collection.configuration
        else { return nil }
        return collection
    }

    /// True if this pack's bindings line up with the Home Row Mods
    /// collection's input set — in which case we render that collection's
    /// interactive keyboard + modifier controls instead of the generic
    /// tap-hold picker.
    var isHomeRowModsPack: Bool {
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
    var associatedPickerConfig: TapHoldPickerConfig? {
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

    // MARK: - Description

    var descriptionBlock: some View {
        Text(pack.shortDescription)
            .font(.system(size: 13))
            .foregroundStyle(.primary)
            .fixedSize(horizontal: false, vertical: true)
            .lineSpacing(2)
    }

    // MARK: - Dependency Section

    @ViewBuilder
    var dependencySection: some View {
        let requires = pack.dependencies.filter { $0.kind == .requires }
        let enhancedBy = pack.dependencies.filter { $0.kind == .enhancedBy }
        let enhances = PackRegistry.starterKit.filter { other in
            other.id != pack.id && other.dependencies.contains { dep in
                dep.packID == pack.id
            }
        }

        if !requires.isEmpty || !enhancedBy.isEmpty || !enhances.isEmpty {
            VStack(alignment: .leading, spacing: 14) {
                // Requires
                if !requires.isEmpty {
                    dependencyGroup(
                        label: "Requires",
                        icon: "exclamationmark.circle",
                        tint: .orange,
                        items: requires.compactMap { dep in
                            PackRegistry.pack(id: dep.packID).map { ($0, dep.description) }
                        }
                    )
                }

                // Enhanced by (this pack gains features from these)
                if !enhancedBy.isEmpty {
                    dependencyGroup(
                        label: "Enhanced by",
                        icon: "sparkles",
                        tint: .blue,
                        items: enhancedBy.compactMap { dep in
                            PackRegistry.pack(id: dep.packID).map { ($0, dep.description) }
                        }
                    )
                }

                // Enhances (other packs that benefit from this one)
                if !enhances.isEmpty {
                    dependencyGroup(
                        label: "Enhances",
                        icon: "arrow.up.right",
                        tint: .green,
                        items: enhances.map { other in
                            let desc = other.dependencies
                                .first { $0.packID == pack.id }?.description ?? ""
                            return (other, desc)
                        }
                    )
                }
            }
            .padding(16)
            .background(
                RoundedRectangle(cornerRadius: 10, style: .continuous)
                    .fill(Color(NSColor.controlBackgroundColor).opacity(0.3))
            )
        }
    }

    private func dependencyGroup(
        label: String,
        icon: String,
        tint: Color,
        items: [(pack: Pack, description: String)]
    ) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            Label(label, systemImage: icon)
                .font(.system(size: 11, weight: .semibold))
                .foregroundStyle(tint)

            ForEach(items, id: \.pack.id) { item in
                Button {
                    PackDetailWindowController.shared.showWindow(
                        pack: item.pack,
                        kanataManager: kanataManager
                    )
                } label: {
                    HStack(spacing: 8) {
                        Image(systemName: item.pack.iconSymbol)
                            .font(.system(size: 11))
                            .foregroundStyle(.secondary)
                            .frame(width: 16)

                        VStack(alignment: .leading, spacing: 1) {
                            Text(item.pack.name)
                                .font(.system(size: 12, weight: .medium))
                                .foregroundStyle(.primary)
                            if !item.description.isEmpty {
                                Text(item.description)
                                    .font(.system(size: 10))
                                    .foregroundStyle(.secondary)
                                    .lineLimit(1)
                            }
                        }

                        Spacer(minLength: 0)

                        Image(systemName: "chevron.right")
                            .font(.system(size: 9, weight: .semibold))
                            .foregroundStyle(.tertiary)
                    }
                    .padding(.horizontal, 10)
                    .padding(.vertical, 8)
                    .background(
                        RoundedRectangle(cornerRadius: 6, style: .continuous)
                            .fill(Color.primary.opacity(0.04))
                    )
                    .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
            }
        }
    }

    // MARK: - Quick settings

    var quickSettingsBlock: some View {
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
    func quickSettingRow(_ setting: PackQuickSetting) -> some View {
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
}
