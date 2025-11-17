import KeyPathCore
import SwiftUI
#if os(macOS)
import AppKit
#endif

struct RulesTabView: View {
    @EnvironmentObject var kanataManager: KanataViewModel
    @State private var selectedTab: RulesSubTab = .collections
    @State private var selectedCollectionsFilter: CollectionsFilter = .active
    @State private var showingResetConfirmation = false
    @State private var settingsToastManager = WizardToastManager()
    @AppStorage("rulesTabTipDismissed") private var rulesTabTipDismissed = false
    private let catalog = RuleCollectionCatalog()

    enum RulesSubTab: String, CaseIterable {
        case collections = "Collections"
        case custom = "Custom Rules"
    }

    enum CollectionsFilter: String, CaseIterable {
        case active = "Active"
        case available = "Available"
    }

    var body: some View {
        VStack(spacing: 0) {
            // Tab Picker with action buttons
            HStack(alignment: .top, spacing: 16) {
                VStack(alignment: .leading, spacing: 6) {
                    HStack(spacing: 8) {
                        ForEach(RulesSubTab.allCases, id: \.self) { tab in
                            Button {
                                withAnimation(.spring(response: 0.35, dampingFraction: 0.8)) {
                                    selectedTab = tab
                                    rulesTabTipDismissed = true
                                }
                            } label: {
                                HStack(spacing: 6) {
                                    Image(systemName: iconName(for: tab))
                                        .imageScale(.small)
                                    Text(tab.rawValue)
                                        .font(.subheadline)
                                        .fontWeight(.semibold)
                                    Text("\(count(for: tab))")
                                        .font(.caption)
                                        .fontWeight(.medium)
                                        .padding(.horizontal, 6)
                                        .padding(.vertical, 2)
                                        .background(Capsule().fill(Color.white.opacity(0.2)))
                                }
                                .padding(.horizontal, 12)
                                .padding(.vertical, 8)
                                .frame(minWidth: 140)
                                .background(segmentBackground(for: tab))
                                .foregroundColor(segmentForeground(for: tab))
                                .clipShape(RoundedRectangle(cornerRadius: 10, style: .continuous))
                                .shadow(color: tab == selectedTab ? segmentBackground(for: tab).opacity(0.3) : .clear, radius: 6, x: 0, y: 3)
                            }
                            .buttonStyle(.plain)
                        }
                    }

                    Text(subtitle(for: selectedTab))
                        .font(.footnote)
                        .foregroundColor(.secondary)

                    if !rulesTabTipDismissed {
                        HStack(spacing: 8) {
                            Image(systemName: "hand.tap")
                                .foregroundColor(.accentColor)
                            Text("Tip: use tabs to switch between curated preset collections and your custom rules.")
                                .font(.caption)
                                .foregroundColor(.secondary)
                            Button("Got it") {
                                withAnimation { rulesTabTipDismissed = true }
                            }
                            .buttonStyle(.borderless)
                            .font(.caption)
                        }
                        .padding(10)
                        .background(RoundedRectangle(cornerRadius: 8).fill(Color.accentColor.opacity(0.08)))
                    }
                }

                Spacer()

                VStack(alignment: .trailing, spacing: 8) {
                    Button(action: { openConfigInEditor() }) {
                        Label("Edit Config", systemImage: "doc.text.magnifyingglass")
                    }
                    .buttonStyle(.bordered)
                    .controlSize(.small)

                    Button(action: { showingResetConfirmation = true }) {
                        Label("Reset", systemImage: "arrow.counterclockwise")
                    }
                    .buttonStyle(.borderedProminent)
                    .controlSize(.small)
                }
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 16)
            .background(Color(NSColor.controlBackgroundColor))

            Divider()

            if selectedTab == .collections {
                HStack(spacing: 10) {
                    ForEach(CollectionsFilter.allCases, id: \.self) { filter in
                        Button {
                            withAnimation(.spring(response: 0.3, dampingFraction: 0.85)) {
                                selectedCollectionsFilter = filter
                            }
                        } label: {
                            HStack(spacing: 6) {
                                Image(systemName: filter == .active ? "switch.2" : "sparkles")
                                    .imageScale(.small)
                                Text(filter.rawValue)
                                    .font(.caption)
                                    .fontWeight(.semibold)
                                Text("\(count(for: filter))")
                                    .font(.caption2)
                                    .padding(.horizontal, 5)
                                    .padding(.vertical, 1)
                                    .background(Capsule().fill(Color.white.opacity(0.2)))
                            }
                            .padding(.horizontal, 10)
                            .padding(.vertical, 6)
                            .background(segmentBackground(for: filter))
                            .foregroundColor(segmentForeground(for: filter))
                            .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
                        }
                        .buttonStyle(.plain)
                    }
                    Spacer()
                }
                .padding(.horizontal, 16)
                .padding(.vertical, 10)
                .background(Color(NSColor.controlBackgroundColor))

                Divider()
            }

            Group {
                switch selectedTab {
                case .collections:
                    if selectedCollectionsFilter == .active {
                        ActiveRulesView()
                    } else {
                        AvailableRulesView()
                    }
                case .custom:
                    CustomRulesView()
                }
            }
            .background(contentBackground(for: selectedTab))
            .animation(.easeInOut(duration: 0.25), value: selectedTab)
        }
        .withToasts(settingsToastManager)
        .alert("Reset Configuration?", isPresented: $showingResetConfirmation) {
            Button("Cancel", role: .cancel) {}
            Button("Open Backups Folder") {
                openBackupsFolder()
            }
            Button("Reset", role: .destructive) {
                resetToDefaultConfig()
            }
        } message: {
            Text("""
            This will reset your configuration to Caps Lock → Escape.
            A safety backup will be stored in ~/.config/keypath/.backups.
            """)
        }
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

    private func count(for tab: RulesSubTab) -> Int {
        switch tab {
        case .collections:
            return kanataManager.ruleCollections.count
        case .custom:
            return kanataManager.customRules.count
        }
    }

    private func count(for filter: CollectionsFilter) -> Int {
        switch filter {
        case .active:
            return kanataManager.ruleCollections.filter { $0.isEnabled }.count
        case .available:
            let existing = Set(kanataManager.ruleCollections.map { $0.id })
            return catalog.defaultCollections().filter { !existing.contains($0.id) }.count
        }
    }

    private func iconName(for tab: RulesSubTab) -> String {
        switch tab {
        case .collections: "square.grid.2x2"
        case .custom: "square.and.pencil"
        }
    }

    private func segmentBackground(for tab: RulesSubTab) -> Color {
        if tab == selectedTab {
            tab == .collections ? Color.blue.opacity(0.25) : Color.orange.opacity(0.25)
        } else {
            Color.secondary.opacity(0.08)
        }
    }

    private func segmentForeground(for tab: RulesSubTab) -> Color {
        tab == selectedTab ? .primary : .secondary
    }

    private func segmentBackground(for filter: CollectionsFilter) -> Color {
        if filter == selectedCollectionsFilter {
            filter == .active ? Color.green.opacity(0.25) : Color.blue.opacity(0.25)
        } else {
            Color.secondary.opacity(0.08)
        }
    }

    private func segmentForeground(for filter: CollectionsFilter) -> Color {
        filter == selectedCollectionsFilter ? .primary : .secondary
    }

    private func subtitle(for tab: RulesSubTab) -> String {
        switch tab {
        case .collections:
            "Toggle between active presets and the curated catalog."
        case .custom:
            "Manage your personal rules independently from presets."
        }
    }

    private func contentBackground(for tab: RulesSubTab) -> Color {
        tab == .collections ? Color.blue.opacity(0.04) : Color.orange.opacity(0.04)
    }
}

// MARK: - Active Rules View

struct ActiveRulesView: View {
    @EnvironmentObject var kanataManager: KanataViewModel
    @State private var isHoveringEmptyState = false

    var body: some View {
        if kanataManager.ruleCollections.isEmpty {
            VStack(spacing: 12) {
                Image(systemName: "list.bullet")
                    .font(.system(size: 48))
                    .foregroundColor(.secondary.opacity(0.5))
                Text("No active key mappings")
                    .font(.title3)
                    .foregroundColor(.secondary)
                Button(action: openConfigInEditor) {
                    Text("Edit your configuration to add key remapping rules.")
                        .font(.body)
                        .foregroundColor(.secondary)
                        .opacity(isHoveringEmptyState ? 0.7 : 1.0)
                }
                .buttonStyle(.plain)
                .onHover { hovering in
                    isHoveringEmptyState = hovering
                }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .settingsBackground()
        } else {
            ScrollView {
                LazyVStack(spacing: 12) {
                    ForEach(kanataManager.ruleCollections) { collection in
                        RuleCollectionRow(
                            collection: collection,
                            onToggle: { isOn in
                                Task { await kanataManager.toggleRuleCollection(collection.id, enabled: isOn) }
                            }
                        )
                        .padding(.horizontal, 12)
                    }
                }
                .padding(.vertical, 8)
            }
            .settingsBackground()
        }
    }

    private func openConfigInEditor() {
        let url = URL(fileURLWithPath: kanataManager.configPath)
        NSWorkspace.shared.open(url)
        AppLogger.shared.log("📝 [Rules] Opened config for editing")
    }
}

private struct RuleCollectionRow: View {
    let collection: RuleCollection
    let onToggle: (Bool) -> Void
    @State private var isExpanded = false

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(alignment: .center, spacing: 12) {
                if let icon = collection.icon {
                    Image(systemName: icon)
                        .font(.title3)
                        .foregroundColor(collection.isEnabled ? .green : .secondary)
                }

                VStack(alignment: .leading, spacing: 2) {
                    Text(collection.name)
                        .font(.headline)
                    Text(collection.summary)
                        .font(.caption)
                        .foregroundColor(.secondary)
                    if let activationDescription = activationDescription {
                        Label(activationDescription, systemImage: "hand.point.up.left")
                            .font(.caption2)
                            .foregroundColor(.accentColor)
                    }
                }

                Spacer()

                Toggle("", isOn: Binding(
                    get: { collection.isEnabled },
                    set: { onToggle($0) }
                ))
                .labelsHidden()
                .toggleStyle(.switch)

                Button(action: { isExpanded.toggle() }) {
                    Image(systemName: isExpanded ? "chevron.up" : "chevron.down")
                        .foregroundColor(.secondary)
                }
                .buttonStyle(.plain)
            }

            if isExpanded {
                VStack(alignment: .leading, spacing: 4) {
                    ForEach(collection.mappings.prefix(8)) { mapping in
                        HStack(spacing: 8) {
                            Text(mappingDescription(for: mapping))
                                .font(.caption.monospaced())
                                .foregroundColor(.primary)
                            Image(systemName: "arrow.right")
                                .font(.caption2)
                                .foregroundColor(.secondary)
                            Text(mapping.output)
                                .font(.caption.monospaced())
                                .foregroundColor(.secondary)
                        }
                        .padding(.vertical, 2)
                    }

                    if collection.mappings.count > 8 {
                        Text("+\(collection.mappings.count - 8) more…")
                            .font(.caption)
                            .foregroundColor(.secondary)
                    }
                }
                .padding(.leading, collection.icon == nil ? 0 : 4)
            }
        }
        .padding(12)
        .background(
            RoundedRectangle(cornerRadius: 12)
                .fill(Color(nsColor: NSColor.windowBackgroundColor))
        )
    }
}

private extension RuleCollectionRow {
    var activationDescription: String? {
        if let hint = collection.activationHint { return hint }
        if let activator = collection.momentaryActivator {
            return "Hold \(prettyKeyName(activator.input)) for \(activator.targetLayer.displayName)"
        }
        return nil
    }

    func mappingDescription(for mapping: KeyMapping) -> String {
        guard let activator = collection.momentaryActivator else {
            return prettyKeyName(mapping.input)
        }
        return "Hold \(prettyKeyName(activator.input)) + \(prettyKeyName(mapping.input))"
    }

    func prettyKeyName(_ raw: String) -> String {
        raw.replacingOccurrences(of: "_", with: " ")
            .trimmingCharacters(in: .whitespaces)
            .capitalized
    }
}

// MARK: - Available Rules View

struct AvailableRulesView: View {
    @EnvironmentObject var kanataManager: KanataViewModel
    private let catalog = RuleCollectionCatalog()

    private var availableCollections: [RuleCollection] {
        let existing = Set(kanataManager.ruleCollections.map { $0.id })
        return catalog.defaultCollections().filter { !existing.contains($0.id) }
    }

    var body: some View {
        ScrollView {
            LazyVStack(spacing: 16) {
                ForEach(availableCollections) { collection in
                    AvailableRuleCollectionCard(collection: collection) {
                        Task { await kanataManager.addRuleCollection(collection) }
                    }
                }

                if availableCollections.isEmpty {
                    Text("All built-in collections are active.")
                        .font(.callout)
                        .foregroundColor(.secondary)
                        .padding()
                }
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 20)
        }
    }
}

private struct AvailableRuleCollectionCard: View {
    let collection: RuleCollection
    let onActivate: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(alignment: .center, spacing: 12) {
                if let icon = collection.icon {
                    Image(systemName: icon)
                        .font(.title2)
                        .foregroundColor(.blue)
                }

                VStack(alignment: .leading, spacing: 4) {
                    Text(collection.name)
                        .font(.headline)
                    Text(collection.summary)
                        .font(.caption)
                        .foregroundColor(.secondary)
                }

                Spacer()

                Button(action: onActivate) {
                    Label("Activate", systemImage: "plus.circle")
                }
                .buttonStyle(.borderedProminent)
                .controlSize(.small)
            }

            if !collection.mappings.isEmpty {
                ScrollView(.horizontal, showsIndicators: false) {
                    HStack(spacing: 8) {
                        ForEach(collection.mappings.prefix(6)) { mapping in
                            HStack(spacing: 4) {
                                Text(mapping.input)
                                    .font(.caption.monospaced())
                                Image(systemName: "arrow.right")
                                    .font(.caption2)
                                Text(mapping.output)
                                    .font(.caption.monospaced())
                            }
                            .padding(.horizontal, 6)
                            .padding(.vertical, 4)
                            .background(Color(NSColor.controlBackgroundColor))
                            .cornerRadius(6)
                        }
                        if collection.mappings.count > 6 {
                            Text("+\(collection.mappings.count - 6) more")
                                .font(.caption)
                                .foregroundColor(.secondary)
                        }
                    }
                }
            }
        }
        .padding(16)
        .background(
            RoundedRectangle(cornerRadius: 14)
                .fill(Color(NSColor.windowBackgroundColor))
        )
    }
}

// MARK: - Custom Rules View

struct CustomRulesView: View {
    @EnvironmentObject var kanataManager: KanataViewModel
    @State private var isPresentingNewRule = false
    @State private var editingRule: CustomRule?
    @State private var pendingDeleteRule: CustomRule?

    private var sortedRules: [CustomRule] {
        kanataManager.customRules.sorted { lhs, rhs in
            if lhs.isEnabled == rhs.isEnabled {
                return lhs.displayTitle.localizedCaseInsensitiveCompare(rhs.displayTitle) == .orderedAscending
            }
            return lhs.isEnabled && !rhs.isEnabled
        }
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack(alignment: .top) {
                VStack(alignment: .leading, spacing: 6) {
                    Text("Custom Rules")
                        .font(.headline)
                    Text("These rules stay separate from presets so you can manage them independently.")
                        .font(.caption)
                        .foregroundColor(.secondary)
                }
                Spacer()
                Button {
                    isPresentingNewRule = true
                } label: {
                    Label("Add Rule", systemImage: "plus.circle.fill")
                        .labelStyle(.titleAndIcon)
                }
                .buttonStyle(.borderedProminent)
                .controlSize(.small)
            }
            .padding(.horizontal, 18)
            .padding(.vertical, 16)

            Divider()

            if sortedRules.isEmpty {
                VStack(spacing: 12) {
                    Image(systemName: "square.and.pencil")
                        .font(.system(size: 48))
                        .foregroundColor(.secondary.opacity(0.5))
                    Text("No custom rules yet")
                        .font(.title3)
                    Text("Add a rule to map individual keys without affecting preset collections.")
                        .font(.callout)
                        .multilineTextAlignment(.center)
                        .foregroundColor(.secondary)
                    Button {
                        isPresentingNewRule = true
                    } label: {
                        Label("Create Your First Rule", systemImage: "plus")
                    }
                    .buttonStyle(.bordered)
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                .padding()
            } else {
                ScrollView {
                    LazyVStack(spacing: 12) {
                        ForEach(sortedRules) { rule in
                            CustomRuleRow(
                                rule: rule,
                                onToggle: { isOn in
                                    _ = Task { await kanataManager.toggleCustomRule(rule.id, enabled: isOn) }
                                },
                                onEdit: {
                                    editingRule = rule
                                },
                                onDelete: {
                                    pendingDeleteRule = rule
                                }
                            )
                            .padding(.horizontal, 16)
                        }
                    }
                    .padding(.vertical, 12)
                }
            }
        }
        .sheet(isPresented: $isPresentingNewRule) {
            CustomRuleEditorView(rule: nil) { newRule in
                _ = Task { await kanataManager.saveCustomRule(newRule) }
            }
        }
        .sheet(item: $editingRule) { rule in
            CustomRuleEditorView(rule: rule) { updatedRule in
                _ = Task { await kanataManager.saveCustomRule(updatedRule) }
            }
        }
        .alert(
            "Delete \"\(pendingDeleteRule?.displayTitle ?? "")\"?",
            isPresented: Binding(
                get: { pendingDeleteRule != nil },
                set: { if !$0 { pendingDeleteRule = nil } }
            )
        ) {
            Button("Cancel", role: .cancel) {}
            Button("Delete", role: .destructive) {
                if let rule = pendingDeleteRule {
                    Task { await kanataManager.removeCustomRule(rule.id) }
                }
                pendingDeleteRule = nil
            }
        } message: {
            Text("This removes the rule from Custom Rules but leaves preset collections untouched.")
        }
        .settingsBackground()
    }
}

private struct CustomRuleRow: View {
    let rule: CustomRule
    let onToggle: (Bool) -> Void
    let onEdit: () -> Void
    let onDelete: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(alignment: .top, spacing: 12) {
                VStack(alignment: .leading, spacing: 4) {
                    Text(rule.displayTitle)
                        .font(.headline)
                    Text("\(rule.input) → \(rule.output)")
                        .font(.caption.monospaced())
                        .foregroundColor(.secondary)
                    if let notes = rule.notes, !notes.isEmpty {
                        Text(notes)
                            .font(.caption)
                            .foregroundColor(.secondary)
                    }
                }

                Spacer()

                Toggle("", isOn: Binding(
                    get: { rule.isEnabled },
                    set: { onToggle($0) }
                ))
                .labelsHidden()
                .toggleStyle(.switch)

                Menu {
                    Button("Edit") { onEdit() }
                    Button("Delete", role: .destructive) { onDelete() }
                } label: {
                    Image(systemName: "ellipsis.circle")
                        .imageScale(.large)
                        .padding(.leading, 4)
                }
                .menuStyle(.borderlessButton)
            }
        }
        .padding(14)
        .background(
            RoundedRectangle(cornerRadius: 12)
                .fill(Color(NSColor.windowBackgroundColor))
        )
    }
}

private struct CustomRuleEditorView: View {
    enum Mode {
        case create
        case edit
    }

    @Environment(\.dismiss) private var dismiss
    @State private var title: String
    @State private var input: String
    @State private var output: String
    @State private var notes: String
    @State private var isEnabled: Bool
    private let existingRule: CustomRule?
    private let mode: Mode
    let onSave: (CustomRule) -> Void

    init(rule: CustomRule?, onSave: @escaping (CustomRule) -> Void) {
        self.existingRule = rule
        self.onSave = onSave
        if let rule {
            _title = State(initialValue: rule.title)
            _input = State(initialValue: rule.input)
            _output = State(initialValue: rule.output)
            _notes = State(initialValue: rule.notes ?? "")
            _isEnabled = State(initialValue: rule.isEnabled)
            mode = .edit
        } else {
            _title = State(initialValue: "")
            _input = State(initialValue: "")
            _output = State(initialValue: "")
            _notes = State(initialValue: "")
            _isEnabled = State(initialValue: true)
            mode = .create
        }
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            Text(mode == .create ? "New Custom Rule" : "Edit Custom Rule")
                .font(.title2.bold())

            VStack(alignment: .leading, spacing: 10) {
                TextField("Friendly name (optional)", text: $title)
                TextField("Input key (e.g. caps_lock)", text: $input)
                TextField("Output key or sequence", text: $output)
                Toggle("Enabled", isOn: $isEnabled)
                VStack(alignment: .leading, spacing: 4) {
                    Text("Notes (optional)")
                        .font(.caption)
                        .foregroundColor(.secondary)
                    TextEditor(text: $notes)
                        .frame(height: 70)
                        .font(.body)
                        .padding(6)
                        .background(
                            RoundedRectangle(cornerRadius: 8)
                                .stroke(Color.secondary.opacity(0.2))
                        )
                }
            }
            .textFieldStyle(.roundedBorder)

            Spacer()

            HStack {
                Button("Cancel") {
                    dismiss()
                }
                .keyboardShortcut(.cancelAction)

                Spacer()

                Button(mode == .create ? "Add Rule" : "Save Changes") {
                    let trimmedNotes = notes.trimmingCharacters(in: .whitespacesAndNewlines)
                    let rule = CustomRule(
                        id: existingRule?.id ?? UUID(),
                        title: title,
                        input: input.trimmingCharacters(in: .whitespacesAndNewlines),
                        output: output.trimmingCharacters(in: .whitespacesAndNewlines),
                        isEnabled: isEnabled,
                        notes: trimmedNotes.isEmpty ? nil : trimmedNotes,
                        createdAt: existingRule?.createdAt ?? Date()
                    )
                    onSave(rule)
                    dismiss()
                }
                .disabled(input.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty || output.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
                .keyboardShortcut(.defaultAction)
            }
        }
        .padding(24)
        .frame(minWidth: 400, minHeight: 320)
    }
}
