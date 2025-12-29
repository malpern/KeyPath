import AppKit
import SwiftUI

/// Launchers section for the overlay drawer.
/// Configuration list for quick launch shortcuts - icons show on the virtual keyboard.
struct OverlayLaunchersSection: View {
    let isDark: Bool

    @StateObject private var store = LauncherStore()
    @State private var showAddSheet = false
    @State private var editingMapping: QuickLaunchMapping?

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            // Header
            Text("Launcher")
                .font(.subheadline.weight(.semibold))
                .foregroundStyle(.primary)
                .padding(.bottom, 12)

            // Activation hint
            activationHint
                .padding(.bottom, 12)

            // Scrollable mappings list
            if store.mappings.isEmpty {
                emptyState
                Spacer(minLength: 0)
            } else {
                ScrollView {
                    mappingsList
                }
            }

            // Add button pinned to bottom
            addButton
                .padding(.top, 12)
        }
        .sheet(isPresented: $showAddSheet) {
            AddLauncherSheet(
                existingKeys: Set(store.mappings.map(\.key)),
                onSave: { mapping in
                    store.addMapping(mapping)
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

    private var activationHint: some View {
        HStack(spacing: 6) {
            // Hyper badge
            HStack(spacing: 2) {
                Image(systemName: "sparkle")
                    .font(.system(size: 8, weight: .bold))
                Text("Hyper")
                    .font(.system(size: 10, weight: .medium))
            }
            .foregroundStyle(.secondary)
            .padding(.horizontal, 6)
            .padding(.vertical, 3)
            .background(
                RoundedRectangle(cornerRadius: 4)
                    .fill(Color.white.opacity(0.1))
            )

            Text("or")
                .font(.system(size: 10))
                .foregroundStyle(.tertiary)

            // Leader + L badge
            HStack(spacing: 2) {
                Text("Leader")
                    .font(.system(size: 10, weight: .medium))
                Text("+")
                    .font(.system(size: 9))
                Text("L")
                    .font(.system(size: 10, weight: .bold, design: .monospaced))
            }
            .foregroundStyle(.secondary)
            .padding(.horizontal, 6)
            .padding(.vertical, 3)
            .background(
                RoundedRectangle(cornerRadius: 4)
                    .fill(Color.white.opacity(0.1))
            )

            Spacer()
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
            ForEach(store.mappings.sorted { $0.key < $1.key }) { mapping in
                LauncherMappingRow(
                    mapping: mapping,
                    isEnabled: Binding(
                        get: { mapping.isEnabled },
                        set: { newValue in
                            var updated = mapping
                            updated.isEnabled = newValue
                            store.updateMapping(updated)
                        }
                    ),
                    onTap: { editingMapping = mapping },
                    onDelete: { store.deleteMapping(mapping.id) }
                )
            }
        }
    }

    private var addButton: some View {
        Button {
            showAddSheet = true
        } label: {
            Label("Add Shortcut", systemImage: "plus")
                .font(.subheadline)
                .frame(maxWidth: .infinity)
        }
        .buttonStyle(.bordered)
        .controlSize(.small)
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
    private static let mappingsKey = "QuickLaunchMappings"

    @Published var mappings: [QuickLaunchMapping] {
        didSet { saveMappings() }
    }

    init() {
        mappings = Self.loadMappings()
    }

    private static func loadMappings() -> [QuickLaunchMapping] {
        guard let data = UserDefaults.standard.data(forKey: mappingsKey),
              let mappings = try? JSONDecoder().decode([QuickLaunchMapping].self, from: data)
        else {
            return defaultMappings
        }
        return mappings
    }

    private func saveMappings() {
        if let data = try? JSONEncoder().encode(mappings) {
            UserDefaults.standard.set(data, forKey: Self.mappingsKey)
        }
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
    let onTap: () -> Void
    var onDelete: (() -> Void)?

    @State private var icon: NSImage?
    @State private var isHovering = false

    private var rowOpacity: Double {
        isEnabled ? 1.0 : 0.35
    }

    var body: some View {
        HStack(spacing: 8) {
            // Icon
            Group {
                if let icon {
                    Image(nsImage: icon)
                        .resizable()
                        .aspectRatio(contentMode: .fit)
                        .frame(width: 16, height: 16)
                        .clipShape(RoundedRectangle(cornerRadius: 3))
                } else {
                    Image(systemName: mapping.isApp ? "app.fill" : "globe")
                        .font(.system(size: 12))
                        .frame(width: 16, height: 16)
                        .foregroundStyle(.secondary)
                }
            }

            // Key badge
            Text(mapping.key.uppercased())
                .font(.system(size: 10, weight: .bold, design: .monospaced))
                .foregroundStyle(.white)
                .frame(width: 18, height: 18)
                .background(
                    RoundedRectangle(cornerRadius: 3)
                        .fill(Color.accentColor)
                )

            // Name
            Text(mapping.displayName)
                .font(.system(size: 11))
                .foregroundStyle(.primary)
                .lineLimit(1)
                .truncationMode(.tail)

            Spacer(minLength: 0)

            // Hover actions
            if isHovering {
                // Delete button
                if let onDelete {
                    Button {
                        onDelete()
                    } label: {
                        Image(systemName: "trash")
                            .font(.system(size: 10))
                            .foregroundStyle(.secondary)
                    }
                    .buttonStyle(.plain)
                    .help("Delete")
                }

                // Checkbox toggle
                Toggle("", isOn: $isEnabled)
                    .toggleStyle(.checkbox)
                    .labelsHidden()
                    .controlSize(.small)
            }
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
        .onHover { isHovering = $0 }
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
                Spacer()
                Button("Add") { save() }
                    .keyboardShortcut(.defaultAction)
                    .disabled(validationError != nil)
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
                Spacer()
                Button("Cancel") { dismiss() }
                    .keyboardShortcut(.cancelAction)
                Button("Save") { save() }
                    .keyboardShortcut(.defaultAction)
                    .disabled(validationError != nil)
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

// MARK: - Preview

#Preview("Overlay Launchers Section") {
    OverlayLaunchersSection(isDark: true)
        .frame(width: 220)
        .padding()
        .background(Color(white: 0.15))
}
