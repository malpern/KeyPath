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
    /// Each key is simulated independently to avoid tap-hold interference.
    /// This is slower but accurate - handles aliases, tap-hold, forks, macros, etc.
    private func buildMappingWithSimulator(for layer: String, configPath: String) async throws -> [UInt16: LayerKeyInfo] {
        var mapping: [UInt16: LayerKeyInfo] = [:]

        // Get all physical keys from the layout
        let physicalKeys = PhysicalLayout.macBookUS.keys
            .filter { $0.keyCode != 0xFFFF } // Skip Touch ID
            .filter { !OverlayKeyboardView.keyCodeToKanataName($0.keyCode).starts(with: "unknown") }

        let startLayer = layer.lowercased() == "base" ? "base" : layer.lowercased()
        AppLogger.shared.debug("🗺️ [LayerKeyMapper] Simulating \(physicalKeys.count) keys individually for layer '\(startLayer)'...")

        // Simulate each key independently to avoid tap-hold interference
        // Run in parallel for performance
        let results = await withTaskGroup(of: (UInt16, String, SimulatorKeyMappingResult?).self) { group in
            for key in physicalKeys {
                let tcpName = OverlayKeyboardView.keyCodeToKanataName(key.keyCode)
                let simName = toSimulatorKeyName(tcpName)
                let keyCode = key.keyCode
                let label = key.label

                group.addTask {
                    // Single key: press, wait 50ms, release, then wait 250ms for tap-hold to resolve.
                    // Tap-hold behaviors need time after release to determine if it was a tap (the
                    // typical threshold is 200ms, so 250ms ensures the tap fires).
                    let simContent = "d:\(simName) t:50 u:\(simName) t:250"
                    do {
                        let result = try await self.simulatorService.simulateKeyMapping(
                            simContent: simContent,
                            configPath: configPath,
                            startLayer: startLayer
                        )
                        return (keyCode, label, result)
                    } catch {
                        AppLogger.shared.debug("🗺️ [LayerKeyMapper] Simulation failed for \(simName): \(error)")
                        return (keyCode, label, nil)
                    }
                }
            }

            var collected: [(UInt16, String, SimulatorKeyMappingResult?)] = []
            for await result in group {
                collected.append(result)
            }
            return collected
        }

        // Process results
        for (keyCode, fallbackLabel, result) in results {
            guard let result, let keyMapping = result.mappings.first else {
                // Simulation failed or no mapping - use physical label
                mapping[keyCode] = LayerKeyInfo(
                    displayLabel: fallbackLabel,
                    outputKey: nil,
                    outputKeyCode: nil,
                    isTransparent: false,
                    isLayerSwitch: false
                )
                continue
            }

            if keyMapping.transparent {
                // Key passes through unchanged
                mapping[keyCode] = .transparent(fallbackLabel: fallbackLabel)
            } else if keyMapping.outputs.isEmpty {
                // Explicit no-op (e.g., XX) returns no outputs from simulator
                mapping[keyCode] = LayerKeyInfo(
                    displayLabel: "",
                    outputKey: nil,
                    outputKeyCode: nil,
                    isTransparent: false,
                    isLayerSwitch: false
                )
            } else if keyMapping.outputs.allSatisfy({ $0.lowercased() == "xx" }) {
                // Explicitly blocked key should render blank in the overlay
                mapping[keyCode] = LayerKeyInfo(
                    displayLabel: "",
                    outputKey: nil,
                    outputKeyCode: nil,
                    isTransparent: false,
                    isLayerSwitch: false
                )
            } else if keyMapping.outputs.isEmpty {
                // No output (blocked key)
                mapping[keyCode] = .transparent(fallbackLabel: fallbackLabel)
            } else {
                // Convert all outputs to display labels and combine
                var displayParts: [String] = []
                var primaryOutputKey: String?
                var primaryOutputKeyCode: UInt16?

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

        AppLogger.shared.info("🗺️ [LayerKeyMapper] Built mapping: \(mapping.count) keys")
        return mapping
    }

    /// Derive the hold-action display label for a specific physical key by simulating a long press.
    /// Used when Kanata's HoldActivated event omits the action string.
    /// - Parameters:
    ///   - keyCode: macOS virtual key code
    ///   - configPath: Kanata config path
    ///   - startLayer: Layer to start the simulation in
    /// - Returns: Display label for the hold action, or nil if not resolved
    func holdDisplayLabel(
        for keyCode: UInt16,
        configPath: String,
        startLayer: String
    ) async throws -> String? {
        let tcpName = OverlayKeyboardView.keyCodeToKanataName(keyCode)
        let simName = toSimulatorKeyName(tcpName)

        // Long press: hold for 400ms to exceed typical tap-hold timeouts (200ms default)
        // Use simulateRaw to specify start layer and a long press
        let simContent = "d:\(simName) t:400 u:\(simName)"
        let result = try await simulatorService.simulateRaw(
            simContent: simContent,
            configPath: configPath,
            startLayer: startLayer
        )

        // Find the first output press event — for dual-role keys this should be the hold action
        if let outputKey = result.events.compactMap({ event -> String? in
            if case let .output(_, action, key) = event, action == .press {
                return key
            }
            return nil
        }).first {
            return kanataKeyToDisplayLabel(outputKey)
        }
        return nil
    }

    // MARK: - Key Name Conversion

    /// Convert TCP key name (from OverlayKeyboardView.keyCodeToKanataName) to simulator-compatible name
    /// The simulator uses abbreviated names like "min" instead of "minus"
    private func toSimulatorKeyName(_ tcpName: String) -> String {
        switch tcpName.lowercased() {
        // Punctuation keys use abbreviated names in simulator
        case "minus": "min"
        case "equal": "eql"
        case "grave": "grv"
        case "backslash": "bksl"
        case "leftbrace": "lbrc"
        case "rightbrace": "rbrc"
        case "semicolon": "scln"
        case "apostrophe": "apos"
        case "comma": "comm"
        case "dot": "."
        case "slash": "/"
        // Modifiers
        case "leftshift": "lsft"
        case "rightshift": "rsft"
        case "leftmeta": "lmet"
        case "rightmeta": "rmet"
        case "leftalt": "lalt"
        case "rightalt": "ralt"
        case "leftctrl": "lctl"
        case "rightctrl": "rctl"
        case "capslock": "caps"
        // Special keys
        case "backspace": "bspc"
        case "enter": "ret"
        case "space": "spc"
        case "escape": "esc"
        default:
            tcpName
        }
    }

    /// Convert Kanata key name to display label using standard Mac keyboard symbols
    /// Reference: https://support.apple.com/en-us/HT201236
    private func kanataKeyToDisplayLabel(_ kanataKey: String) -> String {
        switch kanataKey.lowercased() {
        // Letters
        case let key where key.count == 1 && key.first!.isLetter:
            key.uppercased()
        // Numbers
        case let key where key.count == 1 && key.first!.isNumber:
            key
        // Arrow keys - Mac uses these specific Unicode arrows
        // Handle both kanata names and simulator output symbols (◀▶▲▼)
        case "left", "◀": "←"
        case "right", "▶": "→"
        case "up", "▲": "↑"
        case "down", "▼": "↓"
        // Modifier symbols from simulator (used in combos like Cmd+Arrow)
        // The simulator outputs ‹◆ for left-Cmd, ◆› for right-Cmd, etc.
        case "‹◆", "◆›": "⌘" // Command
        case "‹⎇", "⎇›": "⌥" // Option
        case "‹⇧", "⇧›": "⇧" // Shift
        case "‹⎈", "⎈›": "⌃" // Control
        // Modifiers - Standard Mac symbols
        case "leftshift", "lsft": "⇧" // U+21E7 Upwards White Arrow
        case "rightshift", "rsft": "⇧"
        case "leftmeta", "lmet": "⌘" // U+2318 Place of Interest Sign (Command)
        case "rightmeta", "rmet": "⌘"
        case "leftalt", "lalt": "⌥" // U+2325 Option Key
        case "rightalt", "ralt": "⌥"
        case "leftctrl", "lctl": "⌃" // U+2303 Up Arrowhead (Control)
        case "rightctrl", "rctl": "⌃"
        // Common keys - Standard Mac symbols
        case "space", "spc": "␣" // U+2423 Open Box (standard space symbol)
        case "enter", "ret": "↩" // U+21A9 Return symbol
        case "backspace", "bspc": "⌫" // U+232B Delete to the Left
        case "tab": "⇥" // U+21E5 Rightwards Arrow to Bar
        case "escape", "esc": "⎋" // U+238B Broken Circle with Northwest Arrow (Escape)
        case "capslock", "caps": "⇪" // U+21EA Upwards White Arrow from Bar (Caps Lock)
        case "delete", "del": "⌦" // U+2326 Erase to the Right
        case "fn": "fn" // Function key (no standard symbol)
        // Punctuation - Show actual characters
        case "grave", "grv": "`"
        case "minus", "min": "-"
        case "equal", "eql": "="
        case "leftbrace", "lbrc": "["
        case "rightbrace", "rbrc": "]"
        case "backslash", "bksl": "\\"
        case "semicolon", "scln": ";"
        case "apostrophe", "apos": "'"
        case "comma", "comm": ","
        case "dot", ".": "."
        case "slash", "/": "/"
        // Function keys
        case let key where key.hasPrefix("f") && Int(String(key.dropFirst())) != nil:
            key.uppercased()
        // Navigation keys
        case "home": "↖"
        case "end": "↘"
        case "pageup", "pgup": "⇞"
        case "pagedown", "pgdn": "⇟"
        default:
            // Return as-is if unknown
            kanataKey
        }
    }

    /// Check if a key is a modifier symbol from the simulator
    private func isModifierSymbol(_ key: String) -> Bool {
        switch key {
        case "‹◆", "◆›", "‹⎇", "⎇›", "‹⇧", "⇧›", "‹⎈", "⎈›":
            true
        default:
            false
        }
    }

    /// Convert Kanata key name to macOS key code
    private func kanataKeyToKeyCode(_ kanataKey: String) -> UInt16? {
        // Handle simulator output symbols (arrows)
        let normalizedKey: String = switch kanataKey {
        case "◀": "left"
        case "▶": "right"
        case "▲": "up"
        case "▼": "down"
        default: kanataKey
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
