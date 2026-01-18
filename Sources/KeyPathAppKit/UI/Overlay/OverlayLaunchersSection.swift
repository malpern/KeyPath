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

    @StateObject private var store = LauncherStore()
    @State private var showAddSheet = false
    @State private var editingMapping: QuickLaunchMapping?

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
                            .font(.system(size: 14))
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
                existingKeys: Set(store.mappings.map(\.key)),
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
                existingKeys: Set(store.mappings.filter { $0.id != mapping.id }.map(\.key)),
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
                .font(.system(size: 24))
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

// MARK: - Data Model

/// A quick launch mapping (simplified, self-contained version)
struct QuickLaunchMapping: Identifiable, Codable, Equatable {
    var id: UUID
    var key: String
    var targetType: TargetType
    var targetName: String // App name or URL
    var isEnabled: Bool

    enum TargetType: String, Codable {
        case app
        case website
    }

    var isApp: Bool { targetType == .app }

    var displayName: String {
        if targetType == .website {
            return targetName
                .replacingOccurrences(of: "https://", with: "")
                .replacingOccurrences(of: "http://", with: "")
                .components(separatedBy: "/").first ?? targetName
        }
        return targetName
    }

    init(id: UUID = UUID(), key: String, targetType: TargetType, targetName: String, isEnabled: Bool = true) {
        self.id = id
        self.key = key
        self.targetType = targetType
        self.targetName = targetName
        self.isEnabled = isEnabled
    }
}

// MARK: - Store

@MainActor
final class LauncherStore: ObservableObject {
    @Published var mappings: [QuickLaunchMapping] = []

    init() {
        loadFromRuleCollections()
    }

    /// Load mappings from the shared RuleCollectionStore (same source as keyboard view)
    func loadFromRuleCollections() {
        Task { @MainActor in
            let collections = await RuleCollectionStore.shared.loadCollections()

            // Find the launcher collection and extract its mappings
            guard let launcherCollection = collections.first(where: { $0.id == RuleCollectionIdentifier.launcher }),
                  let config = launcherCollection.configuration.launcherGridConfig
            else {
                AppLogger.shared.debug("🚀 [LauncherStore] No launcher config found, using defaults")
                mappings = Self.defaultMappings
                return
            }

            // Convert LauncherMapping to QuickLaunchMapping, filtering for installed apps
            let convertedMappings: [QuickLaunchMapping] = config.mappings.compactMap { mapping in
                guard mapping.isEnabled else { return nil }

                switch mapping.target {
                case let .app(name, bundleId):
                    // Check if app is installed
                    guard Self.isAppInstalled(name: name, bundleId: bundleId) else { return nil }
                    return QuickLaunchMapping(
                        id: mapping.id,
                        key: mapping.key,
                        targetType: .app,
                        targetName: name,
                        isEnabled: mapping.isEnabled
                    )
                case let .url(urlString):
                    return QuickLaunchMapping(
                        id: mapping.id,
                        key: mapping.key,
                        targetType: .website,
                        targetName: urlString,
                        isEnabled: mapping.isEnabled
                    )
                case .folder, .script:
                    // Skip folders and scripts for now
                    return nil
                }
            }

            mappings = convertedMappings
            AppLogger.shared.info("🚀 [LauncherStore] Loaded \(mappings.count) launcher mappings")
        }
    }

    /// Mappings sorted by proximity to home row (ASDF JKL; are closest)
    var sortedMappings: [QuickLaunchMapping] {
        mappings.sorted { Self.homeRowProximity(for: $0.key) < Self.homeRowProximity(for: $1.key) }
    }

    /// Home row proximity score (lower = closer to home row)
    /// Home row keys (ASDFGHJKL;) = 0
    /// Adjacent rows = 1, 2, etc.
    /// Number row = 3
    private static func homeRowProximity(for key: String) -> Int {
        let k = key.lowercased()

        // Home row - priority 0
        let homeRow: Set<String> = ["a", "s", "d", "f", "g", "h", "j", "k", "l", ";"]
        if homeRow.contains(k) { return 0 }

        // Top row (QWERTY) - priority 1
        let topRow: Set<String> = ["q", "w", "e", "r", "t", "y", "u", "i", "o", "p", "[", "]"]
        if topRow.contains(k) { return 1 }

        // Bottom row (ZXCV) - priority 2
        let bottomRow: Set<String> = ["z", "x", "c", "v", "b", "n", "m", ",", ".", "/"]
        if bottomRow.contains(k) { return 2 }

        // Number row - priority 3
        let numberRow: Set<String> = ["1", "2", "3", "4", "5", "6", "7", "8", "9", "0", "-", "="]
        if numberRow.contains(k) { return 3 }

        // Function keys and others - priority 4
        return 4
    }

    /// Check if an app is installed on the system
    private static func isAppInstalled(name: String, bundleId: String?) -> Bool {
        // Try bundle ID first (most reliable)
        if let bundleId, NSWorkspace.shared.urlForApplication(withBundleIdentifier: bundleId) != nil {
            return true
        }

        // Fall back to app name in common locations
        let paths = [
            "/Applications/\(name).app",
            "/System/Applications/\(name).app",
            "/System/Applications/Utilities/\(name).app",
            "/Applications/Utilities/\(name).app"
        ]

        for path in paths {
            if FileManager.default.fileExists(atPath: path) {
                return true
            }
        }

        return false
    }

    func addMapping(_ mapping: QuickLaunchMapping) {
        mappings.append(mapping)
    }

    func updateMapping(_ mapping: QuickLaunchMapping) {
        if let index = mappings.firstIndex(where: { $0.id == mapping.id }) {
            mappings[index] = mapping
        }
    }

    func deleteMapping(_ id: UUID) {
        mappings.removeAll { $0.id == id }
    }

    private static var defaultMappings: [QuickLaunchMapping] {
        [
            QuickLaunchMapping(key: "s", targetType: .app, targetName: "Safari"),
            QuickLaunchMapping(key: "t", targetType: .app, targetName: "Terminal"),
            QuickLaunchMapping(key: "f", targetType: .app, targetName: "Finder"),
            QuickLaunchMapping(key: "g", targetType: .website, targetName: "github.com")
        ]
    }

    /// Get icon for an app - checks multiple locations
    static func appIcon(for appName: String) -> NSImage? {
        let paths = [
            "/Applications/\(appName).app",
            "/System/Applications/\(appName).app",
            "/System/Applications/Utilities/\(appName).app",
            "/Applications/Utilities/\(appName).app"
        ]

        for path in paths {
            if FileManager.default.fileExists(atPath: path) {
                return NSWorkspace.shared.icon(forFile: path)
            }
        }

        // Try to find by bundle ID using Launch Services
        if let url = NSWorkspace.shared.urlForApplication(withBundleIdentifier: "com.apple.\(appName.lowercased())") {
            return NSWorkspace.shared.icon(forFile: url.path)
        }

        return nil
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

    @State private var icon: NSImage?
    @State private var isHovering = false
    @State private var deleteButtonFrame: CGRect = .zero

    private var rowOpacity: Double {
        let baseOpacity = isEnabled ? 1.0 : 0.5
        return baseOpacity * Double(1 - fadeAmount * 0.5)
    }

    var body: some View {
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
                        .font(.system(size: 12))
                        .frame(width: 16, height: 16)
                        .foregroundStyle(.secondary)
                }
            }

            // Name - strikethrough when disabled
            Text(mapping.displayName)
                .font(.system(size: 11))
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
                        .font(.system(size: 10))
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
            Text(mapping.key.uppercased())
                .font(.system(size: 10, weight: .bold, design: .monospaced))
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
        .onHover { hovering in
            isHovering = hovering
            // Notify parent for keyboard highlighting
            onHoverChange?(hovering ? mapping.key : nil)
        }
        .onTapGesture { onTap() }
        .task {
            await loadIcon()
        }
    }

    private func loadIcon() async {
        if mapping.isApp {
            icon = LauncherStore.appIcon(for: mapping.targetName)
        } else {
            icon = await FaviconLoader.shared.favicon(for: mapping.targetName)
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

    var body: some View {
        VStack(spacing: 16) {
            Text("Add Shortcut")
                .font(.headline)

            Form {
                TextField("Key", text: $key)
                    .textFieldStyle(.roundedBorder)
                    .frame(width: 50)
                    .onChange(of: key) { _, new in
                        key = String(new.prefix(1)).lowercased()
                    }

                Picker("Type", selection: $targetType) {
                    Text("App").tag(QuickLaunchMapping.TargetType.app)
                    Text("Website").tag(QuickLaunchMapping.TargetType.website)
                }
                .pickerStyle(.segmented)
                .accessibilityIdentifier("overlay-launcher-add-type-picker")

                if targetType == .app {
                    TextField("App Name", text: $targetName)
                        .textFieldStyle(.roundedBorder)
                } else {
                    TextField("URL (e.g. github.com)", text: $targetName)
                        .textFieldStyle(.roundedBorder)
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
        if key.isEmpty { return "Enter a key" }
        if existingKeys.contains(key) { return "Key '\(key.uppercased())' already used" }
        if targetName.isEmpty { return targetType == .app ? "Enter app name" : "Enter URL" }
        return nil
    }

    private func save() {
        let mapping = QuickLaunchMapping(
            key: key,
            targetType: targetType,
            targetName: targetName
        )
        onSave(mapping)
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
    }

    var body: some View {
        VStack(spacing: 16) {
            Text("Edit Shortcut")
                .font(.headline)

            Form {
                TextField("Key", text: $key)
                    .textFieldStyle(.roundedBorder)
                    .frame(width: 50)
                    .onChange(of: key) { _, new in
                        key = String(new.prefix(1)).lowercased()
                    }

                Picker("Type", selection: $targetType) {
                    Text("App").tag(QuickLaunchMapping.TargetType.app)
                    Text("Website").tag(QuickLaunchMapping.TargetType.website)
                }
                .pickerStyle(.segmented)
                .accessibilityIdentifier("overlay-launcher-edit-type-picker")

                if targetType == .app {
                    TextField("App Name", text: $targetName)
                        .textFieldStyle(.roundedBorder)
                } else {
                    TextField("URL (e.g. github.com)", text: $targetName)
                        .textFieldStyle(.roundedBorder)
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
        if key.isEmpty { return "Enter a key" }
        if key != mapping.key, existingKeys.contains(key) {
            return "Key '\(key.uppercased())' already used"
        }
        if targetName.isEmpty {
            return targetType == .app ? "Enter app name" : "Enter URL"
        }
        return nil
    }

    private func save() {
        var updated = mapping
        updated.key = key
        updated.targetType = targetType
        updated.targetName = targetName
        onSave(updated)
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
