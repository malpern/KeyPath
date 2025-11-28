import KeyPathCore
import SwiftUI

#if os(macOS)
    import AppKit
#endif

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
                            mappings: kanataManager.customRules.map { ($0.input, $0.output, nil, nil, $0.title.isEmpty ? nil : $0.title, false, $0.isEnabled, $0.id) },
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
                            ExpandableCollectionRow(
                                name: dynamicCollectionName(for: collection),
                                icon: collection.icon ?? "circle",
                                count: collection.displayStyle == .singleKeyPicker ? 1 : collection.mappings.count,
                                isEnabled: collection.isEnabled,
                                mappings: collection.mappings.map {
                                    ($0.input, $0.output, $0.shiftedOutput, $0.ctrlOutput, $0.description, $0.sectionBreak, collection.isEnabled, $0.id)
                                },
                                onToggle: { isOn in
                                    Task { await kanataManager.toggleRuleCollection(collection.id, enabled: isOn) }
                                },
                                onEditMapping: nil,
                                onDeleteMapping: nil,
                                description: collection.summary,
                                layerActivator: collection.momentaryActivator,
                                displayStyle: collection.displayStyle,
                                collection: collection.displayStyle == .singleKeyPicker ? collection : nil,
                                onSelectOutput: collection.displayStyle == .singleKeyPicker ? { output in
                                    Task { await kanataManager.updateCollectionOutput(collection.id, output: output) }
                                } : nil,
                                scrollID: "collection-\(collection.id.uuidString)",
                                scrollProxy: scrollProxy
                            )
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

    /// Generate a dynamic name for picker-style collections that shows the current mapping
    private func dynamicCollectionName(for collection: RuleCollection) -> String {
        guard collection.displayStyle == .singleKeyPicker,
              let inputKey = collection.pickerInputKey
        else {
            return collection.name
        }

        // Format input key with Mac symbol
        let inputDisplay = formatKeyWithSymbol(inputKey)

        // Get selected output and its label
        let selectedOutput = collection.selectedOutput ?? collection.presetOptions.first?.output ?? ""
        let outputLabel = collection.presetOptions.first { $0.output == selectedOutput }?.label ?? selectedOutput

        return "\(inputDisplay) → \(outputLabel)"
    }

    /// Format a key name with its Mac symbol
    private func formatKeyWithSymbol(_ key: String) -> String {
        let keySymbols: [String: String] = [
            "caps": "⇪ Caps Lock",
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
            "bspc": "⌫ Delete",
            "del": "⌦ Forward Delete"
        ]
        return keySymbols[key.lowercased()] ?? key.capitalized
    }

    private func openConfigInEditor() {
        let url = URL(fileURLWithPath: kanataManager.configPath)
        NSWorkspace.shared.open(url)
        AppLogger.shared.log("📝 [Rules] Opened config for editing")
    }

    private func openBackupsFolder() {
        let backupsPath = "\(NSHomeDirectory())/.config/keypath/.backups"
        NSWorkspace.shared.selectFile(nil, inFileViewerRootedAtPath: backupsPath)
    }

    private func resetToDefaultConfig() {
        Task {
            do {
                try await kanataManager.resetToDefaultConfig()
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
    let mappings: [(input: String, output: String, shiftedOutput: String?, ctrlOutput: String?, description: String?, sectionBreak: Bool, enabled: Bool, id: UUID)]
    let onToggle: (Bool) -> Void
    let onEditMapping: ((UUID) -> Void)?
    let onDeleteMapping: ((UUID) -> Void)?
    var showZeroState: Bool = false
    var onCreateFirstRule: (() -> Void)?
    var description: String?
    var layerActivator: MomentaryActivator?
    var defaultExpanded: Bool = false
    var displayStyle: RuleCollectionDisplayStyle = .list
    /// For singleKeyPicker style: the full collection with presets
    var collection: RuleCollection?
    var onSelectOutput: ((String) -> Void)?
    /// Unique ID for scroll-to behavior
    var scrollID: String?
    /// Scroll proxy for auto-scrolling when expanded
    var scrollProxy: ScrollViewProxy?

    @State private var isExpanded = false
    @State private var isHovered = false
    @State private var hasInitialized = false
    @State private var localEnabled: Bool? // Optimistic local state for instant toggle feedback

    /// Effective enabled state: use local optimistic value if set, otherwise parent value
    private var effectiveEnabled: Bool {
        localEnabled ?? isEnabled
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

                        if let activator = layerActivator {
                            Label("Hold \(prettyKeyName(activator.input))", systemImage: "hand.point.up.left")
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

                    Image(systemName: isExpanded ? "chevron.up" : "chevron.down")
                        .font(.callout)
                        .foregroundColor(.secondary)
                }
                .padding(12)
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .background(Color(NSColor.windowBackgroundColor))
            .overlay(
                RoundedRectangle(cornerRadius: 10)
                    .stroke(Color.white.opacity(isHovered ? 0.15 : 0), lineWidth: 1)
            )
            .onHover { hovering in
                isHovered = hovering
            }

            // Expanded Mappings or Zero State
            if isExpanded {
                if showZeroState, let onCreate = onCreateFirstRule {
                    // Zero State
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
                } else if displayStyle == .table {
                    // Table view for complex collections like Vim
                    MappingTableContent(mappings: mappings)
                        .padding(.top, 8)
                        .padding(.bottom, 12)
                        .padding(.horizontal, 12)
                } else {
                    // List view for standard collections and custom rules
                    VStack(spacing: 6) {
                        ForEach(mappings, id: \.id) { mapping in
                            MappingRowView(
                                mapping: mapping,
                                layerActivator: layerActivator,
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
    let mapping: (input: String, output: String, shiftedOutput: String?, ctrlOutput: String?, description: String?, sectionBreak: Bool, enabled: Bool, id: UUID)
    let layerActivator: MomentaryActivator?
    let onEditMapping: ((UUID) -> Void)?
    let onDeleteMapping: ((UUID) -> Void)?
    let prettyKeyName: (String) -> String

    @State private var isHovered = false

    private var isEditable: Bool {
        onEditMapping != nil
    }

    var body: some View {
        HStack(spacing: 8) {
            // Mapping content
            HStack(spacing: 8) {
                // Show layer activator if present
                if let activator = layerActivator {
                    HStack(spacing: 4) {
                        Text("Hold")
                            .font(.body.monospaced().weight(.semibold))
                            .foregroundColor(.accentColor)
                        Text(prettyKeyName(activator.input))
                            .font(.body.monospaced().weight(.semibold))
                            .foregroundColor(.primary)
                    }
                    .padding(.horizontal, 12)
                    .padding(.vertical, 6)
                    .background(
                        Capsule()
                            .fill(Color(NSColor.controlBackgroundColor))
                    )

                    Text("+")
                        .font(.body)
                        .foregroundColor(.secondary)
                }

                Text(prettyKeyName(mapping.input))
                    .font(.body.monospaced().weight(.semibold))
                    .foregroundColor(.primary)
                    .padding(.horizontal, 12)
                    .padding(.vertical, 6)
                    .background(
                        Capsule()
                            .fill(Color(NSColor.controlBackgroundColor))
                    )

                Image(systemName: "arrow.right")
                    .font(.body.weight(.medium))
                    .foregroundColor(.secondary)

                Text(prettyKeyName(mapping.output))
                    .font(.body.monospaced().weight(.semibold))
                    .foregroundColor(.primary)
                    .padding(.horizontal, 12)
                    .padding(.vertical, 6)
                    .background(
                        Capsule()
                            .fill(Color(NSColor.controlBackgroundColor))
                    )

                // Show rule name/title if provided
                if let title = mapping.description, !title.isEmpty {
                    Text(title)
                        .font(.subheadline)
                        .foregroundColor(.secondary)
                }
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

                    // Spacer to match chevron width in header
                    Spacer()
                        .frame(width: 24)
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
    let mappings: [(input: String, output: String, shiftedOutput: String?, ctrlOutput: String?, description: String?, sectionBreak: Bool, enabled: Bool, id: UUID)]

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
        return key
    }

    /// Format output for display (convert Kanata codes to readable symbols)
    private func formatOutput(_ output: String) -> String {
        // Split by space to handle multi-key sequences, format each part, rejoin with space
        output.split(separator: " ").map { part in
            String(part)
                // Multi-modifier combinations (order matters - longest first)
                .replacingOccurrences(of: "C-M-A-S-", with: "⌃ ⌘ ⌥ ⇧ ")
                .replacingOccurrences(of: "C-M-A-", with: "⌃ ⌘ ⌥ ")
                .replacingOccurrences(of: "M-S-", with: "⌘ ⇧ ")
                .replacingOccurrences(of: "C-S-", with: "⌃ ⇧ ")
                .replacingOccurrences(of: "A-S-", with: "⌥ ⇧ ")
                // Single modifiers
                .replacingOccurrences(of: "M-", with: "⌘ ")
                .replacingOccurrences(of: "A-", with: "⌥ ")
                .replacingOccurrences(of: "C-", with: "⌃ ")
                .replacingOccurrences(of: "S-", with: "⇧ ")
                // Arrow keys and special keys
                .replacingOccurrences(of: "left", with: "←")
                .replacingOccurrences(of: "right", with: "→")
                .replacingOccurrences(of: "up", with: "↑")
                .replacingOccurrences(of: "down", with: "↓")
                .replacingOccurrences(of: "ret", with: "↩")
                .replacingOccurrences(of: "bspc", with: "⌫")
                .replacingOccurrences(of: "del", with: "⌦")
                .replacingOccurrences(of: "pgup", with: "Pg ↑")
                .replacingOccurrences(of: "pgdn", with: "Pg ↓")
                .replacingOccurrences(of: "esc", with: "⎋")
        }.joined(separator: " ")
    }
}
