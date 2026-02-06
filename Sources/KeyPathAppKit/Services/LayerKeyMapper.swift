import Foundation
import KeyPathCore

/// Information about what a key does in a specific layer
struct LayerKeyInfo: Equatable, Sendable {
    /// What to show on the key (e.g., "←", "A", "⌘")
    let displayLabel: String
    /// Kanata key name for output (e.g., "left", "a", "leftmeta")
    let outputKey: String?
    /// Key code for the output key (for dual highlighting)
    let outputKeyCode: UInt16?
    /// Whether this key is transparent (falls through to lower layer)
    let isTransparent: Bool
    /// Whether this is a layer switch key
    let isLayerSwitch: Bool
    /// App identifier for launch action (bundle ID or app name)
    /// When set, overlay should show app icon instead of text
    let appLaunchIdentifier: String?
    /// System action identifier (e.g., "dnd", "spotlight")
    /// When set, overlay should show SF Symbol icon for the action
    let systemActionIdentifier: String?
    /// URL identifier for web URL mapping (e.g., "github.com", "https://example.com")
    /// When set, overlay should show favicon instead of text
    let urlIdentifier: String?
    /// Which collection this key belongs to (for color-coding in overlay)
    let collectionId: UUID?

    init(
        displayLabel: String,
        outputKey: String?,
        outputKeyCode: UInt16?,
        isTransparent: Bool,
        isLayerSwitch: Bool,
        appLaunchIdentifier: String? = nil,
        systemActionIdentifier: String? = nil,
        urlIdentifier: String? = nil,
        collectionId: UUID? = nil
    ) {
        self.displayLabel = displayLabel
        self.outputKey = outputKey
        self.outputKeyCode = outputKeyCode
        self.isTransparent = isTransparent
        self.isLayerSwitch = isLayerSwitch
        self.appLaunchIdentifier = appLaunchIdentifier
        self.systemActionIdentifier = systemActionIdentifier
        self.urlIdentifier = urlIdentifier
        self.collectionId = collectionId
    }

    /// Creates info for a normal key mapping
    static func mapped(displayLabel: String, outputKey: String, outputKeyCode: UInt16?, collectionId: UUID? = nil) -> LayerKeyInfo {
        LayerKeyInfo(
            displayLabel: displayLabel,
            outputKey: outputKey,
            outputKeyCode: outputKeyCode,
            isTransparent: false,
            isLayerSwitch: false,
            collectionId: collectionId
        )
    }

    /// Creates info for a transparent key
    static func transparent(fallbackLabel: String, collectionId: UUID? = nil) -> LayerKeyInfo {
        LayerKeyInfo(
            displayLabel: fallbackLabel,
            outputKey: nil,
            outputKeyCode: nil,
            isTransparent: true,
            isLayerSwitch: false,
            collectionId: collectionId
        )
    }

    /// Creates info for a layer switch key
    static func layerSwitch(displayLabel: String, collectionId: UUID? = nil) -> LayerKeyInfo {
        LayerKeyInfo(
            displayLabel: displayLabel,
            outputKey: nil,
            outputKeyCode: nil,
            isTransparent: false,
            isLayerSwitch: true,
            collectionId: collectionId
        )
    }

    /// Creates info for an app launch action
    /// - Parameter appIdentifier: The app name or bundle ID
    /// - Note: displayLabel is set to the app identifier for consumers that need text
    ///         (like Mapper), while appLaunchIdentifier enables icon rendering
    static func appLaunch(appIdentifier: String, collectionId: UUID? = nil) -> LayerKeyInfo {
        LayerKeyInfo(
            displayLabel: appIdentifier, // Use app name as display label
            outputKey: nil,
            outputKeyCode: nil,
            isTransparent: false,
            isLayerSwitch: false,
            appLaunchIdentifier: appIdentifier,
            collectionId: collectionId
        )
    }

    /// Creates info for a system action (DND, Spotlight, etc.)
    /// - Parameters:
    ///   - action: The system action name (e.g., "dnd", "spotlight")
    ///   - description: Human-readable description for display
    static func systemAction(action: String, description: String, collectionId: UUID? = nil) -> LayerKeyInfo {
        LayerKeyInfo(
            displayLabel: description,
            outputKey: nil,
            outputKeyCode: nil,
            isTransparent: false,
            isLayerSwitch: false,
            appLaunchIdentifier: nil,
            systemActionIdentifier: action,
            collectionId: collectionId
        )
    }

    /// Creates info for a generic push-msg action
    /// - Parameter message: The message content for display
    static func pushMsg(message: String, collectionId: UUID? = nil) -> LayerKeyInfo {
        LayerKeyInfo(
            displayLabel: message,
            outputKey: nil,
            outputKeyCode: nil,
            isTransparent: false,
            isLayerSwitch: false,
            appLaunchIdentifier: nil,
            collectionId: collectionId
        )
    }

    /// Creates info for a web URL action
    /// - Parameter url: The URL to open (e.g., "github.com", "https://example.com")
    /// - Note: displayLabel is set to the domain for text display,
    ///         while urlIdentifier enables favicon rendering
    static func webURL(url: String, collectionId: UUID? = nil) -> LayerKeyInfo {
        let displayDomain = extractDomain(from: url)
        return LayerKeyInfo(
            displayLabel: displayDomain,
            outputKey: nil,
            outputKeyCode: nil,
            isTransparent: false,
            isLayerSwitch: false,
            appLaunchIdentifier: nil,
            systemActionIdentifier: nil,
            urlIdentifier: url,
            collectionId: collectionId
        )
    }

    /// Extract domain from URL for display purposes
    /// - Parameter url: The full URL
    /// - Returns: Just the domain portion (e.g., "github.com" from "https://github.com/user/repo")
    private static func extractDomain(from url: String) -> String {
        let cleaned = URLMappingFormatter.decodeFromPushMessage(url)
            .replacingOccurrences(of: "https://", with: "")
            .replacingOccurrences(of: "http://", with: "")
        return cleaned.components(separatedBy: "/").first ?? url
    }
}

/// Service that builds key mappings for each layer using the kanata-simulator.
/// Maps physical key codes to what they output in each layer.
actor LayerKeyMapper {
    let simulatorService: SimulatorService
    var cache: [String: [UInt16: LayerKeyInfo]] = [:]
    var configHash: String = ""

    init(simulatorService: SimulatorService = SimulatorService()) {
        self.simulatorService = simulatorService
    }

    // MARK: - Public API

    /// Get the key mapping for a specific layer
    /// - Parameters:
    ///   - layer: The layer name (e.g., "base", "nav", "symbols")
    ///   - configPath: Path to the kanata config file
    ///   - layout: The physical keyboard layout to use for mapping
    ///   - collections: All rule collections (for tracking collection ownership)
    /// - Returns: Dictionary mapping physical key codes to their layer-specific info
    func getMapping(for layer: String, configPath: String, layout: PhysicalLayout, collections: [RuleCollection] = []) async throws -> [UInt16: LayerKeyInfo] {
        // Normalize layer name to lowercase for consistent cache keys
        let normalizedLayer = layer.lowercased()
        AppLogger.shared.info("🗺️ [LayerKeyMapper] getMapping called for layer '\(layer)' (normalized: '\(normalizedLayer)')")

        if !FeatureFlags.simulatorAndVirtualKeysEnabled {
            AppLogger.shared.info("🗺️ [LayerKeyMapper] Simulator disabled; using fallback mapping")
            let mapping = buildFallbackMapping(layout: layout)
            cache[normalizedLayer] = mapping
            return mapping
        }

        // Check if config changed (invalidate cache)
        let currentHash = try configFileHash(configPath)
        if currentHash != configHash {
            AppLogger.shared.debug("🗺️ [LayerKeyMapper] Config changed, clearing cache")
            cache.removeAll()
            configHash = currentHash
        }

        // Return cached if available (use normalized key)
        if let cached = cache[normalizedLayer] {
            AppLogger.shared.debug("🗺️ [LayerKeyMapper] Returning cached mapping (\(cached.count) keys)")
            return cached
        }

        AppLogger.shared.info("🗺️ [LayerKeyMapper] Building new mapping for '\(normalizedLayer)'...")

        // Build key→collection reverse index for collection ownership tracking
        let keyToCollection = buildKeyCollectionMap(for: normalizedLayer, collections: collections)
        let activatorKeys = buildActivatorKeySet(for: normalizedLayer, collections: collections)
        AppLogger.shared.debug("🗺️ [LayerKeyMapper] Built key→collection map: \(keyToCollection.count) keys")

        // Use batch simulation for accurate key mapping
        // This handles aliases, tap-hold, forks, macros, etc.
        let mapping = try await buildMappingWithSimulator(
            for: normalizedLayer,
            configPath: configPath,
            layout: layout,
            keyToCollection: keyToCollection,
            activatorKeys: activatorKeys
        )

        cache[normalizedLayer] = mapping
        AppLogger.shared.info("🗺️ [LayerKeyMapper] Built mapping: \(mapping.count) keys")
        return mapping
    }

    /// Invalidate all cached mappings (call when config changes)
    func invalidateCache() {
        cache.removeAll()
        configHash = ""
    }

    /// Pre-build mappings for all layers at once
    /// This should be called at startup to ensure instant layer switching
    /// - Parameters:
    ///   - layerNames: List of all layer names (from TCP RequestLayerNames)
    ///   - configPath: Path to the kanata config file
    ///   - layout: The physical keyboard layout to use for mapping
    ///   - collections: All rule collections (for tracking collection ownership)
    func prebuildAllLayers(_ layerNames: [String], configPath: String, layout: PhysicalLayout, collections: [RuleCollection] = []) async {
        // Normalize layer names to lowercase
        let normalizedLayers = layerNames.map { $0.lowercased() }
        AppLogger.shared.info("🗺️ [LayerKeyMapper] Pre-building mappings for \(normalizedLayers.count) layers: \(normalizedLayers.joined(separator: ", "))")

        if !FeatureFlags.simulatorAndVirtualKeysEnabled {
            let mapping = buildFallbackMapping(layout: layout)
            for layer in normalizedLayers {
                cache[layer] = mapping
            }
            AppLogger.shared.info("🗺️ [LayerKeyMapper] Simulator disabled; cached fallback mapping for \(normalizedLayers.count) layers")
            return
        }

        // Update config hash
        if let hash = try? configFileHash(configPath) {
            if hash != configHash {
                cache.removeAll()
                configHash = hash
            }
        }

        // Build mappings for all layers in parallel
        await withTaskGroup(of: (String, [UInt16: LayerKeyInfo]?).self) { group in
            for layer in normalizedLayers {
                group.addTask {
                    do {
                        // Build key→collection map for this layer
                        let keyToCollection = self.buildKeyCollectionMap(for: layer, collections: collections)
                        let activatorKeys = self.buildActivatorKeySet(for: layer, collections: collections)
                        let mapping = try await self.buildMappingWithSimulator(
                            for: layer,
                            configPath: configPath,
                            layout: layout,
                            keyToCollection: keyToCollection,
                            activatorKeys: activatorKeys
                        )
                        return (layer, mapping)
                    } catch {
                        AppLogger.shared.error("🗺️ [LayerKeyMapper] Failed to build mapping for '\(layer)': \(error)")
                        return (layer, nil)
                    }
                }
            }

            for await (layer, mapping) in group {
                if let mapping {
                    cache[layer] = mapping
                    AppLogger.shared.debug("🗺️ [LayerKeyMapper] Cached mapping for '\(layer)' (\(mapping.count) keys)")
                }
            }
        }

        AppLogger.shared.info("🗺️ [LayerKeyMapper] Pre-build complete: \(cache.count) layers cached")
    }

}
