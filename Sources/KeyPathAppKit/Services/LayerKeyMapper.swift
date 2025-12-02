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

    /// Creates info for a normal key mapping
    static func mapped(displayLabel: String, outputKey: String, outputKeyCode: UInt16?) -> LayerKeyInfo {
        LayerKeyInfo(
            displayLabel: displayLabel,
            outputKey: outputKey,
            outputKeyCode: outputKeyCode,
            isTransparent: false,
            isLayerSwitch: false
        )
    }

    /// Creates info for a transparent key
    static func transparent(fallbackLabel: String) -> LayerKeyInfo {
        LayerKeyInfo(
            displayLabel: fallbackLabel,
            outputKey: nil,
            outputKeyCode: nil,
            isTransparent: true,
            isLayerSwitch: false
        )
    }

    /// Creates info for a layer switch key
    static func layerSwitch(displayLabel: String) -> LayerKeyInfo {
        LayerKeyInfo(
            displayLabel: displayLabel,
            outputKey: nil,
            outputKeyCode: nil,
            isTransparent: false,
            isLayerSwitch: true
        )
    }
}

/// Service that builds key mappings for each layer using the kanata-simulator.
/// Maps physical key codes to what they output in each layer.
actor LayerKeyMapper {
    private let simulatorService: SimulatorService
    private var cache: [String: [UInt16: LayerKeyInfo]] = [:]
    private var configHash: String = ""

    init(simulatorService: SimulatorService = SimulatorService()) {
        self.simulatorService = simulatorService
    }

    // MARK: - Public API

    /// Get the key mapping for a specific layer
    /// - Parameters:
    ///   - layer: The layer name (e.g., "base", "nav", "symbols")
    ///   - configPath: Path to the kanata config file
    /// - Returns: Dictionary mapping physical key codes to their layer-specific info
    func getMapping(for layer: String, configPath: String) async throws -> [UInt16: LayerKeyInfo] {
        // Normalize layer name to lowercase for consistent cache keys
        let normalizedLayer = layer.lowercased()
        AppLogger.shared.info("🗺️ [LayerKeyMapper] getMapping called for layer '\(layer)' (normalized: '\(normalizedLayer)')")

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

        // Use batch simulation for accurate key mapping
        // This handles aliases, tap-hold, forks, macros, etc.
        let mapping = try await buildMappingWithSimulator(for: normalizedLayer, configPath: configPath)

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
    func prebuildAllLayers(_ layerNames: [String], configPath: String) async {
        // Normalize layer names to lowercase
        let normalizedLayers = layerNames.map { $0.lowercased() }
        AppLogger.shared.info("🗺️ [LayerKeyMapper] Pre-building mappings for \(normalizedLayers.count) layers: \(normalizedLayers.joined(separator: ", "))")

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
                        let mapping = try await self.buildMappingWithSimulator(for: layer, configPath: configPath)
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

    // MARK: - Key Mapping via Simulator

    /// Build mapping using simulator's --key-mapping mode
    /// This is fast (~50ms) and accurate - handles aliases, tap-hold, forks, macros, etc.
    /// The new --key-mapping mode provides direct input→outputs pairs, eliminating
    /// the need for fragile timestamp-based correlation.
    private func buildMappingWithSimulator(for layer: String, configPath: String) async throws -> [UInt16: LayerKeyInfo] {
        var mapping: [UInt16: LayerKeyInfo] = [:]

        // Get all physical keys from the layout
        let physicalKeys = PhysicalLayout.macBookUS.keys
            .filter { $0.keyCode != 0xFFFF } // Skip Touch ID
            .filter { !OverlayKeyboardView.keyCodeToKanataName($0.keyCode).starts(with: "unknown") }

        // Build a single sim file with all keys
        var simParts: [String] = []
        var keyCodeByKanataName: [String: (keyCode: UInt16, label: String)] = [:]

        for key in physicalKeys {
            let tcpName = OverlayKeyboardView.keyCodeToKanataName(key.keyCode)
            let simName = toSimulatorKeyName(tcpName)
            keyCodeByKanataName[simName.uppercased()] = (key.keyCode, key.label)

            // press, wait 50ms, release
            simParts.append("d:\(simName) t:50 u:\(simName)")
        }

        let simContent = simParts.joined(separator: " ")
        AppLogger.shared.debug("🗺️ [LayerKeyMapper] Simulating \(physicalKeys.count) keys with --key-mapping for layer '\(layer)'...")

        // Run simulation with --key-mapping mode
        let startLayer = layer.lowercased() == "base" ? "base" : layer.lowercased()
        let result: SimulatorKeyMappingResult
        do {
            result = try await simulatorService.simulateKeyMapping(
                simContent: simContent,
                configPath: configPath,
                startLayer: startLayer
            )
        } catch {
            AppLogger.shared.error("🗺️ [LayerKeyMapper] Simulation failed: \(error)")
            // Fall back to physical labels
            for key in physicalKeys {
                mapping[key.keyCode] = LayerKeyInfo(
                    displayLabel: key.label,
                    outputKey: nil,
                    outputKeyCode: nil,
                    isTransparent: false,
                    isLayerSwitch: false
                )
            }
            return mapping
        }

        // Process each key mapping from the result
        for keyMapping in result.mappings {
            // Look up keyCode from input name
            guard let (keyCode, fallbackLabel) = keyCodeByKanataName[keyMapping.input.uppercased()] else {
                AppLogger.shared.debug("🗺️ [LayerKeyMapper] Unknown input key: \(keyMapping.input)")
                continue
            }

            if keyMapping.transparent {
                // Key passes through unchanged
                mapping[keyCode] = .transparent(fallbackLabel: fallbackLabel)
            } else if keyMapping.outputs.isEmpty {
                // No output (blocked key)
                mapping[keyCode] = .transparent(fallbackLabel: fallbackLabel)
            } else {
                // Convert all outputs to display labels and combine
                var displayParts: [String] = []
                var primaryOutputKey: String? = nil
                var primaryOutputKeyCode: UInt16? = nil

                for output in keyMapping.outputs {
                    let label = kanataKeyToDisplayLabel(output)
                    displayParts.append(label)
                    // Use the non-modifier key as the primary (for dual highlighting)
                    if !isModifierSymbol(output) {
                        primaryOutputKey = output
                        primaryOutputKeyCode = kanataKeyToKeyCode(output)
                    }
                }

                let combinedLabel = displayParts.joined()
                let outputKey = primaryOutputKey ?? keyMapping.outputs.first

                if let outputKey {
                    mapping[keyCode] = .mapped(
                        displayLabel: combinedLabel,
                        outputKey: outputKey,
                        outputKeyCode: primaryOutputKeyCode
                    )
                    if outputKey.uppercased() != keyMapping.input.uppercased() {
                        AppLogger.shared.debug("🗺️ [LayerKeyMapper] Mapped \(keyMapping.input)(\(keyCode)) -> \(outputKey)(\(combinedLabel))")
                    }
                } else {
                    mapping[keyCode] = LayerKeyInfo(
                        displayLabel: combinedLabel,
                        outputKey: nil,
                        outputKeyCode: nil,
                        isTransparent: false,
                        isLayerSwitch: false
                    )
                }
            }
        }

        // Fill in any missing keys with their physical labels
        for key in physicalKeys where mapping[key.keyCode] == nil {
            mapping[key.keyCode] = LayerKeyInfo(
                displayLabel: key.label,
                outputKey: nil,
                outputKeyCode: nil,
                isTransparent: false,
                isLayerSwitch: false
            )
        }

        return mapping
    }

    // MARK: - Key Name Conversion

    /// Convert TCP key name (from OverlayKeyboardView.keyCodeToKanataName) to simulator-compatible name
    /// The simulator uses abbreviated names like "min" instead of "minus"
    private func toSimulatorKeyName(_ tcpName: String) -> String {
        switch tcpName.lowercased() {
        // Punctuation keys use abbreviated names in simulator
        case "minus": return "min"
        case "equal": return "eql"
        case "grave": return "grv"
        case "backslash": return "bksl"
        case "leftbrace": return "lbrc"
        case "rightbrace": return "rbrc"
        case "semicolon": return "scln"
        case "apostrophe": return "apos"
        case "comma": return "comm"
        case "dot": return "."
        case "slash": return "/"

        // Modifiers
        case "leftshift": return "lsft"
        case "rightshift": return "rsft"
        case "leftmeta": return "lmet"
        case "rightmeta": return "rmet"
        case "leftalt": return "lalt"
        case "rightalt": return "ralt"
        case "leftctrl": return "lctl"
        case "rightctrl": return "rctl"
        case "capslock": return "caps"

        // Special keys
        case "backspace": return "bspc"
        case "enter": return "ret"
        case "space": return "spc"
        case "escape": return "esc"

        default:
            return tcpName
        }
    }

    /// Convert Kanata key name to display label
    private func kanataKeyToDisplayLabel(_ kanataKey: String) -> String {
        switch kanataKey.lowercased() {
        // Letters
        case let key where key.count == 1 && key.first!.isLetter:
            return key.uppercased()

        // Numbers
        case let key where key.count == 1 && key.first!.isNumber:
            return key

        // Arrow keys (handle both kanata names and simulator output symbols)
        case "left", "◀": return "←"
        case "right", "▶": return "→"
        case "up", "▲": return "↑"
        case "down", "▼": return "↓"

        // Modifier symbols from simulator (used in combos like Cmd+Arrow)
        case "‹◆", "◆›": return "⌘"  // Cmd (left/right)
        case "‹⎇", "⎇›": return "⌥"  // Alt/Option (left/right)
        case "‹⇧", "⇧›": return "⇧"  // Shift (left/right)
        case "‹⎈", "⎈›": return "⌃"  // Ctrl (left/right)

        // Modifiers
        case "leftshift", "lsft": return "⇧"
        case "rightshift", "rsft": return "⇧"
        case "leftmeta", "lmet": return "⌘"
        case "rightmeta", "rmet": return "⌘"
        case "leftalt", "lalt": return "⌥"
        case "rightalt", "ralt": return "⌥"
        case "leftctrl", "lctl": return "⌃"
        case "rightctrl", "rctl": return "⌃"

        // Common keys
        case "space", "spc": return "␣"
        case "enter", "ret": return "↩"
        case "backspace", "bspc": return "⌫"
        case "tab": return "⇥"
        case "escape", "esc": return "esc"
        case "capslock", "caps": return "⇪"
        case "delete", "del": return "⌦"

        // Punctuation
        case "grave": return "`"
        case "minus": return "-"
        case "equal": return "="
        case "leftbrace": return "["
        case "rightbrace": return "]"
        case "backslash": return "\\"
        case "semicolon": return ";"
        case "apostrophe": return "'"
        case "comma": return ","
        case "dot": return "."
        case "slash": return "/"

        // Function keys
        case let key where key.hasPrefix("f") && Int(String(key.dropFirst())) != nil:
            return key.uppercased()

        // Home/End/Page keys
        case "home": return "⇱"
        case "end": return "⇲"
        case "pageup", "pgup": return "⇞"
        case "pagedown", "pgdn": return "⇟"

        default:
            // Return as-is if unknown
            return kanataKey
        }
    }

    /// Check if a key is a modifier symbol from the simulator
    private func isModifierSymbol(_ key: String) -> Bool {
        switch key {
        case "‹◆", "◆›", "‹⎇", "⎇›", "‹⇧", "⇧›", "‹⎈", "⎈›":
            return true
        default:
            return false
        }
    }

    /// Convert Kanata key name to macOS key code
    private func kanataKeyToKeyCode(_ kanataKey: String) -> UInt16? {
        // Handle simulator output symbols (arrows)
        let normalizedKey: String
        switch kanataKey {
        case "◀": normalizedKey = "left"
        case "▶": normalizedKey = "right"
        case "▲": normalizedKey = "up"
        case "▼": normalizedKey = "down"
        default: normalizedKey = kanataKey
        }

        // Reverse lookup using OverlayKeyboardView.keyCodeToKanataName
        let allKeyCodes: [UInt16] = Array(0 ... 127) + [0xFFFF]
        for code in allKeyCodes {
            let name = OverlayKeyboardView.keyCodeToKanataName(code)
            if name.lowercased() == normalizedKey.lowercased() {
                return code
            }
        }
        return nil
    }

    // MARK: - Helpers

    /// Get hash of config file for cache invalidation
    private func configFileHash(_ path: String) throws -> String {
        let data = try Data(contentsOf: URL(fileURLWithPath: path))
        // Simple hash based on file size and first/last bytes
        let size = data.count
        let first = data.first ?? 0
        let last = data.last ?? 0
        return "\(size)-\(first)-\(last)"
    }
}
