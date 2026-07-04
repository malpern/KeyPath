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
    /// Short vim-language label for overlay keycaps (e.g., "yank", "put", "d")
    /// When set, overlay prefers this over displayLabel for VIM layer keys
    let vimLabel: String?
    /// Custom shifted output label (overrides the system default shift symbol on the keycap)
    let customShiftLabel: String?

    init(
        displayLabel: String,
        outputKey: String?,
        outputKeyCode: UInt16?,
        isTransparent: Bool,
        isLayerSwitch: Bool,
        appLaunchIdentifier: String? = nil,
        systemActionIdentifier: String? = nil,
        urlIdentifier: String? = nil,
        collectionId: UUID? = nil,
        vimLabel: String? = nil,
        customShiftLabel: String? = nil
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
        self.vimLabel = vimLabel
        self.customShiftLabel = customShiftLabel
    }

    /// Creates info for a normal key mapping
    static func mapped(displayLabel: String, outputKey: String, outputKeyCode: UInt16?, collectionId: UUID? = nil, vimLabel: String? = nil) -> LayerKeyInfo {
        LayerKeyInfo(
            displayLabel: displayLabel,
            outputKey: outputKey,
            outputKeyCode: outputKeyCode,
            isTransparent: false,
            isLayerSwitch: false,
            collectionId: collectionId,
            vimLabel: vimLabel
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

struct SimulationReport: Sendable {
    let layerName: String
    let totalKeys: Int
    let failedKeys: [FailedSimKey]
    let configPath: String

    struct FailedSimKey: Sendable {
        let keyCode: UInt16
        let kanataName: String
    }

    var failureCount: Int {
        failedKeys.count
    }

    var hasSignificantFailures: Bool {
        failedKeys.count > 5
    }

    func copyableText() -> String {
        var lines: [String] = []
        lines.append("## Kanata Simulator Failure Report")
        lines.append("Layer: \(layerName)")
        lines.append("Config: \(configPath)")
        lines.append("Result: \(failedKeys.count)/\(totalKeys) keys failed simulation")
        lines.append("")
        lines.append("### Failed keys")
        for key in failedKeys {
            lines.append("- keyCode \(key.keyCode) (\(key.kanataName))")
        }
        lines.append("")
        lines.append("### What this means")
        lines.append("The kanata-simulator could not resolve what these keys output on the '\(layerName)' layer.")
        lines.append("Overlay icons for these keys will fall back to zone subtitles or base-layer labels.")
        lines.append("The sim command format is: `ls:\(layerName) d:<key> t:50 u:<key> t:250`")
        return lines.joined(separator: "\n")
    }
}

/// Service that builds key mappings for each layer using the kanata-simulator.
/// Maps physical key codes to what they output in each layer.
actor LayerKeyMapper {
    static let shared = LayerKeyMapper()

    let simulatorService: SimulatorService
    var cache: [String: [UInt16: LayerKeyInfo]] = [:]
    var configHash: String = ""
    /// Injectable feature-flag check. Defaults to the persisted flag; tests inject a
    /// constant so simulator integration tests never depend on process-global
    /// UserDefaults state that other test classes may mutate (#896).
    let simulatorEnabled: @Sendable () -> Bool

    init(
        simulatorService: SimulatorService = SimulatorService(),
        simulatorEnabled: @escaping @Sendable () -> Bool = { FeatureFlags.simulatorAndVirtualKeysEnabled }
    ) {
        self.simulatorService = simulatorService
        self.simulatorEnabled = simulatorEnabled
    }

    // MARK: - Public API

    /// Get the key mapping for a specific layer
    /// - Parameters:
    ///   - layer: The layer name (e.g., "base", "nav", "symbols")
    ///   - configPath: Path to the kanata config file
    ///   - layout: The physical keyboard layout to use for mapping
    ///   - collections: All rule collections (for tracking collection ownership)
    ///   - cacheKeySuffix: Optional cache partition key for context-dependent mapping views
    /// - Returns: Dictionary mapping physical key codes to their layer-specific info
    func getMapping(
        for layer: String,
        configPath: String,
        layout: PhysicalLayout,
        collections: [RuleCollection] = [],
        cacheKeySuffix: String = "default"
    ) async throws -> (mapping: [UInt16: LayerKeyInfo], report: SimulationReport?) {
        // Normalize layer name to lowercase for consistent cache keys
        let normalizedLayer = layer.lowercased()
        let cacheKey = "\(normalizedLayer)|\(cacheKeySuffix)"
        AppLogger.shared
            .info("🗺️ [LayerKeyMapper] getMapping called for layer '\(layer)' (normalized: '\(normalizedLayer)', cacheKeySuffix: '\(cacheKeySuffix)')")

        if !simulatorEnabled() {
            AppLogger.shared.info("🗺️ [LayerKeyMapper] Simulator disabled; using fallback mapping")
            let mapping = buildFallbackMapping(layout: layout)
            cache[cacheKey] = mapping
            return (mapping, nil)
        }

        // Check if config changed (invalidate cache)
        let currentHash = try configFileHash(configPath)
        if currentHash != configHash {
            AppLogger.shared.debug("🗺️ [LayerKeyMapper] Config changed, clearing cache")
            cache.removeAll()
            configHash = currentHash
        }

        if let cached = cache[cacheKey] {
            AppLogger.shared.debug("🗺️ [LayerKeyMapper] Returning cached mapping (\(cached.count) keys)")
            return (cached, nil)
        }

        AppLogger.shared.info("🗺️ [LayerKeyMapper] Building new mapping for '\(normalizedLayer)'...")

        // Build key→collection reverse index for collection ownership tracking
        let keyToCollection = buildKeyCollectionMap(for: normalizedLayer, collections: collections)
        let activatorKeys = buildActivatorKeySet(for: normalizedLayer, collections: collections)
        let keyToVimLabel = buildKeyVimLabelMap(for: normalizedLayer, collections: collections)
        AppLogger.shared.debug("🗺️ [LayerKeyMapper] Built key→collection map: \(keyToCollection.count) keys")

        let (mapping, report) = try await buildMappingWithSimulator(
            for: normalizedLayer,
            configPath: configPath,
            layout: layout,
            keyToCollection: keyToCollection,
            activatorKeys: activatorKeys,
            keyToVimLabel: keyToVimLabel
        )

        cache[cacheKey] = mapping
        AppLogger.shared.info("🗺️ [LayerKeyMapper] Built mapping: \(mapping.count) keys")
        return (mapping, report)
    }

    /// Return a cached mapping if available, nil otherwise.
    func getCachedMapping(for layer: String, cacheKeySuffix: String = "neovim-scope-fallback") -> [UInt16: LayerKeyInfo]? {
        cache["\(layer.lowercased())|\(cacheKeySuffix)"]
    }

    /// Invalidate all cached mappings (call when config changes)
    func invalidateCache() {
        cache.removeAll()
        configHash = ""
    }

    /// Pre-build mappings for all layers at once, populating both neovim-scope cache partitions.
    /// Call after layer names and rule collections are available to ensure instant layer switching.
    /// - Parameters:
    ///   - layerNames: List of all layer names (e.g. from rule collections or TCP RequestLayerNames)
    ///   - configPath: Path to the kanata config file
    ///   - layout: The physical keyboard layout to use for mapping
    ///   - allEnabledCollections: All enabled rule collections
    func prebuildAllLayers(
        _ layerNames: [String],
        configPath: String,
        layout: PhysicalLayout,
        allEnabledCollections: [RuleCollection] = []
    ) async {
        let normalizedLayers = layerNames.map { $0.lowercased() }
        AppLogger.shared.info("🗺️ [LayerKeyMapper] Pre-building mappings for \(normalizedLayers.count) layers: \(normalizedLayers.joined(separator: ", "))")

        if !simulatorEnabled() {
            let mapping = buildFallbackMapping(layout: layout)
            for layer in normalizedLayers {
                cache["\(layer)|default"] = mapping
                cache["\(layer)|neovim-scope-approved"] = mapping
                cache["\(layer)|neovim-scope-fallback"] = mapping
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

        let collectionsWithoutNeovim = allEnabledCollections.filter { $0.id != RuleCollectionIdentifier.neovimTerminal }
        let hasNeovimCollection = allEnabledCollections.contains { $0.id == RuleCollectionIdentifier.neovimTerminal }

        // Build both neovim scope variants for each layer in parallel.
        // Each task returns (layer, suffix, mapping) so we store with the correct composite key.
        await withTaskGroup(of: (String, String, [UInt16: LayerKeyInfo]?).self) { group in
            for layer in normalizedLayers {
                // Fallback variant (no neovim collection)
                group.addTask {
                    do {
                        let keyToCollection = self.buildKeyCollectionMap(for: layer, collections: collectionsWithoutNeovim)
                        let activatorKeys = self.buildActivatorKeySet(for: layer, collections: collectionsWithoutNeovim)
                        let keyToVimLabel = self.buildKeyVimLabelMap(for: layer, collections: collectionsWithoutNeovim)
                        let (mapping, _) = try await self.buildMappingWithSimulator(
                            for: layer,
                            configPath: configPath,
                            layout: layout,
                            keyToCollection: keyToCollection,
                            activatorKeys: activatorKeys,
                            keyToVimLabel: keyToVimLabel
                        )
                        return (layer, "neovim-scope-fallback", mapping)
                    } catch {
                        AppLogger.shared.error("🗺️ [LayerKeyMapper] Failed to build fallback mapping for '\(layer)': \(error)")
                        return (layer, "neovim-scope-fallback", nil)
                    }
                }

                // Approved variant (with neovim collection) — only if the collection exists
                if hasNeovimCollection {
                    group.addTask {
                        do {
                            let keyToCollection = self.buildKeyCollectionMap(for: layer, collections: allEnabledCollections)
                            let activatorKeys = self.buildActivatorKeySet(for: layer, collections: allEnabledCollections)
                            let keyToVimLabel = self.buildKeyVimLabelMap(for: layer, collections: allEnabledCollections)
                            let (mapping, _) = try await self.buildMappingWithSimulator(
                                for: layer,
                                configPath: configPath,
                                layout: layout,
                                keyToCollection: keyToCollection,
                                activatorKeys: activatorKeys,
                                keyToVimLabel: keyToVimLabel
                            )
                            return (layer, "neovim-scope-approved", mapping)
                        } catch {
                            AppLogger.shared.error("🗺️ [LayerKeyMapper] Failed to build approved mapping for '\(layer)': \(error)")
                            return (layer, "neovim-scope-approved", nil)
                        }
                    }
                }
            }

            for await (layer, suffix, mapping) in group {
                if let mapping {
                    cache["\(layer)|\(suffix)"] = mapping
                    AppLogger.shared.debug("🗺️ [LayerKeyMapper] Cached mapping for '\(layer)|\(suffix)' (\(mapping.count) keys)")
                }
            }
        }

        AppLogger.shared.info("🗺️ [LayerKeyMapper] Pre-build complete: \(cache.count) cache entries")
    }
}
