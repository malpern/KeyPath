import AppKit
import KeyPathCore
import SwiftUI

/// Launchers section for the overlay drawer.
/// Configuration list for quick launch shortcuts - icons show on the virtual keyboard.
struct OverlayLaunchersSection: View {
    let isDark: Bool
    /// Fade amount for monochrome/opacity transition (0 = full color, 1 = faded)
    var fadeAmount: CGFloat = 0
    /// Callback when hovering a mapping row - passes key for keyboard highlighting
    var onMappingHover: ((String?) -> Void)?
    /// Callback when customize is tapped (opens slide-over panel)
    var onCustomize: (() -> Void)?
    /// KanataViewModel for opening Pack Detail window
    var kanataViewModel: KanataViewModel?

    @State private var store: LauncherStore
    @State private var showAddSheet = false
    @State private var editingMapping: LauncherMapping?

    init(
        isDark: Bool,
        fadeAmount: CGFloat = 0,
        onMappingHover: ((String?) -> Void)? = nil,
        onCustomize: (() -> Void)? = nil,
        kanataViewModel: KanataViewModel? = nil
    ) {
        self.isDark = isDark
        self.fadeAmount = fadeAmount
        self.onMappingHover = onMappingHover
        self.onCustomize = onCustomize
        self.kanataViewModel = kanataViewModel
        _store = State(initialValue: LauncherStore())
    }

    /// Testing init that accepts pre-populated mappings instead of loading from RuleCollectionStore.
    init(isDark: Bool, fadeAmount: CGFloat = 0, testMappings: [LauncherMapping]) {
        self.isDark = isDark
        self.fadeAmount = fadeAmount
        onMappingHover = nil
        onCustomize = nil
        kanataViewModel = nil
        let store = LauncherStore(testMappings: testMappings)
        _store = State(initialValue: store)
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            // Scrollable content (mappings list)
            ScrollView {
                VStack(alignment: .leading, spacing: 0) {
                    // Mappings list or empty state
                    if store.mappings.isEmpty {
                        emptyState
                    } else {
                        mappingsList
                    }
                }
            }

            Spacer(minLength: 0)

            // Bottom controls: Add/Edit (left) and Settings (right)
            HStack(spacing: 8) {
                Button {
                    openLauncherPackDetail()
                } label: {
                    HStack(spacing: 6) {
                        Image(systemName: "plus")
                        Text("Add Shortcut")
                    }
                    .font(.subheadline)
                    .padding(.horizontal, 12)
                    .padding(.vertical, 6)
                    .background(
                        RoundedRectangle(cornerRadius: 6)
                            .fill(Color.primary.opacity(0.1))
                    )
                    .overlay(
                        RoundedRectangle(cornerRadius: 6)
                            .strokeBorder(Color.primary.opacity(0.2), lineWidth: 0.5)
                    )
                }
                .buttonStyle(.plain)
                .accessibilityIdentifier("overlay-launcher-add")

                Spacer()

                // Settings icon - opens slide-over panel
                if onCustomize != nil {
                    Button {
                        onCustomize?()
                    } label: {
                        Image(systemName: "slider.horizontal.3")
                            .font(.body)
                            .foregroundStyle(.secondary)
                    }
                    .buttonStyle(.plain)
                    .accessibilityIdentifier("overlay-launcher-customize")
                    .accessibilityLabel("Launcher settings")
                }
            }
            .padding(.top, 6)
        }
        .onReceive(NotificationCenter.default.publisher(for: .launcherSelectKey)) { notification in
            guard let key = notification.userInfo?["key"] as? String else { return }
            editOrCreateMapping(forKey: key)
        }
        .sheet(item: $editingMapping) { mapping in
            LauncherMappingEditor(
                mapping: mapping,
                existingKeys: Set(store.mappings.filter { $0.id != mapping.id }.map { LauncherGridConfig.normalizeKey($0.key) }),
                onSave: { updated in
                    saveOrAddLauncherMapping(updated)
                    editingMapping = nil
                },
                onCancel: {
                    editingMapping = nil
                },
                onDelete: {
                    withAnimation(.easeOut(duration: 0.15)) {
                        store.deleteMapping(mapping.id)
                    }
                    editingMapping = nil
                }
            )
        }
    }

    private func openLauncherPackDetail() {
        guard let vm = kanataViewModel else { return }
        PackDetailWindowController.shared.showWindow(
            pack: PackRegistry.launcher,
            kanataManager: vm,
            fromOverlay: true
        )
    }

    private func saveOrAddLauncherMapping(_ mapping: LauncherMapping) {
        Task { @MainActor in
            var collections = await RuleCollectionStore.shared.loadCollections()
            guard let index = collections.firstIndex(where: { $0.id == RuleCollectionIdentifier.launcher }),
                  var config = collections[index].configuration.launcherGridConfig
            else { return }
            if let mappingIndex = config.mappings.firstIndex(where: { $0.id == mapping.id }) {
                config.mappings[mappingIndex] = mapping
            } else {
                config.mappings.append(mapping)
            }
            collections[index].configuration = .launcherGrid(config)
            try? await RuleCollectionStore.shared.saveCollections(collections)
            NotificationCenter.default.post(name: .ruleCollectionsChanged, object: nil)
            store.reloadFromCollections()
        }
    }

    private func editOrCreateMapping(forKey key: String) {
        Task { @MainActor in
            let collections = await RuleCollectionStore.shared.loadCollections()
            guard let collection = collections.first(where: { $0.id == RuleCollectionIdentifier.launcher }),
                  let config = collection.configuration.launcherGridConfig
            else { return }
            let normalized = LauncherGridConfig.normalizeKey(key)
            if let existing = config.mappings.first(where: { LauncherGridConfig.normalizeKey($0.key) == normalized }) {
                editingMapping = existing
            } else {
                editingMapping = LauncherMapping(key: normalized, action: .launchApp(name: "", bundleId: nil))
            }
        }
    }

    private var emptyState: some View {
        VStack(spacing: 6) {
            Image(systemName: "plus.circle.dashed")
                .font(.title2)
                .foregroundStyle(.tertiary)
            Text("Add shortcuts below")
                .font(.caption)
                .foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 16)
    }

    private var mappingsList: some View {
        VStack(spacing: 2) {
            ForEach(store.sortedMappings) { mapping in
                LauncherMappingRow(
                    mapping: mapping,
                    isEnabled: Binding(
                        get: { mapping.isEnabled },
                        set: { newValue in
                            var updated = mapping
                            updated.isEnabled = newValue
                            withAnimation(.easeInOut(duration: 0.2)) {
                                store.updateMapping(updated)
                            }
                        }
                    ),
                    fadeAmount: fadeAmount,
                    onTap: { editingMapping = mapping },
                    onDelete: {
                        withAnimation(.easeOut(duration: 0.15)) {
                            store.deleteMapping(mapping.id)
                        }
                    },
                    onPoofAt: { screenPoint in
                        // Play a delete affordance at the delete location
                        playDeletePoof(at: screenPoint)
                        // Then delete with a quick fade
                        withAnimation(.easeOut(duration: 0.1)) {
                            store.deleteMapping(mapping.id)
                        }
                    },
                    onHoverChange: onMappingHover
                )
                .transition(.asymmetric(
                    insertion: .opacity.combined(with: .move(edge: .top)).combined(with: .scale(scale: 0.8)),
                    removal: .opacity // Simple fade since poof handles the visual
                ))
            }
        }
        .animation(.easeInOut(duration: 0.25), value: store.sortedMappings.map(\.id))
    }

    private func playDeletePoof(at screenPoint: NSPoint) {
        if #available(macOS 14.0, *) {
            NSCursor.disappearingItem.push()
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.15) {
                NSCursor.pop()
            }
        } else {
            legacyPoof(at: screenPoint)
        }
    }

    @available(macOS, deprecated: 14.0)
    private func legacyPoof(at screenPoint: NSPoint) {
        NSAnimationEffect.disappearingItemDefault.show(
            centeredAt: screenPoint,
            size: .zero // Use default size
        )
    }
}

// MARK: - Mapping Row

private struct LauncherMappingRow: View {
    let mapping: LauncherMapping
    @Binding var isEnabled: Bool
    /// Fade amount for monochrome/opacity transition (0 = full color, 1 = faded)
    var fadeAmount: CGFloat = 0
    let onTap: () -> Void
    var onDelete: (() -> Void)?
    /// Called with screen coordinates to trigger native poof animation
    var onPoofAt: ((NSPoint) -> Void)?
    /// Callback when hovering this row - passes key for keyboard highlighting
    var onHoverChange: ((String?) -> Void)?

    @Environment(\.services) private var services
    @State private var icon: NSImage?
    @State private var isHovering = false
    @State private var deleteButtonFrame: CGRect = .zero
    @AppStorage(KeymapPreferences.keymapIdKey) private var selectedKeymapId: String = LogicalKeymap.defaultId
    @AppStorage(KeymapPreferences.includePunctuationStoreKey) private var includePunctuationStore: String = "{}"

    private var keyTranslator: LauncherKeymapTranslator {
        LauncherKeymapTranslator(keymapId: selectedKeymapId, includePunctuationStore: includePunctuationStore)
    }

    private var displayKey: String {
        keyTranslator.displayLabel(for: mapping.key)
    }

    private var displayName: String {
        mapping.userDescription ?? mapping.action.displayName
    }

    private var rowOpacity: Double {
        let baseOpacity = isEnabled ? 1.0 : 0.5
        return baseOpacity * Double(1 - fadeAmount * 0.5)
    }

    var body: some View {
        Button(action: { onTap() }) {
            HStack(spacing: 8) {
                // Icon or Checkbox (checkbox replaces icon on hover)
                Group {
                    if isHovering {
                        // Checkbox toggle on hover (replaces icon)
                        Toggle("", isOn: $isEnabled)
                            .toggleStyle(.checkbox)
                            .labelsHidden()
                            .controlSize(.small)
                            .frame(width: 16, height: 16)
                            .accessibilityIdentifier("overlay-launcher-toggle-\(mapping.key)")
                            .accessibilityLabel("Toggle \(displayName)")
                    } else if let icon {
                        Image(nsImage: icon)
                            .resizable()
                            .aspectRatio(contentMode: .fit)
                            .frame(width: 16, height: 16)
                            .clipShape(RoundedRectangle(cornerRadius: 3))
                            .saturation(Double(1 - fadeAmount)) // Monochromatic when faded
                    } else {
                        Image(systemName: fallbackIcon)
                            .font(.footnote)
                            .frame(width: 16, height: 16)
                            .foregroundStyle(.secondary)
                    }
                }

                // Name - strikethrough when disabled
                Text(displayName)
                    .font(.caption)
                    .foregroundStyle(isEnabled ? .primary : .secondary)
                    .strikethrough(!isEnabled, color: .secondary)
                    .lineLimit(1)
                    .truncationMode(.tail)

                Spacer(minLength: 0)

                // Delete button on hover (before key badge)
                if isHovering, onPoofAt != nil || onDelete != nil {
                    Button {
                        // Get screen coordinates for the poof animation
                        if let onPoofAt, let window = NSApp.keyWindow {
                            // Convert the row's center to screen coordinates
                            let windowFrame = window.frame
                            let rowCenter = CGPoint(
                                x: deleteButtonFrame.midX,
                                y: deleteButtonFrame.midY
                            )
                            // Convert from SwiftUI coordinates (origin top-left) to screen (origin bottom-left)
                            let screenPoint = NSPoint(
                                x: windowFrame.origin.x + rowCenter.x,
                                y: windowFrame.origin.y + windowFrame.height - rowCenter.y
                            )
                            onPoofAt(screenPoint)
                        } else {
                            onDelete?()
                        }
                    } label: {
                        Image(systemName: "trash")
                            .font(.caption2)
                            .foregroundStyle(.secondary)
                    }
                    .buttonStyle(.plain)
                    .accessibilityIdentifier("overlay-launcher-delete-\(mapping.key)")
                    .help("Delete")
                    .accessibilityLabel("Delete \(displayName)")
                    .background(
                        GeometryReader { geo in
                            Color.clear.preference(
                                key: FramePreferenceKey.self,
                                value: geo.frame(in: .global)
                            )
                        }
                    )
                    .onPreferenceChange(FramePreferenceKey.self) { frame in
                        deleteButtonFrame = frame
                    }
                }

                // Key badge (far right) - dimmed when disabled
                Text(displayKey.uppercased())
                    .font(.caption2.monospaced().weight(.bold))
                    .foregroundStyle(.white)
                    .frame(width: 18, height: 18)
                    .background(
                        RoundedRectangle(cornerRadius: 3)
                            .fill(isEnabled ? Color.accentColor : Color.gray)
                    )
            }
            .opacity(rowOpacity)
            .padding(.horizontal, 6)
            .padding(.vertical, 4)
            .frame(maxWidth: .infinity, alignment: .leading)
            .contentShape(Rectangle())
            .background(
                RoundedRectangle(cornerRadius: 4)
                    .fill(isHovering ? Color.white.opacity(0.06) : Color.clear)
            )
        }
        .buttonStyle(.plain)
        .accessibilityIdentifier("overlay-launcher-row-\(mapping.key)")
        .accessibilityLabel("\(displayName), key \(displayKey)")
        .accessibilityValue(isEnabled ? "enabled" : "disabled")
        .accessibilityHint("Use the Edit, Enable, Disable, or Delete accessibility actions to manage this launcher.")
        .accessibilityAction(named: "Edit") { onTap() }
        .accessibilityAction(named: isEnabled ? "Disable" : "Enable") {
            isEnabled.toggle()
        }
        .accessibilityAction(named: "Delete") { onDelete?() }
        .onHover { hovering in
            isHovering = hovering
            // Notify parent for keyboard highlighting
            onHoverChange?(hovering ? mapping.key : nil)
        }
        .task {
            await loadIcon()
        }
    }

    private var fallbackIcon: String {
        switch mapping.action {
        case .launchApp: "app.fill"
        case .openURL: "globe"
        case .openFolder: "folder.fill"
        case .runScript: "terminal.fill"
        default: "questionmark.circle"
        }
    }

    private func loadIcon() async {
        if let customPath = mapping.customIconPath {
            let expanded = (customPath as NSString).expandingTildeInPath
            if let nsImage = NSImage(contentsOfFile: expanded) {
                nsImage.size = NSSize(width: 16, height: 16)
                icon = nsImage
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
}

// MARK: - Preference Keys

/// Preference key for capturing frame in global coordinate space
private struct FramePreferenceKey: PreferenceKey {
    static let defaultValue: CGRect = .zero
    static func reduce(value: inout CGRect, nextValue: () -> CGRect) {
        value = nextValue()
    }
}

// MARK: - Preview

#Preview("Overlay Launchers Section") {
    OverlayLaunchersSection(isDark: true)
        .frame(width: 220)
        .padding()
        .background(Color(white: 0.15))
}
