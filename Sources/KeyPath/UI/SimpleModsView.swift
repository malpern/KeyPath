import SwiftUI

/// View for managing simple key mappings
struct SimpleModsView: View {
    @StateObject private var service: SimpleModsService
    @Environment(\.dismiss) private var dismiss
    @State private var searchText = ""
    @State private var selectedCategory: String? = nil
    
    init(configPath: String) {
        _service = StateObject(wrappedValue: SimpleModsService(configPath: configPath))
    }
    
    var body: some View {
        NavigationStack {
            VStack(spacing: 0) {
                // Search bar
                HStack {
                    Image(systemName: "magnifyingglass")
                        .foregroundColor(.secondary)
                    TextField("Search mappings...", text: $searchText)
                        .textFieldStyle(.plain)
                }
                .padding()
                .background(Color(NSColor.controlBackgroundColor))
                
                // Category filter
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
                
                Divider()
                
                // Mappings list
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
                        ForEach(filteredMappings) { mapping in
                            MappingRow(
                                mapping: mapping,
                                service: service
                            )
                        }
                    }
                    .padding()
                }
                
                if let error = service.lastError {
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
                    service.lastError = "Failed to load mappings: \(error.localizedDescription)"
                }
            }
        }
        .frame(width: 600, height: 500)
    }
    
    private var filteredMappings: [SimpleMapping] {
        var mappings = service.mappings
        
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
        
        // Filter by category
        if let category = selectedCategory {
            let presetKeys = Set(service.getPresetsByCategory()[category]?.map { "\($0.fromKey)->\($0.toKey)" } ?? [])
            mappings = mappings.filter { mapping in
                presetKeys.contains("\(mapping.fromKey)->\(mapping.toKey)")
            }
        }
        
        return mappings
    }
    
    @EnvironmentObject private var kanataViewModel: KanataViewModel
    
    private func findViewModel() -> KanataViewModel {
        return kanataViewModel
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

/// Row for a single mapping
private struct MappingRow: View {
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

