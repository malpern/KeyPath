import AppKit
import SwiftUI
import UniformTypeIdentifiers

// MARK: - Mapping Editor

struct LauncherMappingEditor: View {
    let mapping: LauncherMapping?
    let existingKeys: Set<String>
    let onSave: (LauncherMapping) -> Void
    let onCancel: () -> Void
    var onDelete: (() -> Void)?

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
    @State private var keystrokeKey: String
    @State private var selectedSystemAction: SystemActionInfo?
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
        case keystroke = "Key"
        case systemAction = "System"

        var requiresScriptExecution: Bool {
            self == .script
        }

        var iconName: String {
            switch self {
            case .app: "app.fill"
            case .website: "globe"
            case .folder: "folder.fill"
            case .script: "terminal.fill"
            case .keystroke: "keyboard"
            case .systemAction: "gearshape"
            }
        }
    }

    init(
        mapping: LauncherMapping?,
        existingKeys: Set<String>,
        onSave: @escaping (LauncherMapping) -> Void,
        onCancel: @escaping () -> Void,
        onDelete: (() -> Void)? = nil
    ) {
        self.mapping = mapping
        self.existingKeys = existingKeys
        self.onSave = onSave
        self.onCancel = onCancel
        self.onDelete = onDelete

        if let mapping {
            _key = State(initialValue: mapping.key)
            _isEnabled = State(initialValue: mapping.isEnabled)
            _customIconPath = State(initialValue: mapping.customIconPath ?? "")
            _userDescription = State(initialValue: mapping.userDescription ?? "")
            switch mapping.action {
            case let .launchApp(name, bundleId):
                _targetType = State(initialValue: .app)
                _appName = State(initialValue: name)
                _bundleId = State(initialValue: bundleId ?? "")
                _url = State(initialValue: "")
                _folderPath = State(initialValue: "")
                _folderName = State(initialValue: "")
                _scriptPath = State(initialValue: "")
                _scriptName = State(initialValue: "")
                _keystrokeKey = State(initialValue: "")
                _selectedSystemAction = State(initialValue: nil)
            case let .openURL(urlString):
                _targetType = State(initialValue: .website)
                _appName = State(initialValue: "")
                _bundleId = State(initialValue: "")
                _url = State(initialValue: urlString)
                _folderPath = State(initialValue: "")
                _folderName = State(initialValue: "")
                _scriptPath = State(initialValue: "")
                _scriptName = State(initialValue: "")
                _keystrokeKey = State(initialValue: "")
                _selectedSystemAction = State(initialValue: nil)
            case let .openFolder(path, name):
                _targetType = State(initialValue: .folder)
                _appName = State(initialValue: "")
                _bundleId = State(initialValue: "")
                _url = State(initialValue: "")
                _folderPath = State(initialValue: path)
                _folderName = State(initialValue: name ?? "")
                _scriptPath = State(initialValue: "")
                _scriptName = State(initialValue: "")
                _keystrokeKey = State(initialValue: "")
                _selectedSystemAction = State(initialValue: nil)
            case let .runScript(path, name):
                _targetType = State(initialValue: .script)
                _appName = State(initialValue: "")
                _bundleId = State(initialValue: "")
                _url = State(initialValue: "")
                _folderPath = State(initialValue: "")
                _folderName = State(initialValue: "")
                _scriptPath = State(initialValue: path)
                _scriptName = State(initialValue: name ?? "")
                _keystrokeKey = State(initialValue: "")
                _selectedSystemAction = State(initialValue: nil)
            case let .keystroke(key):
                _targetType = State(initialValue: .keystroke)
                _appName = State(initialValue: "")
                _bundleId = State(initialValue: "")
                _url = State(initialValue: "")
                _folderPath = State(initialValue: "")
                _folderName = State(initialValue: "")
                _scriptPath = State(initialValue: "")
                _scriptName = State(initialValue: "")
                _keystrokeKey = State(initialValue: key)
                _selectedSystemAction = State(initialValue: nil)
            case let .systemAction(id):
                _targetType = State(initialValue: .systemAction)
                _appName = State(initialValue: "")
                _bundleId = State(initialValue: "")
                _url = State(initialValue: "")
                _folderPath = State(initialValue: "")
                _folderName = State(initialValue: "")
                _scriptPath = State(initialValue: "")
                _scriptName = State(initialValue: "")
                _keystrokeKey = State(initialValue: "")
                _selectedSystemAction = State(initialValue: SystemActionInfo.allActions.first { $0.id == id })
            default:
                _targetType = State(initialValue: .app)
                _appName = State(initialValue: "")
                _bundleId = State(initialValue: "")
                _url = State(initialValue: "")
                _folderPath = State(initialValue: "")
                _folderName = State(initialValue: "")
                _scriptPath = State(initialValue: "")
                _scriptName = State(initialValue: "")
                _keystrokeKey = State(initialValue: "")
                _selectedSystemAction = State(initialValue: nil)
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
            _keystrokeKey = State(initialValue: "")
            _selectedSystemAction = State(initialValue: nil)
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
                if mapping != nil, let onDelete {
                    Button("Delete", role: .destructive) {
                        onDelete()
                    }
                    .foregroundColor(.red)
                    .accessibilityIdentifier("launcher-editor-delete-button")
                }

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
                    .font(.title)
                    .foregroundColor(.secondary)
                    .frame(width: 56, height: 56)
                    .background(
                        RoundedRectangle(cornerRadius: 12)
                            .fill(Color.secondary.opacity(0.12))
                    )
            }

            VStack(alignment: .leading, spacing: 3) {
                Text(currentDisplayName.isEmpty ? "New Launcher" : currentDisplayName)
                    .font(.title3.weight(.medium))
                    .lineLimit(1)
                    .foregroundColor(currentDisplayName.isEmpty ? .secondary : .primary)
                Text(targetType.rawValue)
                    .font(.subheadline)
                    .foregroundColor(.secondary)
            }

            Spacer()

            if !normalizedKey.isEmpty {
                Text(displayKey.uppercased())
                    .font(.title2.bold().monospaced())
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
            if scriptPath.isEmpty {
                formRow("Script") {
                    Button {
                        browseForScript()
                    } label: {
                        Label("Select Script...", systemImage: "doc.badge.plus")
                    }
                    .accessibilityIdentifier("launcher-editor-script-browse-button")
                }
            } else {
                formRow("Script") {
                    HStack(spacing: 8) {
                        Image(systemName: "terminal.fill")
                            .foregroundStyle(.secondary)
                            .frame(width: 16)
                        VStack(alignment: .leading, spacing: 1) {
                            Text(scriptDisplayName)
                                .font(.callout)
                                .lineLimit(1)
                            Text(scriptPath)
                                .font(.caption)
                                .foregroundStyle(.secondary)
                                .lineLimit(1)
                                .truncationMode(.middle)
                        }
                        Spacer()
                        Menu {
                            Button {
                                let url = URL(fileURLWithPath: (scriptPath as NSString).expandingTildeInPath)
                                NSWorkspace.shared.open(url)
                            } label: {
                                Label("Open in Editor", systemImage: "pencil.and.outline")
                            }
                            Button {
                                let url = URL(fileURLWithPath: (scriptPath as NSString).expandingTildeInPath)
                                NSWorkspace.shared.activateFileViewerSelecting([url])
                            } label: {
                                Label("Show in Finder", systemImage: "folder")
                            }
                            Divider()
                            Button {
                                browseForScript()
                            } label: {
                                Label("Choose Different Script...", systemImage: "arrow.triangle.2.circlepath")
                            }
                            Divider()
                            Button(role: .destructive) {
                                scriptPath = ""
                                scriptName = ""
                            } label: {
                                Label("Remove Script", systemImage: "trash")
                            }
                        } label: {
                            Image(systemName: "gearshape")
                                .foregroundStyle(.secondary)
                        }
                        .menuStyle(.borderlessButton)
                        .frame(width: 24)
                        .accessibilityIdentifier("launcher-editor-script-gear-menu")
                        .accessibilityLabel("Script options")
                    }
                    .padding(8)
                    .background(
                        RoundedRectangle(cornerRadius: 6, style: .continuous)
                            .fill(Color.primary.opacity(0.04))
                    )
                    .overlay(
                        RoundedRectangle(cornerRadius: 6, style: .continuous)
                            .strokeBorder(Color.primary.opacity(0.1), lineWidth: 0.5)
                    )
                }
                if let warning = scriptPathWarning {
                    warningLabel(warning)
                        .padding(.leading, 84)
                }
                formRow("Name") {
                    TextField("Display name (optional)", text: $scriptName)
                        .textFieldStyle(.roundedBorder)
                        .accessibilityIdentifier("launcher-editor-script-name-field")
                }
                if let preview = scriptPreview {
                    formRow("") {
                        Text(coloredScriptPreview(preview))
                            .font(.caption.monospaced())
                            .lineLimit(10)
                            .frame(maxWidth: .infinity, alignment: .leading)
                            .padding(8)
                            .background(
                                RoundedRectangle(cornerRadius: 6, style: .continuous)
                                    .fill(Color.primary.opacity(0.04))
                            )
                    }
                }
            }
        case .keystroke:
            formRow("Key") {
                TextField("e.g., esc, f5, mute", text: $keystrokeKey)
                    .textFieldStyle(.roundedBorder)
                    .accessibilityIdentifier("launcher-editor-keystroke-field")
            }
        case .systemAction:
            formRow("Action") {
                Picker("", selection: $selectedSystemAction) {
                    Text("Choose...").tag(nil as SystemActionInfo?)
                    ForEach(SystemActionInfo.allActions) { action in
                        Label(action.name, systemImage: action.sfSymbol).tag(action as SystemActionInfo?)
                    }
                }
                .labelsHidden()
                .accessibilityIdentifier("launcher-editor-system-action-picker")
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
                    .accessibilityLabel("Remove custom icon")
                }
            }
        }
    }

    // MARK: - Helpers

    private func formRow(_ label: String, @ViewBuilder content: () -> some View) -> some View {
        HStack(alignment: .firstTextBaseline, spacing: 12) {
            Text(label)
                .font(.callout)
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
        case .keystroke: keystrokeKey.isEmpty ? "Key" : keystrokeKey.uppercased()
        case .systemAction: selectedSystemAction?.name ?? "System Action"
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
        switch mapping.action {
        case .launchApp, .openFolder, .runScript:
            icon = AppIconResolver.icon(for: mapping.action)
        case let .openURL(urlString):
            icon = await services.faviconFetcher.fetchFavicon(for: urlString)
        case .keystroke:
            icon = NSImage(systemSymbolName: "keyboard", accessibilityDescription: "Key")
        case let .systemAction(id):
            if let info = SystemActionInfo.allActions.first(where: { $0.id == id }) {
                icon = NSImage(systemSymbolName: info.sfSymbol, accessibilityDescription: info.name)
            }
        default:
            break
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
        case .keystroke:
            if keystrokeKey.trimmingCharacters(in: .whitespaces).isEmpty { return "Key name is required" }
        case .systemAction:
            if selectedSystemAction == nil { return "Choose a system action" }
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

    private var scriptDisplayName: String {
        if !scriptName.isEmpty { return scriptName }
        let expanded = (scriptPath as NSString).expandingTildeInPath
        return URL(fileURLWithPath: expanded).lastPathComponent
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
        let action: KeyAction = switch targetType {
        case .app:
            .launchApp(name: appName, bundleId: bundleId.isEmpty ? nil : bundleId)
        case .website:
            .openURL(url)
        case .folder:
            .openFolder(path: folderPath, name: folderName.isEmpty ? nil : folderName)
        case .script:
            .runScript(path: scriptPath, name: scriptName.isEmpty ? nil : scriptName)
        case .keystroke:
            .keystroke(key: keystrokeKey.trimmingCharacters(in: .whitespaces).lowercased())
        case .systemAction:
            .systemAction(id: selectedSystemAction?.id ?? "")
        }

        let result = LauncherMapping(
            id: mapping?.id ?? UUID(),
            key: normalizedKey,
            action: action,
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
            icon = AppIconResolver.icon(for: .launchApp(name: appName, bundleId: bundleId.isEmpty ? nil : bundleId))
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
