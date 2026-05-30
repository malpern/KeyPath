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
                chord: ChordDefinition(id: UUID(), keys: ["s", "d"], action: .keystroke(key: "esc")),
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
        VStack(alignment: .leading, spacing: 6) {
            HStack(spacing: 6) {
                Image(systemName: group.category.icon)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                Text(group.name)
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(.secondary)
                Spacer()
                Text("\(group.timeout)ms")
                    .font(.caption.monospaced())
                    .foregroundStyle(.tertiary)
            }

            VStack(spacing: 6) {
                ForEach(Array(group.chords.enumerated()), id: \.element.id) { chordIndex, chord in
                    ChordRuleRow(
                        chord: chord,
                        onToggle: {
                            ensureConfigPopulated()
                            config.groups[groupIndex].chords[chordIndex].isEnabled.toggle()
                            onConfigChanged(config)
                            SoundManager.shared.playTinkSound()
                        },
                        onEdit: {
                            ensureConfigPopulated()
                            editingChord = (groupIndex, chordIndex)
                        },
                        onDelete: {
                            ensureConfigPopulated()
                            config.groups[groupIndex].chords.remove(at: chordIndex)
                            onConfigChanged(config)
                        }
                    )
                }
            }
            .padding(8)
            .background(Color(NSColor.controlBackgroundColor).opacity(0.8))
            .clipShape(RoundedRectangle(cornerRadius: 10, style: .continuous))

            Button {
                addingChordToGroup = groupIndex
            } label: {
                HStack(spacing: 4) {
                    Image(systemName: "plus")
                        .font(.caption2.weight(.semibold))
                    Text("Add chord")
                        .font(.subheadline)
                }
                .foregroundStyle(Color.accentColor)
            }
            .buttonStyle(.plain)
            .accessibilityIdentifier("chord-pack-add-chord-\(groupIndex)")
        }
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
                    .font(.caption2.weight(.semibold))
                Text("Add group")
                    .font(.subheadline)
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

// MARK: - Chord Rule Row (matches GlobalRulesCard style)

private struct ChordRuleRow: View {
    let chord: ChordDefinition
    let onToggle: () -> Void
    let onEdit: () -> Void
    let onDelete: () -> Void

    @State private var isHovered = false

    private static let keycapTextColor = KeyPathColors.keycapText
    private static let keycapBgColor = Color(white: 0.12)

    var body: some View {
        HStack(spacing: 0) {
            // Checkbox — separate button to avoid gesture conflict
            Button(action: onToggle) {
                Image(systemName: chord.isEnabled ? "checkmark.circle.fill" : "circle")
                    .font(.body)
                    .foregroundStyle(chord.isEnabled ? Color.accentColor : Color.secondary.opacity(0.4))
                    .frame(width: 30, height: 30)
                    .contentShape(Rectangle())
            }
            .buttonStyle(.plain)

            // Rest of the row — tapping opens editor
            Button(action: onEdit) {
                ZStack(alignment: .trailing) {
                    HStack {
                        // Input keys — left aligned
                        HStack(spacing: 3) {
                            ForEach(chord.keys, id: \.self) { key in
                                Text(key.uppercased())
                                    .font(.body.monospaced().weight(.semibold))
                                    .foregroundStyle(chord.isEnabled ? Self.keycapTextColor : Self.keycapTextColor.opacity(0.4))
                                    .padding(.horizontal, 10)
                                    .padding(.vertical, 6)
                                    .background(
                                        RoundedRectangle(cornerRadius: 6)
                                            .fill(chord.isEnabled ? Self.keycapBgColor : Self.keycapBgColor.opacity(0.4))
                                    )
                                    .overlay(
                                        RoundedRectangle(cornerRadius: 6)
                                            .strokeBorder(Color.secondary.opacity(0.15), lineWidth: 0.5)
                                    )
                            }
                        }

                        Spacer()

                        // Arrow — centered
                        Image(systemName: "arrow.right")
                            .font(.body.weight(.medium))
                            .foregroundStyle(.secondary)

                        Spacer()

                        // Output — right aligned
                        outputKeycap(for: chord.action, enabled: chord.isEnabled)
                    }

                    // Hover action buttons
                    if isHovered {
                        HStack(spacing: 2) {
                            Button(action: onEdit) {
                                Image(systemName: "pencil")
                                    .font(.caption.weight(.semibold))
                                    .foregroundStyle(.white)
                                    .frame(width: 24, height: 24)
                                    .background(Circle().fill(Color.accentColor))
                            }
                            .buttonStyle(.plain)
                            .accessibilityLabel("Edit chord")

                            Button(action: onDelete) {
                                Image(systemName: "trash")
                                    .font(.caption.weight(.semibold))
                                    .foregroundStyle(.white)
                                    .frame(width: 24, height: 24)
                                    .background(Circle().fill(Color.red.opacity(0.85)))
                            }
                            .buttonStyle(.plain)
                            .accessibilityLabel("Delete chord")
                        }
                        .padding(.trailing, 4)
                        .transition(.opacity.combined(with: .scale(scale: 0.8)))
                    }
                }
                .padding(.vertical, 6)
                .padding(.horizontal, 8)
                .background(isHovered ? Color.accentColor.opacity(0.15) : Color.clear)
                .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
                .overlay(
                    RoundedRectangle(cornerRadius: 8, style: .continuous)
                        .stroke(Color.accentColor.opacity(isHovered ? 0.4 : 0), lineWidth: 1)
                )
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
        }
        .onHover { hovering in
            withAnimation(.easeInOut(duration: 0.15)) {
                isHovered = hovering
            }
        }
    }

    @ViewBuilder
    private func outputKeycap(for action: KeyAction, enabled: Bool) -> some View {
        let textOpacity: Double = enabled ? 1.0 : 0.4
        let bgOpacity: Double = enabled ? 1.0 : 0.4

        HStack(spacing: 4) {
            if let info = action.commonDisplayInfo, let icon = info.icon {
                Image(systemName: icon)
                    .font(.callout.weight(.semibold))
            }
            Text(action.commonDisplayInfo?.label ?? action.displayName)
                .font(.body.weight(.semibold))
        }
        .foregroundStyle(Self.keycapTextColor.opacity(textOpacity))
        .padding(.horizontal, 10)
        .padding(.vertical, 6)
        .background(
            RoundedRectangle(cornerRadius: 6)
                .fill(Self.keycapBgColor.opacity(bgOpacity))
        )
        .overlay(
            RoundedRectangle(cornerRadius: 6)
                .strokeBorder(Color.secondary.opacity(0.15), lineWidth: 0.5)
        )
    }
}

// MARK: - Sheet Items

private struct ChordEditItem: Identifiable {
    let groupIndex: Int
    let chordIndex: Int
    let chord: ChordDefinition
    var id: UUID {
        chord.id
    }
}

private struct ChordAddItem: Identifiable {
    let groupIndex: Int
    var id: Int {
        groupIndex
    }
}
