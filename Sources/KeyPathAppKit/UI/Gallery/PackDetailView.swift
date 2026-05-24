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
    @State var showKeystrokeHistoryConsent = false

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

    /// Local state for the embedded Chord Groups editor.
    @State var chordGroupsConfig: ChordGroupsConfig = .init()

    /// Help sheet presentation (Home Row Mods only — mirrors the Rules tab's
    /// `?` button that opens the HRM markdown help).
    @State var showingHomeRowModsHelp = false

    /// Non-nil when this pack's associated collection is managed by a
    /// different installed pack (e.g. Home Row Mods managed by Vallack).
    /// Locks the toggle and treats the collection as effectively installed.
    @State var managingPackName: String?
    @State var managingPackID: String?
    @State var showManagedAlert = false
    @State var refreshTask: Task<Void, Never>?

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            header
            ScrollView(showsIndicators: false) {
                VStack(alignment: .leading, spacing: 18) {
                    descriptionBlock
                    bindingsBlock
                    if !nonTimingQuickSettings.isEmpty {
                        quickSettingsBlock
                    }
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
        .onReceive(NotificationCenter.default.publisher(for: .installedPacksChanged)) { _ in
            debouncedRefresh()
        }
        .onReceive(NotificationCenter.default.publisher(for: .ruleCollectionsChanged)) { _ in
            debouncedRefresh()
        }
        .overlay(toastOverlay, alignment: .bottom)
        .sheet(isPresented: $showingHomeRowModsHelp) {
            MarkdownHelpSheet(resource: "home-row-mods", title: "Home Row Mods")
        }
        .sheet(isPresented: $showKeystrokeHistoryConsent) {
            KeystrokeHistoryConsentDialog(
                onConfirm: {
                    showKeystrokeHistoryConsent = false
                    toggleTask = Task { await install() }
                },
                onCancel: {
                    showKeystrokeHistoryConsent = false
                    isInstalled = false
                }
            )
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
        .alert("Part of a Pack", isPresented: $showManagedAlert) {
            if let managingPackName, let managingPackID {
                Button("Turn Off \(managingPackName)", role: .destructive) {
                    Task {
                        let manager = kanataManager.underlyingManager.ruleCollectionsManager
                        try? await PackInstaller.shared.uninstall(packID: managingPackID, manager: manager)
                        kanataManager.underlyingManager.notifyStateChanged()
                        await refreshInstallState()
                    }
                }
            }
            Button("Cancel", role: .cancel) {}
        } message: {
            if let managingPackName {
                Text("\(displayName) is part of the \(managingPackName) pack. To change it independently, turn off the pack first.")
            }
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
                                .font(.caption.weight(.semibold))
                            Text("All Rules")
                                .font(.callout.weight(.medium))
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
                            .font(.title3)
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
                        Text(displayName)
                            .font(.title2.weight(.semibold))
                        if helpResourceName != nil {
                            Button {
                                if helpResourceName != nil {
                                    showingHomeRowModsHelp = true
                                }
                            } label: {
                                Image(systemName: "questionmark.circle")
                                    .font(.body)
                                    .foregroundStyle(.secondary)
                            }
                            .buttonStyle(.plain)
                            .focusable(false)
                            .accessibilityLabel("\(displayName) help")
                            .accessibilityIdentifier("pack-detail-help")
                        }
                    }
                    if let managingPackName {
                        Button {
                            if let parentPackID = managingPackID,
                               let parentPack = PackRegistry.pack(id: parentPackID)
                            {
                                PackDetailWindowController.shared.showWindow(
                                    pack: parentPack,
                                    kanataManager: kanataManager
                                )
                            }
                        } label: {
                            Text("Part of \(managingPackName)")
                                .font(.subheadline.weight(.medium))
                                .foregroundStyle(.white)
                                .padding(.horizontal, 8)
                                .padding(.vertical, 3)
                                .background(Capsule().fill(Color.accentColor))
                        }
                        .buttonStyle(.plain)
                        .onHover { hovering in
                            if hovering { NSCursor.pointingHand.push() } else { NSCursor.pop() }
                        }
                    }
                    Text(pack.tagline)
                        .font(.body)
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
                .disabled(isWorking || managingPackName != nil)
                .overlay {
                    if managingPackName != nil {
                        Color.clear
                            .contentShape(Rectangle())
                            .onTapGesture { showManagedAlert = true }
                    }
                }
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
                    .font(.caption)
                    .foregroundStyle(Color.accentColor)
                Text(summary)
                    .font(.subheadline.weight(.medium))
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
                        .font(.title.weight(.semibold))
                        .foregroundStyle(.tint)
                        .symbolRenderingMode(.hierarchical)
                    Image(systemName: "arrow.right")
                        .font(.caption2.weight(.semibold))
                        .foregroundStyle(.secondary)
                    Image(systemName: secondary)
                        .font(.title.weight(.semibold))
                        .foregroundStyle(.tint)
                        .symbolRenderingMode(.hierarchical)
                }
            } else {
                Image(systemName: pack.iconSymbol)
                    .font(.largeTitle.weight(.semibold))
                    .foregroundStyle(.tint)
                    .symbolRenderingMode(.hierarchical)
            }
        }
    }

    var displayName: String {
        if managingPackName != nil,
           pack.associatedCollectionID == RuleCollectionIdentifier.homeRowMods,
           TypingFeelMapping.usesTopRow(homeRowModsConfig.enabledKeys)
        {
            return "Top Row Mods"
        }
        return pack.name
    }

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

    func liveCollection(for id: UUID) -> RuleCollection? {
        let live = kanataManager.underlyingManager
            .ruleCollectionsManager.ruleCollections
            .first { $0.id == id }
        if let live { return live }
        return RuleCollectionCatalog().defaultCollections()
            .first { $0.id == id }
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

    /// Collection backing the Home Row Arrows pack specifically.
    var associatedHomeRowArrowsCollection: RuleCollection? {
        guard let collection = liveAssociatedCollection,
              collection.id == RuleCollectionIdentifier.homeRowArrows,
              case .layerPresetPicker = collection.configuration
        else { return nil }
        return collection
    }

    /// Collection backing a layer-preset pack (Symbol, Fun). Matches the
    /// `.layerPresetPicker` configuration case.
    var associatedLayerPresetCollection: RuleCollection? {
        guard let collection = liveAssociatedCollection,
              collection.id != RuleCollectionIdentifier.homeRowArrows,
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

    /// Collection backing a chord groups pack. Matches the
    /// `.chordGroups` configuration case.
    var associatedChordGroupsCollection: RuleCollection? {
        guard let collection = liveAssociatedCollection,
              case .chordGroups = collection.configuration
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
            .font(.body)
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
                .font(.subheadline.weight(.semibold))
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
                            .font(.subheadline)
                            .foregroundStyle(.secondary)
                            .frame(width: 16)

                        VStack(alignment: .leading, spacing: 1) {
                            Text(item.pack.name)
                                .font(.callout.weight(.medium))
                                .foregroundStyle(.primary)
                            if !item.description.isEmpty {
                                Text(item.description)
                                    .font(.caption)
                                    .foregroundStyle(.secondary)
                                    .lineLimit(1)
                            }
                        }

                        Spacer(minLength: 0)

                        Image(systemName: "chevron.right")
                            .font(.caption2.weight(.semibold))
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

    private var nonTimingQuickSettings: [PackQuickSetting] {
        pack.quickSettings.filter { $0.id != "holdTimeout" || !isHomeRowModsPack }
    }

    var quickSettingsBlock: some View {
        VStack(alignment: .leading, spacing: 10) {
            ForEach(nonTimingQuickSettings) { setting in
                quickSettingRow(setting)
            }
        }
    }

    private func settingRange(_ s: PackQuickSetting) -> ClosedRange<Double> {
        if case let .slider(_, min: lo, max: hi, step: _, unitSuffix: _) = s.kind {
            return Double(lo)...Double(hi)
        }
        return 0...100
    }

    private func settingStep(_ s: PackQuickSetting) -> Double {
        if case let .slider(_, min: _, max: _, step: step, unitSuffix: _) = s.kind {
            return Double(step)
        }
        return 1
    }

    private func settingSuffix(_ s: PackQuickSetting) -> String {
        if case let .slider(_, min: _, max: _, step: _, unitSuffix: suffix) = s.kind {
            return suffix
        }
        return ""
    }

    @ViewBuilder
    func quickSettingRow(_ setting: PackQuickSetting) -> some View {
        switch setting.kind {
        case let .slider(_, min: lo, max: hi, step: step, unitSuffix: suffix):
            HStack(spacing: 8) {
                Text(setting.label)
                    .font(.callout)
                Slider(
                    value: sliderBinding(for: setting.id),
                    in: Double(lo) ... Double(hi),
                    step: Double(step)
                )
                .frame(maxWidth: 200)
                .accessibilityLabel(setting.label)
                .accessibilityValue("\(quickSettingValues[setting.id] ?? 0)\(suffix)")
                Text("\(quickSettingValues[setting.id] ?? 0)\(suffix)")
                    .font(.subheadline.monospaced())
                    .foregroundStyle(.secondary)
                    .frame(width: 50, alignment: .trailing)
            }
        }
    }
}
