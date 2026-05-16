import SwiftUI

/// Modal dialog for Chord Groups customization (Ben Vallack-style defchords)
struct ChordGroupsModalView: View {
    @Binding var config: ChordGroupsConfig
    let onSave: (ChordGroupsConfig) -> Void
    let onCancel: () -> Void

    @State private var localConfig: ChordGroupsConfig
    @State private var selectedGroupID: UUID?
    @State private var showChordEditor = false
    @State private var editingChord: ChordDefinition?
    @State private var showDeleteConfirmation = false
    @State private var chordToDelete: ChordDefinition?

    init(
        config: Binding<ChordGroupsConfig>,
        onSave: @escaping (ChordGroupsConfig) -> Void,
        onCancel: @escaping () -> Void
    ) {
        _config = config
        self.onSave = onSave
        self.onCancel = onCancel
        _localConfig = State(initialValue: config.wrappedValue)
        _selectedGroupID = State(initialValue: config.wrappedValue.activeGroupID ?? config.wrappedValue.groups.first?.id)
    }

    private var selectedGroup: ChordGroup? {
        localConfig.groups.first { $0.id == selectedGroupID }
    }

    private var selectedGroupIndex: Int? {
        guard let id = selectedGroupID else { return nil }
        return localConfig.groups.firstIndex { $0.id == id }
    }

    var body: some View {
        VStack(spacing: 0) {
            // Header
            HStack {
                Text("Chord Groups Editor")
                    .font(.title2)
                    .fontWeight(.semibold)
                Spacer()
                Button(action: onCancel) {
                    Image(systemName: "xmark.circle.fill")
                        .foregroundColor(.secondary)
                        .font(.title3)
                }
                .buttonStyle(.plain)
                .accessibilityIdentifier("chord-groups-modal-close-button")
                .accessibilityLabel("Close")
            }
            .padding()

            Divider()

            // Main content: sidebar + detail
            HStack(spacing: 0) {
                // Left sidebar: Group list
                groupListSidebar
                    .frame(width: 220)

                Divider()

                // Right panel: Chord editor for selected group
                if let group = selectedGroup, let index = selectedGroupIndex {
                    chordEditorPanel(group: group, index: index)
                } else {
                    emptyState
                }
            }
        }
        .frame(width: 800, height: 600)
        .sheet(isPresented: $showChordEditor) {
            if let editingChord {
                ChordEditorDialog(
                    chord: editingChord,
                    onSave: { updated in
                        if let groupIndex = selectedGroupIndex,
                           let chordIndex = localConfig.groups[groupIndex].chords
                           .firstIndex(where: { $0.id == editingChord.id })
                        {
                            localConfig.groups[groupIndex].chords[chordIndex] = updated
                        }
                        showChordEditor = false
                        self.editingChord = nil
                    },
                    onCancel: {
                        showChordEditor = false
                        self.editingChord = nil
                    }
                )
            }
        }
        .accessibilityIdentifier("chord-groups-modal")
    }

    // MARK: - Group List Sidebar

    private var groupListSidebar: some View {
        VStack(alignment: .leading, spacing: 0) {
            // Sidebar header
            Text("GROUPS")
                .font(.caption)
                .fontWeight(.semibold)
                .foregroundColor(.secondary)
                .padding(.horizontal, 12)
                .padding(.top, 12)
                .padding(.bottom, 8)

            ScrollView {
                VStack(spacing: 4) {
                    ForEach(localConfig.groups) { group in
                        GroupRowView(
                            group: group,
                            isSelected: selectedGroupID == group.id,
                            onSelect: {
                                withAnimation(.easeInOut(duration: 0.15)) {
                                    selectedGroupID = group.id
                                }
                            }
                        )
                    }
                }
                .padding(.horizontal, 8)
                .padding(.vertical, 4)
            }

            Divider()

            // Add group button
            Button(action: addNewGroup) {
                Label("Add Group", systemImage: "plus.circle")
                    .frame(maxWidth: .infinity, alignment: .leading)
            }
            .buttonStyle(.plain)
            .padding(12)
            .accessibilityIdentifier("chord-groups-add-group-button")
            .accessibilityLabel("Add new chord group")
        }
        .background(Color(nsColor: .controlBackgroundColor))
    }

    // MARK: - Chord Editor Panel

    @ViewBuilder
    private func chordEditorPanel(group: ChordGroup, index: Int) -> some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 20) {
                // Group header
                VStack(alignment: .leading, spacing: 8) {
                    HStack {
                        TextField("Group Name", text: Binding(
                            get: { group.name },
                            set: { localConfig.groups[index].name = $0 }
                        ))
                        .textFieldStyle(.plain)
                        .font(.title2)
                        .fontWeight(.semibold)

                        Spacer()

                        // Delete group button
                        if localConfig.groups.count > 1 {
                            Button {
                                deleteGroup(group)
                            } label: {
                                Image(systemName: "trash")
                                    .foregroundColor(.red)
                            }
                            .buttonStyle(.plain)
                            .accessibilityIdentifier("chord-group-delete-button")
                            .accessibilityLabel("Delete group")
                        }
                    }

                    TextField("Description (optional)", text: Binding(
                        get: { group.description ?? "" },
                        set: { localConfig.groups[index].description = $0.isEmpty ? nil : $0 }
                    ))
                    .textFieldStyle(.plain)
                    .font(.subheadline)
                    .foregroundColor(.secondary)
                }

                Divider()

                // Category picker
                VStack(alignment: .leading, spacing: 8) {
                    Text("Category")
                        .font(.headline)

                    Picker("Category", selection: Binding(
                        get: { group.category },
                        set: { newCategory in
                            localConfig.groups[index].category = newCategory
                            // Update timeout to category's suggested value
                            localConfig.groups[index].timeout = newCategory.suggestedTimeout
                        }
                    )) {
                        ForEach(ChordCategory.allCases, id: \.self) { category in
                            HStack {
                                Image(systemName: category.icon)
                                Text(category.displayName)
                            }
                            .tag(category)
                        }
                    }
                    .pickerStyle(.segmented)
                    .accessibilityIdentifier("chord-group-category-picker")
                }

                // Timeout slider
                VStack(alignment: .leading, spacing: 8) {
                    HStack {
                        Text("Timeout")
                            .font(.headline)
                        Spacer()
                        Text("\(group.timeout)ms")
                            .font(.subheadline)
                            .foregroundColor(.secondary)
                        Text("(\(ChordSpeed.nearest(to: group.timeout).rawValue))")
                            .font(.caption)
                            .foregroundColor(.secondary)
                    }

                    Slider(
                        value: Binding(
                            get: { Double(group.timeout) },
                            set: { localConfig.groups[index].timeout = Int($0) }
                        ),
                        in: 100 ... 800,
                        step: 50
                    )

                    // Speed preset buttons
                    HStack(spacing: 8) {
                        ForEach(ChordSpeed.allCases, id: \.self) { speed in
                            Button(speed.rawValue) {
                                localConfig.groups[index].timeout = speed.milliseconds
                            }
                            .buttonStyle(.bordered)
                            .controlSize(.small)
                            .accessibilityIdentifier("chord-speed-preset-\(speed.rawValue.lowercased().replacingOccurrences(of: " ", with: "-"))")
                        }
                    }

                    Text(ChordSpeed.nearest(to: group.timeout).description)
                        .font(.caption)
                        .foregroundColor(.secondary)
                }

                Divider()

                // Chord definitions
                VStack(alignment: .leading, spacing: 12) {
                    HStack {
                        Text("Chord Definitions")
                            .font(.headline)
                        Spacer()
                        Text("\(group.chords.count) chords")
                            .font(.caption)
                            .foregroundColor(.secondary)
                    }

                    if !group.chords.isEmpty {
                        VStack(spacing: 8) {
                            ForEach(group.chords) { chord in
                                ChordRowView(
                                    chord: chord,
                                    onEdit: {
                                        editingChord = chord
                                        showChordEditor = true
                                    },
                                    onDelete: {
                                        chordToDelete = chord
                                        showDeleteConfirmation = true
                                    }
                                )
                            }
                        }
                    } else {
                        Text("No chords yet. Add your first chord below.")
                            .font(.subheadline)
                            .foregroundColor(.secondary)
                            .padding()
                            .frame(maxWidth: .infinity)
                            .background(Color(nsColor: .controlBackgroundColor))
                            .clipShape(.rect(cornerRadius: 8))
                    }

                    Button(action: addNewChord) {
                        Label("Add Chord", systemImage: "plus.circle")
                    }
                    .accessibilityIdentifier("chord-group-add-chord-button")
                }

                // Conflict warnings
                if !group.isValid {
                    let conflicts = group.detectConflicts()
                    VStack(alignment: .leading, spacing: 8) {
                        ForEach(conflicts) { conflict in
                            HStack(spacing: 8) {
                                Image(systemName: "exclamationmark.triangle.fill")
                                    .foregroundColor(.orange)
                                Text(conflict.description)
                                    .font(.caption)
                            }
                            .padding(8)
                            .frame(maxWidth: .infinity, alignment: .leading)
                            .background(Color.orange.opacity(0.1))
                            .clipShape(.rect(cornerRadius: 8))
                        }
                    }
                }

                // Info tip
                HStack(spacing: 8) {
                    Image(systemName: "lightbulb.fill")
                        .foregroundColor(.blue)
                    Text("Tip: Adjacent home row keys (like SD, DF) are most ergonomic")
                        .font(.caption)
                        .foregroundColor(.secondary)
                }
                .padding(8)
                .frame(maxWidth: .infinity, alignment: .leading)
                .background(Color.blue.opacity(0.1))
                .clipShape(.rect(cornerRadius: 8))
            }
            .padding(20)
        }

        Divider()

        // Bottom action buttons
        HStack {
            Button("Cancel", action: onCancel)
                .keyboardShortcut(.escape, modifiers: [])
                .accessibilityIdentifier("chord-groups-modal-cancel-button")

            Spacer()

            Button("Save Changes") {
                onSave(localConfig)
            }
            .keyboardShortcut(.return, modifiers: .command)
            .buttonStyle(.borderedProminent)
            .accessibilityIdentifier("chord-groups-modal-save-button")
        }
        .padding()
    }

    private var emptyState: some View {
        VStack(spacing: 16) {
            Image(systemName: "keyboard.badge.ellipsis")
                .font(.largeTitle)
                .foregroundColor(.secondary)
            Text("No Group Selected")
                .font(.title3)
                .fontWeight(.medium)
            Text("Select a group from the sidebar or add a new one")
                .font(.subheadline)
                .foregroundColor(.secondary)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    // MARK: - Actions

    private func addNewGroup() {
        let newGroup = ChordGroup(
            id: UUID(),
            name: "New Group",
            timeout: 300,
            chords: [],
            description: nil,
            category: .custom
        )
        localConfig.groups.append(newGroup)
        selectedGroupID = newGroup.id
    }

    private func deleteGroup(_ group: ChordGroup) {
        guard localConfig.groups.count > 1 else { return }

        if let index = localConfig.groups.firstIndex(where: { $0.id == group.id }) {
            localConfig.groups.remove(at: index)

            // Select another group
            if let nextGroup = localConfig.groups.first {
                selectedGroupID = nextGroup.id
            }
        }
    }

    private func addNewChord() {
        guard let index = selectedGroupIndex else { return }

        let newChord = ChordDefinition(
            id: UUID(),
            keys: ["s", "d"],
            action: .keystroke(key: "esc"),
            description: nil
        )

        editingChord = newChord
        localConfig.groups[index].chords.append(newChord)
        showChordEditor = true
    }
}

// MARK: - Group Row View

private struct GroupRowView: View {
    let group: ChordGroup
    let isSelected: Bool
    let onSelect: () -> Void

    var body: some View {
        Button(action: onSelect) {
            HStack(spacing: 8) {
                Image(systemName: group.category.icon)
                    .font(.caption)
                    .foregroundColor(isSelected ? .white : .secondary)

                VStack(alignment: .leading, spacing: 2) {
                    Text(group.name)
                        .font(.subheadline)
                        .fontWeight(isSelected ? .semibold : .regular)
                        .foregroundColor(isSelected ? .white : .primary)

                    Text("\(group.chords.count) chords • \(group.timeout)ms")
                        .font(.caption)
                        .foregroundColor(isSelected ? .white.opacity(0.8) : .secondary)
                }

                Spacer()

                if !group.isValid {
                    Image(systemName: "exclamationmark.triangle.fill")
                        .font(.caption)
                        .foregroundColor(isSelected ? .white : .orange)
                }
            }
            .padding(8)
            .background(isSelected ? Color.accentColor : Color.clear)
            .clipShape(.rect(cornerRadius: 6))
        }
        .buttonStyle(.plain)
        .accessibilityIdentifier("chord-group-row-\(group.id)")
    }
}

// MARK: - Chord Row View

private struct ChordRowView: View {
    let chord: ChordDefinition
    let onEdit: () -> Void
    let onDelete: () -> Void

    var body: some View {
        HStack(spacing: 12) {
            // Key bubbles
            HStack(spacing: 4) {
                ForEach(chord.keys, id: \.self) { key in
                    Text(key.uppercased())
                        .font(.system(.caption, design: .monospaced))
                        .fontWeight(.semibold)
                        .padding(.horizontal, 8)
                        .padding(.vertical, 4)
                        .background(Color.accentColor.opacity(0.2))
                        .clipShape(.rect(cornerRadius: 4))
                }
            }

            Image(systemName: "arrow.right")
                .font(.caption)
                .foregroundColor(.secondary)

            Text(chord.action.displayName)
                .font(.system(.subheadline, design: .monospaced))
                .foregroundColor(.primary)

            if let description = chord.description, !description.isEmpty {
                Text("·")
                    .foregroundColor(.secondary)
                Text(description)
                    .font(.caption)
                    .foregroundColor(.secondary)
            }

            Spacer()

            // Ergonomic indicator
            Image(systemName: chord.ergonomicScore.icon)
                .font(.caption)
                .foregroundColor(ergonomicColor(chord.ergonomicScore))

            Button(action: onEdit) {
                Image(systemName: "pencil")
                    .font(.caption)
            }
            .buttonStyle(.plain)
            .accessibilityIdentifier("chord-edit-button-\(chord.id)")

            Button(action: onDelete) {
                Image(systemName: "trash")
                    .font(.caption)
                    .foregroundColor(.red)
            }
            .buttonStyle(.plain)
            .accessibilityIdentifier("chord-delete-button-\(chord.id)")
        }
        .padding(8)
        .background(Color(nsColor: .controlBackgroundColor))
        .clipShape(.rect(cornerRadius: 6))
    }

    private func ergonomicColor(_ score: ErgonomicScore) -> Color {
        switch score {
        case .excellent: .green
        case .good: .blue
        case .moderate: .yellow
        case .fair: .orange
        case .poor: .red
        }
    }
}

// MARK: - Chord Editor Dialog

struct ChordEditorDialog: View {
    let chord: ChordDefinition
    let onSave: (ChordDefinition) -> Void
    let onCancel: () -> Void

    @State private var keys: [String]
    @State private var output: String
    @State private var description: String
    @State private var newKeyInput: String = ""

    init(chord: ChordDefinition, onSave: @escaping (ChordDefinition) -> Void, onCancel: @escaping () -> Void) {
        self.chord = chord
        self.onSave = onSave
        self.onCancel = onCancel
        _keys = State(initialValue: chord.keys)
        _output = State(initialValue: chord.action.kanataOutput)
        _description = State(initialValue: chord.description ?? "")
    }

    private static let keycapText = Color(red: 0.88, green: 0.93, blue: 1.0)
    private static let keycapBg = Color(white: 0.12)

    private let quickOutputs: [(key: String, label: String, icon: String)] = [
        ("esc", "Esc", "escape"),
        ("enter", "Return", "return"),
        ("bspc", "Delete", "delete.backward"),
        ("tab", "Tab", "arrow.right.to.line"),
        ("up", "↑", "arrow.up"),
        ("down", "↓", "arrow.down"),
        ("left", "←", "arrow.left"),
        ("right", "→", "arrow.right"),
        ("C-z", "Undo", "arrow.uturn.backward"),
        ("C-x", "Cut", "scissors"),
        ("C-c", "Copy", "doc.on.doc"),
        ("C-v", "Paste", "doc.on.clipboard"),
    ]

    private var isValid: Bool {
        let validKeys = keys.filter { !$0.isEmpty }
        return validKeys.count >= 2 && !output.isEmpty
    }

    var body: some View {
        VStack(spacing: 0) {
            // Hero: live keycap preview
            keycapPreview
                .padding(.top, 24)
                .padding(.bottom, 16)

            // Form
            VStack(spacing: 16) {
                // Keys
                HStack(alignment: .center) {
                    Text("Keys")
                        .font(.system(size: 12, weight: .medium))
                        .foregroundStyle(.secondary)
                        .frame(width: 70, alignment: .trailing)

                    HStack(spacing: 4) {
                        ForEach(Array(keys.enumerated()), id: \.offset) { index, key in
                            if !key.isEmpty {
                                Button {
                                    keys.remove(at: index)
                                } label: {
                                    HStack(spacing: 3) {
                                        Text(key.uppercased())
                                            .font(.system(size: 12, weight: .semibold, design: .monospaced))
                                        Image(systemName: "xmark")
                                            .font(.system(size: 8, weight: .bold))
                                            .foregroundStyle(.secondary)
                                    }
                                    .padding(.horizontal, 8)
                                    .padding(.vertical, 5)
                                    .background(
                                        RoundedRectangle(cornerRadius: 5, style: .continuous)
                                            .fill(Color.primary.opacity(0.08))
                                    )
                                }
                                .buttonStyle(.plain)
                            }
                        }

                        if keys.filter({ !$0.isEmpty }).count < 4 {
                            TextField("key", text: $newKeyInput)
                                .textFieldStyle(.roundedBorder)
                                .font(.system(size: 12, design: .monospaced))
                                .frame(width: 60)
                                .onSubmit {
                                    let trimmed = newKeyInput.trimmingCharacters(in: .whitespaces).lowercased()
                                    if !trimmed.isEmpty {
                                        keys = keys.filter { !$0.isEmpty }
                                        keys.append(trimmed)
                                        newKeyInput = ""
                                    }
                                }
                        }
                    }
                }

                // Output field + quick picks
                HStack(alignment: .top) {
                    Text("Output")
                        .font(.system(size: 12, weight: .medium))
                        .foregroundStyle(.secondary)
                        .frame(width: 70, alignment: .trailing)
                        .padding(.top, 4)

                    VStack(alignment: .leading, spacing: 8) {
                        TextField("esc", text: $output)
                            .textFieldStyle(.roundedBorder)
                            .font(.system(size: 13, design: .monospaced))

                        LazyVGrid(columns: [GridItem(.adaptive(minimum: 64))], spacing: 4) {
                            ForEach(quickOutputs, id: \.key) { item in
                                Button {
                                    output = item.key
                                } label: {
                                    HStack(spacing: 3) {
                                        Image(systemName: item.icon)
                                            .font(.system(size: 9))
                                        Text(item.label)
                                            .font(.system(size: 10))
                                    }
                                    .frame(maxWidth: .infinity)
                                    .padding(.vertical, 4)
                                    .background(
                                        RoundedRectangle(cornerRadius: 5, style: .continuous)
                                            .fill(output == item.key ? Color.accentColor.opacity(0.2) : Color.primary.opacity(0.05))
                                    )
                                    .overlay(
                                        RoundedRectangle(cornerRadius: 5, style: .continuous)
                                            .strokeBorder(output == item.key ? Color.accentColor.opacity(0.4) : Color.clear, lineWidth: 1)
                                    )
                                }
                                .buttonStyle(.plain)
                                .accessibilityIdentifier("chord-quick-output-\(item.key)")
                            }
                        }
                    }
                }

                // Description
                HStack(alignment: .firstTextBaseline) {
                    Text("Note")
                        .font(.system(size: 12, weight: .medium))
                        .foregroundStyle(.secondary)
                        .frame(width: 70, alignment: .trailing)

                    TextField("Optional description", text: $description)
                        .textFieldStyle(.roundedBorder)
                        .font(.system(size: 13))
                }
            }
            .padding(.horizontal, 24)

            Spacer()

            // Actions
            HStack {
                Button("Cancel", action: onCancel)
                    .keyboardShortcut(.escape, modifiers: [])
                    .accessibilityIdentifier("chord-editor-cancel")

                Spacer()

                Button("Save") {
                    let action: KeyAction = if quickOutputs.contains(where: { $0.key == output }) {
                        .keystroke(key: output)
                    } else if output.contains("-") || output.contains("(") {
                        .rawKanata(output)
                    } else {
                        .keystroke(key: output)
                    }
                    let updated = ChordDefinition(
                        id: chord.id,
                        keys: keys.filter { !$0.isEmpty },
                        action: action,
                        description: description.isEmpty ? nil : description,
                        isEnabled: chord.isEnabled
                    )
                    onSave(updated)
                }
                .keyboardShortcut(.return, modifiers: .command)
                .buttonStyle(.borderedProminent)
                .disabled(!isValid)
                .accessibilityIdentifier("chord-editor-save")
            }
            .padding(20)
        }
        .frame(width: 420, height: 400)
    }

    // MARK: - Keycap Preview

    private var keycapPreview: some View {
        HStack(spacing: 10) {
            // Input keycaps
            HStack(spacing: 4) {
                let displayKeys = keys.filter { !$0.isEmpty }
                if displayKeys.isEmpty {
                    placeholderKeycap("?")
                    placeholderKeycap("?")
                } else {
                    ForEach(displayKeys, id: \.self) { key in
                        keycap(key.uppercased())
                    }
                }
            }

            Image(systemName: "arrow.right")
                .font(.title3.weight(.medium))
                .foregroundStyle(.secondary)

            // Output keycap
            if output.isEmpty {
                placeholderKeycap("?")
            } else {
                keycap(output)
            }
        }
    }

    private func keycap(_ text: String) -> some View {
        Text(text)
            .font(.system(size: 16, weight: .semibold, design: .monospaced))
            .foregroundStyle(Self.keycapText)
            .padding(.horizontal, 14)
            .padding(.vertical, 10)
            .background(
                RoundedRectangle(cornerRadius: 8, style: .continuous)
                    .fill(Self.keycapBg)
            )
            .overlay(
                RoundedRectangle(cornerRadius: 8, style: .continuous)
                    .strokeBorder(Color.secondary.opacity(0.2), lineWidth: 0.5)
            )
    }

    private func placeholderKeycap(_ text: String) -> some View {
        Text(text)
            .font(.system(size: 16, weight: .semibold, design: .monospaced))
            .foregroundStyle(.secondary.opacity(0.4))
            .padding(.horizontal, 14)
            .padding(.vertical, 10)
            .background(
                RoundedRectangle(cornerRadius: 8, style: .continuous)
                    .fill(Self.keycapBg.opacity(0.3))
            )
            .overlay(
                RoundedRectangle(cornerRadius: 8, style: .continuous)
                    .strokeBorder(Color.secondary.opacity(0.1), lineWidth: 0.5)
            )
    }
}
