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
    @Published public private(set) var lastRollbackReason: String? // Tracks why a rollback occurred
    @Published public private(set) var lastRollbackDetails: String? // Additional diagnostic details

    private let configPath: String
    private let parser: SimpleModsParser
    private let writer: SimpleModsWriter
    private let catalog = SimpleModsCatalog.shared

    // Debounce timer for instant apply
    private var applyDebounceTask: Task<Void, Never>?
    private let debounceDelay: TimeInterval = 0.3

    // Apply pipeline dependencies (will be injected)
    private var kanataManager: RuntimeCoordinator?

    public init(configPath: String) {
        self.configPath = configPath
        parser = SimpleModsParser(configPath: configPath)
        writer = SimpleModsWriter(configPath: configPath)
    }

    /// Set dependencies for apply pipeline
    func setDependencies(
        kanataManager: RuntimeCoordinator?
    ) {
        self.kanataManager = kanataManager
    }

    /// Load current mappings from config
    public func load() throws {
        AppLogger.shared.log("📖 [SimpleMods] Loading mappings from config: \(configPath)")
        let (_, allMappings, detectedConflicts) = try parser.parse()
        conflicts = detectedConflicts

        AppLogger.shared.log("📖 [SimpleMods] Found \(allMappings.count) installed mapping(s)")
        if !detectedConflicts.isEmpty {
            AppLogger.shared.log("⚠️ [SimpleMods] Detected \(detectedConflicts.count) conflict(s)")
        }

        // Installed mappings are those that exist in the config file
        installedMappings = allMappings

        // Available presets are those NOT in the config file
        let installedKeys = Set(allMappings.map { "\($0.fromKey)->\($0.toKey)" })
        let allPresets = catalog.getAllPresets()
        availablePresets = allPresets.filter { preset in
            !installedKeys.contains("\(preset.fromKey)->\(preset.toKey)")
        }

        AppLogger.shared.log(
            "📖 [SimpleMods] Load complete: \(installedMappings.count) installed, \(availablePresets.count) available"
        )
        lastError = nil
        lastRollbackReason = nil
        lastRollbackDetails = nil
    }

    /// Add a preset to the config (installed mappings)
    public func addMapping(fromKey: String, toKey: String, enabled: Bool = true) {
        AppLogger.shared.log("➕ [SimpleMods] Add mapping: \(fromKey) → \(toKey) (enabled=\(enabled))")
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
        AppLogger.shared.log("🗑️ [SimpleMods] Remove mapping: \(removed.fromKey) → \(removed.toKey)")

        // Add back to available presets if it's a prese
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
        AppLogger.shared.log(
            "🔁 [SimpleMods] Toggle mapping: \(installedMappings[index].fromKey) → \(installedMappings[index].toKey) -> \(enabled ? "ON" : "OFF")"
        )
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
            AppLogger.shared.log("🔍 [SimpleMods] Validating effective config (pre-write)...")
            let validation = await validateConfig(effectiveContent)
            if !validation.isValid {
                AppLogger.shared.log(
                    "❌ [SimpleMods] Pre-write validation failed with \(validation.errors.count) error(s):")
                for (idx, error) in validation.errors.enumerated() {
                    AppLogger.shared.log("   Error \(idx + 1): \(error)")
                }
                // Revert mappings
                let beforeCount = installedMappings.count
                try? load()
                let afterCount = installedMappings.count

                // Format detailed error message
                let errorDetails = validation.errors.enumerated().map { "\($0.offset + 1). \($0.element)" }
                    .joined(separator: "\n")
                lastError = "Configuration validation failed"
                lastRollbackReason = "Pre-write validation failed"
                lastRollbackDetails = "\(validation.errors.count) error(s) detected:\n\(errorDetails)"

                if beforeCount != afterCount {
                    AppLogger.shared.log(
                        "↩️ [SimpleMods] Rolled back from \(beforeCount) to \(afterCount) mapping(s) due to validation failure"
                    )
                }
                return
            }
            AppLogger.shared.log("✅ [SimpleMods] Pre-write validation passed")

            // Snapshot original file for rollback
            let originalContent: String? = {
                if FileManager.default.fileExists(atPath: configPath) {
                    return try? String(contentsOfFile: configPath, encoding: .utf8)
                }
                return nil
            }()

            // Write block with only installed mappings
            try writer.writeBlock(mappings: installedMappings)
            AppLogger.shared.log(
                "✅ [SimpleMods] Wrote \(installedMappings.count) mapping(s) to sentinel block")

            // Post-write CLI validation on the actual file to catch any syntax issues immediately
            if let manager = kanataManager {
                AppLogger.shared.log("🔍 [SimpleMods] Post-write CLI validation on actual file...")
                let postWriteValidation = await manager.validateConfigFile()
                if !postWriteValidation.isValid {
                    AppLogger.shared.log(
                        "❌ [SimpleMods] Post-write CLI validation failed with \(postWriteValidation.errors.count) error(s):"
                    )
                    for (idx, error) in postWriteValidation.errors.enumerated() {
                        AppLogger.shared.log("   Error \(idx + 1): \(error)")
                    }

                    // Track mapping count before rollback
                    let beforeCount = installedMappings.count

                    // Roll back file conten
                    if let original = originalContent {
                        try original.write(toFile: configPath, atomically: true, encoding: .utf8)
                        AppLogger.shared.log("↩️ [SimpleMods] Rolled back config file to original content")
                    }
                    try? load()
                    let afterCount = installedMappings.count

                    // Format detailed error message with diagnostic info
                    let errorDetails = postWriteValidation.errors.enumerated().map {
                        "\($0.offset + 1). \($0.element)"
                    }.joined(separator: "\n")
                    let diagnosticInfo = """
                    Config file: \(configPath)
                    Mappings before: \(beforeCount)
                    Mappings after rollback: \(afterCount)
                    Validation errors:
                    \(errorDetails)
                    """

                    lastError = "Configuration validation failed"
                    lastRollbackReason = "Post-write CLI validation failed"
                    lastRollbackDetails = diagnosticInfo

                    if beforeCount != afterCount {
                        AppLogger.shared.log(
                            "↩️ [SimpleMods] Rolled back from \(beforeCount) to \(afterCount) mapping(s) due to validation failure"
                        )
                    }
                    AppLogger.shared.log("❌ [SimpleMods] Post-write validation failed - changes rolled back")
                    return
                }
                AppLogger.shared.log("✅ [SimpleMods] Post-write CLI validation passed")
            }

            // Reload Kanata via manager
            if let manager = kanataManager {
                AppLogger.shared.log("🔄 [SimpleMods] Triggering Kanata config reload...")
                _ = await manager.triggerConfigReload()
                AppLogger.shared.log("✅ [SimpleMods] Config reload triggered")
                // Ensure any previous configuration diagnostics are cleared
                manager.clearDiagnostics()
            }

            // Health check
            if let manager = kanataManager {
                AppLogger.shared.log("🏥 [SimpleMods] Health check after reload...")
                try? await Task.sleep(nanoseconds: 1_000_000_000) // 1s

                // Check if service is running using InstallerEngine
                let engine = InstallerEngine()
                let context = await engine.inspectSystem()
                let isHealthy = context.services.kanataRunning

                if !isHealthy {
                    AppLogger.shared.log("⚠️ [SimpleMods] Health check failed - Kanata not running")
                    // Track mapping count before rollback
                    let beforeCount = installedMappings.count
                    // Rollback
                    try? load()
                    let afterCount = installedMappings.count

                    lastError = "Service health check failed"
                    lastRollbackReason = "Kanata service stopped after config reload"
                    lastRollbackDetails = """
                    Kanata service is not running after config reload.
                    This may indicate a configuration issue that caused Kanata to crash.
                    Mappings before: \(beforeCount)
                    Mappings after rollback: \(afterCount)
                    """

                    if beforeCount != afterCount {
                        AppLogger.shared.log(
                            "↩️ [SimpleMods] Rolled back from \(beforeCount) to \(afterCount) mapping(s) due to health check failure"
                        )
                    }
                    return
                }
                AppLogger.shared.log("✅ [SimpleMods] Health check passed - Kanata running")
            }

            // Success - reload to get updated state
            try? load()
            lastError = nil
            lastRollbackReason = nil
            lastRollbackDetails = nil
            AppLogger.shared.log(
                "✅ [SimpleMods] Apply succeeded - \(installedMappings.count) mapping(s) active")

        } catch {
            AppLogger.shared.log("❌ [SimpleMods] Apply error: \(error.localizedDescription)")
            AppLogger.shared.log("   Error type: \(type(of: error))")
            if let nsError = error as NSError? {
                AppLogger.shared.log("   Error domain: \(nsError.domain), code: \(nsError.code)")
            }
            // Track mapping count before rollback
            let beforeCount = installedMappings.count
            // Rollback on error
            try? load()
            let afterCount = installedMappings.count

            lastError = "Unexpected error occurred"
            lastRollbackReason = "Exception during apply"
            lastRollbackDetails = """
            Error: \(error.localizedDescription)
            Error type: \(type(of: error))
            Mappings before: \(beforeCount)
            Mappings after rollback: \(afterCount)
            """

            if beforeCount != afterCount {
                AppLogger.shared.log(
                    "↩️ [SimpleMods] Rolled back from \(beforeCount) to \(afterCount) mapping(s) due to exception"
                )
            }
        }
    }

    /// Validate config conten
    private func validateConfig(_ content: String) async -> (isValid: Bool, errors: [String]) {
        // Use ConfigurationService validation
        let configService = ConfigurationService(
            configDirectory: (configPath as NSString).deletingLastPathComponent)
        return await configService.validateConfiguration(content)
    }

    /// Get presets by category
    public func getPresetsByCategory() -> [String: [SimpleModPreset]] {
        catalog.getPresetsByCategory()
    }
}
