import KeyPathCore
import SwiftUI

struct RulesTabView: View {
    @EnvironmentObject var kanataManager: KanataViewModel
    @State private var selectedTab: RulesSubTab = .active
    @State private var showingResetConfirmation = false
    @State private var settingsToastManager = WizardToastManager()
    @AppStorage("rulesTabTipDismissed") private var rulesTabTipDismissed = false

    enum RulesSubTab: String, CaseIterable {
        case active = "Active Rules"
        case available = "Available Rules"
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
                            Text("Tip: switch tabs to reveal curated presets you can activate with one click.")
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

            // Tab Content
            Group {
                switch selectedTab {
                case .active:
                    ActiveRulesView()
                case .available:
                    AvailableRulesView()
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
        case .active:
            kanataManager.keyMappings.count
        case .available:
            SimpleModsCatalog.shared.getAllPresets().count
        }
    }

    private func iconName(for tab: RulesSubTab) -> String {
        switch tab {
        case .active: "switch.2"
        case .available: "square.grid.2x2"
        }
    }

    private func segmentBackground(for tab: RulesSubTab) -> Color {
        if tab == selectedTab {
            tab == .active ? Color.green.opacity(0.25) : Color.blue.opacity(0.25)
        } else {
            Color.secondary.opacity(0.08)
        }
    }

    private func segmentForeground(for tab: RulesSubTab) -> Color {
        tab == selectedTab ? .primary : .secondary
    }

    private func subtitle(for tab: RulesSubTab) -> String {
        switch tab {
        case .active:
            "These mappings are currently running inside Kanata."
        case .available:
            "Explore curated presets you can activate instantly."
        }
    }

    private func contentBackground(for tab: RulesSubTab) -> Color {
        tab == .active ? Color.green.opacity(0.04) : Color.blue.opacity(0.04)
    }
}

// MARK: - Active Rules View

struct ActiveRulesView: View {
    @EnvironmentObject var kanataManager: KanataViewModel
    @State private var isHoveringEmptyState = false

    var body: some View {
        if kanataManager.keyMappings.isEmpty {
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
                VStack(alignment: .leading, spacing: 0) {
                    ForEach(Array(kanataManager.keyMappings.enumerated()), id: \.element.input) { index, mapping in
                        HStack(spacing: 12) {
                            Text(mapping.input)
                                .font(.body.monospaced())
                                .fontWeight(.medium)
                                .foregroundColor(.primary)

                            Image(systemName: "arrow.right")
                                .font(.caption)
                                .foregroundColor(.secondary)

                            Text(mapping.output)
                                .font(.body.monospaced())
                                .foregroundColor(.secondary)

                            Spacer()
                        }
                        .padding(.horizontal, 20)
                        .padding(.vertical, 10)

                        if index < kanataManager.keyMappings.count - 1 {
                            Divider()
                                .padding(.leading, 20)
                        }
                    }
                }
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

// MARK: - Available Rules View

struct AvailableRulesView: View {
    @EnvironmentObject var kanataManager: KanataViewModel
    @StateObject private var simpleModsService: SimpleModsService
    @State private var selectedPresets: Set<UUID> = []
    @State private var isActivating = false
    @State private var settingsToastManager = WizardToastManager()

    private let presets = SimpleModsCatalog.shared.getAllPresets()
    private var groupedPresets: [String: [SimpleModPreset]] {
        Dictionary(grouping: presets, by: { $0.category })
    }

    init() {
        let configPath = "\(NSHomeDirectory())/Library/Application Support/KeyPath/keypath.kbd"
        _simpleModsService = StateObject(wrappedValue: SimpleModsService(configPath: configPath))
    }

    var body: some View {
        VStack(spacing: 0) {
            // Action bar when items are selected
            if !selectedPresets.isEmpty {
                HStack(spacing: 12) {
                    Text("\(selectedPresets.count) rule\(selectedPresets.count == 1 ? "" : "s") selected")
                        .font(.body)
                        .foregroundColor(.secondary)

                    Spacer()

                    Button(action: clearSelection) {
                        Text("Clear Selection")
                    }
                    .buttonStyle(.bordered)
                    .controlSize(.small)

                    Button(action: activateSelected) {
                        Label(isActivating ? "Activating..." : "Activate", systemImage: "checkmark.circle")
                    }
                    .buttonStyle(.borderedProminent)
                    .controlSize(.small)
                    .disabled(isActivating)
                }
                .padding(.horizontal, 20)
                .padding(.vertical, 12)
                .background(Color(NSColor.controlBackgroundColor))

                Divider()
            }

            List(selection: $selectedPresets) {
                ForEach(groupedPresets.keys.sorted(), id: \.self) { category in
                    Section(header: Text(category)
                        .font(.headline)
                        .foregroundColor(.secondary)) {
                        ForEach(groupedPresets[category]!, id: \.id) { preset in
                            AvailableRuleRow(preset: preset)
                                .tag(preset.id)
                        }
                    }
                }
            }
            .listStyle(.inset)
        }
        .withToasts(settingsToastManager)
    }

    private func clearSelection() {
        selectedPresets.removeAll()
    }

    private func activateSelected() {
        guard !selectedPresets.isEmpty else { return }

        isActivating = true
        Task {
            let presetsToActivate = presets.filter { selectedPresets.contains($0.id) }

            for preset in presetsToActivate {
                // Add mapping via the simple mods service
                simpleModsService.addMapping(
                    fromKey: preset.fromKey,
                    toKey: preset.toKey,
                    enabled: true
                )
            }

            // Refresh the kanata manager to reflect new mappings
            await kanataManager.forceRefreshStatus()

            await MainActor.run {
                settingsToastManager.showSuccess("Activated \(presetsToActivate.count) rule\(presetsToActivate.count == 1 ? "" : "s")")
                selectedPresets.removeAll()
                isActivating = false
            }
        }
    }
}

// MARK: - Available Rule Row

private struct AvailableRuleRow: View {
    let preset: SimpleModPreset

    var body: some View {
        HStack(alignment: .top, spacing: 12) {
            // Left side: Name and keymap details
            VStack(alignment: .leading, spacing: 6) {
                Text(preset.name)
                    .font(.body.weight(.medium))
                    .foregroundColor(.primary)

                // Key codes below title
                HStack(spacing: 6) {
                    Text(preset.fromKey)
                        .font(.caption.monospaced())
                        .foregroundColor(.secondary)
                        .padding(.horizontal, 5)
                        .padding(.vertical, 2)
                        .background(Color(NSColor.controlBackgroundColor))
                        .cornerRadius(3)

                    Image(systemName: "arrow.right")
                        .font(.caption2)
                        .foregroundColor(.secondary)

                    Text(preset.toKey)
                        .font(.caption.monospaced())
                        .foregroundColor(.secondary)
                        .padding(.horizontal, 5)
                        .padding(.vertical, 2)
                        .background(Color(NSColor.controlBackgroundColor))
                        .cornerRadius(3)
                }
            }

            Spacer()

            // Right side: Description
            if !preset.description.isEmpty {
                Text(preset.description)
                    .font(.caption)
                    .foregroundColor(.secondary)
                    .multilineTextAlignment(.trailing)
                    .frame(maxWidth: 250, alignment: .trailing)
            }
        }
        .padding(.vertical, 4)
    }
}
