import KeyPathCore
import SwiftUI

#if os(macOS)
    import AppKit
#endif

/// Helper view for home row key button - extracted to reduce view body complexity
private struct HomeRowKeyButton: View {
    let key: String
    let modSymbol: String
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            HomeRowKeyChipSmall(letter: key.uppercased(), symbol: modSymbol)
        }
        .buttonStyle(.plain)
        .accessibilityIdentifier("rules-summary-home-row-key-button-\(key)")
        .accessibilityLabel("Customize \(key.uppercased()) key")
    }
}

/// State for home row mods editing modal
struct HomeRowModsEditState: Identifiable {
    let id = UUID()
    let collection: RuleCollection
    let selectedKey: String?
}

/// State for home row layer toggles editing modal
struct HomeRowLayerTogglesEditState: Identifiable {
    let id = UUID()
    let collection: RuleCollection
    let selectedKey: String?
}

/// State for chord groups editing modal
struct ChordGroupsEditState: Identifiable {
    let id = UUID()
    let collection: RuleCollection
}

/// State for sequences editing modal
struct SequencesEditState: Identifiable {
    let id = UUID()
    let collection: RuleCollection
}

// MARK: - Toast View (shared with ContentView)

private struct ToastView: View {
    let message: String
    let type: KanataViewModel.ToastType

    var body: some View {
        HStack(spacing: 8) {
            Image(systemName: iconName)
                .foregroundColor(iconColor)

            Text(message)
                .font(.body)
                .foregroundColor(.primary)
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 12)
        .background(
            RoundedRectangle(cornerRadius: 8)
                .fill(Color(NSColor.controlBackgroundColor))
                .shadow(color: .black.opacity(0.2), radius: 8, x: 0, y: 4)
        )
    }

    private var iconName: String {
        switch type {
        case .success: "checkmark.circle.fill"
        case .error: "exclamationmark.triangle.fill"
        case .info: "info.circle.fill"
        case .warning: "exclamationmark.triangle.fill"
        }
    }

    private var iconColor: Color {
        switch type {
        case .success: .green
        case .error: .red
        case .info: .blue
        case .warning: .orange
        }
    }
}

struct RulesTabView: View {
    @EnvironmentObject var kanataManager: KanataViewModel
    @State private var showingResetConfirmation = false
    @State private var showingNewRuleSheet = false
    @State private var settingsToastManager = WizardToastManager()
    @State private var createButtonHovered = false
    /// Stable sort order captured when view appears (enabled collections first)
    @State private var stableSortOrder: [UUID] = []
    /// Track pending selections for immediate UI feedback (before backend confirms)
    @State private var pendingSelections: [UUID: String] = [:]
    /// Track pending toggle states for immediate UI feedback
    @State private var pendingToggles: [UUID: Bool] = [:]
    @State private var homeRowModsEditState: HomeRowModsEditState?
    @State private var homeRowLayerTogglesEditState: HomeRowLayerTogglesEditState?
    @State private var chordGroupsEditState: ChordGroupsEditState?
    @State private var sequencesEditState: SequencesEditState?
    @State private var appKeymaps: [AppKeymap] = []
    private let catalog = RuleCollectionCatalog()

    /// Total count of custom rules (everywhere + app-specific)
    private var totalCustomRulesCount: Int {
        kanataManager.customRules.count + appKeymaps.flatMap(\.overrides).count
    }

    /// Whether there are any custom rules (everywhere or app-specific)
    private var hasAnyCustomRules: Bool {
        !kanataManager.customRules.isEmpty || !appKeymaps.isEmpty
    }

    // Show all catalog collections, merging with existing state
    private var allCollections: [RuleCollection] {
        let catalog = RuleCollectionCatalog()
        return catalog.defaultCollections().map { catalogCollection in
            // Find matching collection from kanataManager to preserve enabled state
            if let existing = kanataManager.ruleCollections.first(where: { $0.id == catalogCollection.id }) {
                return existing
            }
            // Return catalog item with its default enabled state
            return catalogCollection
        }
    }

    /// Collections sorted by stable order (enabled first, captured on view appear)
    private var sortedCollections: [RuleCollection] {
        guard !stableSortOrder.isEmpty else { return allCollections }
        return allCollections.sorted { a, b in
            guard let indexA = stableSortOrder.firstIndex(of: a.id),
                  let indexB = stableSortOrder.firstIndex(of: b.id)
            else {
                return false
            }
            return indexA < indexB
        }
    }

    /// Compute sort order: enabled collections first, then disabled
    private func computeSortOrder() -> [UUID] {
        let enabled = allCollections.filter(\.isEnabled).map(\.id)
        let disabled = allCollections.filter { !$0.isEnabled }.map(\.id)
        return enabled + disabled
    }

    private var customRulesTitle: String {
        "Custom Rules"
    }

    /// Helper to build a collection row - extracted to simplify type-checking
    @ViewBuilder
    private func collectionRow(for collection: RuleCollection, scrollProxy: ScrollViewProxy) -> some View {
        let style = collection.displayStyle
        let isSpecializedTable = style == .table && (
            collection.id == RuleCollectionIdentifier.numpadLayer ||
                collection.id == RuleCollectionIdentifier.vimNavigation ||
                collection.id == RuleCollectionIdentifier.windowSnapping ||
                collection.id == RuleCollectionIdentifier.macFunctionKeys
        )
        let needsCollection = style == .singleKeyPicker || style == .homeRowMods || style == .tapHoldPicker || style == .layerPresetPicker || style == .launcherGrid || isSpecializedTable

        ExpandableCollectionRow(
            collectionId: collection.id.uuidString,
            name: dynamicCollectionName(for: collection),
            icon: collection.icon ?? "circle",
            count: style == .singleKeyPicker || style == .tapHoldPicker ? 1 :
                (style == .layerPresetPicker ? (collection.configuration.layerPresetPickerConfig?.selectedMappings.count ?? 0) : collection.mappings.count),
            isEnabled: pendingToggles[collection.id] ?? collection.isEnabled,
            mappings: collection.mappings.map {
                ($0.input, $0.output, $0.shiftedOutput, $0.ctrlOutput, $0.description, $0.sectionBreak, collection.isEnabled, $0.id, nil)
            },
            onToggle: { isOn in
                pendingToggles[collection.id] = isOn
                if !isOn {
                    pendingSelections.removeValue(forKey: collection.id)
                }
                // Toggle collection directly (welcome dialog moved to drawer's launcher tab)
                Task { await kanataManager.toggleRuleCollection(collection.id, enabled: isOn) }
            },
            onEditMapping: nil,
            onDeleteMapping: nil,
            description: dynamicCollectionDescription(for: collection),
            layerActivator: collection.momentaryActivator,
            leaderKeyDisplay: currentLeaderKeyDisplay,
            activationHint: dynamicActivationHint(for: collection),
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
                Task { await kanataManager.updateHomeRowModsConfig(collectionId: collection.id, config: config) }
            } : nil,
            onOpenHomeRowModsModal: style == .homeRowMods ? {
                homeRowModsEditState = HomeRowModsEditState(collection: collection, selectedKey: nil)
            } : nil,
            onOpenHomeRowModsModalWithKey: style == .homeRowMods ? { key in
                homeRowModsEditState = HomeRowModsEditState(collection: collection, selectedKey: key)
            } : nil,
            onUpdateHomeRowLayerTogglesConfig: style == .homeRowLayerToggles ? { config in
                Task { await kanataManager.updateHomeRowLayerTogglesConfig(collectionId: collection.id, config: config) }
            } : nil,
            onOpenHomeRowLayerTogglesModal: style == .homeRowLayerToggles ? {
                homeRowLayerTogglesEditState = HomeRowLayerTogglesEditState(collection: collection, selectedKey: nil)
            } : nil,
            onOpenHomeRowLayerTogglesModalWithKey: style == .homeRowLayerToggles ? { key in
                homeRowLayerTogglesEditState = HomeRowLayerTogglesEditState(collection: collection, selectedKey: key)
            } : nil,
            onUpdateChordGroupsConfig: style == .chordGroups ? { config in
                Task { await kanataManager.updateChordGroupsConfig(collectionId: collection.id, config: config) }
            } : nil,
            onOpenChordGroupsModal: style == .chordGroups ? {
                chordGroupsEditState = ChordGroupsEditState(collection: collection)
            } : nil,
            onUpdateSequencesConfig: style == .sequences ? { config in
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
            onSelectFunctionKeyMode: collection.id == RuleCollectionIdentifier.macFunctionKeys ? { mode in
                Task { await kanataManager.updateFunctionKeyMode(collection.id, mode: mode) }
            } : nil,
            onLauncherConfigChanged: collection.id == RuleCollectionIdentifier.launcher ? { config in
                Task { await kanataManager.updateLauncherConfig(collection.id, config: config) }
            } : nil,
            scrollID: "collection-\(collection.id.uuidString)",
            scrollProxy: scrollProxy
        )
    }

    var body: some View {
        VStack(spacing: 0) {
            // Top Action Bar
            HStack(spacing: 12) {
                Button {
                    // Close settings and open overlay with mapper tab
                    NotificationCenter.default.post(name: .openOverlayWithMapper, object: nil)
                } label: {
                    Label("Create Rule", systemImage: "plus.circle.fill")
                }
                .buttonStyle(.borderedProminent)
                .controlSize(.large)
                .accessibilityIdentifier("rules-create-button")
                .accessibilityLabel("Create Rule")

                Spacer()

                Button(action: { openConfigInEditor() }) {
                    Label("Edit Config", systemImage: "doc.text")
                }
                .buttonStyle(.bordered)
                .controlSize(.large)
                .accessibilityIdentifier("rules-edit-config-button")
                .accessibilityLabel("Edit Config")

                Button(action: { showingResetConfirmation = true }) {
                    Label("Reset", systemImage: "arrow.counterclockwise")
                }
                .buttonStyle(.bordered)
                .controlSize(.large)
                .tint(.red)
                .accessibilityIdentifier("rules-reset-button")
                .accessibilityLabel("Reset Rules")
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 12)
            .background(Color(NSColor.controlBackgroundColor).opacity(0.3))

            Divider()

            // Rules List
            ScrollViewReader { scrollProxy in
                ScrollView {
                    VStack(spacing: 0) {
                        // Custom Rules Section (toggleable, expanded when has rules)
                        ExpandableCollectionRow(
                            collectionId: "custom-rules",
                            name: customRulesTitle,
                            icon: "square.and.pencil",
                            count: totalCustomRulesCount,
                            isEnabled: kanataManager.customRules.isEmpty
                                || kanataManager.customRules.allSatisfy(\.isEnabled),
                            mappings: kanataManager.customRules.map { ($0.input, $0.output, nil, nil, $0.title.isEmpty ? nil : $0.title, false, $0.isEnabled, $0.id, $0.behavior) },
                            appKeymaps: appKeymaps,
                            onToggle: { isOn in
                                Task {
                                    for rule in kanataManager.customRules {
                                        await kanataManager.toggleCustomRule(rule.id, enabled: isOn)
                                    }
                                }
                            },
                            onEditMapping: { id in
                                // Open overlay with mapper tab and preset values for editing
                                if let rule = kanataManager.customRules.first(where: { $0.id == id }) {
                                    NotificationCenter.default.post(
                                        name: .openOverlayWithMapperPreset,
                                        object: nil,
                                        userInfo: ["inputKey": rule.input, "outputKey": rule.output]
                                    )
                                }
                            },
                            onDeleteMapping: { id in
                                Task { await kanataManager.removeCustomRule(id) }
                            },
                            onDeleteAppRule: { keymap, override in
                                deleteAppRule(keymap: keymap, override: override)
                            },
                            onEditAppRule: { keymap, override in
                                // Open overlay with mapper tab and preset values for editing app-specific rule
                                NotificationCenter.default.post(
                                    name: .openOverlayWithMapperPreset,
                                    object: nil,
                                    userInfo: [
                                        "inputKey": override.inputKey,
                                        "outputKey": override.outputAction,
                                        "appBundleId": keymap.mapping.bundleIdentifier,
                                        "appDisplayName": keymap.mapping.displayName
                                    ]
                                )
                            },
                            showZeroState: !hasAnyCustomRules,
                            onCreateFirstRule: {
                                // Close settings and open overlay with mapper tab
                                NotificationCenter.default.post(name: .openOverlayWithMapper, object: nil)
                            },
                            description: "Remap any key combination or sequence",
                            defaultExpanded: false,
                            scrollID: "custom-rules",
                            scrollProxy: scrollProxy
                        )
                        // Force SwiftUI to re-render when customRules or appKeymaps change
                        .id(
                            "custom-rules-\(kanataManager.customRules.map { "\($0.id)-\($0.input.hashValue)-\($0.output.hashValue)-\($0.title.hashValue)" }.joined())-\(appKeymaps.map(\.id.uuidString).joined())"
                        )
                        .padding(.vertical, 4)

                        // Collection Rows (sorted: enabled first, order stable during session)
                        ForEach(sortedCollections) { collection in
                            collectionRow(for: collection, scrollProxy: scrollProxy)
                                .id("collection-\(collection.id.uuidString)")
                                .padding(.vertical, 4)
                        }
                    }
                    .padding(.vertical, 12)
                    .padding(.horizontal, 12)
                }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
        }
        .frame(maxHeight: 500)
        .settingsBackground()
        .withToasts(settingsToastManager)
        .overlay(alignment: .top) {
            if let toastMessage = kanataManager.toastMessage {
                ToastView(message: toastMessage, type: kanataManager.toastType)
                    .padding(.top, 16)
                    .padding(.horizontal, 20)
                    .transition(.move(edge: .top).combined(with: .opacity))
                    .zIndex(1000)
            }
        }
        .animation(.spring(response: 0.3, dampingFraction: 0.8), value: kanataManager.toastMessage)
        .onAppear {
            // Capture sort order once when view appears (enabled first, then disabled)
            // This ensures stable layout - toggling a rule won't move it until window reopens
            if stableSortOrder.isEmpty {
                stableSortOrder = computeSortOrder()
            }
            // Load app-specific keymaps
            loadAppKeymaps()
        }
        .onReceive(NotificationCenter.default.publisher(for: .appKeymapsDidChange)) { _ in
            loadAppKeymaps()
        }
        .sheet(item: $homeRowModsEditState) { editState in
            HomeRowModsModalView(
                config: Binding(
                    get: { editState.collection.configuration.homeRowModsConfig ?? HomeRowModsConfig() },
                    set: { _ in }
                ),
                onSave: { newConfig in
                    Task {
                        await kanataManager.updateHomeRowModsConfig(collectionId: editState.collection.id, config: newConfig)
                    }
                    homeRowModsEditState = nil
                },
                onCancel: {
                    homeRowModsEditState = nil
                },
                initialSelectedKey: editState.selectedKey
            )
        }
        .sheet(item: $homeRowLayerTogglesEditState) { editState in
            HomeRowLayerTogglesModalView(
                config: Binding(
                    get: { editState.collection.configuration.homeRowLayerTogglesConfig ?? HomeRowLayerTogglesConfig() },
                    set: { _ in }
                ),
                onSave: { newConfig in
                    Task {
                        await kanataManager.updateHomeRowLayerTogglesConfig(collectionId: editState.collection.id, config: newConfig)
                    }
                    homeRowLayerTogglesEditState = nil
                },
                onCancel: {
                    homeRowLayerTogglesEditState = nil
                },
                initialSelectedKey: editState.selectedKey
            )
        }
        .sheet(item: $chordGroupsEditState) { editState in
            ChordGroupsModalView(
                config: Binding(
                    get: { editState.collection.configuration.chordGroupsConfig ?? ChordGroupsConfig() },
                    set: { _ in }
                ),
                onSave: { newConfig in
                    Task {
                        await kanataManager.updateChordGroupsConfig(collectionId: editState.collection.id, config: newConfig)
                    }
                    chordGroupsEditState = nil
                },
                onCancel: {
                    chordGroupsEditState = nil
                }
            )
        }
        .sheet(item: $sequencesEditState) { editState in
            SequencesModalView(
                config: Binding(
                    get: { editState.collection.configuration.sequencesConfig ?? SequencesConfig() },
                    set: { _ in }
                ),
                onSave: { newConfig in
                    Task {
                        await kanataManager.updateSequencesConfig(collectionId: editState.collection.id, config: newConfig)
                    }
                    sequencesEditState = nil
                },
                onCancel: {
                    sequencesEditState = nil
                }
            )
        }
        .sheet(isPresented: $kanataManager.showRuleConflictDialog) {
            if let context = kanataManager.pendingRuleConflict {
                RuleConflictResolutionDialog(
                    context: context,
                    onChoice: { choice in
                        kanataManager.resolveRuleConflict(with: choice)
                    },
                    onCancel: {
                        kanataManager.resolveRuleConflict(with: nil)
                    }
                )
                .interactiveDismissDisabled()
            }
        }
        .alert("Reset Configuration?", isPresented: $showingResetConfirmation) {
            Button("Cancel", role: .cancel) {}
            Button("Open Backups Folder") {
                openBackupsFolder()
            }
            Button("Reset", role: .destructive) {
                resetToDefaultConfig()
            }
        } message: {
            Text(
                """
                This will reset your configuration to macOS Function Keys only (all custom rules removed).
                A safety backup will be stored in ~/.config/keypath/.backups.
                """)
        }
    }

    /// Get the current leader key value (from the Leader Key collection or default to Space)
    private var currentLeaderKey: String {
        // Check pending toggle first - if toggled OFF, default to space
        if let pendingToggle = pendingToggles[RuleCollectionIdentifier.leaderKey], !pendingToggle {
            return "space"
        }

        // Check pending selection (immediate UI feedback)
        if let pending = pendingSelections[RuleCollectionIdentifier.leaderKey] {
            return pending
        }

        // Find the Leader Key collection
        if let leaderCollection = allCollections.first(where: { $0.id == RuleCollectionIdentifier.leaderKey }) {
            // Check pending toggle for enabled state
            let isEnabled = pendingToggles[RuleCollectionIdentifier.leaderKey] ?? leaderCollection.isEnabled
            if isEnabled, let selectedOutput = leaderCollection.configuration.singleKeyPickerConfig?.selectedOutput {
                return selectedOutput
            }
        }

        // Default to space when leader key is off or not set
        return "space"
    }

    /// Format leader key for display in activator hints
    private var currentLeaderKeyDisplay: String {
        formatKeyWithSymbol(currentLeaderKey)
    }

    /// Generate a dynamic description for collections
    /// For tapHoldPicker: returns the collection summary (tap/hold config shown as activation hint)
    /// For launcherGrid: returns dynamic description based on activation mode
    private func dynamicCollectionDescription(for collection: RuleCollection) -> String {
        // Handle launcher grid configurations
        if case .launcherGrid = collection.configuration {
            return dynamicLauncherDescription(for: collection)
        }

        // For tapHoldPicker, always return the summary - the tap/hold config is shown as activation hint
        return collection.summary
    }

    /// Generate a dynamic activation hint for tap-hold picker collections showing the current config
    private func dynamicTapHoldActivationHint(for collection: RuleCollection) -> String? {
        guard case let .tapHoldPicker(config) = collection.configuration else {
            return nil
        }

        // Get the selected tap and hold outputs from config
        let tapOutput = config.selectedTapOutput ?? config.tapOptions.first?.output ?? "hyper"
        let holdOutput = config.selectedHoldOutput ?? config.holdOptions.first?.output ?? "hyper"

        // Find labels for the outputs
        let tapLabel = config.tapOptions.first { $0.output == tapOutput }?.label ?? tapOutput
        let holdLabel = config.holdOptions.first { $0.output == holdOutput }?.label ?? holdOutput

        return "Tap: \(tapLabel), Hold: \(holdLabel)"
    }

    /// Generate a dynamic description for launcher collections showing the current activation mode
    private func dynamicLauncherDescription(for collection: RuleCollection) -> String {
        guard case let .launcherGrid(config) = collection.configuration else {
            return collection.summary
        }

        switch config.activationMode {
        case .holdHyper:
            switch config.hyperTriggerMode {
            case .hold:
                return "Hold Hyper to quickly launch apps and websites with keyboard shortcuts."
            case .tap:
                return "Tap Hyper to toggle the launcher on/off. Then press a shortcut key."
            }
        case .leaderSequence:
            return "Press \(currentLeaderKeyDisplay) → L to activate the launcher layer."
        }
    }

    /// Generate a dynamic activation hint for launcher collections showing the current activation mode
    private func dynamicLauncherActivationHint(for collection: RuleCollection) -> String {
        guard case let .launcherGrid(config) = collection.configuration else {
            return collection.activationHint ?? "Hold Hyper key"
        }

        switch config.activationMode {
        case .holdHyper:
            switch config.hyperTriggerMode {
            case .hold:
                return "Hold Hyper key"
            case .tap:
                return "Tap Hyper key"
            }
        case .leaderSequence:
            return "\(currentLeaderKeyDisplay) → L"
        }
    }

    /// Get the activation hint for a collection - dynamic for launcher and tapHoldPicker
    private func dynamicActivationHint(for collection: RuleCollection) -> String? {
        // Handle launcher grid configurations dynamically
        if case .launcherGrid = collection.configuration {
            return dynamicLauncherActivationHint(for: collection)
        }
        // Handle tap-hold picker configurations dynamically
        if case .tapHoldPicker = collection.configuration {
            return dynamicTapHoldActivationHint(for: collection)
        }
        // All other collections use static activation hint
        return collection.activationHint
    }

    /// Generate a dynamic name for picker-style collections that shows the current mapping
    private func dynamicCollectionName(for collection: RuleCollection) -> String {
        // Use type-safe configuration pattern
        guard case let .singleKeyPicker(config) = collection.configuration else {
            return collection.name
        }

        // Format input key with Mac symbol
        let inputDisplay = formatKeyWithSymbol(config.inputKey)

        // Check for pending toggle first, then pending selection, then actual state
        let effectiveEnabled: Bool = if let pendingToggle = pendingToggles[collection.id] {
            pendingToggle
        } else {
            collection.isEnabled
        }

        // If collection is OFF, show "→ ?"
        guard effectiveEnabled else {
            // For leader-based rules, show "Leader + [key] → ?"
            if collection.momentaryActivator != nil {
                return "\(currentLeaderKeyDisplay) + \(inputDisplay) → ?"
            }
            return "\(inputDisplay) → ?"
        }

        // Check for pending selection (immediate UI feedback)
        let effectiveOutput: String = if let pending = pendingSelections[collection.id] {
            pending
        } else {
            config.selectedOutput ?? config.presetOptions.first?.output ?? ""
        }

        // Get label for the output
        let outputLabel = config.presetOptions.first { $0.output == effectiveOutput }?.label ?? effectiveOutput

        // For leader-based rules, show "Leader + [input] → [output]" instead of "[input] → [output]"
        if collection.momentaryActivator != nil {
            return "\(currentLeaderKeyDisplay) + \(inputDisplay) → \(outputLabel)"
        }

        return "\(inputDisplay) → \(outputLabel)"
    }

    /// Format a modifier key for display
    private func formatModifierForDisplay(_ modifier: String) -> String {
        let displayNames: [String: String] = [
            "lmet": "⌘", "rmet": "⌘",
            "lalt": "⌥", "ralt": "⌥",
            "lctl": "⌃", "rctl": "⌃",
            "lsft": "⇧", "rsft": "⇧"
        ]
        return displayNames[modifier] ?? modifier
    }

    /// Format a key name with its Mac symbol
    private func formatKeyWithSymbol(_ key: String) -> String {
        let keySymbols: [String: String] = [
            "caps": "⇪ Caps Lock",
            "leader": "Leader",
            "lmet": "⌘ Command",
            "rmet": "⌘ Command",
            "lalt": "⌥ Option",
            "ralt": "⌥ Option",
            "lctl": "⌃ Control",
            "rctl": "⌃ Control",
            "lsft": "⇧ Shift",
            "rsft": "⇧ Shift",
            "esc": "⎋ Escape",
            "tab": "⇥ Tab",
            "ret": "↩ Return",
            "spc": "␣ Space",
            "space": "␣ Space",
            "bspc": "⌫ Delete",
            "del": "⌦ Forward Delete"
        ]
        return keySymbols[key.lowercased()] ?? key.capitalized
    }

    private func openConfigInEditor() {
        let url = URL(fileURLWithPath: kanataManager.configPath)
        openFileInPreferredEditor(url)
    }

    private func openBackupsFolder() {
        let backupsPath = "\(NSHomeDirectory())/.config/keypath/.backups"
        NSWorkspace.shared.selectFile(nil, inFileViewerRootedAtPath: backupsPath)
    }

    private func resetToDefaultConfig() {
        Task {
            do {
                try await kanataManager.resetToDefaultConfig()
                // Clear all pending UI state so toggles reflect actual reset state
                pendingToggles.removeAll()
                pendingSelections.removeAll()
                // Recompute sort order to reflect new enabled/disabled state
                stableSortOrder = computeSortOrder()
                settingsToastManager.showSuccess("Configuration reset to default")
            } catch {
                settingsToastManager.showError("Reset failed: \(error.localizedDescription)")
            }
        }
    }

    // MARK: - App Keymaps Helpers

    private func loadAppKeymaps() {
        Task {
            let keymaps = await AppKeymapStore.shared.loadKeymaps()
            await MainActor.run {
                appKeymaps = keymaps.sorted { $0.mapping.displayName < $1.mapping.displayName }
            }
        }
    }

    private func deleteAppRule(keymap: AppKeymap, override: AppKeyOverride) {
        Task {
            var updatedKeymap = keymap
            updatedKeymap.overrides.removeAll { $0.id == override.id }

            do {
                if updatedKeymap.overrides.isEmpty {
                    try await AppKeymapStore.shared.removeKeymap(bundleIdentifier: keymap.mapping.bundleIdentifier)
                } else {
                    try await AppKeymapStore.shared.upsertKeymap(updatedKeymap)
                }

                try await AppConfigGenerator.regenerateFromStore()
                await AppContextService.shared.reloadMappings()
                _ = await kanataManager.underlyingManager.restartKanata(reason: "App rule deleted from Settings")
            } catch {
                AppLogger.shared.log("⚠️ [RulesTabView] Failed to delete app rule: \(error)")
            }
        }
    }
}

// MARK: - Expandable Collection Row

private struct ExpandableCollectionRow: View {
    let collectionId: String
    let name: String
    let icon: String
    let count: Int
    let isEnabled: Bool
    let mappings: [(input: String, output: String, shiftedOutput: String?, ctrlOutput: String?, description: String?, sectionBreak: Bool, enabled: Bool, id: UUID, behavior: MappingBehavior?)]
    var appKeymaps: [AppKeymap] = []
    let onToggle: (Bool) -> Void
    let onEditMapping: ((UUID) -> Void)?
    let onDeleteMapping: ((UUID) -> Void)?
    var onDeleteAppRule: ((AppKeymap, AppKeyOverride) -> Void)?
    var onEditAppRule: ((AppKeymap, AppKeyOverride) -> Void)?
    var showZeroState: Bool = false
    var onCreateFirstRule: (() -> Void)?
    var description: String?
    var layerActivator: MomentaryActivator?
    /// Current leader key display name for layer-based collections
    var leaderKeyDisplay: String = "␣ Space"
    /// Optional activation hint from collection (overrides default formatting)
    var activationHint: String?
    var defaultExpanded: Bool = false
    var displayStyle: RuleCollectionDisplayStyle = .list
    /// For singleKeyPicker style: the full collection with presets
    var collection: RuleCollection?
    var onSelectOutput: ((String) -> Void)?
    /// For tapHoldPicker style: callback to select tap output
    var onSelectTapOutput: ((String) -> Void)?
    /// For tapHoldPicker style: callback to select hold output
    var onSelectHoldOutput: ((String) -> Void)?
    /// For homeRowMods style: callback to update config
    var onUpdateHomeRowModsConfig: ((HomeRowModsConfig) -> Void)?
    /// For homeRowMods style: callback to open modal
    var onOpenHomeRowModsModal: (() -> Void)?
    /// For homeRowMods style: callback to open modal with a specific key selected
    var onOpenHomeRowModsModalWithKey: ((String) -> Void)?
    /// For homeRowLayerToggles style: callback to update config
    var onUpdateHomeRowLayerTogglesConfig: ((HomeRowLayerTogglesConfig) -> Void)?
    /// For homeRowLayerToggles style: callback to open modal
    var onOpenHomeRowLayerTogglesModal: (() -> Void)?
    /// For homeRowLayerToggles style: callback to open modal with a specific key selected
    var onOpenHomeRowLayerTogglesModalWithKey: ((String) -> Void)?
    /// For chordGroups style: callback to update config
    var onUpdateChordGroupsConfig: ((ChordGroupsConfig) -> Void)?
    /// For chordGroups style: callback to open modal
    var onOpenChordGroupsModal: (() -> Void)?
    /// For sequences style: callback to update config
    var onUpdateSequencesConfig: ((SequencesConfig) -> Void)?
    /// For sequences style: callback to open modal
    var onOpenSequencesModal: (() -> Void)?
    /// For layerPresetPicker style: callback to select a layer preset
    var onSelectLayerPreset: ((String) -> Void)?
    /// For windowSnapping: callback to change key convention
    var onSelectWindowConvention: ((WindowKeyConvention) -> Void)?
    /// For functionKeys: callback to change mode (media keys vs function keys)
    var onSelectFunctionKeyMode: ((FunctionKeyMode) -> Void)?
    /// For launcherGrid: callback to update launcher config
    var onLauncherConfigChanged: ((LauncherGridConfig) -> Void)?
    /// Unique ID for scroll-to behavior
    var scrollID: String?
    /// Scroll proxy for auto-scrolling when expanded
    var scrollProxy: ScrollViewProxy?
    /// Optional transparent-mode toggle (used by Vim collection)
    @State private var isExpanded = false
    @State private var isHovered = false
    @State private var hasInitialized = false
    @State private var localEnabled: Bool? // Optimistic local state for instant toggle feedback

    /// Effective enabled state: use local optimistic value if set, otherwise parent value
    private var effectiveEnabled: Bool {
        localEnabled ?? isEnabled
    }

    /// Format a modifier key for display
    private func formatModifierForDisplay(_ modifier: String) -> String {
        let displayNames: [String: String] = [
            "lmet": "⌘", "rmet": "⌘",
            "lalt": "⌥", "ralt": "⌥",
            "lctl": "⌃", "rctl": "⌃",
            "lsft": "⇧", "rsft": "⇧"
        ]
        return displayNames[modifier] ?? modifier
    }

    var body: some View {
        mainContent
    }

    @ViewBuilder
    private var mainContent: some View {
        VStack(alignment: .leading, spacing: 0) {
            scrollAnchorView
            headerButtonView
            expandedContentView
        }
        .background(
            RoundedRectangle(cornerRadius: 10)
                .fill(isHovered ? Color(NSColor.controlBackgroundColor).opacity(0.5) : Color(NSColor.windowBackgroundColor))
        )
        .overlay(
            RoundedRectangle(cornerRadius: 10)
                .stroke(Color.white.opacity(isHovered ? 0.15 : 0), lineWidth: 1)
        )
        .onHover { hovering in
            isHovered = hovering
            if hovering {
                NSCursor.pointingHand.push()
            } else {
                NSCursor.pop()
            }
        }
        .onAppear {
            if !hasInitialized {
                isExpanded = defaultExpanded
                hasInitialized = true
            }
        }
        .onChange(of: defaultExpanded) { _, newValue in
            if newValue, !isExpanded {
                withAnimation(.easeInOut(duration: 0.2)) {
                    isExpanded = true
                }
            }
        }
        .onChange(of: isEnabled) { _, _ in
            localEnabled = nil
        }
    }

    @ViewBuilder
    private var scrollAnchorView: some View {
        if let id = scrollID {
            Color.clear
                .frame(height: 0)
                .id(id)
        }
    }

    @ViewBuilder
    private var headerButtonView: some View {
        Button {
            withAnimation(.easeInOut(duration: 0.2)) {
                isExpanded.toggle()
                // Auto-scroll to show expanded content
                if isExpanded, let id = scrollID, let proxy = scrollProxy {
                    // Delay slightly to allow expansion animation to begin
                    DispatchQueue.main.asyncAfter(deadline: .now() + 0.1) {
                        withAnimation(.easeInOut(duration: 0.3)) {
                            proxy.scrollTo(id, anchor: .top)
                        }
                    }
                }
            }
        } label: {
            HStack(alignment: .top, spacing: 12) {
                iconView(for: icon)
                    .frame(width: 24)

                VStack(alignment: .leading, spacing: 2) {
                    HStack(spacing: 4) {
                        Text(name)
                            .font(.headline)
                            .foregroundColor(.primary)
                        if count > 0, showZeroState || onEditMapping != nil {
                            // Show count for custom rules section only
                            Text("(\(count))")
                                .font(.headline)
                                .fontWeight(.regular)
                                .foregroundColor(.secondary)
                        }
                    }

                    if let desc = description {
                        Text(desc)
                            .font(.subheadline)
                            .foregroundColor(.secondary)
                    }

                    if let hint = activationHint {
                        // Use collection's custom activation hint (e.g., "Hold Hyper key")
                        Label(hint, systemImage: "hand.point.up.left")
                            .font(.caption)
                            .foregroundColor(.accentColor)
                    } else if layerActivator != nil {
                        // Fall back to leader key display for leader-based collections
                        Label("Hold \(leaderKeyDisplay)", systemImage: "hand.point.up.left")
                            .font(.caption)
                            .foregroundColor(.accentColor)
                    }
                }

                Spacer()

                Toggle(
                    "",
                    isOn: Binding(
                        get: { effectiveEnabled },
                        set: { newValue in
                            // Optimistic update: change UI immediately
                            localEnabled = newValue
                            // Then trigger async operation
                            onToggle(newValue)
                        }
                    )
                )
                .labelsHidden()
                .toggleStyle(.switch)
                .tint(.blue)
                .onTapGesture {} // Prevents toggle from triggering row expansion
                .accessibilityIdentifier("rules-summary-toggle-\(collectionId)")
                .accessibilityLabel("Toggle \(name)")
            }
            .padding(12)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
    }

    @ViewBuilder
    private var expandedContentView: some View {
        if isExpanded {
            // Inset back plane container for expanded content
            InsetBackPlane {
                if showZeroState, mappings.isEmpty, appKeymaps.isEmpty, let onCreate = onCreateFirstRule {
                    // Zero State - only show if BOTH showZeroState is true AND all mappings are actually empty
                    VStack(spacing: 12) {
                        Text("No rules yet")
                            .font(.subheadline)
                            .foregroundColor(.secondary)

                        Button {
                            onCreate()
                        } label: {
                            Label("Create Your First Rule", systemImage: "plus.circle.fill")
                                .font(.body.weight(.medium))
                        }
                        .buttonStyle(.borderedProminent)
                        .controlSize(.small)
                    }
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 20)
                } else if displayStyle == .singleKeyPicker, let coll = collection {
                    // Segmented picker for single-key remapping
                    SingleKeyPickerContent(
                        collection: coll,
                        onSelectOutput: { output in
                            onSelectOutput?(output)
                        }
                    )
                    .padding(.top, 8)
                    .padding(.bottom, 12)
                    .padding(.horizontal, 16)
                } else if displayStyle == .tapHoldPicker, let coll = collection {
                    // Tap-hold picker for dual-role keys
                    TapHoldPickerContent(
                        collection: coll,
                        onSelectTapOutput: { tap in
                            onSelectTapOutput?(tap)
                        },
                        onSelectHoldOutput: { hold in
                            onSelectHoldOutput?(hold)
                        }
                    )
                    .padding(.top, 8)
                    .padding(.bottom, 12)
                    .padding(.horizontal, 16)
                } else if displayStyle == .homeRowMods, let coll = collection {
                    // Home Row Mods: show summary with current config, click to customize
                    let config = coll.configuration.homeRowModsConfig ?? HomeRowModsConfig()
                    VStack(alignment: .leading, spacing: 12) {
                        Text("Tap keys for letters, hold for modifiers")
                            .font(.subheadline)
                            .foregroundColor(.secondary)

                        // Summary of current configuration
                        if !config.enabledKeys.isEmpty {
                            VStack(alignment: .leading, spacing: 8) {
                                HStack(spacing: 16) {
                                    // Left hand
                                    if config.enabledKeys.contains(where: { HomeRowModsConfig.leftHandKeys.contains($0) }) {
                                        VStack(alignment: .leading, spacing: 4) {
                                            Text("Left hand")
                                                .font(.caption)
                                                .foregroundColor(.secondary)
                                            HStack(spacing: 6) {
                                                ForEach(HomeRowModsConfig.leftHandKeys, id: \.self) { key in
                                                    if config.enabledKeys.contains(key) {
                                                        let modSymbol = config.modifierAssignments[key].map { formatModifierForDisplay($0) } ?? ""
                                                        HomeRowKeyButton(
                                                            key: key,
                                                            modSymbol: modSymbol,
                                                            action: { onOpenHomeRowModsModalWithKey?(key) }
                                                        )
                                                    }
                                                }
                                            }
                                        }
                                    }

                                    // Right hand
                                    if config.enabledKeys.contains(where: { HomeRowModsConfig.rightHandKeys.contains($0) }) {
                                        VStack(alignment: .leading, spacing: 4) {
                                            Text("Right hand")
                                                .font(.caption)
                                                .foregroundColor(.secondary)
                                            HStack(spacing: 6) {
                                                ForEach(HomeRowModsConfig.rightHandKeys, id: \.self) { key in
                                                    if config.enabledKeys.contains(key) {
                                                        let modSymbol = config.modifierAssignments[key].map { formatModifierForDisplay($0) } ?? ""
                                                        HomeRowKeyButton(
                                                            key: key,
                                                            modSymbol: modSymbol,
                                                            action: { onOpenHomeRowModsModalWithKey?(key) }
                                                        )
                                                    }
                                                }
                                            }
                                        }
                                    }
                                }

                                let hasOffsets = !config.timing.tapOffsets.isEmpty
                                let quickTapText = config.timing.quickTapEnabled ? "Quick tap on" : "Quick tap off"
                                let quickTapTerm = config.timing.quickTapEnabled && config.timing.quickTapTermMs > 0 ? " + \(config.timing.quickTapTermMs)ms" : ""
                                Text("Timing: \(config.timing.tapWindow)ms tap\(quickTapTerm)\(hasOffsets ? " (+ per-key offsets)" : ""), \(config.timing.holdDelay)ms hold · \(quickTapText)")
                                    .font(.caption)
                                    .foregroundColor(.secondary)
                            }
                            .padding(.vertical, 8)
                            .padding(.horizontal, 12)
                            .background(
                                RoundedRectangle(cornerRadius: 8)
                                    .fill(Color(NSColor.controlBackgroundColor).opacity(0.5))
                            )
                        }

                        Button("Customize...") {
                            onOpenHomeRowModsModal?()
                        }
                        .buttonStyle(.bordered)
                        .accessibilityIdentifier("rules-summary-home-row-mods-customize-button")
                        .accessibilityLabel("Customize home row mods")
                    }
                    .padding(.top, 8)
                    .padding(.bottom, 12)
                    .padding(.horizontal, 16)
                } else if displayStyle == .layerPresetPicker, let coll = collection {
                    // Layer preset picker for collections with multiple preset configurations
                    LayerPresetPickerContent(
                        collection: coll,
                        onSelectPreset: { presetId in
                            onSelectLayerPreset?(presetId)
                        }
                    )
                    .padding(.top, 8)
                    .padding(.bottom, 12)
                    .padding(.horizontal, 16)
                } else if displayStyle == .launcherGrid, let coll = collection {
                    // Launcher grid for app/website shortcuts
                    if let config = coll.configuration.launcherGridConfig {
                        LauncherCollectionView(
                            config: Binding(
                                get: { config },
                                set: { newConfig in
                                    onLauncherConfigChanged?(newConfig)
                                }
                            ),
                            onConfigChanged: { newConfig in
                                onLauncherConfigChanged?(newConfig)
                            }
                        )
                        .padding(.top, 8)
                        .padding(.bottom, 12)
                        .padding(.horizontal, 16)
                    }
                } else if displayStyle == .chordGroups, let coll = collection {
                    // Chord Groups: Ben Vallack-style multi-key combinations
                    let config = coll.configuration.chordGroupsConfig ?? ChordGroupsConfig()
                    ChordGroupsCollectionView(
                        config: Binding(
                            get: { config },
                            set: { _ in }
                        ),
                        onConfigChanged: { newConfig in
                            onUpdateChordGroupsConfig?(newConfig)
                        },
                        onOpenModal: {
                            onOpenChordGroupsModal?()
                        }
                    )
                    .padding(.top, 8)
                    .padding(.bottom, 12)
                    .padding(.horizontal, 16)
                } else if displayStyle == .sequences, let coll = collection {
                    // Sequences: Multi-key sequences that trigger layers
                    let config = coll.configuration.sequencesConfig ?? SequencesConfig()
                    VStack(alignment: .leading, spacing: 12) {
                        Text("Create multi-key sequences like 'Leader → w' to activate layers")
                            .font(.subheadline)
                            .foregroundColor(.secondary)

                        if config.sequences.isEmpty {
                            Text("No sequences configured yet")
                                .font(.caption)
                                .foregroundColor(.secondary)
                        } else {
                            VStack(alignment: .leading, spacing: 4) {
                                ForEach(config.sequences.prefix(3)) { sequence in
                                    HStack {
                                        Text(sequence.prettyKeys)
                                            .font(.caption)
                                            .foregroundColor(.primary)
                                        Image(systemName: "arrow.right")
                                            .font(.caption)
                                            .foregroundColor(.secondary)
                                        Text(sequence.action.displayName)
                                            .font(.caption)
                                            .foregroundColor(.secondary)
                                    }
                                }
                                if config.sequences.count > 3 {
                                    Text("+ \(config.sequences.count - 3) more")
                                        .font(.caption)
                                        .foregroundColor(.secondary)
                                }
                            }
                        }

                        Button(action: {
                            onOpenSequencesModal?()
                        }) {
                            Label("Customize...", systemImage: "arrow.right.arrow.left.circle")
                        }
                        .buttonStyle(.bordered)
                        .accessibilityIdentifier("sequences-customize-button")
                        .accessibilityLabel("Customize sequences")
                    }
                    .padding(.top, 8)
                    .padding(.bottom, 12)
                    .padding(.horizontal, 16)
                } else if displayStyle == .table {
                    // Check for specialized collection views
                    if collection?.id == RuleCollectionIdentifier.numpadLayer {
                        // Numpad uses specialized grid
                        VStack(alignment: .leading, spacing: 8) {
                            Text("Transform your keyboard into a numpad")
                                .font(.subheadline)
                                .foregroundColor(.secondary)
                            NumpadTransformGrid(mappings: collection?.mappings ?? [])
                        }
                        .padding(.top, 8)
                        .padding(.bottom, 12)
                        .padding(.horizontal, 16)
                    } else if collection?.id == RuleCollectionIdentifier.vimNavigation {
                        // Vim uses animated category cards
                        VimCommandCardsView(mappings: collection?.mappings ?? [])
                            .padding(.top, 8)
                            .padding(.bottom, 12)
                            .padding(.horizontal, 12)
                    } else if collection?.id == RuleCollectionIdentifier.windowSnapping {
                        // Window snapping uses visual monitor canvas
                        WindowSnappingView(
                            mappings: collection?.mappings ?? [],
                            convention: collection?.windowKeyConvention ?? .standard,
                            onConventionChange: { convention in
                                onSelectWindowConvention?(convention)
                            }
                        )
                        .padding(.top, 8)
                        .padding(.bottom, 12)
                        .padding(.horizontal, 12)
                    } else if collection?.id == RuleCollectionIdentifier.macFunctionKeys {
                        // Function keys use flip card display
                        FunctionKeysView(
                            mappings: collection?.mappings ?? [],
                            currentMode: collection?.functionKeyMode,
                            onModeChange: { mode in
                                onSelectFunctionKeyMode?(mode)
                            }
                        )
                        .padding(.top, 8)
                        .padding(.bottom, 12)
                        .padding(.horizontal, 12)
                    } else {
                        // Generic table for other collections
                        MappingTableContent(mappings: mappings)
                            .padding(.top, 8)
                            .padding(.bottom, 12)
                            .padding(.horizontal, 12)
                    }
                } else {
                    // List view for standard collections and custom rules
                    VStack(spacing: 6) {
                        // Section: "Everywhere" rules (if we have app-specific rules too, show header)
                        if !mappings.isEmpty, !appKeymaps.isEmpty {
                            RulesSectionHeaderCompact(
                                title: "Everywhere",
                                systemImage: "globe"
                            )
                        }

                        ForEach(mappings, id: \.id) { mapping in
                            MappingRowView(
                                mapping: mapping,
                                layerActivator: layerActivator,
                                leaderKeyDisplay: leaderKeyDisplay,
                                onEditMapping: onEditMapping,
                                onDeleteMapping: onDeleteMapping,
                                prettyKeyName: prettyKeyName
                            )
                        }

                        // Section: App-specific rules
                        ForEach(appKeymaps) { keymap in
                            AppRulesSectionHeaderCompact(keymap: keymap)
                                .padding(.top, mappings.isEmpty ? 0 : 8)

                            ForEach(keymap.overrides) { override in
                                AppRuleRowCompact(
                                    keymap: keymap,
                                    override: override,
                                    onEdit: {
                                        onEditAppRule?(keymap, override)
                                    },
                                    onDelete: {
                                        onDeleteAppRule?(keymap, override)
                                    },
                                    prettyKeyName: prettyKeyName
                                )
                            }
                        }
                    }
                    .padding(.top, 8)
                    .padding(.bottom, 12)
                }
            } // InsetBackPlane
        }
    }

    @ViewBuilder
    private func iconView(for icon: String) -> some View {
        let scale: CGFloat = 0.85
        let iconSize: CGFloat = 24 * scale
        if icon.hasPrefix("text:") {
            let text = String(icon.dropFirst(5))
            Text(text)
                .font(.system(size: 14 * scale, weight: .bold, design: .monospaced))
                .foregroundColor(.secondary)
                .frame(width: iconSize, height: iconSize)
        } else if icon.hasPrefix("resource:") {
            let resourceName = String(icon.dropFirst(9))
            // Try Bundle.module first (Swift Package resources), then Bundle.main
            let resourceURL = Bundle.module.url(forResource: resourceName, withExtension: "svg")
                ?? Bundle.main.url(forResource: resourceName, withExtension: "svg")
            if let url = resourceURL, let image = NSImage(contentsOf: url) {
                Image(nsImage: image)
                    .resizable()
                    .aspectRatio(contentMode: .fit)
                    .frame(width: iconSize, height: iconSize)
            } else {
                // Fallback to system image
                Image(systemName: "questionmark.circle")
                    .font(.system(size: iconSize))
                    .foregroundColor(.secondary)
            }
        } else {
            Image(systemName: icon)
                .font(.system(size: iconSize))
                .foregroundColor(.secondary)
        }
    }

    func prettyKeyName(_ raw: String) -> String {
        raw.replacingOccurrences(of: "_", with: " ")
            .trimmingCharacters(in: .whitespaces)
            .capitalized
    }
}

// MARK: - Mapping Row View

private struct MappingRowView: View {
    let mapping: (input: String, output: String, shiftedOutput: String?, ctrlOutput: String?, description: String?, sectionBreak: Bool, enabled: Bool, id: UUID, behavior: MappingBehavior?)
    let layerActivator: MomentaryActivator?
    var leaderKeyDisplay: String = "␣ Space"
    let onEditMapping: ((UUID) -> Void)?
    let onDeleteMapping: ((UUID) -> Void)?
    let prettyKeyName: (String) -> String

    @State private var isHovered = false

    /// Extract app identifier from push-msg launch output
    private var appLaunchIdentifier: String? {
        KeyboardVisualizationViewModel.extractAppLaunchIdentifier(from: mapping.output)
    }

    private var isEditable: Bool {
        onEditMapping != nil
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            HStack(spacing: 8) {
                // Mapping content
                HStack(spacing: 8) {
                    // Show layer activator if present
                    if layerActivator != nil {
                        HStack(spacing: 4) {
                            Text("Hold")
                                .font(.body.monospaced().weight(.semibold))
                                .foregroundColor(.accentColor)
                            Text(leaderKeyDisplay)
                                .font(.body.monospaced().weight(.semibold))
                                .foregroundColor(KeycapStyle.textColor)
                        }
                        .modifier(KeycapStyle())

                        Text("+")
                            .font(.body)
                            .foregroundColor(.secondary)
                    }

                    Text(prettyKeyName(mapping.input))
                        .font(.body.monospaced().weight(.semibold))
                        .foregroundColor(KeycapStyle.textColor)
                        .modifier(KeycapStyle())

                    Image(systemName: "arrow.right")
                        .font(.body.weight(.medium))
                        .foregroundColor(.secondary)

                    // Show app icon + name for launch actions, otherwise show key chip
                    if let appId = appLaunchIdentifier {
                        AppLaunchChip(appIdentifier: appId)
                    } else {
                        Text(prettyKeyName(mapping.output))
                            .font(.body.monospaced().weight(.semibold))
                            .foregroundColor(KeycapStyle.textColor)
                            .modifier(KeycapStyle())
                    }

                    // Show rule name/title if provided
                    if let title = mapping.description, !title.isEmpty {
                        Text(title)
                            .font(.subheadline)
                            .foregroundColor(.secondary)
                    }

                    // Behavior summary for custom rules on same line
                    if let behavior = mapping.behavior {
                        behaviorSummaryView(behavior: behavior)
                    }

                    Spacer(minLength: 0)
                }

                Spacer()

                // Action buttons - subtle icons that appear on hover
                if onEditMapping != nil || onDeleteMapping != nil {
                    HStack(spacing: 4) {
                        if let onEdit = onEditMapping {
                            Button {
                                onEdit(mapping.id)
                            } label: {
                                Image(systemName: "pencil")
                                    .font(.system(size: 12, weight: .medium))
                                    .foregroundColor(.secondary.opacity(isHovered ? 1 : 0.5))
                                    .frame(width: 28, height: 28)
                                    .contentShape(Rectangle())
                            }
                            .buttonStyle(.plain)
                        }

                        if let onDelete = onDeleteMapping {
                            Button {
                                onDelete(mapping.id)
                            } label: {
                                Image(systemName: "trash")
                                    .font(.system(size: 12, weight: .medium))
                                    .foregroundColor(.secondary.opacity(isHovered ? 1 : 0.5))
                                    .frame(width: 28, height: 28)
                                    .contentShape(Rectangle())
                            }
                            .buttonStyle(.plain)
                        }

                        // Spacer for alignment
                        Spacer()
                            .frame(width: 0)
                    }
                }
            }
        }
        .padding(.leading, 48)
        .padding(.trailing, 12)
        .padding(.vertical, 4)
        .padding(.horizontal, 8)
        .background(
            RoundedRectangle(cornerRadius: 8)
                .fill(isHovered && isEditable ? Color.primary.opacity(0.03) : Color.clear)
        )
        .contentShape(Rectangle())
        .onHover { hovering in
            isHovered = hovering
            if isEditable {
                if hovering {
                    NSCursor.pointingHand.push()
                } else {
                    NSCursor.pop()
                }
            }
        }
        .onTapGesture {
            if let onEdit = onEditMapping {
                onEdit(mapping.id)
            }
        }
    }

    @ViewBuilder
    private func behaviorSummaryView(behavior: MappingBehavior) -> some View {
        HStack(spacing: 6) {
            switch behavior {
            case let .dualRole(dr):
                behaviorItem(icon: "hand.point.up.left", label: "Hold", key: dr.holdAction)

            case let .tapDance(td):
                let behaviorItems = extractBehaviorItemsInEditOrder(from: td)

                if behaviorItems.isEmpty {
                    EmptyView()
                } else {
                    ForEach(Array(behaviorItems.enumerated()), id: \.offset) { itemIndex, item in
                        if itemIndex > 0 {
                            Text("•")
                                .font(.caption)
                                .foregroundColor(.secondary.opacity(0.5))
                        }
                        behaviorItem(icon: item.0, label: item.1, key: item.2)
                    }
                }
            }
        }
        .foregroundColor(.secondary)
    }

    // Extract tap dance steps (skip index 0 which is single tap = output)
    private func extractBehaviorItemsInEditOrder(from td: TapDanceBehavior) -> [(String, String, String)] {
        var behaviorItems: [(String, String, String)] = []

        // Step 0 = single tap (shown as "Finish" already)
        // Step 1+ = double tap, triple tap, etc.
        let tapLabels = ["Double Tap", "Triple Tap", "Quad Tap", "5× Tap", "6× Tap", "7× Tap"]
        let tapIcons = ["hand.tap", "hand.tap", "hand.tap", "hand.tap", "hand.tap", "hand.tap"]

        for index in 1 ..< td.steps.count {
            let step = td.steps[index]
            guard !step.action.isEmpty else { continue }

            let labelIndex = index - 1
            let label = labelIndex < tapLabels.count ? tapLabels[labelIndex] : "\(index + 1)× Tap"
            let icon = labelIndex < tapIcons.count ? tapIcons[labelIndex] : "hand.tap"

            behaviorItems.append((icon, label, step.action))
        }

        return behaviorItems
    }

    @ViewBuilder
    private func behaviorItem(icon: String, label: String, key: String) -> some View {
        HStack(spacing: 4) {
            Image(systemName: icon)
                .font(.caption)
            Text(label)
                .font(.caption)
            KeyCapChip(text: formatKeyForBehavior(key))
        }
    }

    /// Format a modifier key for display
    private func formatModifierForDisplay(_ modifier: String) -> String {
        let displayNames: [String: String] = [
            "lmet": "⌘", "rmet": "⌘",
            "lalt": "⌥", "ralt": "⌥",
            "lctl": "⌃", "rctl": "⌃",
            "lsft": "⇧", "rsft": "⇧"
        ]
        return displayNames[modifier] ?? modifier
    }

    private func formatKeyForBehavior(_ key: String) -> String {
        let keySymbols: [String: String] = [
            "spc": "␣ Space",
            "space": "␣ Space",
            "caps": "⇪ Caps",
            "tab": "⇥ Tab",
            "ret": "↩ Return",
            "bspc": "⌫ Delete",
            "del": "⌦ Fwd Del",
            "esc": "⎋ Escape",
            "lmet": "⌘ Cmd",
            "rmet": "⌘ Cmd",
            "lalt": "⌥ Opt",
            "ralt": "⌥ Opt",
            "lctl": "⌃ Ctrl",
            "rctl": "⌃ Ctrl",
            "lsft": "⇧ Shift",
            "rsft": "⇧ Shift"
        ]

        if let symbol = keySymbols[key.lowercased()] {
            return symbol
        }

        // Handle modifier prefixes
        var result = key
        var prefix = ""
        if result.hasPrefix("M-") {
            prefix = "⌘"
            result = String(result.dropFirst(2))
        } else if result.hasPrefix("C-") {
            prefix = "⌃"
            result = String(result.dropFirst(2))
        } else if result.hasPrefix("A-") {
            prefix = "⌥"
            result = String(result.dropFirst(2))
        } else if result.hasPrefix("S-") {
            prefix = "⇧"
            result = String(result.dropFirst(2))
        }

        if let symbol = keySymbols[result.lowercased()] {
            return prefix + symbol
        }

        return prefix + result.capitalized
    }
}

// MARK: - Create Rule Button

private struct CreateRuleButton: View {
    @Binding var isPressed: Bool
    @Binding var externalHover: Bool
    @State private var isHovered = false
    @State private var isMouseDown = false

    private var isAnyHovered: Bool {
        isHovered || externalHover
    }

    var body: some View {
        Button {
            isPressed = true
        } label: {
            ZStack {
                Circle()
                    .fill(fillColor)
                    .frame(width: 80, height: 80)
                    .shadow(color: shadowColor, radius: shadowRadius, x: 0, y: shadowY)

                Image(systemName: "plus.circle.fill")
                    .font(.system(size: 40))
                    .foregroundColor(iconColor)
            }
            .scaleEffect(isMouseDown ? 0.95 : (isAnyHovered ? 1.05 : 1.0))
            .animation(.easeInOut(duration: 0.15), value: isAnyHovered)
            .animation(.easeInOut(duration: 0.1), value: isMouseDown)
        }
        .buttonStyle(.plain)
        .onHover { hovering in
            isHovered = hovering
        }
        .simultaneousGesture(
            DragGesture(minimumDistance: 0)
                .onChanged { _ in
                    isMouseDown = true
                }
                .onEnded { _ in
                    isMouseDown = false
                }
        )
    }

    private var fillColor: Color {
        if isMouseDown {
            Color.blue.opacity(0.3)
        } else if isAnyHovered {
            Color.blue.opacity(0.25)
        } else {
            Color.blue.opacity(0.15)
        }
    }

    private var iconColor: Color {
        if isMouseDown {
            .blue.opacity(0.8)
        } else if isAnyHovered {
            .blue
        } else {
            .blue.opacity(0.9)
        }
    }

    private var shadowColor: Color {
        if isMouseDown {
            .clear
        } else if isAnyHovered {
            Color.blue.opacity(0.3)
        } else {
            .clear
        }
    }

    private var shadowRadius: CGFloat {
        isAnyHovered ? 8 : 0
    }

    private var shadowY: CGFloat {
        isAnyHovered ? 2 : 0
    }
}

// MARK: - Single Key Picker Content

private struct SingleKeyPickerContent: View {
    let collection: RuleCollection
    let onSelectOutput: (String) -> Void

    @State private var selectedOutput: String
    @State private var showingCustomPopover = false
    @State private var customKeyInput = ""

    private var config: SingleKeyPickerConfig? {
        collection.configuration.singleKeyPickerConfig
    }

    init(collection: RuleCollection, onSelectOutput: @escaping (String) -> Void) {
        self.collection = collection
        self.onSelectOutput = onSelectOutput
        let cfg = collection.configuration.singleKeyPickerConfig
        _selectedOutput = State(initialValue: cfg?.selectedOutput ?? cfg?.presetOptions.first?.output ?? "")
    }

    private var selectedPreset: SingleKeyPreset? {
        config?.presetOptions.first { $0.output == selectedOutput }
    }

    private var isCustomSelection: Bool {
        guard let cfg = config else { return false }
        return !cfg.presetOptions.contains { $0.output == selectedOutput }
            && !selectedOutput.isEmpty
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            // Segmented picker
            HStack(spacing: 0) {
                ForEach(config?.presetOptions ?? []) { preset in
                    PickerSegment(
                        label: preset.label,
                        isSelected: selectedOutput == preset.output,
                        isFirst: preset.id == config?.presetOptions.first?.id,
                        isLast: preset.id == config?.presetOptions.last?.id && !isCustomSelection
                    ) {
                        selectedOutput = preset.output
                        onSelectOutput(preset.output)
                    }
                }

                // Custom segment with popover
                PickerSegment(
                    label: "Custom",
                    isSelected: isCustomSelection,
                    isFirst: false,
                    isLast: true
                ) {
                    customKeyInput = isCustomSelection ? selectedOutput : ""
                    showingCustomPopover = true
                }
                .popover(isPresented: $showingCustomPopover, arrowEdge: .bottom) {
                    CustomKeyPopover(
                        keyInput: $customKeyInput,
                        onConfirm: {
                            let normalized = CustomRuleValidator.normalizeKey(customKeyInput)
                            if CustomRuleValidator.isValidKey(normalized) {
                                selectedOutput = normalized
                                onSelectOutput(normalized)
                            }
                            showingCustomPopover = false
                        },
                        onCancel: {
                            showingCustomPopover = false
                        }
                    )
                }
            }
            .padding(.horizontal, 4)

            // Description that updates based on selection
            if let preset = selectedPreset {
                Text(preset.description)
                    .font(.subheadline)
                    .foregroundColor(.secondary)
                    .padding(.horizontal, 4)
                    .transition(.opacity)
                    .id(preset.output)
            } else if isCustomSelection {
                HStack {
                    Text("Custom key: \(selectedOutput)")
                        .font(.subheadline)
                        .foregroundColor(.secondary)
                    Spacer()
                    Button("Edit") {
                        customKeyInput = selectedOutput
                        showingCustomPopover = true
                    }
                    .buttonStyle(.link)
                    .font(.subheadline)
                    .accessibilityIdentifier("rules-summary-custom-key-edit-button")
                    .accessibilityLabel("Edit custom key")
                }
                .padding(.horizontal, 4)
            }
        }
        .padding(.vertical, 8)
        .animation(.easeInOut(duration: 0.15), value: selectedOutput)
    }
}

// MARK: - Layer Preset Picker Content

private struct LayerPresetPickerContent: View {
    let collection: RuleCollection
    let onSelectPreset: (String) -> Void

    @State private var selectedPresetId: String
    @State private var hasInteracted = false // Track if user has clicked a preset
    @Namespace private var symbolAnimation

    private var config: LayerPresetPickerConfig? {
        collection.configuration.layerPresetPickerConfig
    }

    init(collection: RuleCollection, onSelectPreset: @escaping (String) -> Void) {
        self.collection = collection
        self.onSelectPreset = onSelectPreset
        let cfg = collection.configuration.layerPresetPickerConfig
        _selectedPresetId = State(initialValue: cfg?.selectedPresetId ?? cfg?.presets.first?.id ?? "")
    }

    private var selectedPreset: LayerPreset? {
        config?.presets.first { $0.id == selectedPresetId }
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            // Mini-preview cards for each preset
            HStack(spacing: 12) {
                ForEach(config?.presets ?? []) { preset in
                    MiniPresetCard(
                        preset: preset,
                        isSelected: selectedPresetId == preset.id
                    ) {
                        hasInteracted = true // Mark that user clicked
                        selectedPresetId = preset.id
                        onSelectPreset(preset.id)
                    }
                }
            }

            // Full keyboard grid for selected preset
            if let preset = selectedPreset {
                VStack(alignment: .leading, spacing: 8) {
                    Text(preset.description)
                        .font(.subheadline)
                        .foregroundColor(.secondary)

                    AnimatedKeyboardTransformGrid(
                        mappings: preset.mappings,
                        namespace: symbolAnimation,
                        enableAnimation: hasInteracted
                    )
                }
            }
        }
        .padding(.vertical, 8)
        // Only animate after user has interacted - prevents animation on view appear/re-render
        .animation(hasInteracted ? .spring(response: 0.4, dampingFraction: 0.7) : nil, value: selectedPresetId)
    }
}

// MARK: - Mini Preset Card

private struct MiniPresetCard: View {
    let preset: LayerPreset
    let isSelected: Bool
    let onSelect: () -> Void

    @State private var isHovered = false

    // Define keyboard rows for mini preview (home row focus)
    private static let previewRows: [[String]] = [
        ["a", "s", "d", "f", "g", "h", "j", "k", "l", ";"]
    ]

    var body: some View {
        Button(action: onSelect) {
            VStack(alignment: .leading, spacing: 6) {
                // Label
                HStack {
                    if let icon = preset.icon {
                        Image(systemName: icon)
                            .font(.caption)
                    }
                    Text(preset.label)
                        .font(.caption.weight(.medium))
                }
                .foregroundColor(isSelected ? .primary : .secondary)

                // Mini keyboard preview (home row only)
                HStack(spacing: 2) {
                    ForEach(Self.previewRows[0], id: \.self) { key in
                        let output = preset.mappings.first { $0.input.lowercased() == key }?.description ?? key
                        MiniKeycap(label: output)
                    }
                }
            }
            .padding(.horizontal, 10)
            .padding(.vertical, 8)
            .background(
                RoundedRectangle(cornerRadius: 8)
                    .fill(isSelected ? Color.accentColor.opacity(0.15) : Color(NSColor.controlBackgroundColor))
            )
            .overlay(
                RoundedRectangle(cornerRadius: 8)
                    .stroke(isSelected ? Color.accentColor : Color.secondary.opacity(isHovered ? 0.4 : 0.2), lineWidth: isSelected ? 2 : 1)
            )
        }
        .buttonStyle(.plain)
        .accessibilityIdentifier("rules-summary-preset-button-\(preset.id)")
        .accessibilityLabel("Select preset \(preset.label)")
        .onHover { isHovered = $0 }
    }
}

// MARK: - Mini Keycap (for preset previews)

private struct MiniKeycap: View {
    let label: String

    var body: some View {
        Text(label)
            .font(.system(size: 9, weight: .medium, design: .monospaced))
            .frame(width: 16, height: 16)
            .background(
                RoundedRectangle(cornerRadius: 3)
                    .fill(Color(NSColor.controlBackgroundColor))
            )
            .overlay(
                RoundedRectangle(cornerRadius: 3)
                    .stroke(Color.secondary.opacity(0.3), lineWidth: 0.5)
            )
    }
}

// MARK: - Animated Keyboard Transform Grid (with magic move)

/// A keyboard visualization where symbols animate ("magic move") between positions
/// when switching presets. Symbols are rendered in an overlay layer and animate
/// to their target keycap positions, creating a playful shuffling effect.
private struct AnimatedKeyboardTransformGrid: View {
    let mappings: [KeyMapping]
    var namespace: Namespace.ID
    var enableAnimation: Bool = false // Only animate after user interaction

    // Standard QWERTY layout rows (including number row for Mirrored preset)
    private static let keyboardRows: [[String]] = [
        ["1", "2", "3", "4", "5", "6", "7", "8", "9", "0"],
        ["q", "w", "e", "r", "t", "y", "u", "i", "o", "p"],
        ["a", "s", "d", "f", "g", "h", "j", "k", "l", ";"],
        ["z", "x", "c", "v", "b", "n", "m", ",", ".", "/"]
    ]

    // All keys as flat array for position calculation
    private static let allKeys: [String] = keyboardRows.flatMap { $0 }

    private func outputFor(_ input: String) -> String? {
        mappings.first { $0.input.lowercased() == input.lowercased() }?.description
    }

    /// Get all unique symbols and their target key positions
    private var symbolPositions: [(symbol: String, keyIndex: Int)] {
        var result: [(String, Int)] = []
        for (index, key) in Self.allKeys.enumerated() {
            if let symbol = outputFor(key) {
                result.append((symbol, index))
            }
        }
        return result
    }

    var body: some View {
        VStack(spacing: 8) {
            HStack(alignment: .center, spacing: 16) {
                // Input keyboard (static)
                InputKeyboardGrid(keyboardRows: Self.keyboardRows, outputFor: outputFor)

                // Arrow
                Image(systemName: "arrow.right")
                    .font(.title3)
                    .foregroundColor(.secondary)

                // Output keyboard with animated symbols overlay
                OutputKeyboardWithAnimatedSymbols(
                    keyboardRows: Self.keyboardRows,
                    mappings: mappings,
                    namespace: namespace,
                    enableAnimation: enableAnimation
                )
            }

            // Physical position note
            Text("Keys labeled by physical position (QWERTY). Works with any keyboard layout.")
                .font(.caption2)
                .foregroundStyle(.tertiary)
        }
        .padding(12)
        .background(
            RoundedRectangle(cornerRadius: 10)
                .fill(Color(NSColor.controlBackgroundColor).opacity(0.5))
        )
    }
}

// MARK: - Input Keyboard Grid (static)

private struct InputKeyboardGrid: View {
    let keyboardRows: [[String]]
    let outputFor: (String) -> String?

    var body: some View {
        VStack(alignment: .leading, spacing: 2) {
            Text("Physical Position")
                .font(.caption2)
                .foregroundColor(.secondary)
                .padding(.bottom, 2)

            ForEach(Array(keyboardRows.enumerated()), id: \.offset) { rowIndex, row in
                HStack(spacing: 3) {
                    // Keyboard stagger: number=0, qwerty=0, home=8, bottom=16
                    if rowIndex == 2 { Spacer().frame(width: 8) } else if rowIndex == 3 { Spacer().frame(width: 16) }

                    ForEach(row, id: \.self) { key in
                        let hasMapping = outputFor(key) != nil
                        TransformKeycap(
                            label: key.uppercased(),
                            isHighlighted: hasMapping,
                            isInput: true
                        )
                    }
                }
            }
        }
    }
}

// MARK: - Output Keyboard with Animated Symbols

/// The output keyboard renders keycap backgrounds, then overlays animated symbols.
/// Symbols track their target position and animate when it changes.
private struct OutputKeyboardWithAnimatedSymbols: View {
    let keyboardRows: [[String]]
    let mappings: [KeyMapping]
    var namespace: Namespace.ID
    var enableAnimation: Bool = false // Only animate after user interaction

    // Track keycap positions using preference key
    @State private var keycapFrames: [String: CGRect] = [:]

    private func outputFor(_ input: String) -> String? {
        mappings.first { $0.input.lowercased() == input.lowercased() }?.description
    }

    /// Build symbol -> target key mapping
    private var symbolTargets: [String: String] {
        var result: [String: String] = [:]
        for mapping in mappings {
            if let desc = mapping.description {
                result[desc] = mapping.input.lowercased()
            }
        }
        return result
    }

    /// All unique symbols across all possible presets (so they persist between changes)
    private static let allSymbols = [
        "!", "@", "#", "$", "%", "^", "&", "*", "(", ")",
        "~", "`", "-", "=", "+", "[", "]", "{", "}", "|",
        "\\", "_", "/", "?", "'", "\"", ":", ";", "<", ">"
    ]

    /// Default "parking" position for symbols not in current mapping
    /// Places them off the bottom of the keyboard area
    private var parkingFrame: CGRect {
        CGRect(x: 100, y: -50, width: 22, height: 22)
    }

    /// Get the target frame for a symbol - either its mapped key position or the parking area
    private func targetFrameFor(_ symbol: String) -> CGRect {
        if let targetKey = symbolTargets[symbol],
           let frame = keycapFrames[targetKey] {
            return frame
        }
        return parkingFrame
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 2) {
            Text("Becomes")
                .font(.caption2)
                .foregroundColor(.secondary)
                .padding(.bottom, 2)

            // Keycap slots + symbol overlay
            ZStack(alignment: .topLeading) {
                // Layer 1: Keycap backgrounds (stable slots)
                VStack(alignment: .leading, spacing: 2) {
                    ForEach(Array(keyboardRows.enumerated()), id: \.offset) { rowIndex, row in
                        HStack(spacing: 3) {
                            // Keyboard stagger: number=0, qwerty=0, home=8, bottom=16
                            if rowIndex == 2 { Spacer().frame(width: 8) } else if rowIndex == 3 { Spacer().frame(width: 16) }

                            ForEach(row, id: \.self) { key in
                                let hasMapping = outputFor(key) != nil
                                KeycapSlot(key: key, hasMapping: hasMapping)
                                    .background(
                                        GeometryReader { geo in
                                            Color.clear.preference(
                                                key: KeycapFramePreference.self,
                                                value: [key: geo.frame(in: .named("outputKeyboard"))]
                                            )
                                        }
                                    )
                            }
                        }
                    }
                }

                // Layer 2: Animated symbols (floating overlay)
                // IMPORTANT: Always render ALL symbols to enable animation.
                // Symbols not in current mapping are hidden but still present in view tree.
                ForEach(Self.allSymbols, id: \.self) { symbol in
                    FloatingSymbol(
                        symbol: symbol,
                        targetFrame: targetFrameFor(symbol),
                        isVisible: symbolTargets[symbol] != nil,
                        namespace: namespace,
                        enableAnimation: enableAnimation
                    )
                }
            }
            .coordinateSpace(name: "outputKeyboard")
            .onPreferenceChange(KeycapFramePreference.self) { frames in
                keycapFrames = frames
            }
        }
    }
}

// MARK: - Keycap Slot (empty background)

private struct KeycapSlot: View {
    let key: String
    let hasMapping: Bool

    var body: some View {
        ZStack {
            RoundedRectangle(cornerRadius: 4)
                .fill(hasMapping ? Color.accentColor.opacity(0.15) : Color(NSColor.controlBackgroundColor))
            RoundedRectangle(cornerRadius: 4)
                .stroke(hasMapping ? Color.accentColor.opacity(0.5) : Color.secondary.opacity(0.2), lineWidth: 1)

            // Show key label only if no mapping (symbols rendered in overlay)
            if !hasMapping {
                Text(key.uppercased())
                    .font(.system(size: 11, weight: .regular, design: .monospaced))
                    .foregroundColor(.secondary)
            }
        }
        .frame(width: 22, height: 22)
    }
}

// MARK: - Floating Symbol (animates to target position)

/// A symbol that floats above the keyboard and animates to its target keycap.
/// Each symbol has randomized spring parameters for a playful shuffling effect.
/// Symbols not in the current mapping are hidden but remain in the view tree for animation.
private struct FloatingSymbol: View {
    let symbol: String
    let targetFrame: CGRect
    let isVisible: Bool
    var namespace: Namespace.ID
    var enableAnimation: Bool = false // Only animate after user interaction

    // Randomized animation parameters (seeded by symbol for consistency)
    private var springResponse: Double {
        0.3 + Double(abs(symbol.hashValue) % 100) / 500.0 // 0.30-0.50s
    }

    private var dampingFraction: Double {
        0.6 + Double(abs(symbol.hashValue >> 8) % 100) / 500.0 // 0.60-0.80
    }

    private var wobbleAngle: Double {
        Double(abs(symbol.hashValue >> 16) % 25) - 12.0 // -12° to +12°
    }

    /// Animation to use - nil when disabled (prevents "rain down" on view appear)
    private var positionAnimation: Animation? {
        enableAnimation ? .spring(response: springResponse, dampingFraction: dampingFraction) : nil
    }

    @State private var rotation: Angle = .zero
    @State private var scale: CGFloat = 1.0
    @State private var wasVisible: Bool = false

    var body: some View {
        Text(symbol)
            .font(.system(size: 11, weight: .semibold, design: .monospaced))
            .foregroundColor(.accentColor)
            .frame(width: 22, height: 22)
            .scaleEffect(scale)
            .rotationEffect(rotation)
            .opacity(isVisible ? 1.0 : 0.0)
            .position(x: targetFrame.midX, y: targetFrame.midY)
            .animation(positionAnimation, value: targetFrame)
            .animation(positionAnimation, value: isVisible)
            .onChange(of: targetFrame) { _, _ in
                if isVisible, enableAnimation {
                    triggerWobble()
                }
            }
            .onChange(of: isVisible) { _, newVisible in
                if newVisible, !wasVisible, enableAnimation {
                    // Symbol just became visible - trigger entrance wobble
                    triggerWobble()
                }
                wasVisible = newVisible
            }
    }

    private func triggerWobble() {
        rotation = .degrees(wobbleAngle)
        scale = 1.15
        withAnimation(.spring(response: springResponse, dampingFraction: dampingFraction)) {
            rotation = .zero
            scale = 1.0
        }
    }
}

// MARK: - Inset Back Plane

/// A container that creates an inset "back plane" effect for expanded content.
/// Uses an inner shadow and subtle gradient to create depth.
private struct InsetBackPlane<Content: View>: View {
    @ViewBuilder let content: Content

    var body: some View {
        content
            .padding(.horizontal, 8)
            .padding(.vertical, 4)
            .background(
                RoundedRectangle(cornerRadius: 8)
                    .fill(Color(NSColor.windowBackgroundColor).opacity(0.6))
                    .overlay(
                        RoundedRectangle(cornerRadius: 8)
                            .strokeBorder(
                                LinearGradient(
                                    colors: [
                                        Color.black.opacity(0.15),
                                        Color.clear,
                                        Color.white.opacity(0.05)
                                    ],
                                    startPoint: .top,
                                    endPoint: .bottom
                                ),
                                lineWidth: 1
                            )
                    )
                    .shadow(color: Color.black.opacity(0.1), radius: 2, x: 0, y: 1)
            )
            .padding(.horizontal, 12)
            .padding(.top, 4)
            .padding(.bottom, 8)
    }
}

// MARK: - Keycap Frame Preference Key

private struct KeycapFramePreference: PreferenceKey {
    nonisolated(unsafe) static var defaultValue: [String: CGRect] = [:]
    static func reduce(value: inout [String: CGRect], nextValue: () -> [String: CGRect]) {
        value.merge(nextValue()) { $1 }
    }
}

// MARK: - Keyboard Transform Grid (Input → Output) - Static version

private struct KeyboardTransformGrid: View {
    let mappings: [KeyMapping]

    // Standard QWERTY layout rows (letters only for cleaner display)
    private static let keyboardRows: [[String]] = [
        ["q", "w", "e", "r", "t", "y", "u", "i", "o", "p"],
        ["a", "s", "d", "f", "g", "h", "j", "k", "l", ";"],
        ["z", "x", "c", "v", "b", "n", "m", ",", ".", "/"]
    ]

    private func outputFor(_ input: String) -> String? {
        mappings.first { $0.input.lowercased() == input.lowercased() }?.description
    }

    var body: some View {
        VStack(spacing: 8) {
            HStack(alignment: .center, spacing: 16) {
                // Input keyboard
                VStack(alignment: .leading, spacing: 2) {
                    Text("Physical Position")
                        .font(.caption2)
                        .foregroundColor(.secondary)
                        .padding(.bottom, 2)

                    ForEach(Array(Self.keyboardRows.enumerated()), id: \.offset) { rowIndex, row in
                        HStack(spacing: 3) {
                            // Stagger for realistic keyboard look
                            if rowIndex == 1 {
                                Spacer().frame(width: 8)
                            } else if rowIndex == 2 {
                                Spacer().frame(width: 16)
                            }

                            ForEach(row, id: \.self) { key in
                                let hasMapping = outputFor(key) != nil
                                TransformKeycap(
                                    label: key.uppercased(),
                                    isHighlighted: hasMapping,
                                    isInput: true
                                )
                            }
                        }
                    }
                }

                // Arrow
                Image(systemName: "arrow.right")
                    .font(.title3)
                    .foregroundColor(.secondary)

                // Output keyboard
                VStack(alignment: .leading, spacing: 2) {
                    Text("Becomes")
                        .font(.caption2)
                        .foregroundColor(.secondary)
                        .padding(.bottom, 2)

                    ForEach(Array(Self.keyboardRows.enumerated()), id: \.offset) { rowIndex, row in
                        HStack(spacing: 3) {
                            // Match stagger
                            if rowIndex == 1 {
                                Spacer().frame(width: 8)
                            } else if rowIndex == 2 {
                                Spacer().frame(width: 16)
                            }

                            ForEach(row, id: \.self) { key in
                                let output = outputFor(key)
                                TransformKeycap(
                                    label: output ?? key.uppercased(),
                                    isHighlighted: output != nil,
                                    isInput: false
                                )
                            }
                        }
                    }
                }
            }

            // Physical position note for alternative layout users
            Text("Keys labeled by physical position (QWERTY). Works with any keyboard layout.")
                .font(.caption2)
                .foregroundStyle(.tertiary)
        }
        .padding(12)
        .background(
            RoundedRectangle(cornerRadius: 10)
                .fill(Color(NSColor.controlBackgroundColor).opacity(0.5))
        )
    }
}

// MARK: - Transform Keycap

private struct TransformKeycap: View {
    let label: String
    let isHighlighted: Bool
    let isInput: Bool

    var body: some View {
        Text(label)
            .font(.system(size: 11, weight: isHighlighted ? .semibold : .regular, design: .monospaced))
            .frame(width: 22, height: 22)
            .foregroundColor(isHighlighted ? (isInput ? .primary : .accentColor) : .secondary)
            .background(
                RoundedRectangle(cornerRadius: 4)
                    .fill(isHighlighted && !isInput ? Color.accentColor.opacity(0.15) : Color(NSColor.controlBackgroundColor))
            )
            .overlay(
                RoundedRectangle(cornerRadius: 4)
                    .stroke(isHighlighted ? (isInput ? Color.primary.opacity(0.3) : Color.accentColor.opacity(0.5)) : Color.secondary.opacity(0.2), lineWidth: 1)
            )
    }
}

// MARK: - Numpad Transform Grid (specialized for numpad layout)

private struct NumpadTransformGrid: View {
    let mappings: [KeyMapping]

    // Right hand numpad keys
    private static let numpadKeys: [[String]] = [
        ["u", "i", "o"],
        ["j", "k", "l"],
        ["m", ",", "."]
    ]

    // Left hand operator keys
    private static let operatorKeys: [String] = ["a", "s", "d", "f", "g"]

    private func outputFor(_ input: String) -> String? {
        mappings.first { $0.input.lowercased() == input.lowercased() }?.description
    }

    var body: some View {
        VStack(spacing: 8) {
            HStack(alignment: .top, spacing: 24) {
                // Left hand - operators
                VStack(alignment: .leading, spacing: 8) {
                    Text("Left Hand")
                        .font(.caption2)
                        .foregroundColor(.secondary)

                    Text("Operators")
                        .font(.caption.weight(.medium))

                    HStack(spacing: 4) {
                        ForEach(Self.operatorKeys, id: \.self) { key in
                            VStack(spacing: 2) {
                                TransformKeycap(label: key.uppercased(), isHighlighted: true, isInput: true)
                                Image(systemName: "arrow.down")
                                    .font(.system(size: 8))
                                    .foregroundColor(.secondary)
                                TransformKeycap(label: outputFor(key) ?? key, isHighlighted: true, isInput: false)
                            }
                        }
                    }
                }

                Divider()
                    .frame(height: 100)

                // Right hand - numpad
                VStack(alignment: .leading, spacing: 8) {
                    Text("Right Hand")
                        .font(.caption2)
                        .foregroundColor(.secondary)

                    HStack(alignment: .center, spacing: 12) {
                        // Input side
                        VStack(spacing: 3) {
                            ForEach(Self.numpadKeys, id: \.self) { row in
                                HStack(spacing: 3) {
                                    ForEach(row, id: \.self) { key in
                                        TransformKeycap(label: key.uppercased(), isHighlighted: true, isInput: true)
                                    }
                                }
                            }
                            // Zero row
                            HStack(spacing: 3) {
                                TransformKeycap(label: "N", isHighlighted: true, isInput: true)
                                TransformKeycap(label: "/", isHighlighted: true, isInput: true)
                            }
                        }

                        Image(systemName: "arrow.right")
                            .font(.title3)
                            .foregroundColor(.secondary)

                        // Output side (numpad)
                        VStack(spacing: 3) {
                            ForEach(Array(Self.numpadKeys.enumerated()), id: \.offset) { _, row in
                                HStack(spacing: 3) {
                                    ForEach(row, id: \.self) { key in
                                        TransformKeycap(label: outputFor(key) ?? "?", isHighlighted: true, isInput: false)
                                    }
                                }
                            }
                            // Zero row
                            HStack(spacing: 3) {
                                TransformKeycap(label: outputFor("n") ?? "0", isHighlighted: true, isInput: false)
                                TransformKeycap(label: outputFor("/") ?? ".", isHighlighted: true, isInput: false)
                            }
                        }
                    }
                }
            }

            // Physical position note for alternative layout users
            Text("Keys labeled by physical position (QWERTY). Works with any keyboard layout.")
                .font(.caption2)
                .foregroundStyle(.tertiary)
        }
        .padding(16)
        .background(
            RoundedRectangle(cornerRadius: 10)
                .fill(Color(NSColor.controlBackgroundColor).opacity(0.5))
        )
    }
}

// MARK: - Tap-Hold Picker Content

private struct TapHoldPickerContent: View {
    let collection: RuleCollection
    let onSelectTapOutput: (String) -> Void
    let onSelectHoldOutput: (String) -> Void

    @State private var selectedTap: String
    @State private var selectedHold: String
    @State private var showingCustomTapPopover = false
    @State private var showingCustomHoldPopover = false
    @State private var customTapInput = ""
    @State private var customHoldInput = ""

    private var config: TapHoldPickerConfig? {
        collection.configuration.tapHoldPickerConfig
    }

    init(collection: RuleCollection, onSelectTapOutput: @escaping (String) -> Void, onSelectHoldOutput: @escaping (String) -> Void) {
        self.collection = collection
        self.onSelectTapOutput = onSelectTapOutput
        self.onSelectHoldOutput = onSelectHoldOutput
        let cfg = collection.configuration.tapHoldPickerConfig
        let tapOptions = cfg?.tapOptions ?? []
        let holdOptions = cfg?.holdOptions ?? []
        _selectedTap = State(initialValue: cfg?.selectedTapOutput ?? tapOptions.first?.output ?? "hyper")
        _selectedHold = State(initialValue: cfg?.selectedHoldOutput ?? holdOptions.first?.output ?? "hyper")
    }

    private var tapOptions: [SingleKeyPreset] {
        config?.tapOptions ?? []
    }

    private var holdOptions: [SingleKeyPreset] {
        config?.holdOptions ?? []
    }

    private var selectedTapPreset: SingleKeyPreset? {
        tapOptions.first { $0.output == selectedTap }
    }

    private var selectedHoldPreset: SingleKeyPreset? {
        holdOptions.first { $0.output == selectedHold }
    }

    private var isCustomTapSelection: Bool {
        !tapOptions.contains { $0.output == selectedTap } && !selectedTap.isEmpty
    }

    private var isCustomHoldSelection: Bool {
        !holdOptions.contains { $0.output == selectedHold } && !selectedHold.isEmpty
    }

    /// Get display label for a custom tap selection (handles system actions)
    private var customTapDisplayLabel: String {
        displayLabelFor(selectedTap)
    }

    /// Get display label for a custom hold selection (handles system actions)
    private var customHoldDisplayLabel: String {
        displayLabelFor(selectedHold)
    }

    /// Get display label for a custom value (system action or key)
    private func displayLabelFor(_ value: String) -> String {
        if let actionId = CustomRuleValidator.extractSystemActionId(from: value),
           let action = CustomRuleValidator.systemAction(for: actionId) {
            return action.name
        }
        return value
    }

    /// Get SF Symbol for a custom value if it's a system action
    private func sfSymbolFor(_ value: String) -> String? {
        if let actionId = CustomRuleValidator.extractSystemActionId(from: value),
           let action = CustomRuleValidator.systemAction(for: actionId) {
            return action.sfSymbol
        }
        return nil
    }

    /// Check if caps lock is "lost" (not available via tap or hold)
    private var capsLockLost: Bool {
        selectedTap != "caps" && selectedHold != "caps"
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            // TAP section
            VStack(alignment: .leading, spacing: 8) {
                Text("TAP")
                    .font(.caption.weight(.semibold))
                    .foregroundColor(.secondary)

                HStack(spacing: 0) {
                    ForEach(tapOptions) { preset in
                        PickerSegment(
                            label: preset.label,
                            isSelected: selectedTap == preset.output,
                            isFirst: preset.id == tapOptions.first?.id,
                            isLast: preset.id == tapOptions.last?.id && !isCustomTapSelection
                        ) {
                            selectedTap = preset.output
                            onSelectTapOutput(preset.output)
                        }
                    }

                    // Show custom selection as a segment when one is selected
                    if isCustomTapSelection {
                        CustomValueSegment(
                            label: customTapDisplayLabel,
                            sfSymbol: sfSymbolFor(selectedTap),
                            isSelected: true,
                            isLast: false
                        ) {
                            // Already selected, do nothing
                        }
                    }

                    PickerSegment(
                        label: isCustomTapSelection ? "Edit" : "Custom",
                        isSelected: false,
                        isFirst: false,
                        isLast: true
                    ) {
                        customTapInput = isCustomTapSelection ? selectedTap : ""
                        showingCustomTapPopover = true
                    }
                    .popover(isPresented: $showingCustomTapPopover, arrowEdge: .bottom) {
                        CustomKeyPopover(
                            keyInput: $customTapInput,
                            onConfirm: {
                                // For system action outputs, use the value directly
                                if CustomRuleValidator.isSystemActionOutput(customTapInput) {
                                    selectedTap = customTapInput
                                    onSelectTapOutput(customTapInput)
                                } else {
                                    let normalized = CustomRuleValidator.normalizeKey(customTapInput)
                                    if CustomRuleValidator.isValidKey(normalized) {
                                        selectedTap = normalized
                                        onSelectTapOutput(normalized)
                                    }
                                }
                                showingCustomTapPopover = false
                            },
                            onCancel: {
                                showingCustomTapPopover = false
                            }
                        )
                    }
                }
                .padding(.horizontal, 4)

                if let preset = selectedTapPreset {
                    Text(preset.description)
                        .font(.caption)
                        .foregroundColor(.secondary)
                        .padding(.horizontal, 4)
                }
            }

            // HOLD section
            VStack(alignment: .leading, spacing: 8) {
                Text("HOLD")
                    .font(.caption.weight(.semibold))
                    .foregroundColor(.secondary)

                HStack(spacing: 0) {
                    ForEach(holdOptions) { preset in
                        PickerSegment(
                            label: preset.label,
                            isSelected: selectedHold == preset.output,
                            isFirst: preset.id == holdOptions.first?.id,
                            isLast: preset.id == holdOptions.last?.id && !isCustomHoldSelection
                        ) {
                            selectedHold = preset.output
                            onSelectHoldOutput(preset.output)
                        }
                    }

                    // Show custom selection as a segment when one is selected
                    if isCustomHoldSelection {
                        CustomValueSegment(
                            label: customHoldDisplayLabel,
                            sfSymbol: sfSymbolFor(selectedHold),
                            isSelected: true,
                            isLast: false
                        ) {
                            // Already selected, do nothing
                        }
                    }

                    PickerSegment(
                        label: isCustomHoldSelection ? "Edit" : "Custom",
                        isSelected: false,
                        isFirst: false,
                        isLast: true
                    ) {
                        customHoldInput = isCustomHoldSelection ? selectedHold : ""
                        showingCustomHoldPopover = true
                    }
                    .popover(isPresented: $showingCustomHoldPopover, arrowEdge: .bottom) {
                        CustomKeyPopover(
                            keyInput: $customHoldInput,
                            onConfirm: {
                                // For system action outputs, use the value directly
                                if CustomRuleValidator.isSystemActionOutput(customHoldInput) {
                                    selectedHold = customHoldInput
                                    onSelectHoldOutput(customHoldInput)
                                } else {
                                    let normalized = CustomRuleValidator.normalizeKey(customHoldInput)
                                    if CustomRuleValidator.isValidKey(normalized) {
                                        selectedHold = normalized
                                        onSelectHoldOutput(normalized)
                                    }
                                }
                                showingCustomHoldPopover = false
                            },
                            onCancel: {
                                showingCustomHoldPopover = false
                            }
                        )
                    }
                }
                .padding(.horizontal, 4)

                if let preset = selectedHoldPreset {
                    Text(preset.description)
                        .font(.caption)
                        .foregroundColor(.secondary)
                        .padding(.horizontal, 4)
                }
            }

            // Suggestion: Lost Caps Lock
            if capsLockLost {
                HStack(spacing: 8) {
                    Image(systemName: "lightbulb.fill")
                        .foregroundColor(.yellow)
                        .font(.caption)
                    Text("Lost Caps Lock? Enable \"Backup Caps Lock\" to get it back via Both Shifts.")
                        .font(.caption)
                        .foregroundColor(.secondary)
                }
                .padding(10)
                .background(
                    RoundedRectangle(cornerRadius: 8)
                        .fill(Color.yellow.opacity(0.1))
                )
                .padding(.top, 4)
            }
        }
        .padding(.vertical, 8)
        .animation(.easeInOut(duration: 0.15), value: selectedTap)
        .animation(.easeInOut(duration: 0.15), value: selectedHold)
    }
}

// MARK: - Custom Key Popover

private struct CustomKeyPopover: View {
    @Binding var keyInput: String
    let onConfirm: () -> Void
    let onCancel: () -> Void

    @State private var showingSuggestions = true
    @FocusState private var isInputFocused: Bool

    private var structuredSuggestions: [CustomRuleValidator.Suggestion] {
        Array(CustomRuleValidator.structuredSuggestions(for: keyInput).prefix(12))
    }

    private var isValidKey: Bool {
        // For system action outputs, they're already in the correct format
        if CustomRuleValidator.isSystemActionOutput(keyInput) {
            return true
        }
        let normalized = CustomRuleValidator.normalizeKey(keyInput)
        return CustomRuleValidator.isValidKey(normalized)
    }

    /// Display label for the current input (shows friendly name for system actions)
    private var displayLabel: String {
        if let actionId = CustomRuleValidator.extractSystemActionId(from: keyInput),
           let action = CustomRuleValidator.systemAction(for: actionId) {
            return action.name
        }
        return keyInput
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Enter Custom Key or Action")
                .font(.headline)

            // Key input with autocomplete
            VStack(alignment: .leading, spacing: 4) {
                TextField("Key name or action (e.g., tab, Mission Control)", text: $keyInput)
                    .textFieldStyle(.roundedBorder)
                    .focused($isInputFocused)
                    .onSubmit {
                        if isValidKey {
                            onConfirm()
                        }
                    }
                    .onChange(of: keyInput) { _, _ in
                        showingSuggestions = true
                    }

                // Autocomplete suggestions with icons for system actions
                if showingSuggestions, !structuredSuggestions.isEmpty {
                    ScrollView {
                        LazyVStack(alignment: .leading, spacing: 4) {
                            ForEach(Array(structuredSuggestions.enumerated()), id: \.offset) { _, suggestion in
                                Button {
                                    keyInput = suggestion.value
                                    showingSuggestions = false
                                } label: {
                                    HStack(spacing: 6) {
                                        if let symbol = suggestion.sfSymbol {
                                            Image(systemName: symbol)
                                                .font(.caption)
                                                .foregroundColor(.accentColor)
                                                .frame(width: 16)
                                        }
                                        Text(suggestion.displayLabel)
                                            .font(.caption)
                                            .lineLimit(1)
                                        Spacer()
                                    }
                                    .padding(.horizontal, 8)
                                    .padding(.vertical, 6)
                                    .background(Color.accentColor.opacity(0.08))
                                    .cornerRadius(4)
                                }
                                .buttonStyle(.plain)
                            }
                        }
                    }
                    .frame(maxHeight: 180)
                }

                // Show friendly name when system action is selected
                if CustomRuleValidator.isSystemActionOutput(keyInput) {
                    HStack(spacing: 4) {
                        Image(systemName: "checkmark.circle.fill")
                            .foregroundColor(.green)
                            .font(.caption)
                        Text("Action: \(displayLabel)")
                            .font(.caption)
                            .foregroundColor(.secondary)
                    }
                }
                // Validation feedback for invalid input
                else if !keyInput.isEmpty, !isValidKey {
                    Text("Unknown key name")
                        .font(.caption)
                        .foregroundColor(.orange)
                }
            }

            Divider()

            // Buttons
            HStack {
                Button("Cancel") {
                    onCancel()
                }
                .keyboardShortcut(.escape)
                .accessibilityIdentifier("rules-summary-custom-key-cancel-button")
                .accessibilityLabel("Cancel")

                Spacer()

                Button("OK") {
                    onConfirm()
                }
                .keyboardShortcut(.return)
                .disabled(!isValidKey)
                .buttonStyle(.borderedProminent)
                .accessibilityIdentifier("rules-summary-custom-key-ok-button")
                .accessibilityLabel("OK")
            }
        }
        .padding(16)
        .frame(width: 320)
        .onAppear {
            isInputFocused = true
        }
    }
}

private struct PickerSegment: View {
    let label: String
    let isSelected: Bool
    let isFirst: Bool
    let isLast: Bool
    let action: () -> Void

    @State private var isHovered = false

    var body: some View {
        Button(action: action) {
            Text(label)
                .font(.subheadline.weight(isSelected ? .semibold : .regular))
                .foregroundColor(isSelected ? .white : .primary)
                .padding(.horizontal, 16)
                .padding(.vertical, 8)
                .frame(minWidth: 70)
                .background(
                    RoundedRectangle(cornerRadius: isFirst ? 6 : (isLast ? 6 : 0))
                        .fill(isSelected ? Color.accentColor : (isHovered ? Color.primary.opacity(0.08) : Color.clear))
                        .clipShape(SegmentShape(isFirst: isFirst, isLast: isLast))
                )
        }
        .buttonStyle(.plain)
        .accessibilityIdentifier("rules-summary-segment-button-\(label.lowercased().replacingOccurrences(of: " ", with: "-"))")
        .accessibilityLabel(label)
        .onHover { isHovered = $0 }
    }
}

private struct SegmentShape: Shape {
    let isFirst: Bool
    let isLast: Bool

    func path(in rect: CGRect) -> Path {
        let radius: CGFloat = 6
        var path = Path()

        if isFirst, isLast {
            path.addRoundedRect(in: rect, cornerSize: CGSize(width: radius, height: radius))
        } else if isFirst {
            path.move(to: CGPoint(x: rect.minX + radius, y: rect.minY))
            path.addLine(to: CGPoint(x: rect.maxX, y: rect.minY))
            path.addLine(to: CGPoint(x: rect.maxX, y: rect.maxY))
            path.addLine(to: CGPoint(x: rect.minX + radius, y: rect.maxY))
            path.addArc(
                center: CGPoint(x: rect.minX + radius, y: rect.maxY - radius),
                radius: radius, startAngle: .degrees(90), endAngle: .degrees(180), clockwise: false
            )
            path.addLine(to: CGPoint(x: rect.minX, y: rect.minY + radius))
            path.addArc(
                center: CGPoint(x: rect.minX + radius, y: rect.minY + radius),
                radius: radius, startAngle: .degrees(180), endAngle: .degrees(270), clockwise: false
            )
        } else if isLast {
            path.move(to: CGPoint(x: rect.minX, y: rect.minY))
            path.addLine(to: CGPoint(x: rect.maxX - radius, y: rect.minY))
            path.addArc(
                center: CGPoint(x: rect.maxX - radius, y: rect.minY + radius),
                radius: radius, startAngle: .degrees(270), endAngle: .degrees(0), clockwise: false
            )
            path.addLine(to: CGPoint(x: rect.maxX, y: rect.maxY - radius))
            path.addArc(
                center: CGPoint(x: rect.maxX - radius, y: rect.maxY - radius),
                radius: radius, startAngle: .degrees(0), endAngle: .degrees(90), clockwise: false
            )
            path.addLine(to: CGPoint(x: rect.minX, y: rect.maxY))
            path.closeSubpath()
        } else {
            path.addRect(rect)
        }

        return path
    }
}

// MARK: - Custom Value Segment

/// A segment that displays a custom value (with optional icon for system actions)
private struct CustomValueSegment: View {
    let label: String
    let sfSymbol: String?
    let isSelected: Bool
    let isLast: Bool
    let action: () -> Void

    @State private var isHovered = false

    var body: some View {
        Button(action: action) {
            HStack(spacing: 4) {
                if let symbol = sfSymbol {
                    Image(systemName: symbol)
                        .font(.caption)
                }
                Text(label)
                    .font(.subheadline.weight(isSelected ? .semibold : .regular))
                    .lineLimit(1)
            }
            .foregroundColor(isSelected ? .white : .primary)
            .padding(.horizontal, 12)
            .padding(.vertical, 8)
            .frame(minWidth: 60)
            .background(
                RoundedRectangle(cornerRadius: isLast ? 6 : 0)
                    .fill(isSelected ? Color.accentColor : (isHovered ? Color.primary.opacity(0.08) : Color.clear))
                    .clipShape(SegmentShape(isFirst: false, isLast: isLast))
            )
        }
        .buttonStyle(.plain)
        .accessibilityIdentifier("rules-summary-custom-segment-\(label.lowercased().replacingOccurrences(of: " ", with: "-"))")
        .accessibilityLabel(label)
        .onHover { isHovered = $0 }
    }
}

// MARK: - Vim Command Cards View

/// An animated, educational view for Vim navigation commands organized by category.
/// Uses a 2-column layout with equal-height rows and hover effects.
private struct VimCommandCardsView: View {
    let mappings: [KeyMapping]

    @State private var hasAppeared = false

    private var categories: [VimCategory] {
        VimCategory.allCases.filter { !commandsFor($0).isEmpty }
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            // Row 1: Navigation + Editing
            HStack(alignment: .top, spacing: 12) {
                if let nav = categories.first(where: { $0 == .navigation }) {
                    cardView(for: nav, index: 0)
                }
                if let edit = categories.first(where: { $0 == .editing }) {
                    cardView(for: edit, index: 1)
                }
            }
            .fixedSize(horizontal: false, vertical: true)

            // Row 2: Search + Clipboard
            HStack(alignment: .top, spacing: 12) {
                if let search = categories.first(where: { $0 == .search }) {
                    cardView(for: search, index: 2)
                }
                if let clip = categories.first(where: { $0 == .clipboard }) {
                    cardView(for: clip, index: 3)
                }
            }
            .fixedSize(horizontal: false, vertical: true)

            // Shift tip
            HStack(spacing: 6) {
                Image(systemName: "lightbulb.fill")
                    .foregroundColor(.yellow)
                    .font(.caption)
                Text("Hold ⇧ Shift while navigating to select text")
                    .font(.caption)
                    .foregroundColor(.secondary)
            }
            .padding(.top, 4)
            .opacity(hasAppeared ? 1 : 0)
            .animation(.easeOut.delay(0.5), value: hasAppeared)
        }
        .onAppear {
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.1) {
                hasAppeared = true
            }
        }
    }

    @ViewBuilder
    private func cardView(for category: VimCategory, index: Int) -> some View {
        VimCategoryCard(
            category: category,
            commands: commandsFor(category)
        )
        .scaleEffect(hasAppeared ? 1 : 0.8)
        .opacity(hasAppeared ? 1 : 0)
        .animation(
            .spring(response: 0.5, dampingFraction: 0.7)
                .delay(Double(index) * 0.1),
            value: hasAppeared
        )
    }

    private func commandsFor(_ category: VimCategory) -> [KeyMapping] {
        let inputs = category.commandInputs
        return mappings.filter { inputs.contains($0.input.lowercased()) }
    }
}

// MARK: - Vim Category Enum

private enum VimCategory: String, CaseIterable, Identifiable {
    case navigation
    case editing
    case search
    case clipboard

    var id: String { rawValue }

    var title: String {
        switch self {
        case .navigation: "Navigation"
        case .editing: "Editing"
        case .search: "Search"
        case .clipboard: "Clipboard"
        }
    }

    var icon: String {
        switch self {
        case .navigation: "arrow.up.arrow.down"
        case .editing: "scissors"
        case .search: "magnifyingglass"
        case .clipboard: "doc.on.clipboard"
        }
    }

    var commandInputs: [String] {
        switch self {
        case .navigation: ["h", "j", "k", "l", "0", "4", "a", "g"]
        case .editing: ["x", "r", "d", "u", "o"]
        case .search: ["/", "n"]
        case .clipboard: ["y", "p"]
        }
    }

    var accentColor: Color {
        switch self {
        case .navigation: .blue
        case .editing: .orange
        case .search: .purple
        case .clipboard: .green
        }
    }
}

// MARK: - Vim Category Card

private struct VimCategoryCard: View {
    let category: VimCategory
    let commands: [KeyMapping]

    @State private var isHovered = false

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            // Header with icon and title
            HStack(spacing: 8) {
                Image(systemName: category.icon)
                    .font(.system(size: 14, weight: .semibold))
                    .foregroundColor(isHovered ? .white : category.accentColor)
                    .symbolEffect(.bounce, value: isHovered)
                    .frame(width: 26, height: 26)
                    .background(
                        RoundedRectangle(cornerRadius: 6)
                            .fill(isHovered ? category.accentColor : category.accentColor.opacity(0.15))
                    )

                Text(category.title)
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundColor(.primary)

                Spacer()
            }

            // Special HJKL cluster for navigation
            if category == .navigation {
                VimArrowKeysCompact()
                    .padding(.vertical, 4)
            }

            // Command list
            VStack(alignment: .leading, spacing: 2) {
                ForEach(commands, id: \.id) { command in
                    VimCommandRowCompact(command: command, accentColor: category.accentColor)
                }
            }

            Spacer(minLength: 0)
        }
        .padding(12)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        .background(
            RoundedRectangle(cornerRadius: 12)
                .fill(Color(NSColor.controlBackgroundColor).opacity(isHovered ? 0.9 : 0.6))
        )
        .overlay(
            RoundedRectangle(cornerRadius: 12)
                .stroke(category.accentColor.opacity(isHovered ? 0.5 : 0.2), lineWidth: isHovered ? 2 : 1)
        )
        .scaleEffect(isHovered ? 1.02 : 1.0)
        .shadow(color: category.accentColor.opacity(isHovered ? 0.2 : 0), radius: 8, x: 0, y: 4)
        .animation(.spring(response: 0.3, dampingFraction: 0.7), value: isHovered)
        .onHover { hovering in
            isHovered = hovering
        }
    }
}

// MARK: - Vim Arrow Keys View (HJKL with directional pulse)

private struct VimArrowKeysView: View {
    var body: some View {
        VStack(spacing: 8) {
            // Arrow key cluster
            HStack(spacing: 20) {
                // Left side labels
                VStack(alignment: .trailing, spacing: 4) {
                    Text("← H")
                        .font(.system(size: 11, weight: .medium, design: .monospaced))
                    Text("Move left")
                        .font(.caption2)
                        .foregroundColor(.secondary)
                }

                // Center cluster (J K)
                VStack(spacing: 4) {
                    VimArrowKey(key: "K", direction: .up)
                    HStack(spacing: 4) {
                        VimArrowKey(key: "H", direction: .left)
                        VimArrowKey(key: "J", direction: .down)
                        VimArrowKey(key: "L", direction: .right)
                    }
                }

                // Right side labels
                VStack(alignment: .leading, spacing: 4) {
                    Text("L →")
                        .font(.system(size: 11, weight: .medium, design: .monospaced))
                    Text("Move right")
                        .font(.caption2)
                        .foregroundColor(.secondary)
                }
            }
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 8)
    }
}

// MARK: - Vim Arrow Key (with directional pulse)

private struct VimArrowKey: View {
    let key: String
    let direction: ArrowDirection

    @State private var isHovered = false
    @State private var pulseOffset: CGSize = .zero
    @State private var pulseOpacity: Double = 0

    enum ArrowDirection {
        case up, down, left, right

        var arrow: String {
            switch self {
            case .up: "↑"
            case .down: "↓"
            case .left: "←"
            case .right: "→"
            }
        }

        var offset: CGSize {
            switch self {
            case .up: CGSize(width: 0, height: -12)
            case .down: CGSize(width: 0, height: 12)
            case .left: CGSize(width: -12, height: 0)
            case .right: CGSize(width: 12, height: 0)
            }
        }
    }

    var body: some View {
        ZStack {
            // Pulse arrow (animated)
            Text(direction.arrow)
                .font(.system(size: 14, weight: .bold))
                .foregroundColor(.blue)
                .offset(pulseOffset)
                .opacity(pulseOpacity)

            // Key label
            Text(key)
                .font(.system(size: 13, weight: .semibold, design: .monospaced))
                .foregroundColor(isHovered ? .blue : .primary)
                .frame(width: 28, height: 28)
                .background(
                    RoundedRectangle(cornerRadius: 6)
                        .fill(Color(NSColor.controlBackgroundColor))
                )
                .overlay(
                    RoundedRectangle(cornerRadius: 6)
                        .stroke(isHovered ? Color.blue.opacity(0.5) : Color.secondary.opacity(0.2), lineWidth: 1)
                )
        }
        .onHover { hovering in
            isHovered = hovering
            if hovering {
                triggerPulse()
            }
        }
    }

    private func triggerPulse() {
        // Reset
        pulseOffset = .zero
        pulseOpacity = 0.8

        // Animate outward
        withAnimation(.easeOut(duration: 0.4)) {
            pulseOffset = direction.offset
            pulseOpacity = 0
        }
    }
}

// MARK: - Vim Command Row

private struct VimCommandRow: View {
    let command: KeyMapping
    let accentColor: Color

    var body: some View {
        HStack(spacing: 12) {
            // Key
            StandardKeyBadge(key: command.input, color: accentColor)

            // Description
            if let desc = command.description {
                Text(desc)
                    .font(.system(size: 12))
                    .foregroundColor(.primary)
            }

            Spacer()

            // Shift variant indicator
            if command.shiftedOutput != nil {
                HStack(spacing: 2) {
                    Text("+⇧")
                        .font(.system(size: 10, weight: .medium))
                        .foregroundColor(.orange)
                }
            }

            // Ctrl variant indicator
            if command.ctrlOutput != nil {
                HStack(spacing: 2) {
                    Text("+⌃")
                        .font(.system(size: 10, weight: .medium))
                        .foregroundColor(.cyan)
                }
            }
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 6)
    }
}

// MARK: - Vim Arrow Keys Compact (for 2-column layout)

private struct VimArrowKeysCompact: View {
    var body: some View {
        HStack(spacing: 4) {
            ForEach(["H", "J", "K", "L"], id: \.self) { key in
                VimKeyBadge(key: key, color: .blue)
            }
            Text("= Arrow keys")
                .font(.system(size: 10))
                .foregroundColor(.secondary)
        }
    }
}

// MARK: - Vim Key Badge

private struct VimKeyBadge: View {
    let key: String
    let color: Color

    @State private var isHovered = false

    var body: some View {
        Text(key)
            .font(.system(size: 14, weight: .semibold, design: .monospaced))
            .foregroundColor(isHovered ? .white : color)
            .frame(width: 28, height: 28)
            .background(
                RoundedRectangle(cornerRadius: 5)
                    .fill(isHovered ? color : color.opacity(0.15))
            )
            .scaleEffect(isHovered ? 1.1 : 1.0)
            .animation(.spring(response: 0.2, dampingFraction: 0.6), value: isHovered)
            .onHover { isHovered = $0 }
    }
}

// MARK: - Standard Key Badge

/// Consistent key badge styling used across all rule displays
private struct StandardKeyBadge: View {
    let key: String
    var color: Color = .blue

    var body: some View {
        Text(key.uppercased())
            .font(.system(size: 14, weight: .semibold, design: .monospaced))
            .foregroundColor(color)
            .frame(minWidth: 26, minHeight: 26)
            .padding(.horizontal, 4)
            .background(
                RoundedRectangle(cornerRadius: 5)
                    .fill(color.opacity(0.1))
            )
    }
}

// MARK: - Vim Command Row Compact

private struct VimCommandRowCompact: View {
    let command: KeyMapping
    let accentColor: Color

    var body: some View {
        HStack(spacing: 8) {
            // Key
            StandardKeyBadge(key: command.input, color: accentColor)

            // Description
            if let desc = command.description {
                Text(desc)
                    .font(.system(size: 11))
                    .foregroundColor(.secondary)
                    .lineLimit(1)
            }

            Spacer(minLength: 0)

            // Modifier indicators
            if command.shiftedOutput != nil {
                Text("⇧")
                    .font(.system(size: 9))
                    .foregroundColor(.orange)
            }
            if command.ctrlOutput != nil {
                Text("⌃")
                    .font(.system(size: 9))
                    .foregroundColor(.cyan)
            }
        }
        .padding(.vertical, 2)
    }
}

// MARK: - Mapping Table Content

private struct MappingTableContent: View {
    let mappings: [(input: String, output: String, shiftedOutput: String?, ctrlOutput: String?, description: String?, sectionBreak: Bool, enabled: Bool, id: UUID, behavior: MappingBehavior?)]

    private var hasShiftVariants: Bool {
        mappings.contains { $0.shiftedOutput != nil }
    }

    private var hasCtrlVariants: Bool {
        mappings.contains { $0.ctrlOutput != nil }
    }

    private var hasDescriptions: Bool {
        mappings.contains { $0.description != nil }
    }

    // Calculate column widths based on content
    private var keyColumnWidth: CGFloat {
        let maxInput = mappings.map { prettyKeyName($0.input) }.max(by: { $0.count < $1.count }) ?? ""
        return max(60, CGFloat(maxInput.count) * 10 + 20)
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            // Header row
            HStack(spacing: 0) {
                headerCell("Key")
                    .frame(minWidth: 80, alignment: .leading)
                    .padding(.leading, 12)
                    .padding(.trailing, 24)
                if hasDescriptions {
                    headerCell("Description")
                        .frame(minWidth: 150, maxWidth: .infinity, alignment: .leading)
                }
                headerCell("Action")
                    .frame(width: 90)
                if hasShiftVariants {
                    headerCell("+ Shift ⇧", color: .orange)
                        .frame(width: 100)
                }
                if hasCtrlVariants {
                    headerCell("+ Ctrl ⌃", color: .cyan)
                        .frame(width: 100)
                }
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 10)
            .background(Color(NSColor.controlBackgroundColor).opacity(0.5))

            // Data rows
            ForEach(Array(mappings.enumerated()), id: \.element.id) { _, mapping in
                // Section break separator (extra whitespace)
                if mapping.sectionBreak {
                    Spacer()
                        .frame(height: 12)
                }

                HStack(spacing: 0) {
                    keyCell(prettyKeyName(mapping.input))
                        .frame(minWidth: 80, alignment: .leading)
                        .padding(.leading, 12)
                        .padding(.trailing, 24)
                    if hasDescriptions {
                        descriptionCell(mapping.description)
                            .frame(minWidth: 150, maxWidth: .infinity)
                    }
                    actionCell(formatOutput(mapping.output))
                        .frame(width: 90)
                    if hasShiftVariants {
                        modifierCell(mapping.shiftedOutput.map { formatOutput($0) }, color: .orange)
                            .frame(width: 100)
                    }
                    if hasCtrlVariants {
                        modifierCell(mapping.ctrlOutput.map { formatOutput($0) }, color: .cyan)
                            .frame(width: 100)
                    }
                }
                .padding(.horizontal, 12)
                .padding(.vertical, 5)
            }
            .padding(.vertical, 4)
        }
        .background(Color(NSColor.controlBackgroundColor).opacity(0.3))
        .cornerRadius(8)
        .overlay(
            RoundedRectangle(cornerRadius: 8)
                .strokeBorder(Color.gray.opacity(0.2), lineWidth: 1)
        )
    }

    @ViewBuilder
    private func headerCell(_ text: String, color: Color = .secondary) -> some View {
        Text(text)
            .font(.subheadline.weight(.semibold))
            .foregroundColor(color)
    }

    @ViewBuilder
    private func keyCell(_ text: String) -> some View {
        StandardKeyBadge(key: formatKeyForDisplay(text), color: .blue)
            .fixedSize(horizontal: true, vertical: false)
    }

    @ViewBuilder
    private func descriptionCell(_ text: String?) -> some View {
        Text(text ?? "")
            .font(.body)
            .foregroundColor(.primary.opacity(0.8))
            .frame(maxWidth: .infinity, alignment: .leading)
    }

    @ViewBuilder
    private func actionCell(_ text: String) -> some View {
        Text(text)
            .font(.body.monospaced())
            .foregroundColor(.secondary)
            .fixedSize(horizontal: true, vertical: false)
            .frame(maxWidth: .infinity)
    }

    @ViewBuilder
    private func modifierCell(_ text: String?, color: Color) -> some View {
        if let text {
            Text(text)
                .font(.body.monospaced())
                .foregroundColor(color.opacity(0.9))
                .fixedSize(horizontal: true, vertical: false)
                .frame(maxWidth: .infinity)
        } else {
            Text("—")
                .font(.body)
                .foregroundColor(.secondary.opacity(0.3))
                .frame(maxWidth: .infinity)
        }
    }

    private func prettyKeyName(_ raw: String) -> String {
        raw.replacingOccurrences(of: "_", with: " ")
            .trimmingCharacters(in: .whitespaces)
            .capitalized
    }

    /// Format key name for display in Key column (show Mac modifier names & symbols)
    private func formatKeyForDisplay(_ key: String) -> String {
        let macModifiers: [String: String] = [
            // Command
            "Lmet": "⌘ Cmd",
            "Rmet": "⌘ Cmd",
            "Cmd": "⌘ Cmd",
            "Command": "⌘ Cmd",
            // Option/Alt
            "Lalt": "⌥ Opt",
            "Ralt": "⌥ Opt",
            "Alt": "⌥ Opt",
            "Option": "⌥ Opt",
            // Control
            "Lctl": "⌃ Ctrl",
            "Rctl": "⌃ Ctrl",
            "Ctrl": "⌃ Ctrl",
            "Control": "⌃ Ctrl",
            // Shift
            "Lsft": "⇧ Shift",
            "Rsft": "⇧ Shift",
            "Shift": "⇧ Shift",
            // Caps Lock
            "Caps": "⇪ Caps",
            "Capslock": "⇪ Caps",
            // Function keys stay as-is (F1, F2, etc.)
            // Special keys
            "Esc": "⎋ Esc",
            "Tab": "⇥ Tab",
            "Ret": "↩ Return",
            "Return": "↩ Return",
            "Enter": "↩ Return",
            "Spc": "␣ Space",
            "Space": "␣ Space",
            "Bspc": "⌫ Delete",
            "Backspace": "⌫ Delete",
            "Del": "⌦ Fwd Del",
            "Delete": "⌦ Fwd Del",
            // Arrow keys
            "Left": "←",
            "Right": "→",
            "Up": "↑",
            "Down": "↓",
            // Page navigation
            "Pgup": "Pg ↑",
            "Pgdn": "Pg ↓",
            "Home": "↖ Home",
            "End": "↘ End"
        ]

        // Check if we have a Mac-friendly name for this key
        if let macName = macModifiers[key] {
            return macName
        }

        // Handle modifier prefix notation (e.g., "C-M-A-up" -> "⌃⌘⌥↑")
        return formatModifierPrefixNotation(key, macModifiers: macModifiers)
    }

    /// Format modifier prefix notation (e.g., "C-M-A-up" -> "⌃⌘⌥↑")
    private func formatModifierPrefixNotation(_ key: String, macModifiers: [String: String]) -> String {
        // Modifier prefix symbols in Kanata notation
        let modifierPrefixes: [(prefix: String, symbol: String)] = [
            ("C-", "⌃"), // Control
            ("M-", "⌘"), // Meta/Command
            ("A-", "⌥"), // Alt/Option
            ("S-", "⇧") // Shift
        ]

        var remaining = key
        var symbols = ""

        // Extract modifier prefixes in order
        var foundModifier = true
        while foundModifier {
            foundModifier = false
            for (prefix, symbol) in modifierPrefixes {
                if remaining.hasPrefix(prefix) {
                    symbols += symbol
                    remaining = String(remaining.dropFirst(prefix.count))
                    foundModifier = true
                    break
                }
            }
        }

        // Format the base key
        let baseKey = remaining.isEmpty ? key : remaining
        let formattedBase: String = if let macName = macModifiers[baseKey.capitalized] {
            // Extract just the symbol part if it has a name (e.g., "↑" from "↑ Up")
            macName.components(separatedBy: " ").first ?? macName
        } else {
            baseKey.uppercased()
        }

        // Combine modifiers and base key
        if symbols.isEmpty {
            return formattedBase
        } else {
            return "\(symbols)\(formattedBase)"
        }
    }

    /// Format output for display (convert Kanata codes to readable symbols)
    private func formatOutput(_ output: String) -> String {
        // Split by space to handle multi-key sequences, format each part, rejoin with space
        output.split(separator: " ").map { part in
            String(part)
                // Multi-modifier combinations (order matters - longest first)
                .replacingOccurrences(of: "C-M-A-S-", with: "⌃⌘⌥⇧")
                .replacingOccurrences(of: "C-M-A-", with: "⌃⌘⌥")
                .replacingOccurrences(of: "M-S-", with: "⌘⇧")
                .replacingOccurrences(of: "C-S-", with: "⌃⇧")
                .replacingOccurrences(of: "A-S-", with: "⌥⇧")
                // Single modifiers
                .replacingOccurrences(of: "M-", with: "⌘")
                .replacingOccurrences(of: "A-", with: "⌥")
                .replacingOccurrences(of: "C-", with: "⌃")
                .replacingOccurrences(of: "S-", with: "⇧")
                // Arrow keys and special keys
                .replacingOccurrences(of: "left", with: "←")
                .replacingOccurrences(of: "right", with: "→")
                .replacingOccurrences(of: "up", with: "↑")
                .replacingOccurrences(of: "down", with: "↓")
                .replacingOccurrences(of: "ret", with: "↩")
                .replacingOccurrences(of: "bspc", with: "⌫")
                .replacingOccurrences(of: "del", with: "⌦")
                .replacingOccurrences(of: "pgup", with: "Pg↑")
                .replacingOccurrences(of: "pgdn", with: "Pg↓")
                .replacingOccurrences(of: "esc", with: "⎋")
        }.joined(separator: " ")
    }
}

// MARK: - Keycap Style

/// View modifier that applies overlay-style keycap appearance
private struct KeycapStyle: ViewModifier {
    /// Text color matching overlay keycaps (light blue-white)
    static let textColor = Color(red: 0.88, green: 0.93, blue: 1.0)

    /// Background color matching overlay keycaps (dark gray)
    static let backgroundColor = Color(white: 0.12)

    /// Corner radius matching overlay keycaps
    static let cornerRadius: CGFloat = 6

    func body(content: Content) -> some View {
        content
            .padding(.horizontal, 10)
            .padding(.vertical, 6)
            .background(
                RoundedRectangle(cornerRadius: Self.cornerRadius)
                    .fill(Self.backgroundColor)
                    .shadow(color: .black.opacity(0.4), radius: 1, y: 1)
            )
            .overlay(
                RoundedRectangle(cornerRadius: Self.cornerRadius)
                    .stroke(Color.white.opacity(0.15), lineWidth: 0.5)
            )
    }
}

// MARK: - App Launch Chip

/// Displays an app icon and name in a keycap style for app launch actions
private struct AppLaunchChip: View {
    let appIdentifier: String

    @State private var appIcon: NSImage?
    @State private var appName: String?

    var body: some View {
        HStack(spacing: 6) {
            // App icon
            if let icon = appIcon {
                Image(nsImage: icon)
                    .resizable()
                    .aspectRatio(contentMode: .fit)
                    .frame(width: 16, height: 16)
            } else {
                Image(systemName: "app.fill")
                    .font(.system(size: 12))
                    .foregroundColor(KeycapStyle.textColor.opacity(0.6))
                    .frame(width: 16, height: 16)
            }

            // App name
            Text(appName ?? appIdentifier)
                .font(.body.monospaced().weight(.semibold))
                .foregroundColor(KeycapStyle.textColor)
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 6)
        .background(
            RoundedRectangle(cornerRadius: KeycapStyle.cornerRadius)
                .fill(Color.accentColor.opacity(0.25))
                .shadow(color: .black.opacity(0.4), radius: 1, y: 1)
        )
        .overlay(
            RoundedRectangle(cornerRadius: KeycapStyle.cornerRadius)
                .stroke(Color.accentColor.opacity(0.4), lineWidth: 0.5)
        )
        .onAppear {
            loadAppInfo()
        }
    }

    private func loadAppInfo() {
        let workspace = NSWorkspace.shared

        // Try to find app by bundle identifier first
        if let appURL = workspace.urlForApplication(withBundleIdentifier: appIdentifier) {
            loadFromURL(appURL)
            return
        }

        // Try common paths
        let appName = appIdentifier.hasSuffix(".app") ? appIdentifier : "\(appIdentifier).app"
        let commonPaths = [
            "/Applications/\(appName)",
            "/System/Applications/\(appName)",
            "\(NSHomeDirectory())/Applications/\(appName)"
        ]

        for path in commonPaths {
            let url = URL(fileURLWithPath: path)
            if FileManager.default.fileExists(atPath: path) {
                loadFromURL(url)
                return
            }
        }

        // Fallback: use identifier as name (capitalize it)
        let parts = appIdentifier.replacingOccurrences(of: ".", with: " ")
            .split(separator: " ")
            .map(\.capitalized)
        self.appName = parts.last.map { String($0) } ?? appIdentifier
    }

    private func loadFromURL(_ url: URL) {
        // Get icon
        let icon = NSWorkspace.shared.icon(forFile: url.path)
        icon.size = NSSize(width: 32, height: 32) // Request appropriate size
        appIcon = icon

        // Get app name from bundle
        if let bundle = Bundle(url: url),
           let name = bundle.object(forInfoDictionaryKey: "CFBundleName") as? String {
            appName = name
        } else {
            // Use filename without extension
            appName = url.deletingPathExtension().lastPathComponent
        }
    }
}

// MARK: - Rules Section Headers for Custom Rules

/// Compact section header for rule groups (e.g., "Everywhere")
private struct RulesSectionHeaderCompact: View {
    let title: String
    let systemImage: String

    var body: some View {
        HStack(spacing: 6) {
            Image(systemName: systemImage)
                .font(.system(size: 11, weight: .semibold))
                .foregroundStyle(.secondary)

            Text(title)
                .font(.caption.weight(.semibold))
                .foregroundStyle(.secondary)

            Spacer()
        }
        .padding(.bottom, 4)
    }
}

/// Compact section header for app-specific rules with app icon
private struct AppRulesSectionHeaderCompact: View {
    let keymap: AppKeymap

    @State private var appIcon: NSImage?

    var body: some View {
        HStack(spacing: 6) {
            // App icon
            if let icon = appIcon {
                Image(nsImage: icon)
                    .resizable()
                    .frame(width: 14, height: 14)
            } else {
                Image(systemName: "app.fill")
                    .font(.system(size: 11))
                    .foregroundStyle(.secondary)
                    .frame(width: 14, height: 14)
            }

            Text(keymap.mapping.displayName)
                .font(.caption.weight(.semibold))
                .foregroundStyle(.secondary)

            Spacer()
        }
        .padding(.bottom, 4)
        .onAppear {
            loadAppIcon()
        }
    }

    private func loadAppIcon() {
        if let appURL = NSWorkspace.shared.urlForApplication(withBundleIdentifier: keymap.mapping.bundleIdentifier) {
            let icon = NSWorkspace.shared.icon(forFile: appURL.path)
            icon.size = NSSize(width: 28, height: 28)
            appIcon = icon
        }
    }
}

/// Compact row for displaying an app-specific rule override
private struct AppRuleRowCompact: View {
    let keymap: AppKeymap
    let override: AppKeyOverride
    let onEdit: () -> Void
    let onDelete: () -> Void
    let prettyKeyName: (String) -> String

    @State private var isHovered = false

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            HStack(spacing: 8) {
                // Mapping content
                HStack(spacing: 8) {
                    // Input key
                    Text(prettyKeyName(override.inputKey))
                        .font(.body.monospaced().weight(.semibold))
                        .foregroundColor(KeycapStyle.textColor)
                        .modifier(KeycapStyle())

                    Image(systemName: "arrow.right")
                        .font(.body.weight(.medium))
                        .foregroundColor(.secondary)

                    // Output key
                    Text(prettyKeyName(override.outputAction))
                        .font(.body.monospaced().weight(.semibold))
                        .foregroundColor(KeycapStyle.textColor)
                        .modifier(KeycapStyle())

                    Spacer(minLength: 0)
                }

                Spacer()

                // Action buttons - subtle icons that appear on hover (matching MappingRowView)
                HStack(spacing: 4) {
                    Button {
                        onEdit()
                    } label: {
                        Image(systemName: "pencil")
                            .font(.system(size: 12, weight: .medium))
                            .foregroundColor(.secondary.opacity(isHovered ? 1 : 0.5))
                            .frame(width: 28, height: 28)
                            .contentShape(Rectangle())
                    }
                    .buttonStyle(.plain)

                    Button {
                        onDelete()
                    } label: {
                        Image(systemName: "trash")
                            .font(.system(size: 12, weight: .medium))
                            .foregroundColor(.secondary.opacity(isHovered ? 1 : 0.5))
                            .frame(width: 28, height: 28)
                            .contentShape(Rectangle())
                    }
                    .buttonStyle(.plain)

                    // Spacer for alignment
                    Spacer()
                        .frame(width: 0)
                }
            }
        }
        .padding(.leading, 48)
        .padding(.trailing, 12)
        .padding(.vertical, 4)
        .padding(.horizontal, 8)
        .background(
            RoundedRectangle(cornerRadius: 8)
                .fill(isHovered ? Color.primary.opacity(0.03) : Color.clear)
        )
        .contentShape(Rectangle())
        .onHover { hovering in
            isHovered = hovering
            if hovering {
                NSCursor.pointingHand.push()
            } else {
                NSCursor.pop()
            }
        }
        .onTapGesture {
            onEdit()
        }
    }
}
