import Foundation
import KeyPathCore

/// Main service for managing simple modifications
@MainActor
public final class SimpleModsService: ObservableObject {
    @Published public private(set) var installedMappings: [SimpleMapping] = []
    @Published public private(set) var availablePresets: [SimpleModPreset] = []
    @Published public private(set) var conflicts: [MappingConflict] = []
    @Published public private(set) var isApplying = false
    @Published public private(set) var lastError: String?
    
    private let configPath: String
    private let parser: SimpleModsParser
    private let writer: SimpleModsWriter
    private let catalog = SimpleModsCatalog.shared
    
    // Debounce timer for instant apply
    private var applyDebounceTask: Task<Void, Never>?
    private let debounceDelay: TimeInterval = 0.3
    
    // Apply pipeline dependencies (will be injected)
    private var kanataManager: KanataManager?
    
    public init(configPath: String) {
        self.configPath = configPath
        self.parser = SimpleModsParser(configPath: configPath)
        self.writer = SimpleModsWriter(configPath: configPath)
    }
    
    /// Set dependencies for apply pipeline
    func setDependencies(
        kanataManager: KanataManager?
    ) {
        self.kanataManager = kanataManager
    }
    
    /// Load current mappings from config
    public func load() throws {
        let (block, allMappings, detectedConflicts) = try parser.parse()
        self.conflicts = detectedConflicts
        
        // Installed mappings are those that exist in the config file
        self.installedMappings = allMappings
        
        // Available presets are those NOT in the config file
        let installedKeys = Set(allMappings.map { "\($0.fromKey)->\($0.toKey)" })
        let allPresets = catalog.getAllPresets()
        self.availablePresets = allPresets.filter { preset in
            !installedKeys.contains("\(preset.fromKey)->\(preset.toKey)")
        }
        
        self.lastError = nil
    }
    
    /// Add a preset to the config (installed mappings)
    public func addMapping(fromKey: String, toKey: String, enabled: Bool = true) {
        // Check if already installed
        if installedMappings.contains(where: { $0.fromKey == fromKey && $0.toKey == toKey }) {
            lastError = "Mapping already installed"
            return
        }
        
        let newMapping = SimpleMapping(
            fromKey: fromKey,
            toKey: toKey,
            enabled: enabled,
            filePath: configPath
        )
        
        installedMappings.append(newMapping)
        
        // Remove from available presets
        availablePresets.removeAll { $0.fromKey == fromKey && $0.toKey == toKey }
        
        // Apply changes
        applyDebounceTask?.cancel()
        applyDebounceTask = Task {
            try? await Task.sleep(nanoseconds: UInt64(debounceDelay * 1_000_000_000))
            await applyChanges()
        }
    }
    
    /// Remove a mapping from the config entirely
    public func removeMapping(id: UUID) {
        guard let index = installedMappings.firstIndex(where: { $0.id == id }) else {
            return
        }
        
        let removed = installedMappings.remove(at: index)
        
        // Add back to available presets if it's a preset
        if let preset = catalog.findPreset(fromKey: removed.fromKey, toKey: removed.toKey) {
            availablePresets.append(preset)
        }
        
        // Apply changes
        applyDebounceTask?.cancel()
        applyDebounceTask = Task {
            try? await Task.sleep(nanoseconds: UInt64(debounceDelay * 1_000_000_000))
            await applyChanges()
        }
    }
    
    /// Toggle a mapping on/off with instant apply
    public func toggleMapping(id: UUID, enabled: Bool) {
        guard let index = installedMappings.firstIndex(where: { $0.id == id }) else {
            return
        }
        
        // Optimistic update
        installedMappings[index].enabled = enabled
        isApplying = true
        
        // Debounce apply
        applyDebounceTask?.cancel()
        applyDebounceTask = Task {
            try? await Task.sleep(nanoseconds: UInt64(debounceDelay * 1_000_000_000))
            await applyChanges()
        }
    }
    
    /// Apply current mappings to config
    private func applyChanges() async {
        defer {
            isApplying = false
        }
        
        do {
            // Generate effective config
            let effectiveContent = try writer.generateEffectiveConfig()
            
            // Validate config
            let validation = await validateConfig(effectiveContent)
            if !validation.isValid {
                // Revert mappings
                try? load()
                lastError = validation.errors.joined(separator: "; ")
                return
            }
            
            // Write block with only installed mappings
            try writer.writeBlock(mappings: installedMappings)
            
            // Reload Kanata via manager
            if let manager = kanataManager {
                await manager.triggerConfigReload()
            }
            
            // Health check
            if let manager = kanataManager {
                try? await Task.sleep(nanoseconds: 1_000_000_000) // 1s
                let isHealthy = manager.isRunning
                
                if !isHealthy {
                    // Rollback
                    try? load()
                    lastError = "Service health check failed"
                    return
                }
            }
            
            // Success - reload to get updated state
            try? load()
            lastError = nil
            
        } catch {
            // Rollback on error
            try? load()
            lastError = error.localizedDescription
        }
    }
    
    /// Validate config content
    private func validateConfig(_ content: String) async -> (isValid: Bool, errors: [String]) {
        // Use ConfigurationService validation
        let configService = ConfigurationService(configDirectory: (configPath as NSString).deletingLastPathComponent)
        return await configService.validateConfiguration(content)
    }
    
    /// Get presets by category
    public func getPresetsByCategory() -> [String: [SimpleModPreset]] {
        return catalog.getPresetsByCategory()
    }
}

