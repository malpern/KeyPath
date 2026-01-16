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

    // Local state for immediate UI response
    @State private var localHyperTriggerMode: HyperTriggerMode = .hold

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            // Activation mode picker
            activationModeSection
                .padding(.horizontal, 16)
                .padding(.vertical, 12)

            Divider()

            // Main content: Keyboard + Drawer
            HStack(alignment: .top, spacing: 0) {
                // Keyboard visualization
                VStack(spacing: 8) {
                    LauncherKeyboardView(
                        config: $config,
                        selectedKey: selectedKey,
                        onKeyClicked: handleKeyClicked
                    )
                    .padding(16)

                    // Instructions
                    Text("Click any key to configure")
                        .font(.caption)
                        .foregroundColor(.secondary)
                        .padding(.bottom, 12)
                }
                .frame(maxWidth: .infinity)
                .background(Color(NSColor.windowBackgroundColor).opacity(0.5))

                Divider()

                // Drawer with mappings list
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
                .frame(width: 280)
                .onChange(of: config) { _, newValue in
                    onConfigChanged(newValue)
                }
            }
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
                mapping: preselectedKey.map { key in
                    LauncherMapping(key: key, target: .app(name: "", bundleId: nil))
                },
                existingKeys: Set(config.mappings.map(\.key)),
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
    }

    // MARK: - Activation Mode Section

    private var activationModeSection: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                Text("Activation")
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
            .accessibilityIdentifier("launcher-activation-mode-picker")

            // Hyper trigger mode radio buttons (only shown when Hyper mode is selected)
            if config.activationMode == .holdHyper {
                HStack(spacing: 16) {
                    ForEach([HyperTriggerMode.hold, HyperTriggerMode.tap], id: \.self) { mode in
                        Button {
                            // Immediate local update for responsive UI
                            localHyperTriggerMode = mode
                            // Persist via callback
                            var updated = config
                            updated.hyperTriggerMode = mode
                            onConfigChanged(updated)
                        } label: {
                            HStack(spacing: 6) {
                                Image(systemName: localHyperTriggerMode == mode ? "circle.inset.filled" : "circle")
                                    .foregroundColor(localHyperTriggerMode == mode ? .accentColor : .secondary)
                                    .font(.system(size: 14))
                                Text(mode.displayName)
                                    .font(.subheadline)
                                    .foregroundColor(.primary)
                            }
                        }
                        .buttonStyle(.plain)
                        .accessibilityIdentifier("launcher-hyper-trigger-\(mode.rawValue)")
                    }
                }
                .padding(.top, 4)
                .animation(.easeInOut(duration: 0.15), value: localHyperTriggerMode)
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
        // Find available number keys
        let usedKeys = Set(config.mappings.map(\.key))
        let availableKeys = LauncherGridConfig.availableNumberKeys.filter { !usedKeys.contains($0) }

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
    @State private var folderPath: String
    @State private var folderName: String
    @State private var scriptPath: String
    @State private var scriptName: String
    @State private var isEnabled: Bool
    @State private var isScriptExecutionEnabled: Bool = ScriptSecurityService.shared.isScriptExecutionEnabled

    enum TargetType: String, CaseIterable {
        case app = "App"
        case website = "Website"
        case folder = "Folder"
        case script = "Script"

        var requiresScriptExecution: Bool {
            self == .script
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
                        Text(type.rawValue)
                            .tag(type)
                    }
                }
                .pickerStyle(.segmented)
                .accessibilityIdentifier("launcher-editor-type-picker")
                .onChange(of: targetType) { oldValue, newValue in
                    // Prevent switching to script type if execution is disabled
                    if newValue.requiresScriptExecution, !isScriptExecutionEnabled {
                        targetType = oldValue
                    }
                }

                // Script execution disabled warning (shown when trying to select Script)
                if !isScriptExecutionEnabled, targetType == .script {
                    HStack(spacing: 8) {
                        Image(systemName: "lock.shield.fill")
                            .foregroundColor(.orange)
                        VStack(alignment: .leading, spacing: 4) {
                            Text("Script execution is disabled")
                                .font(.caption)
                                .fontWeight(.medium)
                                .foregroundColor(.orange)
                            Button("Enable in Settings") {
                                openSettings()
                            }
                            .buttonStyle(.link)
                            .font(.caption)
                        }
                    }
                    .padding(.vertical, 4)
                    .accessibilityIdentifier("launcher-editor-script-disabled-warning")
                }

                switch targetType {
                case .app:
                    TextField("App Name", text: $appName)
                        .textFieldStyle(.roundedBorder)
                        .accessibilityIdentifier("launcher-editor-app-name-field")
                    TextField("Bundle ID (optional)", text: $bundleId)
                        .textFieldStyle(.roundedBorder)
                        .font(.system(size: 11, design: .monospaced))
                        .accessibilityIdentifier("launcher-editor-bundle-id-field")
                case .website:
                    TextField("URL (e.g., github.com)", text: $url)
                        .textFieldStyle(.roundedBorder)
                        .accessibilityIdentifier("launcher-editor-url-field")
                case .folder:
                    HStack {
                        TextField("Folder Path", text: $folderPath)
                            .textFieldStyle(.roundedBorder)
                            .accessibilityIdentifier("launcher-editor-folder-path-field")
                        Button("Browse...") {
                            browseForFolder()
                        }
                        .accessibilityIdentifier("launcher-editor-folder-browse-button")
                    }

                    // Folder path validation warning
                    if let warning = folderPathWarning {
                        HStack(spacing: 6) {
                            Image(systemName: "exclamationmark.triangle.fill")
                                .foregroundColor(.orange)
                            Text(warning)
                                .font(.caption)
                                .foregroundColor(.orange)
                        }
                    }

                    TextField("Display Name (optional)", text: $folderName)
                        .textFieldStyle(.roundedBorder)
                        .accessibilityIdentifier("launcher-editor-folder-name-field")
                case .script:
                    HStack {
                        TextField("Script Path", text: $scriptPath)
                            .textFieldStyle(.roundedBorder)
                            .accessibilityIdentifier("launcher-editor-script-path-field")
                            .disabled(!isScriptExecutionEnabled)
                        Button("Browse...") {
                            browseForScript()
                        }
                        .accessibilityIdentifier("launcher-editor-script-browse-button")
                        .disabled(!isScriptExecutionEnabled)
                    }

                    // Script path validation warning
                    if let warning = scriptPathWarning {
                        HStack(spacing: 6) {
                            Image(systemName: "exclamationmark.triangle.fill")
                                .foregroundColor(.orange)
                            Text(warning)
                                .font(.caption)
                                .foregroundColor(.orange)
                        }
                    }

                    TextField("Display Name (optional)", text: $scriptName)
                        .textFieldStyle(.roundedBorder)
                        .accessibilityIdentifier("launcher-editor-script-name-field")
                        .disabled(!isScriptExecutionEnabled)
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
        .onAppear {
            // Sync state with security service
            isScriptExecutionEnabled = ScriptSecurityService.shared.isScriptExecutionEnabled
        }
        .onReceive(NotificationCenter.default.publisher(for: UserDefaults.didChangeNotification)) { _ in
            // Update when settings change
            let newValue = ScriptSecurityService.shared.isScriptExecutionEnabled
            if isScriptExecutionEnabled != newValue {
                isScriptExecutionEnabled = newValue
                // If script execution is now disabled and we're editing a script, show warning
                if !newValue, targetType == .script {
                    // Keep on script tab to show warning, but prevent saving
                }
            }
        }
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
        case .folder:
            if folderPath.isEmpty {
                return "Folder path is required"
            }
        case .script:
            if scriptPath.isEmpty {
                return "Script path is required"
            }
            if !isScriptExecutionEnabled {
                return "Script execution is disabled in Settings"
            }
        }

        return nil
    }

    /// Warning for folder path (not a blocking error, just informational)
    private var folderPathWarning: String? {
        guard !folderPath.isEmpty else { return nil }

        let expandedPath = (folderPath as NSString).expandingTildeInPath
        var isDirectory: ObjCBool = false

        if !FileManager.default.fileExists(atPath: expandedPath, isDirectory: &isDirectory) {
            return "Folder not found at this path"
        }

        if !isDirectory.boolValue {
            return "Path points to a file, not a folder"
        }

        return nil
    }

    /// Warning for script path (not a blocking error, just informational)
    private var scriptPathWarning: String? {
        guard !scriptPath.isEmpty else { return nil }

        let expandedPath = (scriptPath as NSString).expandingTildeInPath

        if !FileManager.default.fileExists(atPath: expandedPath) {
            return "Script not found at this path"
        }

        // Check if it's a recognized script type or executable
        let securityService = ScriptSecurityService.shared
        let isScript = securityService.isRecognizedScript(expandedPath)
        let isExecutable = FileManager.default.isExecutableFile(atPath: expandedPath)

        if !isScript, !isExecutable {
            return "File may not be executable"
        }

        return nil
    }

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
            key: key,
            target: target,
            isEnabled: isEnabled
        )
        onSave(result)
    }

    // MARK: - Navigation Methods

    private func openSettings() {
        // Open Settings window on General tab (where script execution toggle is)
        NotificationCenter.default.post(name: .openSettingsGeneral, object: nil)
        // Also open the settings window if it's not already open
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
            // Use ~ shorthand for home directory
            let path = url.path
            if path.hasPrefix(NSHomeDirectory()) {
                folderPath = path.replacingOccurrences(of: NSHomeDirectory(), with: "~")
            } else {
                folderPath = path
            }
            // Auto-set name from folder name if not already set
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

        // Build comprehensive list of script types
        var allowedTypes: [UTType] = [
            .shellScript, // .sh files
            .unixExecutable // Binary executables
        ]

        // Add AppleScript types (both .applescript and .scpt)
        if let appleScriptType = UTType(filenameExtension: "applescript") {
            allowedTypes.append(appleScriptType)
        }
        if let scptType = UTType(filenameExtension: "scpt") {
            allowedTypes.append(scptType)
        }

        // Add common scripting languages
        if let pythonType = UTType(filenameExtension: "py") {
            allowedTypes.append(pythonType)
        }
        if let rubyType = UTType(filenameExtension: "rb") {
            allowedTypes.append(rubyType)
        }
        if let perlType = UTType(filenameExtension: "pl") {
            allowedTypes.append(perlType)
        }

        // Add zsh and bash explicitly (beyond .shellScript)
        if let zshType = UTType(filenameExtension: "zsh") {
            allowedTypes.append(zshType)
        }
        if let bashType = UTType(filenameExtension: "bash") {
            allowedTypes.append(bashType)
        }

        panel.allowedContentTypes = allowedTypes

        if panel.runModal() == .OK, let url = panel.url {
            // Use ~ shorthand for home directory
            let path = url.path
            if path.hasPrefix(NSHomeDirectory()) {
                scriptPath = path.replacingOccurrences(of: NSHomeDirectory(), with: "~")
            } else {
                scriptPath = path
            }
            // Auto-set name from script name if not already set
            if scriptName.isEmpty {
                scriptName = url.deletingPathExtension().lastPathComponent
            }
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
