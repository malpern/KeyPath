import AppKit
import SwiftUI

/// Grid view showing launcher mappings as cards.
///
/// Displays mappings in a multi-column grid with large icons and key badges.
/// Clicking a card opens the editor for that mapping.
struct LauncherDrawerView: View {
    @Binding var config: LauncherGridConfig
    @Binding var selectedKey: String?
    var onAddMapping: () -> Void
    var onEditMapping: (LauncherMapping) -> Void
    var onDeleteMapping: (UUID) -> Void

    private var sortedMappings: [LauncherMapping] {
        config.mappings.sorted { $0.key < $1.key }
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
                Button(action: onAddMapping) {
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
                            LauncherMappingCard(
                                mapping: mapping,
                                isSelected: selectedKey?.lowercased() == mapping.key.lowercased(),
                                onEdit: {
                                    selectedKey = mapping.key
                                    onEditMapping(mapping)
                                },
                                onDelete: { onDeleteMapping(mapping.id) }
                            )
                        }
                    }
                    .padding(12)
                }
            }
        }
        .background(Color(NSColor.controlBackgroundColor))
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
}

// MARK: - Mapping Card

private struct LauncherMappingCard: View {
    let mapping: LauncherMapping
    let isSelected: Bool
    var onEdit: () -> Void
    var onDelete: () -> Void

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
        switch mapping.target {
        case .app: "App"
        case .url: "Website"
        case .folder: "Folder"
        case .script: "Script"
        }
    }

    var body: some View {
        HStack(spacing: 12) {
            iconView

            VStack(alignment: .leading, spacing: 3) {
                Text(mapping.userDescription ?? mapping.target.displayName)
                    .font(.system(size: 13, weight: .medium))
                    .lineLimit(1)
                    .foregroundColor(mapping.isEnabled ? .primary : .secondary)

                HStack(spacing: 4) {
                    Image(systemName: typeIconName)
                        .font(.system(size: 9))
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
                .font(.system(size: 14, weight: .bold, design: .monospaced))
                .foregroundColor(.white)
                .frame(minWidth: 28)
                .padding(.horizontal, 8)
                .padding(.vertical, 6)
                .background(
                    RoundedRectangle(cornerRadius: 6)
                        .fill(Color.accentColor)
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
            Button("Delete", role: .destructive) { onDelete() }
        }
        .accessibilityIdentifier("launcher-card-\(mapping.key)")
        .accessibilityLabel("\(mapping.userDescription ?? mapping.target.displayName), key \(displayKey)")
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
        } else {
            Image(systemName: typeIconName)
                .font(.system(size: 20))
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
        switch mapping.target {
        case .app, .folder, .script:
            icon = AppIconResolver.icon(for: mapping.target)
        case let .url(urlString):
            icon = await services.faviconFetcher.fetchFavicon(for: urlString)
        }
    }

    private var typeIconName: String {
        switch mapping.target {
        case .app: "app.fill"
        case .url: "globe"
        case .folder: "folder.fill"
        case .script: "terminal.fill"
        }
    }
}

// MARK: - Preview

#Preview("Launcher Grid") {
    LauncherDrawerView(
        config: .constant(LauncherGridConfig.defaultConfig),
        selectedKey: .constant("s"),
        onAddMapping: {},
        onEditMapping: { _ in },
        onDeleteMapping: { _ in }
    )
    .frame(width: 900, height: 400)
}

#Preview("Launcher Grid - Empty") {
    LauncherDrawerView(
        config: .constant(LauncherGridConfig(activationMode: .holdHyper, mappings: [])),
        selectedKey: .constant(nil),
        onAddMapping: {},
        onEditMapping: { _ in },
        onDeleteMapping: { _ in }
    )
    .frame(width: 900, height: 300)
}
