//
//  SequencesModalView.swift
//  KeyPath
//
//  Created by Claude Code on 2026-01-09.
//  MAL-45: Kanata Sequences (defseq) UI Support
//

import SwiftUI

/// Modal view for creating and editing key sequences (defseq).
///
/// Follows the pattern established by ChordGroupsModalView:
/// - Two-panel layout (sidebar + editor)
/// - Visual key sequence builder with dropdowns
/// - Preset sequences for quick setup
/// - Conflict detection with warnings
/// - Global timeout configuration
struct SequencesModalView: View {
    // MARK: - State

    @Binding var config: SequencesConfig
    @State private var localConfig: SequencesConfig
    @State private var selectedSequenceID: UUID?
    @State private var conflicts: [SequenceConflict] = []

    // MARK: - Callbacks

    let onSave: (SequencesConfig) -> Void
    let onCancel: () -> Void

    // MARK: - Initialization

    init(
        config: Binding<SequencesConfig>,
        onSave: @escaping (SequencesConfig) -> Void,
        onCancel: @escaping () -> Void
    ) {
        _config = config
        _localConfig = State(initialValue: config.wrappedValue)
        self.onSave = onSave
        self.onCancel = onCancel
    }

    // MARK: - Body

    var body: some View {
        HStack(spacing: 0) {
            // Left sidebar
            sidebar
                .frame(width: 240)
                .background(Color(nsColor: .controlBackgroundColor))

            Divider()

            // Right panel
            if let selectedID = selectedSequenceID,
               let index = localConfig.sequences.firstIndex(where: { $0.id == selectedID }) {
                editorPanel(for: Binding(
                    get: { localConfig.sequences[index] },
                    set: { localConfig.sequences[index] = $0 }
                ))
            } else {
                emptyState
            }
        }
        .frame(width: 900, height: 600)
        .onAppear {
            detectConflicts()
            // Select first sequence if none selected
            if selectedSequenceID == nil, let first = localConfig.sequences.first {
                selectedSequenceID = first.id
            }
        }
    }

    // MARK: - Sidebar

    private var sidebar: some View {
        VStack(alignment: .leading, spacing: 0) {
            // Header
            HStack {
                Text("Sequences")
                    .font(.headline)
                Spacer()
                Button(action: onCancel) {
                    Image(systemName: "xmark.circle.fill")
                        .foregroundColor(.secondary)
                }
                .buttonStyle(.plain)
                .accessibilityIdentifier("sequences-modal-close-button")
                .accessibilityLabel("Close sequences modal")
            }
            .padding()

            Divider()

            // Sequence list
            ScrollView {
                LazyVStack(spacing: 4) {
                    ForEach(localConfig.sequences) { sequence in
                        sequenceRow(sequence)
                    }
                }
                .padding(.vertical, 8)
            }

            Divider()

            // Bottom controls
            VStack(spacing: 12) {
                // Add button
                Button(action: addSequence) {
                    Label("Add Sequence", systemImage: "plus.circle")
                        .frame(maxWidth: .infinity)
                }
                .buttonStyle(.bordered)
                .controlSize(.large)
                .accessibilityIdentifier("sequences-modal-add-button")
                .accessibilityLabel("Add new sequence")

                // Presets menu
                Menu {
                    Button("Window Management") {
                        addPreset(.windowManagementPreset)
                    }
                    .accessibilityIdentifier("sequences-modal-preset-window")
                    Button("Navigation") {
                        addPreset(.navigationPreset)
                    }
                    .accessibilityIdentifier("sequences-modal-preset-navigation")
                } label: {
                    Label("Add Preset", systemImage: "star.circle")
                        .frame(maxWidth: .infinity)
                }
                .buttonStyle(.bordered)
                .controlSize(.large)
                .accessibilityIdentifier("sequences-modal-preset-menu")
                .accessibilityLabel("Add preset sequence")
            }
            .padding()
        }
    }

    private func sequenceRow(_ sequence: SequenceDefinition) -> some View {
        Button(action: { selectedSequenceID = sequence.id }) {
            HStack {
                VStack(alignment: .leading, spacing: 4) {
                    Text(sequence.name)
                        .font(.system(size: 13, weight: .medium))
                        .foregroundColor(.primary)

                    Text(sequence.prettyKeys)
                        .font(.system(size: 11))
                        .foregroundColor(.secondary)
                }

                Spacer()

                // Conflict indicator
                if conflicts.contains(where: {
                    $0.sequence1.id == sequence.id || $0.sequence2.id == sequence.id
                }) {
                    Image(systemName: "exclamationmark.triangle.fill")
                        .foregroundColor(.orange)
                        .font(.system(size: 12))
                }
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 8)
            .background(selectedSequenceID == sequence.id ? Color.accentColor.opacity(0.2) : Color.clear)
            .cornerRadius(6)
        }
        .buttonStyle(.plain)
        .padding(.horizontal, 8)
        .accessibilityIdentifier("sequences-modal-row-\(sequence.id.uuidString)")
        .accessibilityLabel("Sequence: \(sequence.name), keys: \(sequence.prettyKeys)")
    }

    // MARK: - Editor Panel

    private func editorPanel(for sequence: Binding<SequenceDefinition>) -> some View {
        VStack(alignment: .leading, spacing: 20) {
            // Header
            HStack {
                TextField("Sequence Name", text: sequence.name)
                    .textFieldStyle(.plain)
                    .font(.title2)
                    .accessibilityIdentifier("sequences-modal-name-field")
                    .accessibilityLabel("Sequence name")

                Spacer()

                // Delete button
                Button(action: { deleteSequence(sequence.wrappedValue.id) }) {
                    Image(systemName: "trash")
                        .foregroundColor(.red)
                }
                .buttonStyle(.plain)
                .accessibilityIdentifier("sequences-modal-delete-button")
                .accessibilityLabel("Delete sequence")
            }

            Divider()

            ScrollView {
                VStack(alignment: .leading, spacing: 24) {
                    // Key Sequence Builder
                    sequenceBuilder(for: sequence)

                    // Action Section
                    actionSection(for: sequence)

                    // Description
                    descriptionSection(for: sequence)

                    // Global Timeout
                    timeoutSection

                    // Conflicts
                    conflictWarnings(for: sequence.wrappedValue)

                    // Tips
                    tipsSection
                }
                .padding()
            }

            Divider()

            // Bottom buttons
            HStack {
                Spacer()
                Button("Cancel", action: onCancel)
                    .keyboardShortcut(.cancelAction)
                    .accessibilityIdentifier("sequences-modal-cancel-button")
                    .accessibilityLabel("Cancel changes")

                Button("Save") {
                    onSave(localConfig)
                }
                .keyboardShortcut(.defaultAction)
                .buttonStyle(.borderedProminent)
                .disabled(!sequence.wrappedValue.isValid || conflicts.contains(where: {
                    $0.sequence1.id == sequence.wrappedValue.id || $0.sequence2.id == sequence.wrappedValue.id
                }))
                .accessibilityIdentifier("sequences-modal-save-button")
                .accessibilityLabel("Save sequences")
            }
            .padding()
        }
    }

    // MARK: - Sequence Builder

    private func sequenceBuilder(for sequence: Binding<SequenceDefinition>) -> some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Key Sequence")
                .font(.headline)

            HStack(spacing: 8) {
                ForEach(sequence.keys.wrappedValue.indices, id: \.self) { index in
                    KeyPicker(selection: Binding(
                        get: { sequence.keys.wrappedValue[index] },
                        set: { newValue in
                            var keys = sequence.keys.wrappedValue
                            keys[index] = newValue
                            sequence.keys.wrappedValue = keys
                            detectConflicts()
                        }
                    ))
                    .accessibilityIdentifier("sequences-modal-key-picker-\(index)")
                    .accessibilityLabel("Key \(index + 1) in sequence")

                    if index < sequence.keys.wrappedValue.count - 1 {
                        Image(systemName: "arrow.right")
                            .foregroundColor(.secondary)
                            .font(.system(size: 12))
                    }

                    // Remove button
                    if sequence.keys.wrappedValue.count > 1 {
                        Button(action: {
                            var keys = sequence.keys.wrappedValue
                            keys.remove(at: index)
                            sequence.keys.wrappedValue = keys
                            detectConflicts()
                        }) {
                            Image(systemName: "xmark.circle.fill")
                                .foregroundColor(.red.opacity(0.7))
                                .font(.system(size: 14))
                        }
                        .buttonStyle(.plain)
                        .accessibilityIdentifier("sequences-modal-remove-key-\(index)")
                        .accessibilityLabel("Remove key \(index + 1)")
                    }
                }

                // Add key button
                if sequence.keys.wrappedValue.count < 5 {
                    Button(action: {
                        var keys = sequence.keys.wrappedValue
                        keys.append("space")
                        sequence.keys.wrappedValue = keys
                        detectConflicts()
                    }) {
                        Label("Add Key", systemImage: "plus.circle")
                    }
                    .buttonStyle(.bordered)
                    .controlSize(.small)
                    .accessibilityIdentifier("sequences-modal-add-key-button")
                    .accessibilityLabel("Add key to sequence")
                }
            }

            Text("Maximum 5 keys in a sequence")
                .font(.caption)
                .foregroundColor(.secondary)
        }
    }

    // MARK: - Action Section

    private func actionSection(for sequence: Binding<SequenceDefinition>) -> some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Action")
                .font(.headline)

            VStack(alignment: .leading, spacing: 8) {
                Text("⚡ Activate Layer")
                    .font(.system(size: 13, weight: .medium))

                if case let .activateLayer(layer) = sequence.action.wrappedValue {
                    LayerPicker(selection: Binding(
                        get: { layer },
                        set: { sequence.action.wrappedValue = .activateLayer($0) }
                    ))
                    .accessibilityIdentifier("sequences-modal-layer-picker")
                    .accessibilityLabel("Select layer to activate")
                }
            }
            .padding()
            .background(Color.accentColor.opacity(0.1))
            .cornerRadius(8)
        }
    }

    // MARK: - Description Section

    private func descriptionSection(for sequence: Binding<SequenceDefinition>) -> some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Description (Optional)")
                .font(.headline)

            TextEditor(text: Binding(
                get: { sequence.description.wrappedValue ?? "" },
                set: { sequence.description.wrappedValue = $0.isEmpty ? nil : $0 }
            ))
            .frame(height: 60)
            .padding(4)
            .background(Color(nsColor: .textBackgroundColor))
            .cornerRadius(4)
            .accessibilityIdentifier("sequences-modal-description-field")
            .accessibilityLabel("Sequence description")
        }
    }

    // MARK: - Timeout Section

    private var timeoutSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Global Timeout")
                .font(.headline)

            VStack(alignment: .leading, spacing: 8) {
                HStack {
                    Slider(value: Binding(
                        get: { Double(localConfig.globalTimeout) },
                        set: { localConfig.globalTimeout = Int($0) }
                    ), in: 300 ... 1000, step: 50)
                        .accessibilityIdentifier("sequences-modal-timeout-slider")
                        .accessibilityLabel("Global timeout: \(localConfig.globalTimeout) milliseconds")

                    Text("\(localConfig.globalTimeout)ms")
                        .font(.system(.body, design: .monospaced))
                        .frame(width: 70, alignment: .trailing)
                }

                Text(timeoutPreset.description)
                    .font(.caption)
                    .foregroundColor(.secondary)
            }
        }
    }

    private var timeoutPreset: SequenceTimeout {
        switch localConfig.globalTimeout {
        case ..<400: .fast
        case 400 ..< 800: .moderate
        default: .relaxed
        }
    }

    // MARK: - Conflict Warnings

    private func conflictWarnings(for sequence: SequenceDefinition) -> some View {
        let sequenceConflicts = conflicts.filter {
            $0.sequence1.id == sequence.id || $0.sequence2.id == sequence.id
        }

        return Group {
            if !sequenceConflicts.isEmpty {
                VStack(alignment: .leading, spacing: 8) {
                    ForEach(sequenceConflicts) { conflict in
                        HStack(alignment: .top, spacing: 12) {
                            Image(systemName: "exclamationmark.triangle.fill")
                                .foregroundColor(.orange)

                            Text(conflict.description)
                                .font(.system(size: 13))
                                .foregroundColor(.primary)
                        }
                        .padding()
                        .background(Color.orange.opacity(0.1))
                        .cornerRadius(8)
                    }
                }
            }
        }
    }

    // MARK: - Tips Section

    private var tipsSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                Image(systemName: "lightbulb.fill")
                    .foregroundColor(.blue)
                Text("Tips")
                    .font(.headline)
            }

            VStack(alignment: .leading, spacing: 8) {
                Text("• Keep sequences short (2-3 keys) for faster activation")
                Text("• Use memorable combinations like Space → W for windows")
                Text("• Avoid overlapping sequences (e.g., 'a' and 'a b')")
                Text("• Leader key (Space) + letter is a common pattern")
            }
            .font(.caption)
            .foregroundColor(.secondary)
        }
        .padding()
        .background(Color.blue.opacity(0.05))
        .cornerRadius(8)
    }

    // MARK: - Empty State

    private var emptyState: some View {
        VStack(spacing: 16) {
            Image(systemName: "arrow.right.arrow.left.circle")
                .font(.system(size: 60))
                .foregroundColor(.secondary)

            Text("No Sequence Selected")
                .font(.title2)

            Text("Select a sequence from the sidebar or add a new one")
                .font(.body)
                .foregroundColor(.secondary)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    // MARK: - Actions

    private func addSequence() {
        let newSequence = SequenceDefinition(
            name: "New Sequence",
            keys: ["space"],
            action: .activateLayer(.navigation),
            description: nil
        )
        localConfig.sequences.append(newSequence)
        selectedSequenceID = newSequence.id
        detectConflicts()
    }

    private func addPreset(_ preset: SequenceDefinition) {
        localConfig.sequences.append(preset)
        selectedSequenceID = preset.id
        detectConflicts()
    }

    private func deleteSequence(_ id: UUID) {
        localConfig.sequences.removeAll { $0.id == id }
        selectedSequenceID = localConfig.sequences.first?.id
        detectConflicts()
    }

    private func detectConflicts() {
        conflicts = localConfig.detectConflicts()
    }
}

// MARK: - Key Picker

private struct KeyPicker: View {
    @Binding var selection: String

    // Common keys for sequences
    private let commonKeys = [
        "space", "a", "b", "c", "d", "e", "f", "g", "h", "i", "j", "k", "l",
        "m", "n", "o", "p", "q", "r", "s", "t", "u", "v", "w", "x", "y", "z",
        ";", ",", ".", "/", "[", "]", "-", "="
    ]

    var body: some View {
        Picker("", selection: $selection) {
            ForEach(commonKeys, id: \.self) { key in
                Text(key.capitalized).tag(key)
            }
        }
        .pickerStyle(.menu)
        .frame(width: 90)
        .accessibilityIdentifier("sequences-key-picker")
        .accessibilityLabel("Sequence key picker")
    }
}

// MARK: - Layer Picker

private struct LayerPicker: View {
    @Binding var selection: RuleCollectionLayer

    // Available layers from catalog
    private let availableLayers: [RuleCollectionLayer] = [
        .navigation,
        .custom("window"),
        .custom("launcher"),
        .custom("numpad"),
        .custom("sym")
    ]

    var body: some View {
        Picker("Layer", selection: $selection) {
            ForEach(availableLayers, id: \.self) { layer in
                Text(layer.displayName).tag(layer)
            }
        }
        .pickerStyle(.menu)
        .labelsHidden()
        .accessibilityIdentifier("sequences-layer-picker")
        .accessibilityLabel("Sequence layer picker")
    }
}
