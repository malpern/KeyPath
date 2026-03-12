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

    @State private var store: LauncherStore
    @State private var showAddSheet = false
    @State private var editingMapping: QuickLaunchMapping?

    init(
        isDark: Bool,
        fadeAmount: CGFloat = 0,
        onMappingHover: ((String?) -> Void)? = nil,
        onCustomize: (() -> Void)? = nil
    ) {
        self.isDark = isDark
        self.fadeAmount = fadeAmount
        self.onMappingHover = onMappingHover
        self.onCustomize = onCustomize
        _store = State(initialValue: LauncherStore())
    }

    /// Testing init that accepts pre-populated mappings instead of loading from RuleCollectionStore.
    init(isDark: Bool, fadeAmount: CGFloat = 0, testMappings: [QuickLaunchMapping]) {
        self.isDark = isDark
        self.fadeAmount = fadeAmount
        onMappingHover = nil
        onCustomize = nil
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

            // Bottom controls: Add Shortcut (left) and Settings (right)
            HStack(spacing: 8) {
                // Add button
                Button {
                    showAddSheet = true
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
        .sheet(isPresented: $showAddSheet) {
            AddLauncherSheet(
                existingKeys: Set(store.mappings.map { LauncherGridConfig.normalizeKey($0.key) }),
                onSave: { mapping in
                    withAnimation(.easeOut(duration: 0.25)) {
                        store.addMapping(mapping)
                    }
                    showAddSheet = false
                }
            )
        }
        .sheet(item: $editingMapping) { mapping in
            EditLauncherSheet(
                mapping: mapping,
                existingKeys: Set(store.mappings.filter { $0.id != mapping.id }.map { LauncherGridConfig.normalizeKey($0.key) }),
                onSave: { updated in
                    store.updateMapping(updated)
                    editingMapping = nil
                },
                onDelete: {
                    store.deleteMapping(mapping.id)
                    editingMapping = nil
                }
            )
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
    let mapping: QuickLaunchMapping
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
                    } else if let icon {
                        Image(nsImage: icon)
                            .resizable()
                            .aspectRatio(contentMode: .fit)
                            .frame(width: 16, height: 16)
                            .clipShape(RoundedRectangle(cornerRadius: 3))
                            .saturation(Double(1 - fadeAmount)) // Monochromatic when faded
                    } else {
                        Image(systemName: mapping.isApp ? "app.fill" : "globe")
                            .font(.footnote)
                            .frame(width: 16, height: 16)
                            .foregroundStyle(.secondary)
                    }
                }

                // Name - strikethrough when disabled
                Text(mapping.displayName)
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
        .onHover { hovering in
            isHovering = hovering
            // Notify parent for keyboard highlighting
            onHoverChange?(hovering ? mapping.key : nil)
        }
        .task {
            await loadIcon()
        }
    }

    private func loadIcon() async {
        if mapping.isApp {
            icon = LauncherStore.appIcon(name: mapping.targetName, bundleId: mapping.bundleId)
        } else {
            icon = await services.faviconFetcher.fetchFavicon(for: mapping.targetName)
        }
    }
}

// MARK: - Add Sheet

private struct AddLauncherSheet: View {
    let existingKeys: Set<String>
    let onSave: (QuickLaunchMapping) -> Void

    @Environment(\.dismiss) private var dismiss
    @State private var key = ""
    @State private var targetType: QuickLaunchMapping.TargetType = .app
    @State private var targetName = ""
    @State private var bundleId = ""
    @AppStorage(KeymapPreferences.keymapIdKey) private var selectedKeymapId: String = LogicalKeymap.defaultId
    @AppStorage(KeymapPreferences.includePunctuationStoreKey) private var includePunctuationStore: String = "{}"

    private var keyTranslator: LauncherKeymapTranslator {
        LauncherKeymapTranslator(keymapId: selectedKeymapId, includePunctuationStore: includePunctuationStore)
    }

    var body: some View {
        VStack(spacing: 16) {
            Text("Add Shortcut")
                .font(.headline)

            Form {
                TextField("Key", text: Binding(
                    get: { displayKey },
                    set: { updateKey(from: $0) }
                ))
                .textFieldStyle(.roundedBorder)
                .frame(width: 50)
                .accessibilityIdentifier("overlay-launcher-add-key")

                Picker("Type", selection: $targetType) {
                    Text("App").tag(QuickLaunchMapping.TargetType.app)
                    Text("Website").tag(QuickLaunchMapping.TargetType.website)
                }
                .pickerStyle(.segmented)
                .accessibilityIdentifier("overlay-launcher-add-type-picker")

                if targetType == .app {
                    HStack {
                        TextField("App Name", text: $targetName)
                            .textFieldStyle(.roundedBorder)
                            .accessibilityIdentifier("overlay-launcher-add-app-name")
                        Button("Browse...") {
                            browseForApp()
                        }
                        .accessibilityIdentifier("overlay-launcher-add-app-browse")
                    }
                    TextField("Bundle ID (optional)", text: $bundleId)
                        .textFieldStyle(.roundedBorder)
                        .font(.caption.monospaced())
                        .accessibilityIdentifier("overlay-launcher-add-bundle-id")
                } else {
                    TextField("URL (e.g. github.com)", text: $targetName)
                        .textFieldStyle(.roundedBorder)
                        .accessibilityIdentifier("overlay-launcher-add-url")
                }

                if let error = validationError {
                    Text(error)
                        .font(.caption)
                        .foregroundStyle(.red)
                }
            }

            HStack {
                Button("Cancel") { dismiss() }
                    .keyboardShortcut(.cancelAction)
                    .accessibilityIdentifier("overlay-launcher-add-cancel")
                Spacer()
                Button("Add") { save() }
                    .keyboardShortcut(.defaultAction)
                    .disabled(validationError != nil)
                    .accessibilityIdentifier("overlay-launcher-add-save")
            }
        }
        .padding()
        .frame(width: 280)
    }

    private var validationError: String? {
        if normalizedKey.isEmpty { return "Enter a key" }
        if !LauncherGridConfig.isValidKey(normalizedKey) { return "Use a single letter or number" }
        if existingKeys.contains(normalizedKey) { return "Key '\(displayKey.uppercased())' already used" }
        if targetName.isEmpty { return targetType == .app ? "Enter app name" : "Enter URL" }
        return nil
    }

    private func save() {
        let mapping = QuickLaunchMapping(
            key: normalizedKey,
            targetType: targetType,
            targetName: targetName,
            bundleId: targetType == .app ? (bundleId.isEmpty ? nil : bundleId) : nil
        )
        onSave(mapping)
    }

    private func browseForApp() {
        let panel = NSOpenPanel()
        panel.canChooseFiles = true
        panel.canChooseDirectories = false
        panel.allowsMultipleSelection = false
        panel.message = "Select an app to launch"
        panel.prompt = "Select"
        panel.allowedContentTypes = [.application]

        if panel.runModal() == .OK, let url = panel.url {
            targetName = url.deletingPathExtension().lastPathComponent
            bundleId = Bundle(url: url)?.bundleIdentifier ?? ""
        }
    }

    private var normalizedKey: String {
        LauncherGridConfig.normalizeKey(key)
    }

    private var displayKey: String {
        keyTranslator.displayLabel(for: normalizedKey)
    }

    private func updateKey(from displayValue: String) {
        let trimmed = displayValue.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        let first = String(trimmed.prefix(1))
        guard !first.isEmpty else {
            key = ""
            return
        }
        if let canonical = keyTranslator.canonicalKey(for: first) {
            key = canonical
        } else if LauncherGridConfig.isValidKey(first) {
            key = first
        } else {
            key = ""
        }
    }
}

// MARK: - Edit Sheet

private struct EditLauncherSheet: View {
    let mapping: QuickLaunchMapping
    let existingKeys: Set<String>
    let onSave: (QuickLaunchMapping) -> Void
    let onDelete: () -> Void

    @Environment(\.dismiss) private var dismiss
    @State private var key: String
    @State private var targetType: QuickLaunchMapping.TargetType
    @State private var targetName: String
    @State private var bundleId: String
    @AppStorage(KeymapPreferences.keymapIdKey) private var selectedKeymapId: String = LogicalKeymap.defaultId
    @AppStorage(KeymapPreferences.includePunctuationStoreKey) private var includePunctuationStore: String = "{}"

    private var keyTranslator: LauncherKeymapTranslator {
        LauncherKeymapTranslator(keymapId: selectedKeymapId, includePunctuationStore: includePunctuationStore)
    }

    init(
        mapping: QuickLaunchMapping,
        existingKeys: Set<String>,
        onSave: @escaping (QuickLaunchMapping) -> Void,
        onDelete: @escaping () -> Void
    ) {
        self.mapping = mapping
        self.existingKeys = existingKeys
        self.onSave = onSave
        self.onDelete = onDelete
        _key = State(initialValue: mapping.key)
        _targetType = State(initialValue: mapping.targetType)
        _targetName = State(initialValue: mapping.targetName)
        _bundleId = State(initialValue: mapping.bundleId ?? "")
    }

    var body: some View {
        VStack(spacing: 16) {
            Text("Edit Shortcut")
                .font(.headline)

            Form {
                TextField("Key", text: Binding(
                    get: { displayKey },
                    set: { updateKey(from: $0) }
                ))
                .textFieldStyle(.roundedBorder)
                .frame(width: 50)
                .accessibilityIdentifier("overlay-launcher-edit-key")

                Picker("Type", selection: $targetType) {
                    Text("App").tag(QuickLaunchMapping.TargetType.app)
                    Text("Website").tag(QuickLaunchMapping.TargetType.website)
                }
                .pickerStyle(.segmented)
                .accessibilityIdentifier("overlay-launcher-edit-type-picker")

                if targetType == .app {
                    HStack {
                        TextField("App Name", text: $targetName)
                            .textFieldStyle(.roundedBorder)
                            .accessibilityIdentifier("overlay-launcher-edit-app-name")
                        Button("Browse...") {
                            browseForApp()
                        }
                        .accessibilityIdentifier("overlay-launcher-edit-app-browse")
                    }
                    TextField("Bundle ID (optional)", text: $bundleId)
                        .textFieldStyle(.roundedBorder)
                        .font(.caption.monospaced())
                        .accessibilityIdentifier("overlay-launcher-edit-bundle-id")
                } else {
                    TextField("URL (e.g. github.com)", text: $targetName)
                        .textFieldStyle(.roundedBorder)
                        .accessibilityIdentifier("overlay-launcher-edit-url")
                }

                if let error = validationError {
                    Text(error)
                        .font(.caption)
                        .foregroundStyle(.red)
                }
            }

            HStack {
                Button("Delete", role: .destructive) { onDelete() }
                    .accessibilityIdentifier("overlay-launcher-edit-delete")
                Spacer()
                Button("Cancel") { dismiss() }
                    .keyboardShortcut(.cancelAction)
                    .accessibilityIdentifier("overlay-launcher-edit-cancel")
                Button("Save") { save() }
                    .keyboardShortcut(.defaultAction)
                    .disabled(validationError != nil)
                    .accessibilityIdentifier("overlay-launcher-edit-save")
            }
        }
        .padding()
        .frame(width: 280)
    }

    private var validationError: String? {
        if normalizedKey.isEmpty { return "Enter a key" }
        if !LauncherGridConfig.isValidKey(normalizedKey) { return "Use a single letter or number" }
        if normalizedKey != LauncherGridConfig.normalizeKey(mapping.key), existingKeys.contains(normalizedKey) {
            return "Key '\(displayKey.uppercased())' already used"
        }
        if targetName.isEmpty {
            return targetType == .app ? "Enter app name" : "Enter URL"
        }
        return nil
    }

    private func save() {
        var updated = mapping
        updated.key = normalizedKey
        updated.targetType = targetType
        updated.targetName = targetName
        updated.bundleId = targetType == .app ? (bundleId.isEmpty ? nil : bundleId) : nil
        onSave(updated)
    }

    private func browseForApp() {
        let panel = NSOpenPanel()
        panel.canChooseFiles = true
        panel.canChooseDirectories = false
        panel.allowsMultipleSelection = false
        panel.message = "Select an app to launch"
        panel.prompt = "Select"
        panel.allowedContentTypes = [.application]

        if panel.runModal() == .OK, let url = panel.url {
            targetName = url.deletingPathExtension().lastPathComponent
            bundleId = Bundle(url: url)?.bundleIdentifier ?? ""
        }
    }

    private var normalizedKey: String {
        LauncherGridConfig.normalizeKey(key)
    }

    private var displayKey: String {
        keyTranslator.displayLabel(for: normalizedKey)
    }

    private func updateKey(from displayValue: String) {
        let trimmed = displayValue.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        let first = String(trimmed.prefix(1))
        guard !first.isEmpty else {
            key = ""
            return
        }
        if let canonical = keyTranslator.canonicalKey(for: first) {
            key = canonical
        } else if LauncherGridConfig.isValidKey(first) {
            key = first
        } else {
            key = ""
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
