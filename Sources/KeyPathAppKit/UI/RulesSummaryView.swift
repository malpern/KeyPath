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

// MARK: - Rules Tab View

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
        let needsCollection = style == .singleKeyPicker || style == .homeRowMods || style == .tapHoldPicker

        ExpandableCollectionRow(
            name: dynamicCollectionName(for: collection),
            icon: collection.icon ?? "circle",
            count: style == .singleKeyPicker || style == .tapHoldPicker ? 1 : collection.mappings.count,
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
