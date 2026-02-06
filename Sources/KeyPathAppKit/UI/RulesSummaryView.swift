import KeyPathCore
import SwiftUI

#if os(macOS)
    import AppKit
#endif

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

    /// View ID for custom rules section to force re-render on changes
    private var customRulesViewId: String {
        let rulesHash = kanataManager.customRules
            .map { "\($0.id)-\($0.input.hashValue)-\($0.output.hashValue)-\($0.title.hashValue)" }
            .joined()
        let appsHash = appKeymaps.map(\.id.uuidString).joined()
        return "custom-rules-\(rulesHash)-\(appsHash)"
    }

    /// Show all catalog collections, merging with existing state
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
        let needsCollection = style == .singleKeyPicker || style == .homeRowMods || style == .tapHoldPicker || style == .layerPresetPicker || style == .launcherGrid || style == .chordGroups ||
            style ==
            .sequences || isSpecializedTable

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
                AppLogger.shared.log("🎚️ [RulesSummary] onToggle called: collection=\(collection.name), id=\(collection.id), isOn=\(isOn)")
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

                Button {
                    openConfigInEditor()
                } label: {
                    Label("Edit Config", systemImage: "doc.text")
                }
                .buttonStyle(.bordered)
                .controlSize(.large)
                .accessibilityIdentifier("rules-edit-config-button")
                .accessibilityLabel("Edit Config")

                Button {
                    showingResetConfirmation = true
                } label: {
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
                        .id(customRulesViewId)
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
                    get: {
                        // Get the LATEST config from kanataManager, not the stale editState snapshot
                        if let currentCollection = kanataManager.ruleCollections.first(where: { $0.id == editState.collection.id }) {
                            return currentCollection.configuration.chordGroupsConfig ?? ChordGroupsConfig()
                        }
                        return editState.collection.configuration.chordGroupsConfig ?? ChordGroupsConfig()
                    },
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
                    get: {
                        // Get the LATEST config from kanataManager, not the stale editState snapshot
                        if let currentCollection = kanataManager.ruleCollections.first(where: { $0.id == editState.collection.id }) {
                            return currentCollection.configuration.sequencesConfig ?? SequencesConfig()
                        }
                        return editState.collection.configuration.sequencesConfig ?? SequencesConfig()
                    },
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
                """
            )
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

        // If collection is OFF, still show the selected output (not "?")
        // This helps users understand what the rule does before enabling
        let selectedOutput = config.selectedOutput ?? config.presetOptions.first?.output ?? ""
        let outputLabel = config.presetOptions.first { $0.output == selectedOutput }?.label ?? selectedOutput

        guard effectiveEnabled else {
            // For leader-based rules, show "Leader + [key] → [output]"
            if collection.momentaryActivator != nil {
                return "\(currentLeaderKeyDisplay) + \(inputDisplay) → \(outputLabel)"
            }
            return "\(inputDisplay) → \(outputLabel)"
        }

        // Check for pending selection (immediate UI feedback when user is changing the value)
        let effectiveOutput: String = if let pending = pendingSelections[collection.id] {
            pending
        } else {
            selectedOutput
        }

        // Get label for the effective output (may differ from selectedOutput if pending)
        let effectiveOutputLabel = config.presetOptions.first { $0.output == effectiveOutput }?.label ?? effectiveOutput

        // For leader-based rules, show "Leader + [input] → [output]" instead of "[input] → [output]"
        if collection.momentaryActivator != nil {
            return "\(currentLeaderKeyDisplay) + \(inputDisplay) → \(effectiveOutputLabel)"
        }

        return "\(inputDisplay) → \(effectiveOutputLabel)"
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
