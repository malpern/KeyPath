import SwiftUI

struct ChordGroupsPackContent: View {
    @Binding var config: ChordGroupsConfig
    let onConfigChanged: (ChordGroupsConfig) -> Void

    @State private var editingChord: (groupIndex: Int, chordIndex: Int)?
    @State private var addingChordToGroup: Int?

    private var displayConfig: ChordGroupsConfig {
        config.groups.isEmpty ? .benVallackPreset : config
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            ForEach(Array(displayConfig.groups.enumerated()), id: \.element.id) { groupIndex, group in
                groupSection(group: group, groupIndex: groupIndex)
            }

            addGroupRow
        }
        .sheet(item: editingChordBinding) { item in
            ChordEditorDialog(
                chord: item.chord,
                onSave: { updated in
                    ensureConfigPopulated()
                    config.groups[item.groupIndex].chords[item.chordIndex] = updated
                    onConfigChanged(config)
                    editingChord = nil
                },
                onCancel: { editingChord = nil }
            )
        }
        .sheet(item: addingChordBinding) { item in
            ChordEditorDialog(
                chord: ChordDefinition(id: UUID(), keys: ["", ""], output: ""),
                onSave: { newChord in
                    ensureConfigPopulated()
                    config.groups[item.groupIndex].chords.append(newChord)
                    onConfigChanged(config)
                    addingChordToGroup = nil
                },
                onCancel: { addingChordToGroup = nil }
            )
        }
    }

    // MARK: - Group Section

    private func groupSection(group: ChordGroup, groupIndex: Int) -> some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack(spacing: 6) {
                Image(systemName: group.category.icon)
                    .font(.system(size: 10))
                    .foregroundStyle(.secondary)
                Text(group.name)
                    .font(.system(size: 11, weight: .semibold))
                    .foregroundStyle(.secondary)
                Spacer()
                Text("\(group.timeout)ms")
                    .font(.system(size: 10, design: .monospaced))
                    .foregroundStyle(.tertiary)
            }
            .padding(.bottom, 4)

            VStack(spacing: 0) {
                ForEach(Array(group.chords.enumerated()), id: \.element.id) { chordIndex, chord in
                    chordRow(chord: chord, groupIndex: groupIndex, chordIndex: chordIndex, isEnabled: !config.groups.isEmpty)

                    if chordIndex < group.chords.count - 1 {
                        Divider().padding(.leading, 32)
                    }
                }
            }
            .background(Color(nsColor: .controlBackgroundColor))
            .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))

            Button {
                addingChordToGroup = groupIndex
            } label: {
                HStack(spacing: 4) {
                    Image(systemName: "plus")
                        .font(.system(size: 9, weight: .semibold))
                    Text("Add chord")
                        .font(.system(size: 11))
                }
                .foregroundStyle(Color.accentColor)
                .padding(.top, 4)
            }
            .buttonStyle(.plain)
            .accessibilityIdentifier("chord-pack-add-chord-\(groupIndex)")
        }
    }

    // MARK: - Chord Row

    private func chordRow(chord: ChordDefinition, groupIndex: Int, chordIndex: Int, isEnabled: Bool) -> some View {
        HStack(spacing: 8) {
            // Toggle
            Image(systemName: isEnabled ? "checkmark.circle.fill" : "circle")
                .font(.system(size: 14))
                .foregroundStyle(isEnabled ? Color.accentColor : Color.secondary.opacity(0.4))
                .onTapGesture {
                    toggleChordEnabled(groupIndex: groupIndex, chordIndex: chordIndex, currentlyEnabled: isEnabled)
                }

            // Key pills
            HStack(spacing: 2) {
                ForEach(chord.keys, id: \.self) { key in
                    Text(key.uppercased())
                        .font(.system(size: 10, weight: .semibold, design: .monospaced))
                        .padding(.horizontal, 5)
                        .padding(.vertical, 2)
                        .background(Color.accentColor.opacity(0.12))
                        .clipShape(RoundedRectangle(cornerRadius: 3, style: .continuous))
                }
            }

            Image(systemName: "arrow.right")
                .font(.system(size: 8))
                .foregroundStyle(.quaternary)

            Text(chord.output)
                .font(.system(size: 11, design: .monospaced))
                .foregroundStyle(.primary)

            if let desc = chord.description, !desc.isEmpty {
                Text(desc)
                    .font(.system(size: 10))
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
            }

            Spacer()
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 7)
        .contentShape(Rectangle())
        .onTapGesture {
            ensureConfigPopulated()
            editingChord = (groupIndex, chordIndex)
        }
        .accessibilityIdentifier("chord-pack-row-\(groupIndex)-\(chordIndex)")
    }

    // MARK: - Add Group

    private var addGroupRow: some View {
        Button {
            ensureConfigPopulated()
            let newGroup = ChordGroup(
                id: UUID(),
                name: "Custom-\(config.groups.count + 1)",
                timeout: ChordSpeed.moderate.milliseconds,
                chords: [],
                category: .custom
            )
            config.groups.append(newGroup)
            onConfigChanged(config)
        } label: {
            HStack(spacing: 4) {
                Image(systemName: "plus")
                    .font(.system(size: 9, weight: .semibold))
                Text("Add group")
                    .font(.system(size: 11))
            }
            .foregroundStyle(Color.accentColor)
        }
        .buttonStyle(.plain)
        .accessibilityIdentifier("chord-pack-add-group")
    }

    // MARK: - Helpers

    private func ensureConfigPopulated() {
        if config.groups.isEmpty {
            config = .benVallackPreset
        }
    }

    private func toggleChordEnabled(groupIndex: Int, chordIndex: Int, currentlyEnabled: Bool) {
        if currentlyEnabled {
            ensureConfigPopulated()
            config.groups[groupIndex].chords.remove(at: chordIndex)
            onConfigChanged(config)
        } else {
            ensureConfigPopulated()
            onConfigChanged(config)
        }
    }

    // MARK: - Sheet Bindings

    private var editingChordBinding: Binding<ChordEditItem?> {
        Binding(
            get: {
                guard let editing = editingChord else { return nil }
                let src = displayConfig
                guard editing.groupIndex < src.groups.count,
                      editing.chordIndex < src.groups[editing.groupIndex].chords.count
                else { return nil }
                return ChordEditItem(
                    groupIndex: editing.groupIndex,
                    chordIndex: editing.chordIndex,
                    chord: src.groups[editing.groupIndex].chords[editing.chordIndex]
                )
            },
            set: { if $0 == nil { editingChord = nil } }
        )
    }

    private var addingChordBinding: Binding<ChordAddItem?> {
        Binding(
            get: {
                guard let gi = addingChordToGroup, gi < displayConfig.groups.count
                else { return nil }
                return ChordAddItem(groupIndex: gi)
            },
            set: { if $0 == nil { addingChordToGroup = nil } }
        )
    }
}

private struct ChordEditItem: Identifiable {
    let groupIndex: Int
    let chordIndex: Int
    let chord: ChordDefinition
    var id: UUID { chord.id }
}

private struct ChordAddItem: Identifiable {
    let groupIndex: Int
    var id: Int { groupIndex }
}
