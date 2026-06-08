import AppKit
import SwiftUI

/// Grid view showing launcher mappings as cards.
///
/// Displays mappings in a multi-column grid with large icons and key badges.
/// Clicking a card opens the editor for that mapping.
struct LauncherDrawerView: View {
    @Binding var config: LauncherGridConfig
    @Binding var selectedKey: String?
    var onConfigChanged: ((LauncherGridConfig) -> Void)?
    var windowSnappingActive: Bool = false

    @State private var editingMapping: LauncherMapping?
    @State private var showAddMapping = false

    private var sortedMappings: [LauncherMapping] {
        var mappings = config.mappings.sorted { $0.key < $1.key }
        if windowSnappingActive {
            let synthetic = LauncherMapping(
                key: "w",
                action: .systemAction(id: "window-snapping"),
                userDescription: "Window Snapping"
            )
            mappings.insert(synthetic, at: mappings.firstIndex(where: { $0.key > "w" }) ?? mappings.endIndex)
        }
        return mappings
    }

    private func isWindowSnappingEntry(_ mapping: LauncherMapping) -> Bool {
        if case let .systemAction(id) = mapping.action, id == "window-snapping" { return true }
        return false
    }

    private let columns = [
        GridItem(.adaptive(minimum: 250, maximum: 340), spacing: 10),
    ]

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            // Header
            HStack(spacing: 8) {
                Text("Mappings")
                    .font(.headline)
                Text("\(config.mappings.count)")
                    .font(.caption)
                    .foregroundColor(.secondary)
                    .padding(.horizontal, 6)
                    .padding(.vertical, 2)
                    .background(Capsule().fill(Color.secondary.opacity(0.2)))
                Spacer()
                Button(action: { showAddMapping = true }) {
                    Label("Add Mapping", systemImage: "plus")
                }
                .buttonStyle(.bordered)
                .controlSize(.small)
                .accessibilityIdentifier("launcher-drawer-add-button")
                Menu {
                    Button("Reset to Defaults") { config = LauncherGridConfig.defaultConfig }
                    Divider()
                    Button("Clear All", role: .destructive) { config.mappings.removeAll() }
                } label: {
                    Image(systemName: "ellipsis.circle")
                }
                .menuStyle(.borderlessButton)
                .accessibilityIdentifier("launcher-drawer-menu-button")
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 10)

            Divider()

            if config.mappings.isEmpty {
                emptyState
            } else {
                ScrollView {
                    LazyVGrid(columns: columns, spacing: 10) {
                        ForEach(sortedMappings) { mapping in
                            let isSynthetic = isWindowSnappingEntry(mapping)
                            LauncherMappingCard(
                                mapping: mapping,
                                isSelected: !isSynthetic && selectedKey?.lowercased() == mapping.key.lowercased(),
                                onEdit: {
                                    guard !isSynthetic else { return }
                                    selectedKey = mapping.key
                                    editingMapping = mapping
                                },
                                onDelete: { guard !isSynthetic else { return }; deleteMapping(id: mapping.id) },
                                onToggleEnabled: isSynthetic ? nil : { newValue in
                                    toggleMapping(mapping, enabled: newValue)
                                }
                            )
                        }
                    }
                    .padding(12)
                }
            }
        }
        .background(Color(NSColor.controlBackgroundColor))
        .onReceive(NotificationCenter.default.publisher(for: .launcherSelectKey)) { notification in
            guard let key = notification.userInfo?["key"] as? String else { return }
            let normalized = key.lowercased()
            if let existing = config.mappings.first(where: { $0.key.lowercased() == normalized }) {
                selectedKey = key
                editingMapping = existing
            } else {
                selectedKey = key
                editingMapping = LauncherMapping(key: LauncherGridConfig.normalizeKey(key), action: .launchApp(name: "", bundleId: nil))
            }
        }
        .sheet(item: $editingMapping) { mapping in
            let isExisting = config.mappings.contains(where: { $0.id == mapping.id })
            LauncherMappingEditor(
                mapping: mapping,
                existingKeys: Set(config.mappings.filter { $0.id != mapping.id }.map { LauncherGridConfig.normalizeKey($0.key) }),
                onSave: { updated in
                    if isExisting {
                        updateMapping(updated)
                    } else {
                        addMapping(updated)
                    }
                    editingMapping = nil
                },
                onCancel: {
                    editingMapping = nil
                },
                onDelete: isExisting ? {
                    deleteMapping(id: mapping.id)
                    editingMapping = nil
                } : nil
            )
        }
        .sheet(isPresented: $showAddMapping) {
            LauncherMappingEditor(
                mapping: nil,
                existingKeys: Set(config.mappings.map { LauncherGridConfig.normalizeKey($0.key) }),
                onSave: { newMapping in
                    addMapping(newMapping)
                    showAddMapping = false
                },
                onCancel: {
                    showAddMapping = false
                }
            )
        }
    }

    // MARK: - Empty State

    private var emptyState: some View {
        VStack(spacing: 8) {
            Image(systemName: "keyboard")
                .font(.title)
                .foregroundColor(.secondary.opacity(0.5))
            Text("No launchers configured")
                .font(.subheadline)
                .foregroundColor(.secondary)
            Text("Click a key above or tap \"Add Mapping\"")
                .font(.caption)
                .foregroundColor(.secondary.opacity(0.8))
                .multilineTextAlignment(.center)
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 40)
    }

    // MARK: - Actions

    private func updateMapping(_ mapping: LauncherMapping) {
        guard let index = config.mappings.firstIndex(where: { $0.id == mapping.id }) else { return }
        config.mappings[index] = mapping
        onConfigChanged?(config)
    }

    private func addMapping(_ mapping: LauncherMapping) {
        config.mappings.append(mapping)
        onConfigChanged?(config)
        selectedKey = mapping.key
    }

    private func deleteMapping(id: UUID) {
        config.mappings.removeAll { $0.id == id }
        onConfigChanged?(config)
        if let selected = selectedKey,
           config.mappings.first(where: { $0.key.lowercased() == selected.lowercased() }) == nil
        {
            selectedKey = nil
        }
    }

    private func toggleMapping(_ mapping: LauncherMapping, enabled: Bool) {
        guard let index = config.mappings.firstIndex(where: { $0.id == mapping.id }) else { return }
        config.mappings[index].isEnabled = enabled
        onConfigChanged?(config)
    }
}

// MARK: - Mapping Card

private struct LauncherMappingCard: View {
    let mapping: LauncherMapping
    let isSelected: Bool
    var onEdit: () -> Void
    var onDelete: () -> Void
    var onToggleEnabled: ((Bool) -> Void)?

    @Environment(\.services) private var services
    @State private var icon: NSImage?
    @State private var isHovering = false
    @AppStorage(KeymapPreferences.keymapIdKey) private var selectedKeymapId: String = LogicalKeymap.defaultId
    @AppStorage(KeymapPreferences.includePunctuationStoreKey) private var includePunctuationStore: String = "{}"

    private var keyTranslator: LauncherKeymapTranslator {
        LauncherKeymapTranslator(keymapId: selectedKeymapId, includePunctuationStore: includePunctuationStore)
    }

    private var displayKey: String {
        keyTranslator.displayLabel(for: mapping.key)
    }

    private var typeLabel: String {
        switch mapping.action {
        case .launchApp: "App"
        case .openURL: "Website"
        case .openFolder: "Folder"
        case .runScript: "Script"
        case let .systemAction(id) where id == "window-snapping": "Layer"
        default: "Action"
        }
    }

    var body: some View {
        HStack(spacing: 12) {
            // Icon or Checkbox (checkbox replaces icon on hover)
            Group {
                if isHovering {
                    Toggle("", isOn: Binding(
                        get: { mapping.isEnabled },
                        set: { newValue in onToggleEnabled?(newValue) }
                    ))
                    .toggleStyle(.checkbox)
                    .labelsHidden()
                    .controlSize(.regular)
                    .frame(width: 44, height: 44)
                    .accessibilityIdentifier("launcher-card-toggle-\(mapping.key)")
                    .accessibilityLabel("Toggle \(mapping.userDescription ?? mapping.action.displayName)")
                } else {
                    iconView
                }
            }

            VStack(alignment: .leading, spacing: 3) {
                Text(mapping.userDescription ?? mapping.action.displayName)
                    .font(.body.weight(.medium))
                    .lineLimit(1)
                    .foregroundColor(mapping.isEnabled ? .primary : .secondary)
                    .strikethrough(!mapping.isEnabled, color: .secondary)

                HStack(spacing: 4) {
                    Image(systemName: typeIconName)
                        .font(.caption2)
                    Text(typeLabel)
                        .font(.caption2)
                    if !mapping.isEnabled {
                        Text("· Disabled")
                            .font(.caption2)
                    }
                }
                .foregroundColor(.secondary)
            }

            Spacer(minLength: 4)

            Text(displayKey.uppercased())
                .font(.body.bold().monospaced())
                .foregroundColor(.white)
                .frame(minWidth: 28)
                .padding(.horizontal, 8)
                .padding(.vertical, 6)
                .background(
                    RoundedRectangle(cornerRadius: 6)
                        .fill(mapping.isEnabled ? Color.accentColor : Color.gray)
                )
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 10)
        .background(
            RoundedRectangle(cornerRadius: 10)
                .fill(backgroundColor)
        )
        .overlay(
            RoundedRectangle(cornerRadius: 10)
                .stroke(isSelected ? Color.accentColor : Color.clear, lineWidth: 2)
        )
        .contentShape(Rectangle())
        .onTapGesture { onEdit() }
        .onHover { isHovering = $0 }
        .contextMenu {
            Button("Edit") { onEdit() }
            Divider()
            if mapping.isEnabled {
                Button("Disable") { onToggleEnabled?(false) }
            } else {
                Button("Enable") { onToggleEnabled?(true) }
            }
            Divider()
            Button("Delete", role: .destructive) { onDelete() }
        }
        .accessibilityIdentifier("launcher-card-\(mapping.key)")
        .accessibilityLabel("\(mapping.userDescription ?? mapping.action.displayName), key \(displayKey)")
        .accessibilityValue(mapping.isEnabled ? "enabled" : "disabled")
        .accessibilityHint("Use the Edit, Enable, Disable, or Delete accessibility actions to manage this launcher.")
        .accessibilityAction(named: "Edit") { onEdit() }
        .accessibilityAction(named: mapping.isEnabled ? "Disable" : "Enable") {
            onToggleEnabled?(!mapping.isEnabled)
        }
        .accessibilityAction(named: "Delete") { onDelete() }
        .task { await loadIcon() }
    }

    // MARK: - Icon

    @ViewBuilder
    private var iconView: some View {
        if let icon {
            Image(nsImage: icon)
                .resizable()
                .aspectRatio(contentMode: .fit)
                .frame(width: 44, height: 44)
                .clipShape(RoundedRectangle(cornerRadius: 10))
                .shadow(color: .black.opacity(0.15), radius: 2, y: 1)
                .saturation(mapping.isEnabled ? 1.0 : 0.3)
        } else {
            Image(systemName: typeIconName)
                .font(.title2)
                .foregroundColor(.secondary)
                .frame(width: 44, height: 44)
                .background(
                    RoundedRectangle(cornerRadius: 10)
                        .fill(Color.secondary.opacity(0.12))
                )
        }
    }

    private var backgroundColor: Color {
        if isSelected {
            Color.accentColor.opacity(0.12)
        } else if isHovering {
            Color.primary.opacity(0.06)
        } else {
            Color(NSColor.controlBackgroundColor).opacity(0.8)
        }
    }

    private func loadIcon() async {
        if let iconPath = mapping.customIconPath {
            let expanded = (iconPath as NSString).expandingTildeInPath
            if let img = NSImage(contentsOfFile: expanded) {
                img.size = NSSize(width: 44, height: 44)
                icon = img
                return
            }
        }
        switch mapping.action {
        case .launchApp, .openFolder, .runScript:
            icon = AppIconResolver.icon(for: mapping.action)
        case let .openURL(urlString):
            icon = await services.faviconFetcher.fetchFavicon(for: urlString)
        default:
            break
        }
    }

    private var typeIconName: String {
        switch mapping.action {
        case .launchApp: "app.fill"
        case .openURL: "globe"
        case .openFolder: "folder.fill"
        case .runScript: "terminal.fill"
        case let .systemAction(id) where id == "window-snapping": "rectangle.split.2x2"
        default: "questionmark.circle"
        }
    }
}

// MARK: - Preview

#Preview("Launcher Grid") {
    LauncherDrawerView(
        config: .constant(LauncherGridConfig.defaultConfig),
        selectedKey: .constant("s")
    )
    .frame(width: 900, height: 400)
}

#Preview("Launcher Grid - Empty") {
    LauncherDrawerView(
        config: .constant(LauncherGridConfig(activationMode: .holdHyper, mappings: [])),
        selectedKey: .constant(nil)
    )
    .frame(width: 900, height: 300)
}
