import SwiftUI

struct ChordGroupsPackContent: View {
    @Binding var config: ChordGroupsConfig
    let onConfigChanged: (ChordGroupsConfig) -> Void

    @State private var editingChord: (groupIndex: Int, chordIndex: Int)?
    @State private var addingChordToGroup: Int?

    var body: some View {
        VStack(alignment: .leading, spacing: 20) {
            if config.groups.isEmpty {
                emptyState
            } else {
                ForEach(Array(config.groups.enumerated()), id: \.element.id) { groupIndex, group in
                    chordGroupSection(group: group, groupIndex: groupIndex)
                }
            }

            addGroupButton

            howItWorks
        }
        .sheet(item: editingChordBinding) { item in
            ChordEditorDialog(
                chord: item.chord,
                onSave: { updated in
                    config.groups[item.groupIndex].chords[item.chordIndex] = updated
                    onConfigChanged(config)
                    editingChord = nil
                },
                onCancel: { editingChord = nil }
            )
        }
        .sheet(item: addingChordBinding) { item in
            ChordEditorDialog(
                chord: ChordDefinition(
                    id: UUID(),
                    keys: ["", ""],
                    output: "",
                    description: nil
                ),
                onSave: { newChord in
                    config.groups[item.groupIndex].chords.append(newChord)
                    onConfigChanged(config)
                    addingChordToGroup = nil
                },
                onCancel: { addingChordToGroup = nil }
            )
        }
    }

    // MARK: - Empty State

    private var emptyState: some View {
        VStack(spacing: 16) {
            Image(systemName: "keyboard.badge.ellipsis")
                .font(.system(size: 36))
                .foregroundStyle(.secondary)

            Text("No chord groups configured")
                .font(.headline)

            Text("Get started with pre-built navigation and editing chords, or create your own.")
                .font(.subheadline)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)

            Button {
                config = ChordGroupsConfig.benVallackPreset
                onConfigChanged(config)
            } label: {
                Label("Load Starter Chords", systemImage: "wand.and.stars")
            }
            .buttonStyle(.borderedProminent)
            .controlSize(.regular)
            .accessibilityIdentifier("chord-pack-load-presets")
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 24)
    }

    // MARK: - Group Section

    private func chordGroupSection(group: ChordGroup, groupIndex: Int) -> some View {
        VStack(alignment: .leading, spacing: 0) {
            groupHeader(group: group, groupIndex: groupIndex)

            VStack(spacing: 1) {
                ForEach(Array(group.chords.enumerated()), id: \.element.id) { chordIndex, chord in
                    chordRow(chord: chord, groupIndex: groupIndex, chordIndex: chordIndex)
                }

                addChordButton(groupIndex: groupIndex)
            }
            .background(Color(nsColor: .controlBackgroundColor).opacity(0.3))
            .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
        }
    }

    private func groupHeader(group: ChordGroup, groupIndex: Int) -> some View {
        HStack {
            Image(systemName: group.category.icon)
                .font(.system(size: 12))
                .foregroundStyle(.secondary)

            Text(group.name)
                .font(.system(size: 13, weight: .semibold))

            Spacer()

            Menu {
                ForEach(ChordSpeed.allCases, id: \.self) { speed in
                    Button {
                        config.groups[groupIndex].timeout = speed.milliseconds
                        onConfigChanged(config)
                    } label: {
                        HStack {
                            Text(speed.rawValue)
                            if speed.milliseconds == group.timeout {
                                Image(systemName: "checkmark")
                            }
                        }
                    }
                }
            } label: {
                Text("\(group.timeout)ms")
                    .font(.system(size: 11, design: .monospaced))
                    .foregroundStyle(.secondary)
                    .padding(.horizontal, 8)
                    .padding(.vertical, 3)
                    .background(Color.primary.opacity(0.06))
                    .clipShape(Capsule())
            }
            .menuStyle(.borderlessButton)
            .fixedSize()
            .accessibilityIdentifier("chord-pack-group-\(groupIndex)-timeout")

            Button(role: .destructive) {
                config.groups.remove(at: groupIndex)
                onConfigChanged(config)
            } label: {
                Image(systemName: "trash")
                    .font(.system(size: 11))
                    .foregroundStyle(.secondary)
            }
            .buttonStyle(.plain)
            .accessibilityIdentifier("chord-pack-group-\(groupIndex)-delete")
        }
        .padding(.horizontal, 4)
        .padding(.bottom, 6)
    }

    // MARK: - Chord Row

    private func chordRow(chord: ChordDefinition, groupIndex: Int, chordIndex: Int) -> some View {
        HStack(spacing: 8) {
            // Key pills
            HStack(spacing: 3) {
                ForEach(chord.keys, id: \.self) { key in
                    Text(key.uppercased())
                        .font(.system(size: 11, weight: .semibold, design: .monospaced))
                        .padding(.horizontal, 6)
                        .padding(.vertical, 3)
                        .background(Color.accentColor.opacity(0.15))
                        .clipShape(RoundedRectangle(cornerRadius: 4, style: .continuous))
                }
            }

            Image(systemName: "arrow.right")
                .font(.system(size: 10))
                .foregroundStyle(.tertiary)

            Text(chord.output)
                .font(.system(size: 12, design: .monospaced))

            if let desc = chord.description, !desc.isEmpty {
                Text("·")
                    .foregroundStyle(.tertiary)
                Text(desc)
                    .font(.system(size: 11))
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
            }

            Spacer()

            // Ergonomic score
            Image(systemName: chord.ergonomicScore.icon)
                .font(.system(size: 10))
                .foregroundStyle(ergonomicColor(chord.ergonomicScore))

            // Delete
            Button {
                config.groups[groupIndex].chords.remove(at: chordIndex)
                onConfigChanged(config)
            } label: {
                Image(systemName: "xmark")
                    .font(.system(size: 9, weight: .semibold))
                    .foregroundStyle(.tertiary)
            }
            .buttonStyle(.plain)
            .accessibilityIdentifier("chord-pack-chord-delete-\(groupIndex)-\(chordIndex)")
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 8)
        .contentShape(Rectangle())
        .onTapGesture {
            editingChord = (groupIndex, chordIndex)
        }
        .accessibilityIdentifier("chord-pack-chord-row-\(groupIndex)-\(chordIndex)")
    }

    private func addChordButton(groupIndex: Int) -> some View {
        Button {
            addingChordToGroup = groupIndex
        } label: {
            HStack(spacing: 6) {
                Image(systemName: "plus")
                    .font(.system(size: 10, weight: .semibold))
                Text("Add chord")
                    .font(.system(size: 12))
                Spacer()
            }
            .foregroundStyle(.secondary)
            .padding(.horizontal, 12)
            .padding(.vertical, 8)
        }
        .buttonStyle(.plain)
        .accessibilityIdentifier("chord-pack-add-chord-\(groupIndex)")
    }

    // MARK: - Add Group

    private var addGroupButton: some View {
        Button {
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
            HStack(spacing: 6) {
                Image(systemName: "plus.circle")
                    .font(.system(size: 12))
                Text("Add Group")
                    .font(.system(size: 12, weight: .medium))
            }
            .foregroundStyle(Color.accentColor)
        }
        .buttonStyle(.plain)
        .accessibilityIdentifier("chord-pack-add-group")
    }

    // MARK: - How It Works

    private var howItWorks: some View {
        VStack(alignment: .leading, spacing: 8) {
            Divider()
            Text("How Chords Work")
                .font(.system(size: 11, weight: .semibold))
                .foregroundStyle(.secondary)
            Text("Press two or more keys simultaneously (within the timeout window) to trigger a single action. Faster than shortcuts because your fingers never leave home row.")
                .font(.system(size: 11))
                .foregroundStyle(.tertiary)
        }
    }

    // MARK: - Helpers

    private func ergonomicColor(_ score: ErgonomicScore) -> Color {
        switch score {
        case .excellent: .green
        case .good: .blue
        case .moderate: .yellow
        case .fair: .orange
        case .poor: .red
        }
    }

    // MARK: - Sheet Bindings

    private var editingChordBinding: Binding<ChordEditItem?> {
        Binding(
            get: {
                guard let editing = editingChord,
                      editing.groupIndex < config.groups.count,
                      editing.chordIndex < config.groups[editing.groupIndex].chords.count
                else { return nil }
                return ChordEditItem(
                    groupIndex: editing.groupIndex,
                    chordIndex: editing.chordIndex,
                    chord: config.groups[editing.groupIndex].chords[editing.chordIndex]
                )
            },
            set: { newValue in
                if newValue == nil { editingChord = nil }
            }
        )
    }

    private var addingChordBinding: Binding<ChordAddItem?> {
        Binding(
            get: {
                guard let groupIndex = addingChordToGroup,
                      groupIndex < config.groups.count
                else { return nil }
                return ChordAddItem(groupIndex: groupIndex)
            },
            set: { newValue in
                if newValue == nil { addingChordToGroup = nil }
            }
        )
    }
}

// MARK: - Sheet Item Types

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
