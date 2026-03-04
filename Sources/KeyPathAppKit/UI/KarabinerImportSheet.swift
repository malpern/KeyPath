import KeyPathCore
import SwiftUI

/// Sheet for importing Karabiner-Elements configurations into KeyPath rule collections.
struct KarabinerImportSheet: View {
    @Environment(\.dismiss) private var dismiss
    @Environment(KanataViewModel.self) var kanataManager

    @State private var importSource: ImportSource = .autoDetect
    @State private var selectedFileURL: URL?
    @State private var pastedJSON: String = ""

    @State private var profiles: [(name: String, index: Int, isSelected: Bool)] = []
    @State private var selectedProfileIndex: Int?

    @State private var conversionResult: KarabinerConversionResult?
    @State private var selectedCollectionIds: Set<UUID> = []
    @State private var selectedAppKeymapIds: Set<UUID> = []
    @State private var selectedLauncherIds: Set<UUID> = []

    @State private var isLoading = false
    @State private var errorMessage: String?
    @State private var showFilePicker = false
    @State private var showSkippedRules = false
    @State private var pasteDebounceTask: Task<Void, Never>?

    private let converterService = KarabinerConverterService()

    enum ImportSource: String, CaseIterable {
        case autoDetect = "Auto-Detect"
        case file = "Choose File"
        case paste = "Paste JSON"
    }

    var body: some View {
        VStack(spacing: 0) {
            header
            Divider()
            ScrollView {
                VStack(alignment: .leading, spacing: 16) {
                    if conversionResult == nil {
                        sourceSelectionView
                    } else {
                        resultsPreview
                    }
                }
                .padding()
            }
            Divider()
            footer
        }
        .frame(width: 560, height: 620)
        .fileImporter(
            isPresented: $showFilePicker,
            allowedContentTypes: [.json],
            allowsMultipleSelection: false
        ) { result in
            switch result {
            case let .success(urls):
                selectedFileURL = urls.first
            case let .failure(error):
                errorMessage = "Failed to select file: \(error.localizedDescription)"
            }
        }
    }

    // MARK: - Header

    private var header: some View {
        HStack {
            Text("Import from Karabiner")
                .font(.title2)
                .fontWeight(.semibold)
            Spacer()
            Button("Cancel") { dismiss() }
                .accessibilityIdentifier("karabiner-import-cancel")
        }
        .padding()
    }

    // MARK: - Source Selection

    private var sourceSelectionView: some View {
        VStack(alignment: .leading, spacing: 16) {
            // Source picker
            Picker("Import Source", selection: $importSource) {
                ForEach(ImportSource.allCases, id: \.self) { source in
                    Text(source.rawValue).tag(source)
                }
            }
            .pickerStyle(.segmented)
            .onChange(of: importSource) { _, _ in
                errorMessage = nil
                profiles = []
                selectedProfileIndex = nil
            }

            switch importSource {
            case .autoDetect:
                autoDetectView
            case .file:
                filePickerView
            case .paste:
                pasteView
            }

            // Profile selection
            if !profiles.isEmpty {
                VStack(alignment: .leading, spacing: 8) {
                    Text("Profile")
                        .font(.headline)
                    Picker("Profile", selection: $selectedProfileIndex) {
                        ForEach(profiles, id: \.index) { profile in
                            HStack {
                                Text(profile.name)
                                if profile.isSelected {
                                    Text("(active)")
                                        .foregroundStyle(.secondary)
                                }
                            }
                            .tag(profile.index as Int?)
                        }
                    }
                    .pickerStyle(.menu)
                }
            }

            // Error
            if let error = errorMessage {
                HStack(alignment: .top, spacing: 8) {
                    Image(systemName: "exclamationmark.triangle.fill")
                        .foregroundStyle(.red)
                    Text(error)
                        .foregroundStyle(.red)
                        .font(.caption)
                }
                .padding(10)
                .frame(maxWidth: .infinity, alignment: .leading)
                .background(Color.red.opacity(0.1))
                .clipShape(.rect(cornerRadius: 8))
            }

            // Convert button
            Button {
                Task { await runConversion() }
            } label: {
                HStack {
                    if isLoading {
                        ProgressView()
                            .scaleEffect(0.8)
                    }
                    Text(isLoading ? "Converting..." : "Convert")
                }
                .frame(maxWidth: .infinity)
            }
            .buttonStyle(.borderedProminent)
            .disabled(isLoading || !canConvert)
            .accessibilityIdentifier("karabiner-import-convert")
        }
    }

    private var autoDetectView: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("Karabiner Configuration")
                .font(.headline)

            if WizardSystemPaths.karabinerConfigExists {
                HStack(spacing: 8) {
                    Image(systemName: "checkmark.circle.fill")
                        .foregroundStyle(.green)
                    VStack(alignment: .leading) {
                        Text("Configuration found")
                            .fontWeight(.medium)
                        Text(WizardSystemPaths.karabinerConfigPath)
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                }
                .padding(10)
                .frame(maxWidth: .infinity, alignment: .leading)
                .background(Color.green.opacity(0.1))
                .clipShape(.rect(cornerRadius: 8))
                .onAppear { loadProfiles(source: .autoDetect) }
            } else {
                HStack(spacing: 8) {
                    Image(systemName: "xmark.circle.fill")
                        .foregroundStyle(.orange)
                    Text("No Karabiner configuration found at default location")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
                .padding(10)
                .frame(maxWidth: .infinity, alignment: .leading)
                .background(Color.orange.opacity(0.1))
                .clipShape(.rect(cornerRadius: 8))

                Text("Try choosing a file or pasting JSON instead.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
    }

    private var filePickerView: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("Karabiner JSON File")
                .font(.headline)
            if let fileURL = selectedFileURL {
                HStack {
                    Image(systemName: "doc.fill")
                        .foregroundStyle(.secondary)
                    Text(fileURL.lastPathComponent)
                        .foregroundStyle(.secondary)
                    Spacer()
                    Button("Change") { showFilePicker = true }
                }
                .padding(10)
                .background(Color.secondary.opacity(0.1))
                .clipShape(.rect(cornerRadius: 8))
                .onAppear { loadProfiles(source: .file) }
            } else {
                Button("Choose File") { showFilePicker = true }
                    .buttonStyle(.bordered)
                    .accessibilityIdentifier("karabiner-import-file-button")
            }
        }
    }

    private var pasteView: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("Paste JSON")
                .font(.headline)
            TextEditor(text: $pastedJSON)
                .font(.system(.caption, design: .monospaced))
                .frame(height: 120)
                .border(Color.secondary.opacity(0.3))
                .clipShape(.rect(cornerRadius: 4))
                .accessibilityIdentifier("karabiner-import-paste-field")
                .onChange(of: pastedJSON) { _, newValue in
                    pasteDebounceTask?.cancel()
                    guard !newValue.isEmpty else { return }
                    pasteDebounceTask = Task {
                        try? await Task.sleep(for: .milliseconds(500))
                        guard !Task.isCancelled else { return }
                        loadProfiles(source: .paste)
                    }
                }
            Text("Paste the contents of your karabiner.json file")
                .font(.caption)
                .foregroundStyle(.secondary)
        }
    }

    // MARK: - Results Preview

    private var resultsPreview: some View {
        VStack(alignment: .leading, spacing: 16) {
            if let result = conversionResult {
                // Summary
                summaryBanner(result)

                // Collections
                if !result.collections.isEmpty {
                    sectionHeader("Rule Collections", count: result.collections.count)
                    ForEach(result.collections) { collection in
                        checkboxRow(
                            title: collection.name,
                            subtitle: "\(collection.mappings.count) mapping\(collection.mappings.count == 1 ? "" : "s")",
                            icon: collection.icon ?? "keyboard",
                            isSelected: selectedCollectionIds.contains(collection.id)
                        ) {
                            toggleSelection(collection.id, in: &selectedCollectionIds)
                        }
                    }
                }

                // App Keymaps
                if !result.appKeymaps.isEmpty {
                    sectionHeader("App-Specific Rules", count: result.appKeymaps.count)
                    ForEach(result.appKeymaps) { keymap in
                        checkboxRow(
                            title: keymap.mapping.displayName,
                            subtitle: "\(keymap.overrides.count) override\(keymap.overrides.count == 1 ? "" : "s")",
                            icon: "app.badge",
                            isSelected: selectedAppKeymapIds.contains(keymap.id)
                        ) {
                            toggleSelection(keymap.id, in: &selectedAppKeymapIds)
                        }
                    }
                }

                // Launcher Mappings
                if !result.launcherMappings.isEmpty {
                    sectionHeader("Launcher Shortcuts", count: result.launcherMappings.count)
                    ForEach(result.launcherMappings) { mapping in
                        checkboxRow(
                            title: mapping.target.displayName,
                            subtitle: "Key: \(mapping.key)",
                            icon: "arrow.up.forward.app",
                            isSelected: selectedLauncherIds.contains(mapping.id)
                        ) {
                            toggleSelection(mapping.id, in: &selectedLauncherIds)
                        }
                    }
                }

                // Skipped Rules
                if !result.skippedRules.isEmpty {
                    DisclosureGroup(isExpanded: $showSkippedRules) {
                        ForEach(result.skippedRules) { skipped in
                            HStack(alignment: .top, spacing: 8) {
                                Image(systemName: "exclamationmark.triangle")
                                    .foregroundStyle(.orange)
                                    .font(.caption)
                                VStack(alignment: .leading, spacing: 2) {
                                    Text(skipped.description)
                                        .font(.caption)
                                        .fontWeight(.medium)
                                    Text(skipped.reason)
                                        .font(.caption2)
                                        .foregroundStyle(.secondary)
                                }
                            }
                            .padding(.vertical, 2)
                        }
                    } label: {
                        Text("\(result.skippedRules.count) skipped rule\(result.skippedRules.count == 1 ? "" : "s")")
                            .font(.subheadline)
                            .foregroundStyle(.secondary)
                    }
                }

                // Warnings
                ForEach(result.warnings, id: \.self) { warning in
                    HStack(alignment: .top, spacing: 8) {
                        Image(systemName: "info.circle")
                            .foregroundStyle(.blue)
                        Text(warning)
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                }
            }
        }
    }

    // MARK: - Footer

    private var footer: some View {
        HStack {
            if conversionResult != nil {
                Button("Back") {
                    conversionResult = nil
                }
                .accessibilityIdentifier("karabiner-import-back")
            }
            Spacer()
            if conversionResult != nil {
                let totalSelected = selectedCollectionIds.count + selectedAppKeymapIds.count + selectedLauncherIds.count
                Button("Import \(totalSelected) Item\(totalSelected == 1 ? "" : "s")") {
                    Task { await performImport() }
                }
                .buttonStyle(.borderedProminent)
                .disabled(totalSelected == 0)
                .accessibilityIdentifier("karabiner-import-button")
            }
        }
        .padding()
    }

    // MARK: - Helper Views

    private func summaryBanner(_ result: KarabinerConversionResult) -> some View {
        let converted = result.collections.count + result.appKeymaps.count + result.launcherMappings.count
        return HStack(spacing: 8) {
            Image(systemName: converted > 0 ? "checkmark.circle.fill" : "exclamationmark.triangle.fill")
                .foregroundStyle(converted > 0 ? .green : .orange)
            VStack(alignment: .leading) {
                Text("Profile: \(result.profileName)")
                    .fontWeight(.medium)
                Text("\(converted) converted, \(result.skippedRules.count) skipped")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
        .padding(10)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(converted > 0 ? Color.green.opacity(0.1) : Color.orange.opacity(0.1))
        .clipShape(.rect(cornerRadius: 8))
    }

    private func sectionHeader(_ title: String, count: Int) -> some View {
        HStack {
            Text(title)
                .font(.headline)
            Spacer()
            Text("\(count)")
                .font(.caption)
                .foregroundStyle(.secondary)
                .padding(.horizontal, 8)
                .padding(.vertical, 2)
                .background(Color.secondary.opacity(0.15))
                .clipShape(.capsule)
        }
    }

    private func checkboxRow(
        title: String,
        subtitle: String,
        icon: String,
        isSelected: Bool,
        action: @escaping () -> Void
    ) -> some View {
        Button(action: action) {
            HStack(spacing: 10) {
                Image(systemName: isSelected ? "checkmark.circle.fill" : "circle")
                    .foregroundStyle(isSelected ? .blue : .secondary)
                Image(systemName: icon)
                    .foregroundStyle(.secondary)
                    .frame(width: 20)
                VStack(alignment: .leading, spacing: 1) {
                    Text(title)
                        .font(.subheadline)
                        .fontWeight(.medium)
                    Text(subtitle)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
                Spacer()
            }
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .padding(.vertical, 4)
    }

    private func toggleSelection(_ id: UUID, in set: inout Set<UUID>) {
        if set.contains(id) {
            set.remove(id)
        } else {
            set.insert(id)
        }
    }

    // MARK: - Computed Properties

    private var canConvert: Bool {
        switch importSource {
        case .autoDetect:
            WizardSystemPaths.karabinerConfigExists
        case .file:
            selectedFileURL != nil
        case .paste:
            !pastedJSON.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
        }
    }

    // MARK: - Data Loading

    private func loadProfiles(source: ImportSource) {
        guard let data = loadData(source: source) else { return }
        do {
            profiles = try converterService.getProfiles(from: data)
            if selectedProfileIndex == nil {
                selectedProfileIndex = profiles.first(where: { $0.isSelected })?.index ?? profiles.first?.index
            }
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    private func loadData(source: ImportSource) -> Data? {
        switch source {
        case .autoDetect:
            let path = WizardSystemPaths.karabinerConfigPath
            return FileManager.default.contents(atPath: path)
        case .file:
            guard let url = selectedFileURL else { return nil }
            let accessing = url.startAccessingSecurityScopedResource()
            defer { if accessing { url.stopAccessingSecurityScopedResource() } }
            return try? Data(contentsOf: url)
        case .paste:
            return pastedJSON.data(using: .utf8)
        }
    }

    // MARK: - Conversion

    private func runConversion() async {
        isLoading = true
        errorMessage = nil

        guard let data = loadData(source: importSource) else {
            errorMessage = "Could not load configuration data"
            isLoading = false
            return
        }

        // Load profiles if not yet loaded
        if profiles.isEmpty {
            do {
                profiles = try converterService.getProfiles(from: data)
                if profiles.count > 1, selectedProfileIndex == nil {
                    selectedProfileIndex = profiles.first(where: { $0.isSelected })?.index ?? 0
                    isLoading = false
                    return // Let user pick profile
                }
            } catch {
                errorMessage = error.localizedDescription
                isLoading = false
                return
            }
        }

        do {
            let result = try converterService.convert(data: data, profileIndex: selectedProfileIndex)
            conversionResult = result

            // Select all by default
            selectedCollectionIds = Set(result.collections.map(\.id))
            selectedAppKeymapIds = Set(result.appKeymaps.map(\.id))
            selectedLauncherIds = Set(result.launcherMappings.map(\.id))
        } catch {
            errorMessage = error.localizedDescription
        }

        isLoading = false
    }

    // MARK: - Import

    private func performImport() async {
        guard let result = conversionResult else { return }
        var errors: [String] = []

        // Import selected collections
        for collection in result.collections where selectedCollectionIds.contains(collection.id) {
            await kanataManager.addRuleCollection(collection)
        }

        // Import selected app keymaps
        for keymap in result.appKeymaps where selectedAppKeymapIds.contains(keymap.id) {
            do {
                try await AppKeymapStore.shared.upsertKeymap(keymap)
            } catch {
                errors.append("App keymap '\(keymap.mapping.displayName)': \(error.localizedDescription)")
            }
        }

        // Import selected launcher mappings into the launcher collection
        let selectedLaunchers = result.launcherMappings.filter { selectedLauncherIds.contains($0.id) }
        if !selectedLaunchers.isEmpty {
            do {
                try await KarabinerConverterService.persistLauncherMappings(selectedLaunchers)
            } catch {
                errors.append("Launcher mappings: \(error.localizedDescription)")
            }
        }

        if !errors.isEmpty {
            errorMessage = "Some items failed to import: \(errors.joined(separator: "; "))"
        } else {
            dismiss()
        }
    }
}
