import AppKit
import SwiftUI

/// Main view for the Quick Launcher collection configuration.
///
/// Displays a grid of app/website shortcuts that can be customized.
/// Supports activation mode switching (Hold Hyper vs Leader→L sequence).
struct LauncherCollectionView: View {
    @Binding var config: LauncherGridConfig
    let onConfigChanged: (LauncherGridConfig) -> Void

    @State private var showBrowserHistory = false
    @State private var editingMapping: LauncherMapping?
    @State private var showAddMapping = false

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            // Activation mode picker
            activationModeSection

            Divider()

            // Mappings grid
            mappingsSection

            // Action buttons
            actionButtonsSection
        }
        .sheet(isPresented: $showBrowserHistory) {
            BrowserHistorySuggestionsView { selectedSites in
                addSuggestedSites(selectedSites)
            }
        }
        .sheet(item: $editingMapping) { mapping in
            LauncherMappingEditor(
                mapping: mapping,
                existingKeys: Set(config.mappings.map(\.key)),
                onSave: { updated in
                    updateMapping(updated)
                    editingMapping = nil
                },
                onCancel: {
                    editingMapping = nil
                }
            )
        }
        .sheet(isPresented: $showAddMapping) {
            LauncherMappingEditor(
                mapping: nil,
                existingKeys: Set(config.mappings.map(\.key)),
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

    // MARK: - Activation Mode Section

    private var activationModeSection: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("Activation")
                .font(.headline)

            Picker("Activation Mode", selection: Binding(
                get: { config.activationMode },
                set: { newMode in
                    config.activationMode = newMode
                    onConfigChanged(config)
                }
            )) {
                Text("Hold Hyper").tag(LauncherActivationMode.holdHyper)
                Text("Leader → L").tag(LauncherActivationMode.leaderSequence)
            }
            .pickerStyle(.segmented)
            .accessibilityIdentifier("launcher-activation-mode-picker")

            Text(activationDescription)
                .font(.caption)
                .foregroundColor(.secondary)
        }
    }

    private var activationDescription: String {
        switch config.activationMode {
        case .holdHyper:
            "Hold the Hyper key (Caps Lock when held) and press a shortcut key."
        case .leaderSequence:
            "Press Leader, then L, then press a shortcut key."
        }
    }

    // MARK: - Mappings Section

    private var mappingsSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                Text("Shortcuts")
                    .font(.headline)
                Spacer()
                Text("\(config.mappings.filter(\.isEnabled).count) active")
                    .font(.caption)
                    .foregroundColor(.secondary)
            }

            // Apps section
            if !appMappings.isEmpty {
                VStack(alignment: .leading, spacing: 4) {
                    Text("Apps")
                        .font(.subheadline)
                        .foregroundColor(.secondary)

                    LazyVGrid(columns: [GridItem(.adaptive(minimum: 140))], spacing: 8) {
                        ForEach(appMappings) { mapping in
                            LauncherMappingRow(
                                mapping: mapping,
                                onToggle: { toggleMapping(mapping) },
                                onEdit: { editingMapping = mapping },
                                onDelete: { deleteMapping(mapping) }
                            )
                        }
                    }
                }
            }

            // Websites section
            if !websiteMappings.isEmpty {
                VStack(alignment: .leading, spacing: 4) {
                    Text("Websites")
                        .font(.subheadline)
                        .foregroundColor(.secondary)

                    LazyVGrid(columns: [GridItem(.adaptive(minimum: 140))], spacing: 8) {
                        ForEach(websiteMappings) { mapping in
                            LauncherMappingRow(
                                mapping: mapping,
                                onToggle: { toggleMapping(mapping) },
                                onEdit: { editingMapping = mapping },
                                onDelete: { deleteMapping(mapping) }
                            )
                        }
                    }
                }
            }
        }
    }

    private var appMappings: [LauncherMapping] {
        config.mappings.filter(\.target.isApp)
    }

    private var websiteMappings: [LauncherMapping] {
        config.mappings.filter { !$0.target.isApp }
    }

    // MARK: - Action Buttons

    private var actionButtonsSection: some View {
        HStack(spacing: 12) {
            Button(action: { showAddMapping = true }) {
                Label("Add Shortcut", systemImage: "plus")
            }
            .accessibilityIdentifier("launcher-add-button")

            Button(action: { showBrowserHistory = true }) {
                Label("Suggest from History", systemImage: "clock.arrow.circlepath")
            }
            .accessibilityIdentifier("launcher-suggest-button")

            Spacer()

            Menu {
                Button("Reset to Defaults") {
                    resetToDefaults()
                }
                Button("Clear All", role: .destructive) {
                    clearAll()
                }
            } label: {
                Image(systemName: "ellipsis.circle")
            }
            .menuStyle(.borderlessButton)
            .accessibilityIdentifier("launcher-menu-button")
        }
        .padding(.top, 8)
    }

    // MARK: - Actions

    private func toggleMapping(_ mapping: LauncherMapping) {
        guard let index = config.mappings.firstIndex(where: { $0.id == mapping.id }) else { return }
        config.mappings[index].isEnabled.toggle()
        onConfigChanged(config)
    }

    private func updateMapping(_ mapping: LauncherMapping) {
        guard let index = config.mappings.firstIndex(where: { $0.id == mapping.id }) else { return }
        config.mappings[index] = mapping
        onConfigChanged(config)
    }

    private func addMapping(_ mapping: LauncherMapping) {
        config.mappings.append(mapping)
        onConfigChanged(config)
    }

    private func deleteMapping(_ mapping: LauncherMapping) {
        config.mappings.removeAll { $0.id == mapping.id }
        onConfigChanged(config)
    }

    private func addSuggestedSites(_ sites: [BrowserHistoryScanner.VisitedSite]) {
        // Find available number keys
        let usedKeys = Set(config.mappings.map(\.key))
        let availableKeys = ["1", "2", "3", "4", "5", "6", "7", "8", "9", "0"].filter { !usedKeys.contains($0) }

        for (site, key) in zip(sites, availableKeys) {
            let mapping = LauncherMapping(
                key: key,
                target: .url(site.domain),
                isEnabled: true
            )
            config.mappings.append(mapping)
        }
        onConfigChanged(config)
    }

    private func resetToDefaults() {
        config = LauncherGridConfig.defaultConfig
        onConfigChanged(config)
    }

    private func clearAll() {
        config.mappings.removeAll()
        onConfigChanged(config)
    }
}

// MARK: - Mapping Row

private struct LauncherMappingRow: View {
    let mapping: LauncherMapping
    let onToggle: () -> Void
    let onEdit: () -> Void
    let onDelete: () -> Void

    @State private var icon: NSImage?

    var body: some View {
        HStack(spacing: 8) {
            // Icon
            Group {
                if let icon {
                    Image(nsImage: icon)
                        .resizable()
                        .aspectRatio(contentMode: .fit)
                        .frame(width: 20, height: 20)
                } else {
                    Image(systemName: mapping.target.isApp ? "app" : "globe")
                        .frame(width: 20, height: 20)
                        .foregroundColor(.secondary)
                }
            }

            // Key badge
            Text(mapping.key.uppercased())
                .font(.system(size: 11, weight: .semibold, design: .monospaced))
                .padding(.horizontal, 5)
                .padding(.vertical, 2)
                .background(
                    RoundedRectangle(cornerRadius: 4)
                        .fill(Color.accentColor.opacity(mapping.isEnabled ? 0.2 : 0.1))
                )
                .foregroundColor(mapping.isEnabled ? .accentColor : .secondary)

            // Target name
            Text(mapping.target.displayName)
                .font(.system(size: 12))
                .lineLimit(1)
                .foregroundColor(mapping.isEnabled ? .primary : .secondary)

            Spacer()

            // Toggle
            Toggle("", isOn: Binding(
                get: { mapping.isEnabled },
                set: { _ in onToggle() }
            ))
            .labelsHidden()
            .toggleStyle(.switch)
            .controlSize(.mini)
        }
        .padding(.horizontal, 8)
        .padding(.vertical, 6)
        .background(
            RoundedRectangle(cornerRadius: 6)
                .fill(Color(NSColor.controlBackgroundColor))
        )
        .contextMenu {
            Button("Edit") { onEdit() }
            Divider()
            Button("Delete", role: .destructive) { onDelete() }
        }
        .accessibilityIdentifier("launcher-mapping-row-\(mapping.key)")
        .accessibilityLabel("\(mapping.target.displayName), key \(mapping.key)")
        .task {
            await loadIcon()
        }
    }

    private func loadIcon() async {
        switch mapping.target {
        case .app:
            icon = AppIconResolver.icon(for: mapping.target)
        case let .url(urlString):
            icon = await FaviconLoader.shared.favicon(for: urlString)
        }
    }
}

// MARK: - Mapping Editor

private struct LauncherMappingEditor: View {
    let mapping: LauncherMapping?
    let existingKeys: Set<String>
    let onSave: (LauncherMapping) -> Void
    let onCancel: () -> Void

    @State private var key: String
    @State private var targetType: TargetType
    @State private var appName: String
    @State private var bundleId: String
    @State private var url: String
    @State private var isEnabled: Bool

    enum TargetType: String, CaseIterable {
        case app = "App"
        case website = "Website"
    }

    init(
        mapping: LauncherMapping?,
        existingKeys: Set<String>,
        onSave: @escaping (LauncherMapping) -> Void,
        onCancel: @escaping () -> Void
    ) {
        self.mapping = mapping
        self.existingKeys = existingKeys
        self.onSave = onSave
        self.onCancel = onCancel

        if let mapping {
            _key = State(initialValue: mapping.key)
            _isEnabled = State(initialValue: mapping.isEnabled)
            switch mapping.target {
            case let .app(name, bundleId):
                _targetType = State(initialValue: .app)
                _appName = State(initialValue: name)
                _bundleId = State(initialValue: bundleId ?? "")
                _url = State(initialValue: "")
            case let .url(urlString):
                _targetType = State(initialValue: .website)
                _appName = State(initialValue: "")
                _bundleId = State(initialValue: "")
                _url = State(initialValue: urlString)
            }
        } else {
            _key = State(initialValue: "")
            _targetType = State(initialValue: .app)
            _appName = State(initialValue: "")
            _bundleId = State(initialValue: "")
            _url = State(initialValue: "")
            _isEnabled = State(initialValue: true)
        }
    }

    var body: some View {
        VStack(spacing: 16) {
            Text(mapping == nil ? "Add Shortcut" : "Edit Shortcut")
                .font(.headline)

            Form {
                // Key selection
                TextField("Key", text: $key)
                    .textFieldStyle(.roundedBorder)
                    .frame(width: 60)
                    .accessibilityIdentifier("launcher-editor-key-field")
                    .onChange(of: key) { _, newValue in
                        // Limit to single character
                        if newValue.count > 1 {
                            key = String(newValue.prefix(1))
                        }
                    }

                // Target type
                Picker("Type", selection: $targetType) {
                    ForEach(TargetType.allCases, id: \.self) { type in
                        Text(type.rawValue).tag(type)
                    }
                }
                .pickerStyle(.segmented)
                .accessibilityIdentifier("launcher-editor-type-picker")

                if targetType == .app {
                    TextField("App Name", text: $appName)
                        .textFieldStyle(.roundedBorder)
                        .accessibilityIdentifier("launcher-editor-app-name-field")
                    TextField("Bundle ID (optional)", text: $bundleId)
                        .textFieldStyle(.roundedBorder)
                        .font(.system(size: 11, design: .monospaced))
                        .accessibilityIdentifier("launcher-editor-bundle-id-field")
                } else {
                    TextField("URL (e.g., github.com)", text: $url)
                        .textFieldStyle(.roundedBorder)
                        .accessibilityIdentifier("launcher-editor-url-field")
                }

                Toggle("Enabled", isOn: $isEnabled)
                    .accessibilityIdentifier("launcher-editor-enabled-toggle")

                // Validation feedback
                if let error = validationError {
                    Text(error)
                        .font(.caption)
                        .foregroundColor(.red)
                }
            }
            .padding(.horizontal)

            HStack {
                Button("Cancel") { onCancel() }
                    .keyboardShortcut(.cancelAction)
                    .accessibilityIdentifier("launcher-editor-cancel-button")

                Spacer()

                Button("Save") { save() }
                    .keyboardShortcut(.defaultAction)
                    .disabled(!isValid)
                    .accessibilityIdentifier("launcher-editor-save-button")
            }
            .padding(.horizontal)
        }
        .padding()
        .frame(width: 320)
    }

    private var isValid: Bool {
        validationError == nil
    }

    private var validationError: String? {
        if key.isEmpty {
            return "Key is required"
        }
        // Allow same key when editing
        if let mapping, mapping.key == key {
            // OK - same key
        } else if existingKeys.contains(key) {
            return "Key '\(key.uppercased())' is already in use"
        }

        switch targetType {
        case .app:
            if appName.isEmpty {
                return "App name is required"
            }
        case .website:
            if url.isEmpty {
                return "URL is required"
            }
        }

        return nil
    }

    private func save() {
        let target: LauncherTarget = switch targetType {
        case .app:
            .app(name: appName, bundleId: bundleId.isEmpty ? nil : bundleId)
        case .website:
            .url(url)
        }

        let result = LauncherMapping(
            id: mapping?.id ?? UUID(),
            key: key,
            target: target,
            isEnabled: isEnabled
        )
        onSave(result)
    }
}
