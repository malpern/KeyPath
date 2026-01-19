import SwiftUI

/// Inline view for Chord Groups collection with progressive disclosure
struct ChordGroupsCollectionView: View {
    @Binding var config: ChordGroupsConfig
    let onConfigChanged: (ChordGroupsConfig) -> Void
    let onOpenModal: () -> Void

    @State private var showDetails = false
    @State private var selectedGroupID: UUID?
    @State private var showPresetConfirmation = false

    init(
        config: Binding<ChordGroupsConfig>,
        onConfigChanged: @escaping (ChordGroupsConfig) -> Void,
        onOpenModal: @escaping () -> Void
    ) {
        _config = config
        self.onConfigChanged = onConfigChanged
        self.onOpenModal = onOpenModal
        _selectedGroupID = State(initialValue: config.wrappedValue.activeGroupID ?? config.wrappedValue.groups.first?.id)
    }

    private var selectedGroup: ChordGroup? {
        config.groups.first { $0.id == selectedGroupID }
    }

    private var totalChords: Int {
        config.groups.reduce(0) { $0 + $1.chords.count }
    }

    var body: some View {
        VStack(spacing: 0) {
            // Summary stats (always visible)
            if config.groups.isEmpty {
                emptyState
            } else {
                summarySection
                    .padding(.bottom, 12)
            }

            // Progressive disclosure: Show/hide details
            if showDetails {
                detailsSection
                    .transition(.opacity.combined(with: .move(edge: .top)))
            } else if !config.groups.isEmpty {
                Button {
                    withAnimation(.easeInOut(duration: 0.25)) {
                        showDetails = true
                    }
                } label: {
                    HStack {
                        Text("Show Details...")
                            .font(.body)
                        Spacer()
                    }
                    .padding(.vertical, 8)
                }
                .buttonStyle(.plain)
                .foregroundColor(.accentColor)
                .accessibilityIdentifier("chord-groups-show-details-button")
                .accessibilityLabel("Show chord groups details")
            }

            // Full editor button
            if !config.groups.isEmpty {
                Button(action: onOpenModal) {
                    HStack {
                        Text("Open Full Editor...")
                            .font(.body)
                        Spacer()
                        Image(systemName: "arrow.up.forward.square")
                    }
                    .padding(.vertical, 8)
                }
                .buttonStyle(.plain)
                .foregroundColor(.accentColor)
                .accessibilityIdentifier("chord-groups-open-modal-button")
                .accessibilityLabel("Open full chord groups editor")
            }
        }
        .animation(.easeInOut(duration: 0.25), value: showDetails)
        .alert("Load Ben Vallack Preset?", isPresented: $showPresetConfirmation) {
            Button("Cancel", role: .cancel) {}
            Button("Load Preset") {
                confirmLoadPreset()
            }
        } message: {
            Text("""
            This will load 2 chord groups with 7 total chords:

            • Navigation (250ms): s+d → Esc, d+f → Enter, j+k → Up, k+l → Down
            • Editing (400ms): a+s → Backspace, s+d+f → Cut, e+r → Undo

            These are Ben Vallack's home row chord combinations for fast navigation and editing.
            """)
        }
    }

    // MARK: - Summary Section

    @ViewBuilder
    private var summarySection: some View {
        HStack(spacing: 12) {
            Image(systemName: "keyboard.badge.ellipsis")
                .font(.title3)
                .foregroundColor(.accentColor)

            VStack(alignment: .leading, spacing: 4) {
                Text("\(config.groups.count) group\(config.groups.count == 1 ? "" : "s") • \(totalChords) chord\(totalChords == 1 ? "" : "s")")
                    .font(.body)
                    .fontWeight(.medium)

                if let group = selectedGroup {
                    Text("\(group.name): \(group.chords.count) chords @ \(group.timeout)ms")
                        .font(.caption)
                        .foregroundColor(.secondary)
                }
            }

            Spacer()

            // Quick actions
            Menu {
                Button(action: loadBenVallackPreset) {
                    Label("Load Ben Vallack Preset", systemImage: "wand.and.stars")
                }

                Button(action: addNewGroup) {
                    Label("Add New Group", systemImage: "plus.circle")
                }

                Button(action: onOpenModal) {
                    Label("Open Full Editor", systemImage: "arrow.up.forward.square")
                }
            } label: {
                Image(systemName: "ellipsis.circle")
                    .font(.title3)
            }
            .menuStyle(.borderlessButton)
            .accessibilityIdentifier("chord-groups-menu")
            .accessibilityLabel("Chord groups actions")
        }
    }

    @ViewBuilder
    private var emptyState: some View {
        VStack(spacing: 12) {
            Image(systemName: "keyboard.badge.ellipsis")
                .font(.largeTitle)
                .foregroundColor(.secondary)

            Text("No Chord Groups Yet")
                .font(.headline)

            Text("Create multi-key combinations for faster navigation and editing")
                .font(.subheadline)
                .foregroundColor(.secondary)
                .multilineTextAlignment(.center)

            HStack(spacing: 12) {
                Button(action: loadBenVallackPreset) {
                    Label("Load Ben Vallack Preset", systemImage: "wand.and.stars")
                }
                .buttonStyle(.bordered)
                .accessibilityIdentifier("chord-groups-load-preset-button")

                Button(action: onOpenModal) {
                    Label("Create Custom", systemImage: "plus.circle")
                }
                .buttonStyle(.bordered)
                .accessibilityIdentifier("chord-groups-create-custom-button")
            }
        }
        .padding(.vertical, 16)
        .frame(maxWidth: .infinity)
    }

    // MARK: - Details Section

    @ViewBuilder
    private var detailsSection: some View {
        VStack(alignment: .leading, spacing: 16) {
            // Group selector
            if config.groups.count > 1 {
                VStack(alignment: .leading, spacing: 8) {
                    Text("Active Group")
                        .font(.body)
                        .fontWeight(.medium)

                    Picker("Group", selection: Binding(
                        get: { selectedGroupID ?? config.groups.first?.id ?? UUID() },
                        set: { newValue in
                            selectedGroupID = newValue
                            config.activeGroupID = newValue
                            updateConfig()
                        }
                    )) {
                        ForEach(config.groups) { group in
                            HStack {
                                Image(systemName: group.category.icon)
                                Text(group.name)
                                Text("(\(group.chords.count))")
                                    .foregroundColor(.secondary)
                            }
                            .tag(group.id)
                        }
                    }
                    .pickerStyle(.segmented)
                    .accessibilityIdentifier("chord-groups-group-picker")
                }
            }

            // Selected group details
            if let group = selectedGroup {
                groupDetailsView(group: group)
            }

            // Hide details button
            Button {
                withAnimation(.easeInOut(duration: 0.25)) {
                    showDetails = false
                }
            } label: {
                HStack {
                    Text("Hide Details")
                        .font(.body)
                    Spacer()
                }
                .padding(.vertical, 8)
            }
            .buttonStyle(.plain)
            .foregroundColor(.accentColor)
            .accessibilityIdentifier("chord-groups-hide-details-button")
            .accessibilityLabel("Hide chord groups details")
        }
    }

    @ViewBuilder
    private func groupDetailsView(group: ChordGroup) -> some View {
        VStack(alignment: .leading, spacing: 12) {
            // Group info
            HStack {
                Image(systemName: group.category.icon)
                    .foregroundColor(.accentColor)
                VStack(alignment: .leading, spacing: 2) {
                    Text(group.name)
                        .font(.headline)
                    Text("\(group.category.displayName) • \(group.timeout)ms timeout")
                        .font(.caption)
                        .foregroundColor(.secondary)
                }
                Spacer()
            }
            .padding(8)
            .background(Color(nsColor: .controlBackgroundColor))
            .cornerRadius(8)

            // Chords list
            if !group.chords.isEmpty {
                VStack(alignment: .leading, spacing: 4) {
                    Text("Chords:")
                        .font(.caption)
                        .foregroundColor(.secondary)

                    ForEach(group.chords.prefix(5)) { chord in
                        InlineChordRowView(chord: chord)
                    }

                    if group.chords.count > 5 {
                        Text("+ \(group.chords.count - 5) more...")
                            .font(.caption)
                            .foregroundColor(.secondary)
                            .padding(.leading, 8)
                    }
                }
            } else {
                Text("No chords in this group yet")
                    .font(.caption)
                    .foregroundColor(.secondary)
                    .italic()
                    .padding(8)
            }

            // Conflict warnings
            if !group.isValid {
                let conflicts = group.detectConflicts()
                VStack(alignment: .leading, spacing: 4) {
                    ForEach(conflicts) { conflict in
                        HStack(spacing: 6) {
                            Image(systemName: "exclamationmark.triangle.fill")
                                .font(.caption)
                                .foregroundColor(.orange)
                            Text(conflict.description)
                                .font(.caption)
                                .foregroundColor(.orange)
                        }
                        .padding(.vertical, 4)
                        .padding(.horizontal, 8)
                        .background(Color.orange.opacity(0.1))
                        .cornerRadius(6)
                    }
                }
            }
        }
    }

    // MARK: - Actions

    private func updateConfig() {
        onConfigChanged(config)
    }

    private func loadBenVallackPreset() {
        showPresetConfirmation = true
    }

    private func confirmLoadPreset() {
        config = ChordGroupsConfig.benVallackPreset
        selectedGroupID = config.activeGroupID
        showDetails = true // Auto-expand to show the loaded groups
        updateConfig()
    }

    private func addNewGroup() {
        let newGroup = ChordGroup(
            id: UUID(),
            name: "New Group",
            timeout: 300,
            chords: [],
            description: nil,
            category: .custom
        )
        config.groups.append(newGroup)
        selectedGroupID = newGroup.id
        config.activeGroupID = newGroup.id
        showDetails = true
        updateConfig()
    }
}

// MARK: - Inline Chord Row View

private struct InlineChordRowView: View {
    let chord: ChordDefinition

    var body: some View {
        HStack(spacing: 8) {
            // Key bubbles (compact)
            HStack(spacing: 2) {
                ForEach(chord.keys, id: \.self) { key in
                    Text(key.uppercased())
                        .font(.system(size: 9, design: .monospaced))
                        .fontWeight(.semibold)
                        .padding(.horizontal, 4)
                        .padding(.vertical, 2)
                        .background(Color.accentColor.opacity(0.2))
                        .cornerRadius(3)
                }
            }

            Image(systemName: "arrow.right")
                .font(.system(size: 8))
                .foregroundColor(.secondary)

            Text(chord.output)
                .font(.system(size: 11, design: .monospaced))

            if let description = chord.description, !description.isEmpty {
                Text("·")
                    .font(.caption)
                    .foregroundColor(.secondary)
                Text(description)
                    .font(.caption)
                    .foregroundColor(.secondary)
                    .lineLimit(1)
            }

            Spacer()

            // Ergonomic indicator (small)
            Image(systemName: chord.ergonomicScore.icon)
                .font(.system(size: 10))
                .foregroundColor(ergonomicColor(chord.ergonomicScore))
        }
        .padding(.vertical, 4)
        .padding(.horizontal, 8)
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
