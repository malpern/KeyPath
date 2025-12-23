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
    @State private var isPresentingNewRule = false
    @State private var editingRule: CustomRule?
    @State private var createButtonHovered = false
    /// Stable sort order captured when view appears (enabled collections first)
    @State private var stableSortOrder: [UUID] = []
    /// Track pending selections for immediate UI feedback (before backend confirms)
    @State private var pendingSelections: [UUID: String] = [:]
    /// Track pending toggle states for immediate UI feedback
    @State private var pendingToggles: [UUID: Bool] = [:]
    @State private var homeRowModsEditState: HomeRowModsEditState?
    private let catalog = RuleCollectionCatalog()

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
        let isNumpadTable = style == .table && collection.id == RuleCollectionIdentifier.numpadLayer
        let needsCollection = style == .singleKeyPicker || style == .homeRowMods || style == .tapHoldPicker || style == .layerPresetPicker || isNumpadTable

        ExpandableCollectionRow(
            name: dynamicCollectionName(for: collection),
            icon: collection.icon ?? "circle",
            count: style == .singleKeyPicker || style == .tapHoldPicker ? 1 : (style == .layerPresetPicker ? (collection.layerPresets?.first { $0.id == collection.selectedLayerPreset }?.mappings.count ?? 0) : collection.mappings.count),
            isEnabled: pendingToggles[collection.id] ?? collection.isEnabled,
            mappings: collection.mappings.map {
                ($0.input, $0.output, $0.shiftedOutput, $0.ctrlOutput, $0.description, $0.sectionBreak, collection.isEnabled, $0.id, nil)
            },
            onToggle: { isOn in
                pendingToggles[collection.id] = isOn
                if !isOn {
                    pendingSelections.removeValue(forKey: collection.id)
                }
                Task { await kanataManager.toggleRuleCollection(collection.id, enabled: isOn) }
            },
            onEditMapping: nil,
            onDeleteMapping: nil,
            description: dynamicCollectionDescription(for: collection),
            layerActivator: collection.momentaryActivator,
            leaderKeyDisplay: currentLeaderKeyDisplay,
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
            onSelectLayerPreset: style == .layerPresetPicker ? { presetId in
                Task { await kanataManager.updateCollectionLayerPreset(collection.id, presetId: presetId) }
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
                    isPresentingNewRule = true
                } label: {
                    Label("Create Rule", systemImage: "plus.circle.fill")
                }
                .buttonStyle(.borderedProminent)
                .controlSize(.large)

                Spacer()

                Button(action: { openConfigInEditor() }) {
                    Label("Edit Config", systemImage: "doc.text")
                }
                .buttonStyle(.bordered)
                .controlSize(.large)

                Button(action: { showingResetConfirmation = true }) {
                    Label("Reset", systemImage: "arrow.counterclockwise")
                }
                .buttonStyle(.bordered)
                .controlSize(.large)
                .tint(.red)
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
                            name: customRulesTitle,
                            icon: "square.and.pencil",
                            count: kanataManager.customRules.count,
                            isEnabled: kanataManager.customRules.isEmpty
                                || kanataManager.customRules.allSatisfy(\.isEnabled),
                            mappings: kanataManager.customRules.map { ($0.input, $0.output, nil, nil, $0.title.isEmpty ? nil : $0.title, false, $0.isEnabled, $0.id, $0.behavior) },
                            onToggle: { isOn in
                                Task {
                                    for rule in kanataManager.customRules {
                                        await kanataManager.toggleCustomRule(rule.id, enabled: isOn)
                                    }
                                }
                            },
                            onEditMapping: { id in
                                if let rule = kanataManager.customRules.first(where: { $0.id == id }) {
                                    editingRule = rule
                                }
                            },
                            onDeleteMapping: { id in
                                Task { await kanataManager.removeCustomRule(id) }
                            },
                            showZeroState: kanataManager.customRules.isEmpty,
                            onCreateFirstRule: { isPresentingNewRule = true },
                            description: "Remap any key combination or sequence",
                            defaultExpanded: !kanataManager.customRules.isEmpty,
                            scrollID: "custom-rules",
                            scrollProxy: scrollProxy
                        )
                        // Force SwiftUI to re-render when customRules changes (count OR content)
                        .id("custom-rules-\(kanataManager.customRules.map { "\($0.id)-\($0.input.hashValue)-\($0.output.hashValue)-\($0.title.hashValue)" }.joined())")
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
        }
        .sheet(isPresented: $isPresentingNewRule) {
            CustomRuleEditorView(
                rule: nil,
                existingRules: kanataManager.customRules
            ) { newRule in
                _ = Task { await kanataManager.saveCustomRule(newRule) }
            }
        }
        .sheet(item: $homeRowModsEditState) { editState in
            HomeRowModsModalView(
                config: Binding(
                    get: { editState.collection.homeRowModsConfig ?? HomeRowModsConfig() },
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
        .sheet(item: $editingRule) { rule in
            CustomRuleEditorView(
                rule: rule,
                existingRules: kanataManager.customRules
            ) { updatedRule in
                _ = Task { await kanataManager.saveCustomRule(updatedRule) }
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
            if isEnabled, let selectedOutput = leaderCollection.selectedOutput {
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

    /// Generate a dynamic description for tap-hold picker collections showing configured values
    private func dynamicCollectionDescription(for collection: RuleCollection) -> String {
        guard collection.displayStyle == .tapHoldPicker else {
            return collection.summary
        }

        // Check effective enabled state
        let effectiveEnabled: Bool = if let pendingToggle = pendingToggles[collection.id] {
            pendingToggle
        } else {
            collection.isEnabled
        }

        // If disabled, show the generic summary
        guard effectiveEnabled else {
            return collection.summary
        }

        // Get the selected tap and hold outputs
        let tapOutput = collection.selectedTapOutput ?? collection.tapHoldOptions?.tapOptions.first?.output ?? "esc"
        let holdOutput = collection.selectedHoldOutput ?? collection.tapHoldOptions?.holdOptions.first?.output ?? "hyper"

        // Find labels for the outputs
        let tapLabel = collection.tapHoldOptions?.tapOptions.first { $0.output == tapOutput }?.label ?? tapOutput
        let holdLabel = collection.tapHoldOptions?.holdOptions.first { $0.output == holdOutput }?.label ?? holdOutput

        return "Tap: \(tapLabel), Hold: \(holdLabel)"
    }

    /// Generate a dynamic name for picker-style collections that shows the current mapping
    private func dynamicCollectionName(for collection: RuleCollection) -> String {
        guard collection.displayStyle == .singleKeyPicker,
              let inputKey = collection.pickerInputKey
        else {
            return collection.name
        }

        // Format input key with Mac symbol
        let inputDisplay = formatKeyWithSymbol(inputKey)

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
            collection.selectedOutput ?? collection.presetOptions.first?.output ?? ""
        }

        // Get label for the output
        let outputLabel = collection.presetOptions.first { $0.output == effectiveOutput }?.label ?? effectiveOutput

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
}

// MARK: - Expandable Collection Row

private struct ExpandableCollectionRow: View {
    let name: String
    let icon: String
    let count: Int
    let isEnabled: Bool
    let mappings: [(input: String, output: String, shiftedOutput: String?, ctrlOutput: String?, description: String?, sectionBreak: Bool, enabled: Bool, id: UUID, behavior: MappingBehavior?)]
    let onToggle: (Bool) -> Void
    let onEditMapping: ((UUID) -> Void)?
    let onDeleteMapping: ((UUID) -> Void)?
    var showZeroState: Bool = false
    var onCreateFirstRule: (() -> Void)?
    var description: String?
    var layerActivator: MomentaryActivator?
    /// Current leader key display name for layer-based collections
    var leaderKeyDisplay: String = "␣ Space"
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
    /// For layerPresetPicker style: callback to select a layer preset
    var onSelectLayerPreset: ((String) -> Void)?
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
        VStack(alignment: .leading, spacing: 0) {
            // Scroll anchor for auto-scroll when expanded
            if let id = scrollID {
                Color.clear
                    .frame(height: 0)
                    .id(id)
            }

            // Header Row (clickable for expand/collapse)
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

                        if layerActivator != nil {
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
                }
                .padding(12)
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
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

            // Expanded Mappings or Zero State
            if isExpanded {
                if showZeroState, mappings.isEmpty, let onCreate = onCreateFirstRule {
                    // Zero State - only show if BOTH showZeroState is true AND mappings is actually empty
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
                    let config = coll.homeRowModsConfig ?? HomeRowModsConfig()
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
                                                        Button(action: {
                                                            onOpenHomeRowModsModalWithKey?(key)
                                                        }) {
                                                            HomeRowKeyChipSmall(letter: key.uppercased(), symbol: modSymbol)
                                                        }
                                                        .buttonStyle(.plain)
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
                                                        Button(action: {
                                                            onOpenHomeRowModsModalWithKey?(key)
                                                        }) {
                                                            HomeRowKeyChipSmall(letter: key.uppercased(), symbol: modSymbol)
                                                        }
                                                        .buttonStyle(.plain)
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
                } else if displayStyle == .table {
                    // Check if this is the numpad collection - use specialized grid
                    if collection?.id == RuleCollectionIdentifier.numpadLayer {
                        VStack(alignment: .leading, spacing: 8) {
                            Text("Transform your keyboard into a numpad")
                                .font(.subheadline)
                                .foregroundColor(.secondary)
                            NumpadTransformGrid(mappings: collection?.mappings ?? [])
                        }
                        .padding(.top, 8)
                        .padding(.bottom, 12)
                        .padding(.horizontal, 16)
                    } else {
                        // Table view for complex collections like Vim
                        MappingTableContent(mappings: mappings)
                            .padding(.top, 8)
                            .padding(.bottom, 12)
                            .padding(.horizontal, 12)
                    }
                } else {
                    // List view for standard collections and custom rules
                    VStack(spacing: 6) {
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
                    }
                    .padding(.top, 8)
                    .padding(.bottom, 12)
                }
            }
        }
        .onAppear {
            if !hasInitialized {
                isExpanded = defaultExpanded
                hasInitialized = true
            }
        }
        .onChange(of: defaultExpanded) { _, newValue in
            // Auto-expand when rules are added (going from empty to non-empty)
            if newValue, !isExpanded {
                withAnimation(.easeInOut(duration: 0.2)) {
                    isExpanded = true
                }
            }
        }
        .onChange(of: isEnabled) { _, _ in
            // Parent state updated, clear local override to stay in sync
            localEnabled = nil
        }
    }

    @ViewBuilder
    func iconView(for icon: String) -> some View {
        if icon.hasPrefix("text:") {
            let text = String(icon.dropFirst(5))
            Text(text)
                .font(.system(size: 14, weight: .bold, design: .monospaced))
                .foregroundColor(.secondary)
                .frame(width: 24, height: 24)
        } else if icon.hasPrefix("resource:") {
            let resourceName = String(icon.dropFirst(9))
            if let resourceURL = Bundle.main.url(forResource: resourceName, withExtension: "svg"),
               let image = NSImage(contentsOf: resourceURL) {
                Image(nsImage: image)
                    .resizable()
                    .aspectRatio(contentMode: .fit)
                    .frame(width: 24, height: 24)
            } else {
                // Fallback to system image
                Image(systemName: "questionmark.circle")
                    .font(.system(size: 24))
                    .foregroundColor(.secondary)
            }
        } else {
            Image(systemName: icon)
                .font(.system(size: 24))
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

    init(collection: RuleCollection, onSelectOutput: @escaping (String) -> Void) {
        self.collection = collection
        self.onSelectOutput = onSelectOutput
        _selectedOutput = State(initialValue: collection.selectedOutput ?? collection.presetOptions.first?.output ?? "")
    }

    private var selectedPreset: SingleKeyPreset? {
        collection.presetOptions.first { $0.output == selectedOutput }
    }

    private var isCustomSelection: Bool {
        !collection.presetOptions.contains { $0.output == selectedOutput }
            && !selectedOutput.isEmpty
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            // Segmented picker
            HStack(spacing: 0) {
                ForEach(collection.presetOptions) { preset in
                    PickerSegment(
                        label: preset.label,
                        isSelected: selectedOutput == preset.output,
                        isFirst: preset.id == collection.presetOptions.first?.id,
                        isLast: preset.id == collection.presetOptions.last?.id && !isCustomSelection
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

    init(collection: RuleCollection, onSelectPreset: @escaping (String) -> Void) {
        self.collection = collection
        self.onSelectPreset = onSelectPreset
        _selectedPresetId = State(initialValue: collection.selectedLayerPreset ?? collection.layerPresets?.first?.id ?? "")
    }

    private var selectedPreset: LayerPreset? {
        collection.layerPresets?.first { $0.id == selectedPresetId }
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            // Mini-preview cards for each preset
            HStack(spacing: 12) {
                ForEach(collection.layerPresets ?? []) { preset in
                    MiniPresetCard(
                        preset: preset,
                        isSelected: selectedPresetId == preset.id
                    ) {
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

                    KeyboardTransformGrid(mappings: preset.mappings)
                }
                .transition(.opacity.combined(with: .scale(scale: 0.98)))
                .id(preset.id)
            }
        }
        .padding(.vertical, 8)
        .animation(.easeInOut(duration: 0.2), value: selectedPresetId)
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

// MARK: - Keyboard Transform Grid (Input → Output)

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

    init(collection: RuleCollection, onSelectTapOutput: @escaping (String) -> Void, onSelectHoldOutput: @escaping (String) -> Void) {
        self.collection = collection
        self.onSelectTapOutput = onSelectTapOutput
        self.onSelectHoldOutput = onSelectHoldOutput
        let tapOptions = collection.tapHoldOptions?.tapOptions ?? []
        let holdOptions = collection.tapHoldOptions?.holdOptions ?? []
        _selectedTap = State(initialValue: collection.selectedTapOutput ?? tapOptions.first?.output ?? "esc")
        _selectedHold = State(initialValue: collection.selectedHoldOutput ?? holdOptions.first?.output ?? "hyper")
    }

    private var tapOptions: [SingleKeyPreset] {
        collection.tapHoldOptions?.tapOptions ?? []
    }

    private var holdOptions: [SingleKeyPreset] {
        collection.tapHoldOptions?.holdOptions ?? []
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

                    PickerSegment(
                        label: "Custom",
                        isSelected: isCustomTapSelection,
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
                                let normalized = CustomRuleValidator.normalizeKey(customTapInput)
                                if CustomRuleValidator.isValidKey(normalized) {
                                    selectedTap = normalized
                                    onSelectTapOutput(normalized)
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

                    PickerSegment(
                        label: "Custom",
                        isSelected: isCustomHoldSelection,
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
                                let normalized = CustomRuleValidator.normalizeKey(customHoldInput)
                                if CustomRuleValidator.isValidKey(normalized) {
                                    selectedHold = normalized
                                    onSelectHoldOutput(normalized)
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

    @State private var showingSuggestions = false
    @FocusState private var isInputFocused: Bool

    private var suggestions: [String] {
        CustomRuleValidator.suggestions(for: keyInput).prefix(8).map { $0 }
    }

    private var isValidKey: Bool {
        let normalized = CustomRuleValidator.normalizeKey(keyInput)
        return CustomRuleValidator.isValidKey(normalized)
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Enter Custom Key")
                .font(.headline)

            // Key input with autocomplete
            VStack(alignment: .leading, spacing: 4) {
                TextField("Key name (e.g., tab, grv)", text: $keyInput)
                    .textFieldStyle(.roundedBorder)
                    .focused($isInputFocused)
                    .onSubmit {
                        if isValidKey {
                            onConfirm()
                        }
                    }
                    .onChange(of: keyInput) { _, newValue in
                        showingSuggestions = !newValue.isEmpty
                    }

                // Autocomplete suggestions
                if showingSuggestions, !suggestions.isEmpty {
                    ScrollView(.horizontal, showsIndicators: false) {
                        HStack(spacing: 6) {
                            ForEach(suggestions, id: \.self) { suggestion in
                                Button {
                                    keyInput = suggestion
                                    showingSuggestions = false
                                } label: {
                                    Text(suggestion)
                                        .font(.caption.monospaced())
                                        .padding(.horizontal, 8)
                                        .padding(.vertical, 4)
                                        .background(Color.accentColor.opacity(0.1))
                                        .cornerRadius(4)
                                }
                                .buttonStyle(.plain)
                            }
                        }
                    }
                    .frame(height: 28)
                }

                // Validation feedback
                if !keyInput.isEmpty, !isValidKey {
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

                Spacer()

                Button("OK") {
                    onConfirm()
                }
                .keyboardShortcut(.return)
                .disabled(!isValidKey)
                .buttonStyle(.borderedProminent)
            }
        }
        .padding(16)
        .frame(width: 280)
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
        Text(formatKeyForDisplay(text))
            .font(.body.monospaced().bold())
            .foregroundColor(.primary)
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
