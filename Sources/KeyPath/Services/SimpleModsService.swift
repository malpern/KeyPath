import Foundation
import KeyPathCore

/// Main service for managing simple modifications
@MainActor
public final class SimpleModsService: ObservableObject {
    @Published public private(set) var mappings: [SimpleMapping] = []
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
    public func setDependencies(
        kanataManager: KanataManager?
    ) {
        self.kanataManager = kanataManager
    }
    
    /// Load current mappings from config
    public func load() throws {
        let (block, allMappings, detectedConflicts) = try parser.parse()
        self.conflicts = detectedConflicts
        
        // Merge presets with actual mappings
        var mergedMappings: [SimpleMapping] = []
        let presets = catalog.getAllPresets()
        
        for preset in presets {
            // Check if this preset is already mapped
            if let existing = allMappings.first(where: { $0.fromKey == preset.fromKey && $0.toKey == preset.toKey }) {
                mergedMappings.append(existing)
            } else {
                // Add as available but disabled
                mergedMappings.append(SimpleMapping(
                    fromKey: preset.fromKey,
                    toKey: preset.toKey,
                    enabled: false,
                    filePath: configPath
                ))
            }
        }
        
        // Add any custom mappings not in presets
        for mapping in allMappings {
            if !presets.contains(where: { $0.fromKey == mapping.fromKey && $0.toKey == mapping.toKey }) {
                mergedMappings.append(mapping)
            }
        }
        
        self.mappings = mergedMappings
        self.lastError = nil
    }
    
    /// Toggle a mapping on/off with instant apply
    public func toggleMapping(id: UUID, enabled: Bool) {
        guard let index = mappings.firstIndex(where: { $0.id == id }) else {
            return
        }
        
        // Optimistic update
        mappings[index].enabled = enabled
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
            
            // Write block with current mappings
            try writer.writeBlock(mappings: mappings)
            
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

