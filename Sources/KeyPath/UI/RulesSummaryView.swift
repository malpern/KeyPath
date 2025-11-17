import KeyPathCore
import SwiftUI
#if os(macOS)
import AppKit
#endif

struct RulesTabView: View {
    @EnvironmentObject var kanataManager: KanataViewModel
    @State private var selectedTab: RulesSubTab = .active
    @State private var showingResetConfirmation = false
    @State private var settingsToastManager = WizardToastManager()
    @AppStorage("rulesTabTipDismissed") private var rulesTabTipDismissed = false
    private let catalog = RuleCollectionCatalog()

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
            return kanataManager.ruleCollections.enabledMappings().count
        case .available:
            let existing = Set(kanataManager.ruleCollections.map { $0.id })
            return catalog.defaultCollections().filter { !existing.contains($0.id) }.count
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
                            Text(mapping.input)
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
