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
                           .firstIndex(where: { $0.id == editingChord.id }) {
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
                            .cornerRadius(8)
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
                            .cornerRadius(8)
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
                .cornerRadius(8)
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
                .font(.system(size: 48))
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
            output: "esc",
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
            .cornerRadius(6)
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
                        .cornerRadius(4)
                }
            }

            Image(systemName: "arrow.right")
                .font(.caption)
                .foregroundColor(.secondary)

            Text(chord.output)
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
        .cornerRadius(6)
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

private struct ChordEditorDialog: View {
    let chord: ChordDefinition
    let onSave: (ChordDefinition) -> Void
    let onCancel: () -> Void

    @State private var keys: [String]
    @State private var output: String
    @State private var description: String

    init(chord: ChordDefinition, onSave: @escaping (ChordDefinition) -> Void, onCancel: @escaping () -> Void) {
        self.chord = chord
        self.onSave = onSave
        self.onCancel = onCancel
        _keys = State(initialValue: chord.keys)
        _output = State(initialValue: chord.output)
        _description = State(initialValue: chord.description ?? "")
    }

    private let commonOutputs = [
        ("esc", "Escape"),
        ("enter", "Enter"),
        ("tab", "Tab"),
        ("bspc", "Backspace"),
        ("del", "Delete"),
        ("up", "Up Arrow"),
        ("down", "Down Arrow"),
        ("left", "Left Arrow"),
        ("right", "Right Arrow"),
        ("C-c", "Copy (Ctrl+C)"),
        ("C-v", "Paste (Ctrl+V)"),
        ("C-x", "Cut (Ctrl+X)"),
        ("C-z", "Undo (Ctrl+Z)")
    ]

    var body: some View {
        VStack(spacing: 0) {
            // Header
            HStack {
                Text("Edit Chord")
                    .font(.title3)
                    .fontWeight(.semibold)
                Spacer()
                Button(action: onCancel) {
                    Image(systemName: "xmark.circle.fill")
                        .foregroundColor(.secondary)
                }
                .buttonStyle(.plain)
                .accessibilityIdentifier("chord-groups-edit-close-button")
                .accessibilityLabel("Close chord editor")
            }
            .padding()

            Divider()

            ScrollView {
                VStack(alignment: .leading, spacing: 20) {
                    // Keys selection
                    VStack(alignment: .leading, spacing: 8) {
                        Text("Keys")
                            .font(.headline)

                        TextField("Keys (space-separated)", text: Binding(
                            get: { keys.joined(separator: " ") },
                            set: { keys = $0.split(separator: " ").map(String.init) }
                        ))
                        .textFieldStyle(.roundedBorder)

                        Text("Enter 2-4 keys separated by spaces (e.g., 's d' or 'j k l')")
                            .font(.caption)
                            .foregroundColor(.secondary)
                    }

                    // Output
                    VStack(alignment: .leading, spacing: 8) {
                        Text("Output")
                            .font(.headline)

                        TextField("Kanata output", text: $output)
                            .textFieldStyle(.roundedBorder)

                        Text("Common outputs:")
                            .font(.caption)
                            .foregroundColor(.secondary)

                        LazyVGrid(columns: [GridItem(.adaptive(minimum: 120))], spacing: 8) {
                            ForEach(commonOutputs, id: \.0) { outputKey, label in
                                Button {
                                    output = outputKey
                                } label: {
                                    Text(label)
                                        .font(.caption)
                                        .frame(maxWidth: .infinity)
                                }
                                .buttonStyle(.bordered)
                                .controlSize(.small)
                                .accessibilityIdentifier("chord-groups-common-output-\(outputKey)")
                                .accessibilityLabel("Set output to \(label)")
                            }
                        }
                    }

                    // Description
                    VStack(alignment: .leading, spacing: 8) {
                        Text("Description (optional)")
                            .font(.headline)

                        TextField("What does this chord do?", text: $description)
                            .textFieldStyle(.roundedBorder)
                    }

                    // Preview
                    if !keys.isEmpty, !output.isEmpty {
                        VStack(alignment: .leading, spacing: 8) {
                            Text("Preview")
                                .font(.headline)

                            HStack(spacing: 12) {
                                HStack(spacing: 4) {
                                    ForEach(keys, id: \.self) { key in
                                        Text(key.uppercased())
                                            .font(.system(.caption, design: .monospaced))
                                            .fontWeight(.semibold)
                                            .padding(.horizontal, 8)
                                            .padding(.vertical, 4)
                                            .background(Color.accentColor.opacity(0.2))
                                            .cornerRadius(4)
                                    }
                                }

                                Image(systemName: "arrow.right")
                                    .foregroundColor(.secondary)

                                Text(output)
                                    .font(.system(.subheadline, design: .monospaced))
                            }
                            .padding(8)
                            .frame(maxWidth: .infinity, alignment: .leading)
                            .background(Color(nsColor: .controlBackgroundColor))
                            .cornerRadius(8)
                        }
                    }
                }
                .padding()
            }

            Divider()

            // Actions
            HStack {
                Button("Cancel", action: onCancel)
                    .keyboardShortcut(.escape, modifiers: [])
                    .accessibilityIdentifier("chord-groups-edit-cancel-button")
                    .accessibilityLabel("Cancel chord changes")

                Spacer()

                Button("Save") {
                    let updated = ChordDefinition(
                        id: chord.id,
                        keys: keys,
                        output: output,
                        description: description.isEmpty ? nil : description
                    )
                    onSave(updated)
                }
                .keyboardShortcut(.return, modifiers: .command)
                .buttonStyle(.borderedProminent)
                .disabled(keys.count < 2 || output.isEmpty)
                .accessibilityIdentifier("chord-groups-edit-save-button")
                .accessibilityLabel("Save chord")
            }
            .padding()
        }
        .frame(width: 500, height: 600)
    }
}
