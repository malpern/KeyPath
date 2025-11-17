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
    private let catalog = RuleCollectionCatalog()

    var body: some View {
        HStack(alignment: .top, spacing: 0) {
            // Left Column: Create Rule + Advanced
            VStack(alignment: .leading, spacing: 24) {
                // Create Rule Section
                VStack(spacing: 16) {
                    VStack(spacing: 12) {
                        CreateRuleButton(
                            isPressed: $isPresentingNewRule,
                            externalHover: $createButtonHovered
                        )

                        Button {
                            isPresentingNewRule = true
                        } label: {
                            Text("Create Rule")
                                .font(.title3.weight(.semibold))
                                .multilineTextAlignment(.center)
                        }
                        .buttonStyle(.plain)
                        .onHover { hovering in
                            createButtonHovered = hovering
                        }
                    }

                    Button {
                        isPresentingNewRule = true
                    } label: {
                        Text("Create")
                            .frame(minWidth: 100)
                    }
                    .buttonStyle(.borderedProminent)
                    .controlSize(.large)
                }
                .frame(minWidth: 220)

                // Action buttons centered
                HStack(spacing: 8) {
                    Button(action: { openConfigInEditor() }) {
                        Label("Edit Config File", systemImage: "doc.text.magnifyingglass")
                    }
                    .buttonStyle(.bordered)
                    .controlSize(.small)

                    Button(action: { showingResetConfirmation = true }) {
                        Label("Reset to Default", systemImage: "arrow.counterclockwise")
                    }
                    .buttonStyle(.bordered)
                    .controlSize(.small)
                    .tint(.red)
                }
                .frame(maxWidth: .infinity)

                Spacer()
            }
            .padding(20)
            .frame(width: 280)
            .background(Color(NSColor.windowBackgroundColor))

            // Right Column: Rules List
            ScrollView {
                VStack(spacing: 0) {
                    // Custom Rules Section (toggleable, expanded when has rules)
                    ExpandableCollectionRow(
                        name: "Custom Rules",
                        icon: "square.and.pencil",
                        count: kanataManager.customRules.count,
                        isEnabled: kanataManager.customRules.isEmpty || kanataManager.customRules.allSatisfy { $0.isEnabled },
                        mappings: kanataManager.customRules.map { ($0.input, $0.output, $0.isEnabled, $0.id) },
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
                        defaultExpanded: !kanataManager.customRules.isEmpty
                    )
                    .padding(.vertical, 4)

                    // Collection Rows
                    ForEach(kanataManager.ruleCollections) { collection in
                        ExpandableCollectionRow(
                            name: collection.name,
                            icon: collection.icon ?? "circle",
                            count: collection.mappings.count,
                            isEnabled: collection.isEnabled,
                            mappings: collection.mappings.map { ($0.input, $0.output, collection.isEnabled, $0.id) },
                            onToggle: { isOn in
                                Task { await kanataManager.toggleRuleCollection(collection.id, enabled: isOn) }
                            },
                            onEditMapping: nil,
                            onDeleteMapping: nil,
                            description: collection.summary,
                            layerActivator: collection.momentaryActivator
                        )
                        .padding(.vertical, 4)
                    }
                }
                .padding(.vertical, 12)
                .padding(.horizontal, 12)
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .background(Color(NSColor.windowBackgroundColor))
        }
        .frame(maxHeight: 450)
        .settingsBackground()
        .withToasts(settingsToastManager)
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

}

// MARK: - Expandable Collection Row

private struct ExpandableCollectionRow: View {
    let name: String
    let icon: String
    let count: Int
    let isEnabled: Bool
    let mappings: [(input: String, output: String, enabled: Bool, id: UUID)]
    let onToggle: (Bool) -> Void
    let onEditMapping: ((UUID) -> Void)?
    let onDeleteMapping: ((UUID) -> Void)?
    var showZeroState: Bool = false
    var onCreateFirstRule: (() -> Void)? = nil
    var description: String? = nil
    var layerActivator: MomentaryActivator? = nil
    var defaultExpanded: Bool = false

    @State private var isExpanded = false
    @State private var isHovered = false
    @State private var hasInitialized = false

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            // Header Row (clickable for expand/collapse)
            Button {
                withAnimation(.easeInOut(duration: 0.2)) {
                    isExpanded.toggle()
                }
            } label: {
                HStack(alignment: .top, spacing: 12) {
                    iconView(for: icon)
                        .frame(width: 24)

                    VStack(alignment: .leading, spacing: 2) {
                        Text(name)
                            .font(.headline)
                            .foregroundColor(.primary)

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

                    Toggle("", isOn: Binding(
                        get: { isEnabled },
                        set: { onToggle($0) }
                    ))
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
                } else {
                    VStack(spacing: 6) {
                        ForEach(mappings, id: \.id) { mapping in
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

                                Spacer()

                                if let onEdit = onEditMapping {
                                    Button {
                                        onEdit(mapping.id)
                                    } label: {
                                        Image(systemName: "pencil")
                                            .font(.callout)
                                    }
                                    .buttonStyle(.plain)
                                    .foregroundColor(.blue)
                                }

                                if let onDelete = onDeleteMapping {
                                    Button {
                                        onDelete(mapping.id)
                                    } label: {
                                        Image(systemName: "trash")
                                            .font(.callout)
                                    }
                                    .buttonStyle(.plain)
                                    .foregroundColor(.red)
                                }
                            }
                            .padding(.horizontal, 12)
                            .padding(.vertical, 4)
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
    }

    @ViewBuilder
    func iconView(for icon: String) -> some View {
        if icon.hasPrefix("text:") {
            let text = String(icon.dropFirst(5))
            Text(text)
                .font(.system(size: 14, weight: .bold, design: .monospaced))
                .foregroundColor(.secondary)
                .frame(width: 24, height: 24)
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
            return Color.blue.opacity(0.3)
        } else if isAnyHovered {
            return Color.blue.opacity(0.25)
        } else {
            return Color.blue.opacity(0.15)
        }
    }

    private var iconColor: Color {
        if isMouseDown {
            return .blue.opacity(0.8)
        } else if isAnyHovered {
            return .blue
        } else {
            return .blue.opacity(0.9)
        }
    }

    private var shadowColor: Color {
        if isMouseDown {
            return .clear
        } else if isAnyHovered {
            return Color.blue.opacity(0.3)
        } else {
            return .clear
        }
    }

    private var shadowRadius: CGFloat {
        isAnyHovered ? 8 : 0
    }

    private var shadowY: CGFloat {
        isAnyHovered ? 2 : 0
    }
}

// MARK: - Custom Rules Collection Row

private struct CustomRulesCollectionRow: View {
    @EnvironmentObject var kanataManager: KanataViewModel
    @Binding var isPresentingNewRule: Bool
    @State private var isExpanded = false
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
        VStack(alignment: .leading, spacing: 8) {
            headerRow

            if isExpanded {
                expandedContent
            }
        }
        .padding(12)
        .background(
            RoundedRectangle(cornerRadius: 10)
                .fill(Color(NSColor.windowBackgroundColor))
        )
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
            Button("Cancel", role: .cancel) {
                pendingDeleteRule = nil
            }
            Button("Delete", role: .destructive) {
                if let rule = pendingDeleteRule {
                    Task { await kanataManager.removeCustomRule(rule.id) }
                }
                pendingDeleteRule = nil
            }
        }
    }

    private var headerRow: some View {
        HStack(alignment: .top, spacing: 12) {
            Image(systemName: "square.and.pencil")
                .font(.system(size: 24))
                .foregroundColor(.secondary)

            VStack(alignment: .leading, spacing: 2) {
                Text("Custom Rules")
                    .font(.headline)
                Text("\(kanataManager.customRules.count) custom \(kanataManager.customRules.count == 1 ? "rule" : "rules")")
                    .font(.subheadline)
                    .foregroundColor(.secondary)
            }

            Spacer()

            Toggle("", isOn: Binding(
                get: { areCustomRulesEnabled },
                set: { newValue in
                    Task {
                        // Toggle all custom rules
                        for rule in kanataManager.customRules {
                            await kanataManager.toggleCustomRule(rule.id, enabled: newValue)
                        }
                    }
                }
            ))
            .labelsHidden()
            .toggleStyle(.switch)
            .tint(.blue)
            .disabled(kanataManager.customRules.isEmpty)

            Button(action: { isExpanded.toggle() }) {
                Image(systemName: isExpanded ? "chevron.up" : "chevron.down")
                    .foregroundColor(.secondary)
            }
            .buttonStyle(.plain)
        }
    }

    private var areCustomRulesEnabled: Bool {
        !kanataManager.customRules.isEmpty && kanataManager.customRules.allSatisfy { $0.isEnabled }
    }

    private var expandedContent: some View {
        VStack(alignment: .leading, spacing: 4) {
            ForEach(Array(sortedRules.prefix(8))) { rule in
                customRuleRow(rule)
            }

            if sortedRules.count > 8 {
                Text("+ \(sortedRules.count - 8) more")
                    .font(.caption)
                    .foregroundColor(.secondary)
                    .padding(.horizontal, 12)
                    .padding(.top, 4)
            }
        }
        .padding(.top, 4)
    }

    private func customRuleRow(_ rule: CustomRule) -> some View {
        HStack(spacing: 8) {
            Text(rule.input)
                .font(.callout.monospaced().weight(.medium))
                .foregroundColor(.primary)
                .padding(.horizontal, 8)
                .padding(.vertical, 4)
                .background(Color(NSColor.controlBackgroundColor))
                .cornerRadius(6)

            Image(systemName: "arrow.right")
                .font(.callout)
                .foregroundColor(.secondary)

            Text(rule.output)
                .font(.callout.monospaced().weight(.medium))
                .foregroundColor(.primary)
                .padding(.horizontal, 8)
                .padding(.vertical, 4)
                .background(Color(NSColor.controlBackgroundColor))
                .cornerRadius(6)

            Spacer()

            HStack(spacing: 8) {
                Button(action: { editingRule = rule }) {
                    Image(systemName: "pencil")
                        .font(.callout)
                }
                .buttonStyle(.plain)
                .foregroundColor(.blue)

                Button(action: { pendingDeleteRule = rule }) {
                    Image(systemName: "trash")
                        .font(.callout)
                }
                .buttonStyle(.plain)
                .foregroundColor(.red)
            }
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 6)
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
            HStack(alignment: .top, spacing: 12) {
                if let icon = collection.icon {
                    iconView(for: icon)
                }

                VStack(alignment: .leading, spacing: 2) {
                    Text(collection.name)
                        .font(.headline)
                    Text(collection.summary)
                        .font(.subheadline)
                        .foregroundColor(.secondary)
                    if let activationDescription = activationDescription {
                        Label(activationDescription, systemImage: "hand.point.up.left")
                            .font(.caption)
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
                .tint(.blue)

                Button(action: { isExpanded.toggle() }) {
                    Image(systemName: isExpanded ? "chevron.up" : "chevron.down")
                        .foregroundColor(.secondary)
                }
                .buttonStyle(.plain)
            }

            if isExpanded {
                VStack(alignment: .leading, spacing: 6) {
                    ForEach(collection.mappings.prefix(8)) { mapping in
                        HStack(spacing: 8) {
                            Text(mappingDescription(for: mapping))
                                .font(.callout.monospaced().weight(.medium))
                                .foregroundColor(.primary)
                                .padding(.horizontal, 8)
                                .padding(.vertical, 4)
                                .background(Color(NSColor.controlBackgroundColor))
                                .cornerRadius(6)

                            Image(systemName: "arrow.right")
                                .font(.callout)
                                .foregroundColor(.secondary)

                            Text(mapping.output)
                                .font(.callout.monospaced().weight(.medium))
                                .foregroundColor(.primary)
                                .padding(.horizontal, 8)
                                .padding(.vertical, 4)
                                .background(Color(NSColor.controlBackgroundColor))
                                .cornerRadius(6)
                        }
                        .padding(.vertical, 2)
                    }

                    if collection.mappings.count > 8 {
                        Text("+\(collection.mappings.count - 8) more…")
                            .font(.callout)
                            .foregroundColor(.secondary)
                            .padding(.top, 4)
                    }
                }
                .padding(.leading, collection.icon == nil ? 0 : 4)
                .padding(.top, 4)
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
    @ViewBuilder
    func iconView(for icon: String) -> some View {
        if icon.hasPrefix("text:") {
            let text = String(icon.dropFirst(5))
            Text(text)
                .font(.system(size: 14, weight: .bold, design: .monospaced))
                .foregroundColor(.secondary)
                .frame(width: 24, height: 24)
        } else {
            Image(systemName: icon)
                .font(.system(size: 24))
                .foregroundColor(.secondary)
        }
    }

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
                VStack(spacing: 20) {
                    VStack(spacing: 12) {
                        Image(systemName: "square.and.pencil")
                            .font(.system(size: 48, weight: .ultraLight))
                            .foregroundColor(.secondary.opacity(0.3))

                        VStack(spacing: 4) {
                            Text("No Custom Rules Yet")
                                .font(.title3)
                                .fontWeight(.medium)
                                .foregroundColor(.primary)

                            Text("Create personalized key mappings")
                                .font(.subheadline)
                                .foregroundColor(.secondary)
                        }
                    }

                    Button {
                        isPresentingNewRule = true
                    } label: {
                        Label("Create Your First Rule", systemImage: "plus.circle.fill")
                            .font(.body.weight(.medium))
                    }
                    .buttonStyle(.borderedProminent)
                    .controlSize(.large)
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                .padding(40)
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
