import SwiftUI

/// View for managing simple key mappings
struct SimpleModsView: View {
    @StateObject private var service: SimpleModsService
    @Environment(\.dismiss) private var dismiss
    @State private var searchText = ""
    @State private var uiError: String?
    @State private var selectedCategory: String?
    @State private var selectedTab: TabSelection = .installed
    @State private var showErrorMessage = false
    @State private var showSuccessMessage = false
    @State private var statusMessage = ""
    @State private var statusMessageTimer: DispatchWorkItem?
    @State private var previousMappingCount = 0

    enum TabSelection {
        case installed
        case available
    }

    init(configPath: String) {
        _service = StateObject(wrappedValue: SimpleModsService(configPath: configPath))
    }

    var body: some View {
        NavigationStack {
            VStack(spacing: 0) {
                // Tab selector
                HStack(spacing: 0) {
                    TabButton(
                        title: "Installed",
                        badge: service.installedMappings.count,
                        isSelected: selectedTab == .installed
                    ) {
                        selectedTab = .installed
                    }

                    TabButton(
                        title: "Available",
                        badge: service.availablePresets.count,
                        isSelected: selectedTab == .available
                    ) {
                        selectedTab = .available
                    }
                }
                .padding(.horizontal)
                .padding(.top, 8)

                // Search bar
                HStack {
                    Image(systemName: "magnifyingglass")
                        .foregroundColor(.secondary)
                    TextField("Search mappings...", text: $searchText)
                        .textFieldStyle(.plain)
                }
                .padding()
                .background(Color(NSColor.controlBackgroundColor))

                // Category filter (only for Available tab)
                if selectedTab == .available {
                    ScrollView(.horizontal, showsIndicators: false) {
                        HStack(spacing: 12) {
                            CategoryButton(
                                title: "All",
                                isSelected: selectedCategory == nil
                            ) {
                                selectedCategory = nil
                            }

                            ForEach(Array(service.getPresetsByCategory().keys.sorted()), id: \.self) { category in
                                CategoryButton(
                                    title: category,
                                    isSelected: selectedCategory == category
                                ) {
                                    selectedCategory = category
                                }
                            }
                        }
                        .padding(.horizontal)
                    }
                    .padding(.vertical, 8)
                }

                Divider()

                // Content
                if service.isApplying {
                    HStack {
                        ProgressView()
                            .scaleEffect(0.8)
                        Text("Applying changes...")
                            .font(.caption)
                            .foregroundColor(.secondary)
                    }
                    .padding()
                }

                ScrollView {
                    LazyVStack(alignment: .leading, spacing: 12) {
                        if selectedTab == .installed {
                            if filteredInstalledMappings.isEmpty {
                                VStack(spacing: 12) {
                                    EmptyStateView(
                                        icon: "keyboard",
                                        title: "No mappings installed",
                                        message: "Add mappings from the Available tab to get started."
                                    )

                                    Button(
                                        action: { selectedTab = .available },
                                        label: {
                                            HStack(spacing: 6) {
                                                Image(systemName: "arrow.right.circle")
                                                Text("Browse available presets")
                                            }
                                        }
                                    )
                                    .buttonStyle(.bordered)
                                    .accessibilityIdentifier("simple-mods-browse-presets-button")
                                    .accessibilityLabel("Browse available presets")
                                    .controlSize(.small)
                                }
                            } else {
                                ForEach(filteredInstalledMappings) { mapping in
                                    InstalledMappingRow(
                                        mapping: mapping,
                                        service: service
                                    )
                                }
                            }
                        } else {
                            if filteredAvailablePresets.isEmpty {
                                EmptyStateView(
                                    icon: "checkmark.circle",
                                    title: "All presets installed",
                                    message: "All available mappings are already in your config."
                                )
                            } else {
                                ForEach(filteredAvailablePresets) { preset in
                                    AvailablePresetRow(
                                        preset: preset,
                                        service: service
                                    )
                                }
                            }
                        }
                    }
                    .padding()
                }
            }
            .safeAreaInset(edge: .bottom, spacing: 0) {
                // Toast notification area (similar to ContentView)
                Group {
                    if showErrorMessage || showSuccessMessage {
                        StatusMessageView(message: statusMessage, isVisible: true)
                            .padding(.horizontal)
                            .padding(.bottom, 12)
                            .transition(.opacity)
                    } else {
                        Color.clear
                            .frame(height: 0)
                    }
                }
                .frame(height: (showErrorMessage || showSuccessMessage) ? 80 : 0)
                .animation(.easeInOut(duration: 0.25), value: showErrorMessage)
                .animation(.easeInOut(duration: 0.25), value: showSuccessMessage)
            }
            .navigationTitle("Simple Key Mappings")
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Done") {
                        dismiss()
                    }
                    .accessibilityIdentifier("simple-mods-done-button")
                    .accessibilityLabel("Done")
                }
            }
            .onAppear {
                // Set dependencies
                let viewModel = findViewModel()
                service.setDependencies(
                    kanataManager: viewModel.underlyingManager
                )

                // Load mappings
                do {
                    try service.load()
                    previousMappingCount = service.installedMappings.count
                } catch {
                    uiError = "Failed to load mappings: \(error.localizedDescription)"
                }
            }
            // Show toast notifications for errors and success
            .onChange(of: service.lastError) { _, newValue in
                if let error = newValue {
                    // Check if this is a rollback scenario
                    if let rollbackReason = service.lastRollbackReason {
                        let details = service.lastRollbackDetails ?? ""
                        let fullMessage = "❌ Configuration Error\n\(rollbackReason)\n\nDetails:\n\(details)"
                        showToast(fullMessage, isError: true)
                    } else {
                        showToast("❌ \(error)", isError: true)
                    }
                    uiError = error
                } else {
                    // Success - clear errors
                    uiError = nil
                    showErrorMessage = false
                }
            }
            .onChange(of: service.installedMappings.count) { oldCount, newCount in
                // Track previous count
                previousMappingCount = oldCount

                // Only show success toast if NOT a rollback (no error state)
                if service.lastError == nil, service.lastRollbackReason == nil {
                    // Switch to installed tab when a mapping is added
                    if newCount > oldCount, selectedTab == .available {
                        selectedTab = .installed
                        // Fetch last reload duration from TCP status for richer success message
                        Task {
                            let client = KanataTCPClient(port: 37001)
                            let status = try? await client.getStatus()

                            // FIX #1: Explicitly close connection to prevent file descriptor leak
                            await client.cancelInflightAndCloseConnection()

                            if let dur = status?.last_reload?.duration_ms {
                                showToast("✅ Mapping added (reload \(dur) ms)", isError: false)
                            } else {
                                showToast("✅ Mapping added successfully", isError: false)
                            }
                        }
                    } else if newCount < oldCount {
                        // Only show success if user-initiated (not rollback)
                        showToast("✅ Mapping removed successfully", isError: false)
                    }
                }
            }
            .onChange(of: service.lastRollbackReason) { _, rollbackReason in
                if let reason = rollbackReason {
                    // This is a rollback - show error toast with details
                    let details = service.lastRollbackDetails ?? "No additional details available"
                    let fullMessage =
                        "❌ Configuration Error\n\(reason)\n\nChanges have been rolled back.\n\n\(details)"
                    showToast(fullMessage, isError: true)
                }
            }
            .onChange(of: service.isApplying) { _, isApplying in
                // When applying starts, clear any existing messages
                if isApplying {
                    showErrorMessage = false
                    showSuccessMessage = false
                }
            }
        }
        .frame(width: 600, height: 500)
    }

    private var filteredInstalledMappings: [SimpleMapping] {
        var mappings = service.installedMappings

        // Filter by search
        if !searchText.isEmpty {
            mappings = mappings.filter { mapping in
                mapping.fromKey.localizedCaseInsensitiveContains(searchText)
                    || mapping.toKey.localizedCaseInsensitiveContains(searchText)
                    || service.getPresetsByCategory().values.flatMap { $0 }
                    .first(where: { $0.fromKey == mapping.fromKey && $0.toKey == mapping.toKey })?
                    .name.localizedCaseInsensitiveContains(searchText) ?? false
            }
        }

        return mappings
    }

    private var filteredAvailablePresets: [SimpleModPreset] {
        var presets = service.availablePresets

        // Filter by search
        if !searchText.isEmpty {
            presets = presets.filter { preset in
                preset.name.localizedCaseInsensitiveContains(searchText)
                    || preset.fromKey.localizedCaseInsensitiveContains(searchText)
                    || preset.toKey.localizedCaseInsensitiveContains(searchText)
                    || preset.description.localizedCaseInsensitiveContains(searchText)
            }
        }

        // Filter by category
        if let category = selectedCategory {
            presets = presets.filter { $0.category == category }
        }

        return presets
    }

    @EnvironmentObject private var kanataViewModel: KanataViewModel

    private func findViewModel() -> KanataViewModel {
        kanataViewModel
    }

    private func showToast(_ message: String, isError: Bool) {
        statusMessageTimer?.cancel()
        statusMessage = message
        showErrorMessage = isError
        showSuccessMessage = !isError

        // Auto-dismiss after duration
        let workItem = DispatchWorkItem {
            showErrorMessage = false
            showSuccessMessage = false
        }
        statusMessageTimer = workItem
        DispatchQueue.main.asyncAfter(deadline: .now() + (isError ? 5.0 : 3.0), execute: workItem)
    }
}

/// Tab button for switching between Installed and Available
private struct TabButton: View {
    let title: String
    let badge: Int
    let isSelected: Bool
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            HStack(spacing: 6) {
                Text(title)
                    .font(.headline)
                if badge > 0 {
                    Text("\(badge)")
                        .font(.caption2)
                        .padding(.horizontal, 6)
                        .padding(.vertical, 2)
                        .background(isSelected ? Color.white.opacity(0.3) : Color.secondary.opacity(0.2))
                        .cornerRadius(8)
                }
            }
            .frame(maxWidth: .infinity)
            .padding(.vertical, 8)
            .background(isSelected ? Color.accentColor : Color.clear)
            .foregroundColor(isSelected ? .white : .primary)
            .cornerRadius(8)
        }
        .buttonStyle(.plain)
        .accessibilityIdentifier("simple-mods-tab-button-\(title.lowercased().replacingOccurrences(of: " ", with: "-"))")
        .accessibilityLabel(title)
    }
}

/// Empty state view
private struct EmptyStateView: View {
    let icon: String
    let title: String
    let message: String

    var body: some View {
        VStack(spacing: 12) {
            Image(systemName: icon)
                .font(.system(size: 48))
                .foregroundColor(.secondary)
            Text(title)
                .font(.headline)
            Text(message)
                .font(.caption)
                .foregroundColor(.secondary)
                .multilineTextAlignment(.center)
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 40)
    }
}

/// Category filter button
private struct CategoryButton: View {
    let title: String
    let isSelected: Bool
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            Text(title)
                .font(.caption)
                .padding(.horizontal, 12)
                .padding(.vertical, 6)
                .background(isSelected ? Color.accentColor : Color(NSColor.controlBackgroundColor))
                .foregroundColor(isSelected ? .white : .primary)
                .cornerRadius(6)
        }
        .accessibilityIdentifier("simple-mods-category-button-\(title.lowercased().replacingOccurrences(of: " ", with: "-"))")
        .accessibilityLabel(title)
        .buttonStyle(.plain)
    }
}

/// Row for an installed mapping (with toggle and delete)
private struct InstalledMappingRow: View {
    let mapping: SimpleMapping
    @ObservedObject var service: SimpleModsService

    var body: some View {
        HStack {
            VStack(alignment: .leading, spacing: 6) {
                if let name = mappingDisplayName {
                    Text(name)
                        .font(.headline)
                }
                HStack(spacing: 8) {
                    KeyCapChip(text: mapping.fromKey)
                    Text("→")
                        .foregroundColor(.secondary)
                    KeyCapChip(text: mapping.toKey)
                }
            }

            Spacer()

            Toggle(
                "",
                isOn: Binding(
                    get: { mapping.enabled },
                    set: { newValue in
                        service.toggleMapping(id: mapping.id, enabled: newValue)
                    }
                )
            )
            .toggleStyle(.switch)
            .disabled(service.isApplying)
            .accessibilityIdentifier("simple-mods-mapping-toggle-\(mapping.id)")
            .accessibilityLabel("Toggle \(mapping.fromKey) → \(mapping.toKey)")

            Button(
                action: {
                    service.removeMapping(id: mapping.id)
                },
                label: {
                    Image(systemName: "trash")
                        .foregroundColor(.red)
                }
            )
            .buttonStyle(.plain)
            .disabled(service.isApplying)
            .accessibilityIdentifier("simple-mods-delete-button-\(mapping.id)")
            .accessibilityLabel("Delete mapping")
        }
        .padding()
        .background(Color(NSColor.controlBackgroundColor))
        .cornerRadius(8)
    }

    private var mappingDisplayName: String? {
        let presets = service.getPresetsByCategory().values.flatMap { $0 }
        if let name = presets.first(where: {
            $0.fromKey == mapping.fromKey && $0.toKey == mapping.toKey
        })?.name {
            // Hide trivial labels that just restate the mapping
            let trivial1 = "\(mapping.fromKey) → \(mapping.toKey)"
            let trivial2 = "\(mapping.fromKey) to \(mapping.toKey)"
            if name.caseInsensitiveCompare(trivial1) == .orderedSame
                || name.caseInsensitiveCompare(trivial2) == .orderedSame
            {
                return nil
            }
            return name
        }
        return nil
    }
}

/// Row for an available preset (with add button)
private struct AvailablePresetRow: View {
    let preset: SimpleModPreset
    @ObservedObject var service: SimpleModsService
    @State private var showConflictSheet = false
    @State private var conflictingMapping: SimpleMapping?

    var body: some View {
        HStack {
            VStack(alignment: .leading, spacing: 6) {
                if let title = titleText {
                    Text(title)
                        .font(.headline)
                }
                HStack(spacing: 8) {
                    KeyCapChip(text: preset.fromKey)
                    Text("→")
                        .foregroundColor(.secondary)
                    KeyCapChip(text: preset.toKey)
                }
                if let tip = helpfulDescription {
                    Text(tip)
                        .font(.caption)
                        .foregroundColor(.secondary)
                }
            }

            Spacer()

            Button(
                action: {
                    if let existing = service.installedMappings.first(where: {
                        $0.fromKey == preset.fromKey && $0.enabled && $0.toKey != preset.toKey
                    }) {
                        conflictingMapping = existing
                        showConflictSheet = true
                    } else {
                        service.addMapping(fromKey: preset.fromKey, toKey: preset.toKey, enabled: true)
                    }
                },
                label: {
                    HStack(spacing: 4) {
                        Image(systemName: "plus.circle.fill")
                        Text("Add")
                    }
                    .font(.caption)
                    .foregroundColor(.white)
                    .padding(.horizontal, 12)
                    .padding(.vertical, 6)
                    .background(Color.accentColor)
                    .cornerRadius(6)
                }
            )
            .buttonStyle(.plain)
            .disabled(service.isApplying)
            .accessibilityIdentifier("simple-mods-add-preset-button-\(preset.fromKey)")
            .accessibilityLabel("Add preset \(preset.fromKey) → \(preset.toKey)")
        }
        .padding()
        .background(Color(NSColor.controlBackgroundColor))
        .cornerRadius(8)
        .sheet(isPresented: $showConflictSheet) {
            if let existing = conflictingMapping {
                ConflictMappingDialog(
                    fromKey: preset.fromKey,
                    existingTo: existing.toKey,
                    newTo: preset.toKey,
                    onReplace: {
                        service.removeMapping(id: existing.id)
                        service.addMapping(fromKey: preset.fromKey, toKey: preset.toKey, enabled: true)
                        showConflictSheet = false
                    },
                    onKeep: {
                        showConflictSheet = false
                    }
                )
            }
        }
    }

    // MARK: - Display helpers

    private var titleText: String? {
        let trivial1 = "\(preset.fromKey) → \(preset.toKey)"
        let trivial2 = "\(preset.fromKey) to \(preset.toKey)"
        if preset.name.caseInsensitiveCompare(trivial1) == .orderedSame
            || preset.name.caseInsensitiveCompare(trivial2) == .orderedSame
        {
            return nil
        }
        return preset.name
    }

    private var helpfulDescription: String? {
        let desc = preset.description.trimmingCharacters(in: .whitespacesAndNewlines)
        if desc.isEmpty { return nil }

        // Hide if description just restates the mapping
        let mappingStrings = [
            "\(preset.fromKey) → \(preset.toKey)",
            "\(preset.fromKey)->\(preset.toKey)",
            "\(preset.fromKey) to \(preset.toKey)"
        ]
        if mappingStrings.contains(where: { desc.caseInsensitiveCompare($0) == .orderedSame }) {
            return nil
        }
        // If description contains both keys and nothing else meaningful, hide
        let lower = desc.lowercased()
        let tokens = [preset.fromKey.lowercased(), preset.toKey.lowercased()]
        let alnum = lower.replacingOccurrences(of: "[^a-z0-9 ]", with: "", options: .regularExpression)
        if tokens.allSatisfy({ alnum.contains($0) }), !lower.contains("useful"), !lower.contains("vim"),
           !lower.contains("tip"), !lower.contains("recommend")
        {
            return nil
        }
        return desc
    }
}

/// Visual dialog for resolving conflicting mappings
private struct ConflictMappingDialog: View {
    let fromKey: String
    let existingTo: String
    let newTo: String
    let onReplace: () -> Void
    let onKeep: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            Text("Conflicting mapping detected")
                .font(.title3)
                .bold()
            Text("You already have this key mapped. Choose which mapping to keep.")
                .foregroundColor(.secondary)
                .fixedSize(horizontal: false, vertical: true)

            HStack(spacing: 16) {
                mappingCard(title: "Existing", toKey: existingTo)
                mappingCard(title: "New", toKey: newTo)
            }

            HStack(spacing: 12) {
                Button("Replace with New", role: .destructive) { onReplace() }
                    .buttonStyle(.borderedProminent)
                    .accessibilityIdentifier("simple-mods-conflict-replace-button")
                    .accessibilityLabel("Replace with New")
                Button("Keep Existing") { onKeep() }
                    .buttonStyle(.bordered)
                    .accessibilityIdentifier("simple-mods-conflict-keep-button")
                    .accessibilityLabel("Keep Existing")
            }
            .padding(.top, 4)
        }
        .padding(20)
        .frame(minWidth: 480)
    }

    private func mappingCard(title: String, toKey: String) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(title)
                .font(.caption)
                .foregroundColor(.secondary)
            HStack(spacing: 8) {
                KeyCapChip(text: fromKey)
                Text("→").foregroundColor(.secondary)
                KeyCapChip(text: toKey)
            }
            .padding(10)
            .background(Color(NSColor.controlBackgroundColor))
            .cornerRadius(8)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }
}

// MARK: - KeyCap styling for key labels

struct KeyCapChip: View {
    let text: String
    @State private var isHovered = false

    var body: some View {
        Text(text)
            .font(.caption)
            .foregroundColor(isHovered ? Color(NSColor.windowBackgroundColor) : Color.primary)
            .padding(.horizontal, 8)
            .padding(.vertical, 4)
            .background(
                RoundedRectangle(cornerRadius: 6)
                    .fill(isHovered ? Color.primary : Color(NSColor.controlBackgroundColor))
            )
            .overlay(
                RoundedRectangle(cornerRadius: 6)
                    .stroke(Color.secondary.opacity(0.2), lineWidth: 1)
            )
            .onHover { hovering in
                isHovered = hovering
            }
    }
}

/// Small key chip showing letter above modifier symbol (for home row mods summary)
struct HomeRowKeyChipSmall: View {
    let letter: String
    let symbol: String
    @State private var isHovered = false

    var body: some View {
        VStack(spacing: 2) {
            Text(letter)
                .font(.system(size: 14, weight: .medium))
            if !symbol.isEmpty {
                Text(symbol)
                    .font(.system(size: 12))
                    .foregroundColor(isHovered ? Color(NSColor.windowBackgroundColor).opacity(0.8) : Color.secondary)
            }
        }
        .frame(width: 36, height: 40)
        .foregroundColor(isHovered ? Color(NSColor.windowBackgroundColor) : Color.primary)
        .background(
            RoundedRectangle(cornerRadius: 6)
                .fill(isHovered ? Color.primary : Color(NSColor.controlBackgroundColor))
        )
        .overlay(
            RoundedRectangle(cornerRadius: 6)
                .stroke(Color.secondary.opacity(0.2), lineWidth: 1)
        )
        .onHover { hovering in
            isHovered = hovering
            if hovering {
                NSCursor.pointingHand.push()
            } else {
                NSCursor.pop()
            }
        }
    }
}
