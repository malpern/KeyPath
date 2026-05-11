import AppKit
import SwiftUI
import UniformTypeIdentifiers

/// Main view for the Quick Launcher collection configuration.
///
/// Displays a keyboard visualization with app/website icons on mapped keys,
/// alongside a drawer with the list of mappings for editing.
/// Supports activation mode switching (Hold Hyper vs Leader→L sequence).
struct LauncherCollectionView: View {
    @Binding var config: LauncherGridConfig
    let onConfigChanged: (LauncherGridConfig) -> Void

    @State private var selectedKey: String?
    @State private var showBrowserHistory = false
    @State private var editingMapping: LauncherMapping?
    @State private var showAddMapping = false
    @State private var preselectedKey: String?

    /// Local state for immediate UI response
    @State private var localHyperTriggerMode: HyperTriggerMode = .hold

    private var existingDomains: Set<String> {
        Set(config.mappings.compactMap { mapping in
            if case let .url(domain) = mapping.target {
                return normalizeDomain(domain)
            }
            return nil
        })
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            // Activation mode picker
            activationModeSection
                .padding(.horizontal, 16)
                .padding(.vertical, 12)

            Divider()

            // Keyboard visualization (full width)
            VStack(spacing: 8) {
                LauncherKeyboardView(
                    config: $config,
                    selectedKey: selectedKey,
                    onKeyClicked: handleKeyClicked
                )
                .padding(.horizontal, 4)
                .padding(.vertical, 12)

                Text("Click any key to configure")
                    .font(.caption)
                    .foregroundColor(.secondary)
                    .padding(.bottom, 12)
            }
            .frame(maxWidth: .infinity)
            .background(Color(NSColor.windowBackgroundColor).opacity(0.5))

            Divider()

            // Mappings list (full width)
            LauncherDrawerView(
                config: $config,
                selectedKey: $selectedKey,
                onAddMapping: { showAddMapping = true },
                onEditMapping: { mapping in
                    editingMapping = mapping
                },
                onDeleteMapping: { id in
                    deleteMapping(id: id)
                }
            )
            .onChange(of: config) { _, newValue in
                onConfigChanged(newValue)
            }
        }
        .sheet(isPresented: $showBrowserHistory) {
            BrowserHistorySuggestionsView(existingDomains: existingDomains) { selectedSites in
                addSuggestedSites(selectedSites)
            }
        }
        .sheet(item: $editingMapping) { mapping in
            LauncherMappingEditor(
                mapping: mapping,
                existingKeys: Set(config.mappings.map { LauncherGridConfig.normalizeKey($0.key) }),
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
                mapping: preselectedKey.map { key in
                    LauncherMapping(key: key, target: .app(name: "", bundleId: nil))
                },
                existingKeys: Set(config.mappings.map { LauncherGridConfig.normalizeKey($0.key) }),
                onSave: { newMapping in
                    addMapping(newMapping)
                    showAddMapping = false
                    preselectedKey = nil
                },
                onCancel: {
                    showAddMapping = false
                    preselectedKey = nil
                }
            )
        }
        .onReceive(NotificationCenter.default.publisher(for: .launcherSelectKey)) { notification in
            guard let key = notification.userInfo?["key"] as? String else { return }
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.3) {
                handleKeyClicked(key)
            }
        }
    }

    // MARK: - Activation Mode Section

    private var activationModeSection: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                Text("Launcher Settings")
                    .font(.headline)

                Spacer()

                Button(action: { showBrowserHistory = true }) {
                    Label("Suggest from History", systemImage: "clock.arrow.circlepath")
                        .font(.caption)
                }
                .buttonStyle(.bordered)
                .controlSize(.small)
                .accessibilityIdentifier("launcher-suggest-button")
            }

            Picker("Activation Mode", selection: Binding(
                get: { config.activationMode },
                set: { newMode in
                    config.activationMode = newMode
                    onConfigChanged(config)
                }
            )) {
                Text(LauncherActivationMode.holdHyper.displayName).tag(LauncherActivationMode.holdHyper)
                Text(LauncherActivationMode.leaderSequence.displayName).tag(LauncherActivationMode.leaderSequence)
            }
            .pickerStyle(.segmented)
            .labelsHidden()
            .accessibilityIdentifier("launcher-activation-mode-picker")

            // Hyper trigger mode segmented picker (only shown when Hyper mode is selected)
            if config.activationMode == .holdHyper {
                Picker("Trigger Mode", selection: Binding(
                    get: { localHyperTriggerMode },
                    set: { newMode in
                        localHyperTriggerMode = newMode
                        var updated = config
                        updated.hyperTriggerMode = newMode
                        onConfigChanged(updated)
                    }
                )) {
                    Text(HyperTriggerMode.hold.displayName).tag(HyperTriggerMode.hold)
                    Text(HyperTriggerMode.tap.displayName).tag(HyperTriggerMode.tap)
                }
                .pickerStyle(.segmented)
                .labelsHidden()
                .accessibilityIdentifier("launcher-hyper-trigger-picker")
                .onAppear {
                    localHyperTriggerMode = config.hyperTriggerMode
                }
            }

            Text(activationDescription)
                .font(.caption)
                .foregroundColor(.secondary)
        }
    }

    private var activationDescription: String {
        switch config.activationMode {
        case .holdHyper:
            localHyperTriggerMode.description + " Then press a shortcut key."
        case .leaderSequence:
            "Press Leader, then L, then press a shortcut key."
        }
    }

    // MARK: - Actions

    private func handleKeyClicked(_ key: String) {
        // Check if key is already mapped
        if let existingMapping = config.mappings.first(where: { $0.key.lowercased() == key.lowercased() }) {
            // Key is mapped - select it and open edit dialog
            selectedKey = key
            editingMapping = existingMapping
        } else {
            // Key is unmapped - open add dialog with key pre-selected
            preselectedKey = key
            showAddMapping = true
        }
    }

    private func updateMapping(_ mapping: LauncherMapping) {
        guard let index = config.mappings.firstIndex(where: { $0.id == mapping.id }) else { return }
        config.mappings[index] = mapping
        onConfigChanged(config)
    }

    private func addMapping(_ mapping: LauncherMapping) {
        config.mappings.append(mapping)
        onConfigChanged(config)
        // Select the newly added key
        selectedKey = mapping.key
    }

    private func deleteMapping(id: UUID) {
        config.mappings.removeAll { $0.id == id }
        onConfigChanged(config)
        // Clear selection if deleted key was selected
        if let selected = selectedKey,
           config.mappings.first(where: { $0.key.lowercased() == selected.lowercased() }) == nil
        {
            selectedKey = nil
        }
    }

    private func addSuggestedSites(_ sites: [BrowserHistoryScanner.VisitedSite]) {
        let usedKeys = Set(config.mappings.map { LauncherGridConfig.normalizeKey($0.key) })
        let availableKeys = LauncherGridConfig.suggestionKeyOrder.filter { !usedKeys.contains($0) }
        let existing = existingDomains

        for (site, key) in zip(sites, availableKeys) {
            if existing.contains(normalizeDomain(site.domain)) {
                continue
            }
            let mapping = LauncherMapping(
                key: key,
                target: .url(site.domain),
                isEnabled: true
            )
            config.mappings.append(mapping)
        }
        onConfigChanged(config)
    }

    private func normalizeDomain(_ domain: String) -> String {
        let lower = domain.lowercased()
        if lower.hasPrefix("www.") {
            return String(lower.dropFirst(4))
        }
        return lower
    }
}

// MARK: - Mapping Editor

struct LauncherMappingEditor: View {
    let mapping: LauncherMapping?
    let existingKeys: Set<String>
    let onSave: (LauncherMapping) -> Void
    let onCancel: () -> Void

    @Environment(\.services) private var services
    @State private var key: String
    @State private var targetType: TargetType
    @State private var appName: String
    @State private var bundleId: String
    @State private var url: String
    @State private var folderPath: String
    @State private var folderName: String
    @State private var scriptPath: String
    @State private var scriptName: String
    @State private var isEnabled: Bool
    @State private var customIconPath: String
    @State private var userDescription: String
    @State private var isScriptExecutionEnabled: Bool = ScriptSecurityService.shared.isScriptExecutionEnabled
    @State private var showScriptEnableConfirmation = false
    @State private var icon: NSImage?
    @AppStorage(KeymapPreferences.keymapIdKey) private var selectedKeymapId: String = LogicalKeymap.defaultId
    @AppStorage(KeymapPreferences.includePunctuationStoreKey) private var includePunctuationStore: String = "{}"

    enum TargetType: String, CaseIterable {
        case app = "App"
        case website = "Website"
        case folder = "Folder"
        case script = "Script"

        var requiresScriptExecution: Bool {
            self == .script
        }

        var iconName: String {
            switch self {
            case .app: "app.fill"
            case .website: "globe"
            case .folder: "folder.fill"
            case .script: "terminal.fill"
            }
        }
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
            _customIconPath = State(initialValue: mapping.customIconPath ?? "")
            _userDescription = State(initialValue: mapping.userDescription ?? "")
            switch mapping.target {
            case let .app(name, bundleId):
                _targetType = State(initialValue: .app)
                _appName = State(initialValue: name)
                _bundleId = State(initialValue: bundleId ?? "")
                _url = State(initialValue: "")
                _folderPath = State(initialValue: "")
                _folderName = State(initialValue: "")
                _scriptPath = State(initialValue: "")
                _scriptName = State(initialValue: "")
            case let .url(urlString):
                _targetType = State(initialValue: .website)
                _appName = State(initialValue: "")
                _bundleId = State(initialValue: "")
                _url = State(initialValue: urlString)
                _folderPath = State(initialValue: "")
                _folderName = State(initialValue: "")
                _scriptPath = State(initialValue: "")
                _scriptName = State(initialValue: "")
            case let .folder(path, name):
                _targetType = State(initialValue: .folder)
                _appName = State(initialValue: "")
                _bundleId = State(initialValue: "")
                _url = State(initialValue: "")
                _folderPath = State(initialValue: path)
                _folderName = State(initialValue: name ?? "")
                _scriptPath = State(initialValue: "")
                _scriptName = State(initialValue: "")
            case let .script(path, name):
                _targetType = State(initialValue: .script)
                _appName = State(initialValue: "")
                _bundleId = State(initialValue: "")
                _url = State(initialValue: "")
                _folderPath = State(initialValue: "")
                _folderName = State(initialValue: "")
                _scriptPath = State(initialValue: path)
                _scriptName = State(initialValue: name ?? "")
            }
        } else {
            _key = State(initialValue: "")
            _targetType = State(initialValue: .app)
            _appName = State(initialValue: "")
            _bundleId = State(initialValue: "")
            _url = State(initialValue: "")
            _folderPath = State(initialValue: "")
            _folderName = State(initialValue: "")
            _scriptPath = State(initialValue: "")
            _scriptName = State(initialValue: "")
            _isEnabled = State(initialValue: true)
            _customIconPath = State(initialValue: "")
            _userDescription = State(initialValue: "")
        }
    }

    var body: some View {
        VStack(spacing: 0) {
            // Title + Enabled toggle
            HStack {
                Text(mapping == nil ? "Add Launcher" : "Edit Launcher")
                    .font(.headline)
                Spacer()
                Toggle(isOn: $isEnabled) {
                    Text(isEnabled ? "Enabled" : "Disabled")
                        .font(.caption)
                        .foregroundColor(.secondary)
                }
                .toggleStyle(.switch)
                .controlSize(.small)
                .accessibilityIdentifier("launcher-editor-enabled-toggle")
            }
            .padding(.horizontal, 24)
            .padding(.top, 20)
            .padding(.bottom, 14)

            Divider()

            // Content
            ScrollView {
                VStack(alignment: .leading, spacing: 16) {
                    previewCard

                    // Form fields — right-aligned labels, left-aligned controls
                    VStack(spacing: 10) {
                        formRow("Key") {
                            HStack(spacing: 8) {
                                TextField("", text: Binding(
                                    get: { displayKey },
                                    set: { updateKey(from: $0) }
                                ))
                                .textFieldStyle(.roundedBorder)
                                .frame(width: 48)
                                .accessibilityIdentifier("launcher-editor-key-field")

                                Text("Single letter or number")
                                    .font(.caption)
                                    .foregroundColor(.secondary)
                            }
                        }

                        formRow("Type") {
                            Picker("Type", selection: $targetType) {
                                ForEach(TargetType.allCases, id: \.self) { type in
                                    Text(type.rawValue).tag(type)
                                }
                            }
                            .pickerStyle(.segmented)
                            .labelsHidden()
                            .accessibilityIdentifier("launcher-editor-type-picker")
                            .onChange(of: targetType) { oldValue, newValue in
                                if newValue.requiresScriptExecution, !isScriptExecutionEnabled {
                                    targetType = oldValue
                                }
                            }
                        }

                        if !isScriptExecutionEnabled, targetType.requiresScriptExecution {
                            HStack(spacing: 8) {
                                Image(systemName: "lock.shield.fill")
                                    .foregroundColor(.orange)
                                VStack(alignment: .leading, spacing: 4) {
                                    Text("Script execution is disabled")
                                        .font(.caption)
                                        .fontWeight(.medium)
                                        .foregroundColor(.orange)
                                    Button("Allow Scripts") {
                                        showScriptEnableConfirmation = true
                                    }
                                    .buttonStyle(.link)
                                    .font(.caption)
                                }
                            }
                            .padding(.leading, 84)
                            .accessibilityIdentifier("launcher-editor-script-disabled-warning")
                        }

                        targetFormRows
                    }

                    // Validation
                    if let error = validationError {
                        HStack(spacing: 6) {
                            Image(systemName: "exclamationmark.circle.fill")
                                .foregroundColor(.red)
                            Text(error)
                                .font(.caption)
                                .foregroundColor(.red)
                        }
                        .padding(.leading, 84)
                    }
                }
                .padding(24)
            }

            Divider()

            // Buttons
            HStack {
                Button("Cancel") { onCancel() }
                    .keyboardShortcut(.cancelAction)
                    .accessibilityIdentifier("launcher-editor-cancel-button")
                Spacer()
                Button("Save") {
                    if targetType == .script, !isScriptExecutionEnabled {
                        showScriptEnableConfirmation = true
                    } else {
                        save()
                    }
                }
                    .keyboardShortcut(.defaultAction)
                    .buttonStyle(.borderedProminent)
                    .disabled(!isValid)
                    .accessibilityIdentifier("launcher-editor-save-button")
            }
            .padding(.horizontal, 24)
            .padding(.vertical, 16)
        }
        .frame(width: 480)
        .frame(minHeight: 400)
        .sheet(isPresented: $showScriptEnableConfirmation) {
            ScriptEnableConfirmationView(
                onAllow: {
                    isScriptExecutionEnabled = true
                    showScriptEnableConfirmation = false
                    save()
                },
                onCancel: {
                    showScriptEnableConfirmation = false
                }
            )
        }
        .onAppear {
            isScriptExecutionEnabled = ScriptSecurityService.shared.isScriptExecutionEnabled
        }
        .task {
            await loadIcon()
        }
        .onReceive(NotificationObserverManager.defaultCenter.publisher(for: UserDefaults.didChangeNotification)) { _ in
            let newValue = ScriptSecurityService.shared.isScriptExecutionEnabled
            if isScriptExecutionEnabled != newValue {
                isScriptExecutionEnabled = newValue
            }
        }
    }

    // MARK: - Preview Card

    private var previewCard: some View {
        HStack(spacing: 14) {
            if let icon {
                Image(nsImage: icon)
                    .resizable()
                    .aspectRatio(contentMode: .fit)
                    .frame(width: 56, height: 56)
                    .clipShape(RoundedRectangle(cornerRadius: 12))
                    .shadow(color: .black.opacity(0.15), radius: 3, y: 1)
            } else {
                Image(systemName: targetType.iconName)
                    .font(.system(size: 24))
                    .foregroundColor(.secondary)
                    .frame(width: 56, height: 56)
                    .background(
                        RoundedRectangle(cornerRadius: 12)
                            .fill(Color.secondary.opacity(0.12))
                    )
            }

            VStack(alignment: .leading, spacing: 3) {
                Text(currentDisplayName.isEmpty ? "New Launcher" : currentDisplayName)
                    .font(.system(size: 15, weight: .medium))
                    .lineLimit(1)
                    .foregroundColor(currentDisplayName.isEmpty ? .secondary : .primary)
                Text(targetType.rawValue)
                    .font(.subheadline)
                    .foregroundColor(.secondary)
            }

            Spacer()

            if !normalizedKey.isEmpty {
                Text(displayKey.uppercased())
                    .font(.system(size: 20, weight: .bold, design: .monospaced))
                    .foregroundColor(.white)
                    .frame(minWidth: 40)
                    .padding(.horizontal, 12)
                    .padding(.vertical, 10)
                    .background(
                        RoundedRectangle(cornerRadius: 8)
                            .fill(Color.accentColor)
                    )
            }
        }
        .padding(16)
        .background(
            RoundedRectangle(cornerRadius: 12)
                .fill(Color(NSColor.windowBackgroundColor))
        )
        .overlay(
            RoundedRectangle(cornerRadius: 12)
                .stroke(Color.secondary.opacity(0.2), lineWidth: 1)
        )
    }

    // MARK: - Form Rows

    @ViewBuilder
    private var targetFormRows: some View {
        switch targetType {
        case .app:
            formRow("App") {
                HStack {
                    TextField("Name", text: $appName)
                        .textFieldStyle(.roundedBorder)
                        .accessibilityIdentifier("launcher-editor-app-name-field")
                    Button("Browse...") { browseForApp() }
                        .accessibilityIdentifier("launcher-editor-app-browse-button")
                }
            }
            formRow("Bundle ID") {
                TextField("Optional", text: $bundleId)
                    .textFieldStyle(.roundedBorder)
                    .font(.caption.monospaced())
                    .accessibilityIdentifier("launcher-editor-bundle-id-field")
            }
        case .website:
            formRow("URL") {
                TextField("e.g., github.com", text: $url)
                    .textFieldStyle(.roundedBorder)
                    .accessibilityIdentifier("launcher-editor-url-field")
            }
        case .folder:
            formRow("Path") {
                HStack {
                    TextField("Folder path", text: $folderPath)
                        .textFieldStyle(.roundedBorder)
                        .accessibilityIdentifier("launcher-editor-folder-path-field")
                    Button("Browse...") { browseForFolder() }
                        .accessibilityIdentifier("launcher-editor-folder-browse-button")
                }
            }
            if let warning = folderPathWarning {
                warningLabel(warning)
                    .padding(.leading, 84)
            }
            formRow("Name") {
                TextField("Display name (optional)", text: $folderName)
                    .textFieldStyle(.roundedBorder)
                    .accessibilityIdentifier("launcher-editor-folder-name-field")
            }
        case .script:
            formRow("Path") {
                HStack {
                    TextField("Script path", text: $scriptPath)
                        .textFieldStyle(.roundedBorder)
                        .accessibilityIdentifier("launcher-editor-script-path-field")
                        .disabled(!isScriptExecutionEnabled)
                    Button("Browse...") { browseForScript() }
                        .accessibilityIdentifier("launcher-editor-script-browse-button")
                        .disabled(!isScriptExecutionEnabled)
                }
            }
            if let warning = scriptPathWarning {
                warningLabel(warning)
                    .padding(.leading, 84)
            }
            formRow("Name") {
                TextField("Display name (optional)", text: $scriptName)
                    .textFieldStyle(.roundedBorder)
                    .accessibilityIdentifier("launcher-editor-script-name-field")
                    .disabled(!isScriptExecutionEnabled)
            }
            if let preview = scriptPreview {
                formRow("") {
                    VStack(alignment: .leading, spacing: 6) {
                        Text(coloredScriptPreview(preview))
                            .font(.system(size: 10, design: .monospaced))
                            .lineLimit(10)
                            .frame(maxWidth: .infinity, alignment: .leading)
                            .padding(8)
                            .background(
                                RoundedRectangle(cornerRadius: 6, style: .continuous)
                                    .fill(Color.primary.opacity(0.04))
                            )
                        Button {
                            let url = URL(fileURLWithPath: (scriptPath as NSString).expandingTildeInPath)
                            NSWorkspace.shared.open(url)
                        } label: {
                            Label("Open in Editor", systemImage: "pencil.and.outline")
                                .font(.caption)
                        }
                        .buttonStyle(.bordered)
                        .controlSize(.small)
                        .accessibilityIdentifier("launcher-editor-open-script")
                    }
                }
            }

            // Description (shown in overlay sidebar)
            formRow("Description") {
                TextField("What this shortcut does (optional)", text: $userDescription)
                    .textFieldStyle(.roundedBorder)
                    .accessibilityIdentifier("launcher-editor-description-field")
            }

            // Custom icon (available for all target types)
            formRow("Icon") {
                HStack(spacing: 8) {
                    if !customIconPath.isEmpty,
                       let img = NSImage(contentsOfFile: (customIconPath as NSString).expandingTildeInPath)
                    {
                        Image(nsImage: img)
                            .resizable()
                            .aspectRatio(contentMode: .fit)
                            .frame(width: 20, height: 20)
                            .clipShape(RoundedRectangle(cornerRadius: 4))
                    }
                    Button(customIconPath.isEmpty ? "Choose..." : "Change...") {
                        browseForIcon()
                    }
                    .controlSize(.small)
                    .accessibilityIdentifier("launcher-editor-icon-browse")
                    if !customIconPath.isEmpty {
                        Button {
                            customIconPath = ""
                        } label: {
                            Image(systemName: "xmark.circle.fill")
                                .foregroundStyle(.secondary)
                        }
                        .buttonStyle(.plain)
                        .help("Remove custom icon")
                        .accessibilityIdentifier("launcher-editor-icon-clear")
                    }
                }
            }
        }
    }

    // MARK: - Helpers

    private func formRow<Content: View>(_ label: String, @ViewBuilder content: () -> Content) -> some View {
        HStack(alignment: .firstTextBaseline, spacing: 12) {
            Text(label)
                .font(.system(size: 12))
                .foregroundColor(.secondary)
                .frame(width: 72, alignment: .trailing)
            content()
        }
    }

    private func warningLabel(_ text: String) -> some View {
        HStack(spacing: 6) {
            Image(systemName: "exclamationmark.triangle.fill")
                .foregroundColor(.orange)
            Text(text)
                .font(.caption)
                .foregroundColor(.orange)
        }
    }

    private var currentDisplayName: String {
        if !userDescription.isEmpty { return userDescription }
        return switch targetType {
        case .app: appName
        case .website: url
        case .folder: folderName.isEmpty ? (folderPath as NSString).lastPathComponent : folderName
        case .script: scriptName.isEmpty ? (scriptPath as NSString).lastPathComponent : scriptName
        }
    }

    // MARK: - Icon Loading

    private func loadIcon() async {
        if !customIconPath.isEmpty {
            let expanded = (customIconPath as NSString).expandingTildeInPath
            if let img = NSImage(contentsOfFile: expanded) {
                img.size = NSSize(width: 56, height: 56)
                icon = img
                return
            }
        }
        guard let mapping else { return }
        switch mapping.target {
        case .app, .folder, .script:
            icon = AppIconResolver.icon(for: mapping.target)
        case let .url(urlString):
            icon = await services.faviconFetcher.fetchFavicon(for: urlString)
        }
    }

    // MARK: - Validation

    private var isValid: Bool {
        validationError == nil
    }

    private var validationError: String? {
        if normalizedKey.isEmpty {
            return "Key is required"
        }
        if !LauncherGridConfig.isValidKey(normalizedKey) {
            return "Use a single letter or number"
        }
        if let mapping, LauncherGridConfig.normalizeKey(mapping.key) == normalizedKey {
            // OK - same key
        } else if existingKeys.contains(normalizedKey) {
            return "Key '\(displayKey.uppercased())' is already in use"
        }

        switch targetType {
        case .app:
            if appName.isEmpty { return "App name is required" }
        case .website:
            if url.isEmpty { return "URL is required" }
        case .folder:
            if folderPath.isEmpty { return "Folder path is required" }
        case .script:
            if scriptPath.isEmpty { return "Script path is required" }
            if !isScriptExecutionEnabled { return "Script execution is disabled in Settings" }
        }

        return nil
    }

    private var folderPathWarning: String? {
        guard !folderPath.isEmpty else { return nil }
        let expandedPath = (folderPath as NSString).expandingTildeInPath
        var isDirectory: ObjCBool = false
        if !Foundation.FileManager().fileExists(atPath: expandedPath, isDirectory: &isDirectory) {
            return "Folder not found at this path"
        }
        if !isDirectory.boolValue {
            return "Path points to a file, not a folder"
        }
        return nil
    }

    private var scriptPathWarning: String? {
        guard !scriptPath.isEmpty else { return nil }
        let expandedPath = (scriptPath as NSString).expandingTildeInPath
        if !Foundation.FileManager().fileExists(atPath: expandedPath) {
            return "Script not found at this path"
        }
        let securityService = ScriptSecurityService.shared
        let isScript = securityService.isRecognizedScript(expandedPath)
        let isExecutable = Foundation.FileManager().isExecutableFile(atPath: expandedPath)
        if !isScript, !isExecutable {
            return "File may not be executable"
        }
        return nil
    }

    private func coloredScriptPreview(_ text: String) -> AttributedString {
        var result = AttributedString()
        let lines = text.components(separatedBy: .newlines)
        for (index, line) in lines.enumerated() {
            var attr = AttributedString(line)
            let trimmed = line.trimmingCharacters(in: .whitespaces)
            if trimmed.hasPrefix("#!") {
                attr.foregroundColor = .accentColor
            } else if trimmed.hasPrefix("#") || trimmed.hasPrefix("--") || trimmed.hasPrefix("//") {
                attr.foregroundColor = Color(.tertiaryLabelColor)
            } else {
                attr.foregroundColor = .secondary
            }
            result.append(attr)
            if index < lines.count - 1 {
                result.append(AttributedString("\n"))
            }
        }
        return result
    }

    private var scriptPreview: String? {
        guard !scriptPath.isEmpty else { return nil }
        let expanded = (scriptPath as NSString).expandingTildeInPath
        guard let data = Foundation.FileManager().contents(atPath: expanded),
              let content = String(data: data, encoding: .utf8),
              !content.isEmpty
        else { return nil }
        let lines = content.components(separatedBy: .newlines).prefix(10)
        return lines.joined(separator: "\n")
    }

    // MARK: - Actions

    private func save() {
        let target: LauncherTarget = switch targetType {
        case .app:
            .app(name: appName, bundleId: bundleId.isEmpty ? nil : bundleId)
        case .website:
            .url(url)
        case .folder:
            .folder(path: folderPath, name: folderName.isEmpty ? nil : folderName)
        case .script:
            .script(path: scriptPath, name: scriptName.isEmpty ? nil : scriptName)
        }

        let result = LauncherMapping(
            id: mapping?.id ?? UUID(),
            key: normalizedKey,
            target: target,
            isEnabled: isEnabled,
            customIconPath: customIconPath.isEmpty ? nil : customIconPath,
            userDescription: userDescription.isEmpty ? nil : userDescription
        )
        onSave(result)
    }

    private func openSettings() {
        NotificationObserverManager.defaultCenter.post(name: Notification.Name.openSettingsGeneral, object: nil)
        NSApp.sendAction(Selector(("showSettingsWindow:")), to: nil, from: nil)
    }

    // MARK: - Browse Methods

    private func browseForFolder() {
        let panel = NSOpenPanel()
        panel.canChooseFiles = false
        panel.canChooseDirectories = true
        panel.allowsMultipleSelection = false
        panel.message = "Select a folder to open"
        panel.prompt = "Select"

        if panel.runModal() == .OK, let url = panel.url {
            let path = url.path
            if path.hasPrefix(NSHomeDirectory()) {
                folderPath = path.replacingOccurrences(of: NSHomeDirectory(), with: "~")
            } else {
                folderPath = path
            }
            if folderName.isEmpty {
                folderName = url.lastPathComponent
            }
        }
    }

    private func browseForScript() {
        let panel = NSOpenPanel()
        panel.canChooseFiles = true
        panel.canChooseDirectories = false
        panel.allowsMultipleSelection = false
        panel.message = "Select a script file"
        panel.prompt = "Select"

        var allowedTypes: [UTType] = [.shellScript, .unixExecutable]
        if let t = UTType(filenameExtension: "applescript") { allowedTypes.append(t) }
        if let t = UTType(filenameExtension: "scpt") { allowedTypes.append(t) }
        if let t = UTType(filenameExtension: "py") { allowedTypes.append(t) }
        if let t = UTType(filenameExtension: "rb") { allowedTypes.append(t) }
        if let t = UTType(filenameExtension: "pl") { allowedTypes.append(t) }
        if let t = UTType(filenameExtension: "zsh") { allowedTypes.append(t) }
        if let t = UTType(filenameExtension: "bash") { allowedTypes.append(t) }
        panel.allowedContentTypes = allowedTypes

        if panel.runModal() == .OK, let url = panel.url {
            let path = url.path
            if path.hasPrefix(NSHomeDirectory()) {
                scriptPath = path.replacingOccurrences(of: NSHomeDirectory(), with: "~")
            } else {
                scriptPath = path
            }
            if scriptName.isEmpty {
                scriptName = url.deletingPathExtension().lastPathComponent
            }
        }
    }

    private func browseForIcon() {
        let panel = NSOpenPanel()
        panel.canChooseFiles = true
        panel.canChooseDirectories = false
        panel.allowsMultipleSelection = false
        panel.message = "Choose an icon image"
        panel.prompt = "Select"
        panel.allowedContentTypes = [.png, .jpeg, .icns, .svg, .tiff]

        if panel.runModal() == .OK, let url = panel.url {
            let path = url.path
            if path.hasPrefix(NSHomeDirectory()) {
                customIconPath = path.replacingOccurrences(of: NSHomeDirectory(), with: "~")
            } else {
                customIconPath = path
            }
        }
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
            appName = url.deletingPathExtension().lastPathComponent
            bundleId = Bundle(url: url)?.bundleIdentifier ?? ""
            icon = AppIconResolver.icon(for: .app(name: appName, bundleId: bundleId.isEmpty ? nil : bundleId))
        }
    }

    private var normalizedKey: String {
        LauncherGridConfig.normalizeKey(key)
    }

    private var keyTranslator: LauncherKeymapTranslator {
        LauncherKeymapTranslator(keymapId: selectedKeymapId, includePunctuationStore: includePunctuationStore)
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

// MARK: - Preview

#Preview("Launcher Collection View") {
    LauncherCollectionView(
        config: .constant(LauncherGridConfig.defaultConfig),
        onConfigChanged: { _ in }
    )
    .frame(width: 900, height: 400)
}

#Preview("Launcher Collection - Empty") {
    LauncherCollectionView(
        config: .constant(LauncherGridConfig(activationMode: .leaderSequence, mappings: [])),
        onConfigChanged: { _ in }
    )
    .frame(width: 900, height: 400)
}
