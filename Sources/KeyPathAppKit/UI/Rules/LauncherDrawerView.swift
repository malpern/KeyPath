import AppKit
import SwiftUI

/// Drawer view showing the list of launcher mappings.
///
/// Displays apps and websites in separate sections.
/// Clicking a mapping highlights the corresponding key on the keyboard.
struct LauncherDrawerView: View {
    @Binding var config: LauncherGridConfig
    @Binding var selectedKey: String?
    var onAddMapping: () -> Void
    var onEditMapping: (LauncherMapping) -> Void
    var onDeleteMapping: (UUID) -> Void

    /// App mappings (sorted by key)
    private var appMappings: [LauncherMapping] {
        config.mappings
            .filter(\.target.isApp)
            .sorted { $0.key < $1.key }
    }

    /// Website mappings (sorted by key)
    private var websiteMappings: [LauncherMapping] {
        config.mappings
            .filter(\.target.isURL)
            .sorted { $0.key < $1.key }
    }

    /// Folder mappings (sorted by key)
    private var folderMappings: [LauncherMapping] {
        config.mappings
            .filter(\.target.isFolder)
            .sorted { $0.key < $1.key }
    }

    /// Script mappings (sorted by key)
    private var scriptMappings: [LauncherMapping] {
        config.mappings
            .filter(\.target.isScript)
            .sorted { $0.key < $1.key }
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            // Header
            HStack {
                Text("Launchers")
                    .font(.headline)
                Spacer()
                Text("\(config.mappings.count)")
                    .font(.caption)
                    .foregroundColor(.secondary)
                    .padding(.horizontal, 6)
                    .padding(.vertical, 2)
                    .background(
                        Capsule()
                            .fill(Color.secondary.opacity(0.2))
                    )
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 10)

            Divider()

            // Scrollable content
            ScrollView {
                VStack(alignment: .leading, spacing: 16) {
                    // Apps section
                    if !appMappings.isEmpty {
                        sectionHeader("Apps", count: appMappings.count)
                        mappingsList(appMappings)
                    }

                    // Websites section
                    if !websiteMappings.isEmpty {
                        sectionHeader("Websites", count: websiteMappings.count)
                        mappingsList(websiteMappings)
                    }

                    // Folders section
                    if !folderMappings.isEmpty {
                        sectionHeader("Folders", count: folderMappings.count)
                        mappingsList(folderMappings)
                    }

                    // Scripts section
                    if !scriptMappings.isEmpty {
                        sectionHeader("Scripts", count: scriptMappings.count)
                        mappingsList(scriptMappings)
                    }

                    // Empty state
                    if config.mappings.isEmpty {
                        emptyState
                    }
                }
                .padding(12)
            }

            Divider()

            // Action buttons
            actionButtons
        }
        .background(Color(NSColor.controlBackgroundColor))
    }

    // MARK: - Section Header

    private func sectionHeader(_ title: String, count _: Int) -> some View {
        HStack {
            Text(title)
                .font(.subheadline.weight(.medium))
                .foregroundColor(.secondary)
            Spacer()
        }
    }

    // MARK: - Mappings List

    private func mappingsList(_ mappings: [LauncherMapping]) -> some View {
        VStack(spacing: 6) {
            ForEach(mappings) { mapping in
                DrawerMappingRow(
                    mapping: mapping,
                    isSelected: selectedKey?.lowercased() == mapping.key.lowercased(),
                    onSelect: {
                        selectedKey = mapping.key
                    },
                    onEdit: {
                        onEditMapping(mapping)
                    },
                    onDelete: {
                        onDeleteMapping(mapping.id)
                    }
                )
            }
        }
    }

    // MARK: - Empty State

    private var emptyState: some View {
        VStack(spacing: 8) {
            Image(systemName: "keyboard")
                .font(.system(size: 32))
                .foregroundColor(.secondary.opacity(0.5))
            Text("No launchers configured")
                .font(.subheadline)
                .foregroundColor(.secondary)
            Text("Click a key or use \"Add\" to create shortcuts")
                .font(.caption)
                .foregroundColor(.secondary.opacity(0.8))
                .multilineTextAlignment(.center)
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 20)
    }

    // MARK: - Action Buttons

    private var actionButtons: some View {
        HStack(spacing: 8) {
            Button(action: onAddMapping) {
                Label("Add", systemImage: "plus")
            }
            .buttonStyle(.bordered)
            .accessibilityIdentifier("launcher-drawer-add-button")

            Spacer()

            Menu {
                Button("Reset to Defaults") {
                    config = LauncherGridConfig.defaultConfig
                }
                Divider()
                Button("Clear All", role: .destructive) {
                    config.mappings.removeAll()
                }
            } label: {
                Image(systemName: "ellipsis.circle")
            }
            .menuStyle(.borderlessButton)
            .accessibilityIdentifier("launcher-drawer-menu-button")
        }
        .padding(12)
    }
}

// MARK: - Drawer Mapping Row

/// Individual row in the drawer for a launcher mapping.
private struct DrawerMappingRow: View {
    let mapping: LauncherMapping
    let isSelected: Bool
    var onSelect: () -> Void
    var onEdit: () -> Void
    var onDelete: () -> Void

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

    var body: some View {
        HStack(spacing: 10) {
            // Icon
            Group {
                if let icon {
                    Image(nsImage: icon)
                        .resizable()
                        .aspectRatio(contentMode: .fit)
                        .frame(width: 24, height: 24)
                        .clipShape(RoundedRectangle(cornerRadius: 5))
                } else {
                    Image(systemName: fallbackIconName)
                        .frame(width: 24, height: 24)
                        .foregroundColor(.secondary)
                }
            }

            // Key badge
            Text(displayKey.uppercased())
                .font(.system(size: 12, weight: .bold, design: .monospaced))
                .foregroundColor(.white)
                .padding(.horizontal, 6)
                .padding(.vertical, 3)
                .background(
                    RoundedRectangle(cornerRadius: 4)
                        .fill(Color.accentColor)
                )

            // Target name
            Text(mapping.target.displayName)
                .font(.system(size: 13))
                .lineLimit(1)
                .foregroundColor(mapping.isEnabled ? .primary : .secondary)

            Spacer()

            // Disabled indicator
            if !mapping.isEnabled {
                Image(systemName: "eye.slash")
                    .font(.caption)
                    .foregroundColor(.secondary)
            }
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 8)
        .background(
            RoundedRectangle(cornerRadius: 8)
                .fill(backgroundColor)
        )
        .overlay(
            RoundedRectangle(cornerRadius: 8)
                .stroke(isSelected ? Color.accentColor : Color.clear, lineWidth: 2)
        )
        .contentShape(Rectangle())
        .onTapGesture {
            onSelect()
        }
        .onHover { hovering in
            isHovering = hovering
        }
        .contextMenu {
            Button("Edit") { onEdit() }
            Divider()
            Button("Delete", role: .destructive) { onDelete() }
        }
        .accessibilityIdentifier("launcher-drawer-row-\(mapping.key)")
        .accessibilityLabel("\(mapping.target.displayName), key \(displayKey)")
        .task {
            await loadIcon()
        }
    }

    private var backgroundColor: Color {
        if isSelected {
            Color.accentColor.opacity(0.15)
        } else if isHovering {
            Color.primary.opacity(0.05)
        } else {
            Color.clear
        }
    }

    private func loadIcon() async {
        switch mapping.target {
        case .app:
            icon = AppIconResolver.icon(for: mapping.target)
        case let .url(urlString):
            icon = await FaviconFetcher.shared.fetchFavicon(for: urlString)
        case .folder, .script:
            icon = AppIconResolver.icon(for: mapping.target)
        }
    }

    /// Fallback SF Symbol name based on target type
    private var fallbackIconName: String {
        switch mapping.target {
        case .app: "app.fill"
        case .url: "globe"
        case .folder: "folder.fill"
        case .script: "terminal.fill"
        }
    }
}

// MARK: - Preview

#Preview("Launcher Drawer") {
    LauncherDrawerView(
        config: .constant(LauncherGridConfig.defaultConfig),
        selectedKey: .constant("s"),
        onAddMapping: {},
        onEditMapping: { _ in },
        onDeleteMapping: { _ in }
    )
    .frame(width: 280, height: 500)
}

#Preview("Launcher Drawer - Empty") {
    LauncherDrawerView(
        config: .constant(LauncherGridConfig(activationMode: .holdHyper, mappings: [])),
        selectedKey: .constant(nil),
        onAddMapping: {},
        onEditMapping: { _ in },
        onDeleteMapping: { _ in }
    )
    .frame(width: 280, height: 420)
}
