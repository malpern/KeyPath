import SwiftUI

/// View for managing simple key mappings
struct SimpleModsView: View {
    @StateObject private var service: SimpleModsService
    @Environment(\.dismiss) private var dismiss
    @State private var searchText = ""
    @State private var uiError: String? = nil
    @State private var selectedCategory: String? = nil
    @State private var selectedTab: TabSelection = .installed
    
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
                                EmptyStateView(
                                    icon: "keyboard",
                                    title: "No mappings installed",
                                    message: "Add mappings from the Available tab to get started."
                                )
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
                
                if let error = uiError ?? service.lastError {
                    HStack {
                        Image(systemName: "exclamationmark.triangle.fill")
                            .foregroundColor(.orange)
                        Text(error)
                            .font(.caption)
                            .foregroundColor(.secondary)
                    }
                    .padding()
                    .background(Color(NSColor.controlBackgroundColor))
                }
            }
            .navigationTitle("Simple Key Mappings")
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Done") {
                        dismiss()
                    }
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
                } catch {
                    uiError = "Failed to load mappings: \(error.localizedDescription)"
                }
            }
            .onChange(of: service.installedMappings.count) { oldCount, newCount in
                // Switch to installed tab when a mapping is added
                if newCount > oldCount && selectedTab == .available {
                    selectedTab = .installed
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
                mapping.fromKey.localizedCaseInsensitiveContains(searchText) ||
                mapping.toKey.localizedCaseInsensitiveContains(searchText) ||
                service.getPresetsByCategory().values.flatMap { $0 }
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
                preset.name.localizedCaseInsensitiveContains(searchText) ||
                preset.fromKey.localizedCaseInsensitiveContains(searchText) ||
                preset.toKey.localizedCaseInsensitiveContains(searchText) ||
                preset.description.localizedCaseInsensitiveContains(searchText)
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
        return kanataViewModel
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
        .buttonStyle(.plain)
    }
}

/// Row for an installed mapping (with toggle and delete)
private struct InstalledMappingRow: View {
    let mapping: SimpleMapping
    @ObservedObject var service: SimpleModsService
    
    var body: some View {
        HStack {
            VStack(alignment: .leading, spacing: 4) {
                Text(mappingName)
                    .font(.headline)
                Text("\(mapping.fromKey) → \(mapping.toKey)")
                    .font(.caption)
                    .foregroundColor(.secondary)
            }
            
            Spacer()
            
            Toggle("", isOn: Binding(
                get: { mapping.enabled },
                set: { newValue in
                    service.toggleMapping(id: mapping.id, enabled: newValue)
                }
            ))
            .toggleStyle(.switch)
            .disabled(service.isApplying)
            
            Button(action: {
                service.removeMapping(id: mapping.id)
            }) {
                Image(systemName: "trash")
                    .foregroundColor(.red)
            }
            .buttonStyle(.plain)
            .disabled(service.isApplying)
        }
        .padding()
        .background(Color(NSColor.controlBackgroundColor))
        .cornerRadius(8)
    }
    
    private var mappingName: String {
        let presets = service.getPresetsByCategory().values.flatMap { $0 }
        return presets.first(where: { $0.fromKey == mapping.fromKey && $0.toKey == mapping.toKey })?.name ?? "\(mapping.fromKey) → \(mapping.toKey)"
    }
}

/// Row for an available preset (with add button)
private struct AvailablePresetRow: View {
    let preset: SimpleModPreset
    @ObservedObject var service: SimpleModsService
    
    var body: some View {
        HStack {
            VStack(alignment: .leading, spacing: 4) {
                Text(preset.name)
                    .font(.headline)
                Text(preset.description)
                    .font(.caption)
                    .foregroundColor(.secondary)
                Text("\(preset.fromKey) → \(preset.toKey)")
                    .font(.caption2)
                    .foregroundColor(.secondary.opacity(0.7))
            }
            
            Spacer()
            
            Button(action: {
                service.addMapping(fromKey: preset.fromKey, toKey: preset.toKey, enabled: true)
            }) {
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
            .buttonStyle(.plain)
            .disabled(service.isApplying)
        }
        .padding()
        .background(Color(NSColor.controlBackgroundColor))
        .cornerRadius(8)
    }
}
