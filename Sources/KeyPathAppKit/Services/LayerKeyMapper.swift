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
        AppLogger.shared.info("🗺️ [LayerKeyMapper] getMapping called for layer '\(layer)'")

        // Check if config changed (invalidate cache)
        let currentHash = try configFileHash(configPath)
        if currentHash != configHash {
            AppLogger.shared.debug("🗺️ [LayerKeyMapper] Config changed, clearing cache")
            cache.removeAll()
            configHash = currentHash
        }

        // Return cached if available
        if let cached = cache[layer] {
            AppLogger.shared.debug("🗺️ [LayerKeyMapper] Returning cached mapping (\(cached.count) keys)")
            return cached
        }

        AppLogger.shared.info("🗺️ [LayerKeyMapper] Building new mapping for '\(layer)'...")

        // Use batch simulation for accurate key mapping
        // This handles aliases, tap-hold, forks, macros, etc.
        let mapping = try await buildMappingWithSimulator(for: layer, configPath: configPath)

        cache[layer] = mapping
        AppLogger.shared.info("🗺️ [LayerKeyMapper] Built mapping: \(mapping.count) keys")
        return mapping
    }

    /// Invalidate all cached mappings (call when config changes)
    func invalidateCache() {
        cache.removeAll()
        configHash = ""
    }

    // MARK: - Batch Simulation

    /// Build mapping by simulating ALL keys in a single simulator call
    /// This is fast (~50ms) and accurate (handles aliases, tap-hold, forks, etc.)
    private func buildMappingWithSimulator(for layer: String, configPath: String) async throws -> [UInt16: LayerKeyInfo] {
        var mapping: [UInt16: LayerKeyInfo] = [:]

        // Get all physical keys from the layout
        let physicalKeys = PhysicalLayout.macBookUS.keys
            .filter { $0.keyCode != 0xFFFF } // Skip Touch ID
            .filter { !OverlayKeyboardView.keyCodeToKanataName($0.keyCode).starts(with: "unknown") }

        // Build a single sim file with all keys
        // Use t:100 between keys to clearly separate input/output pairs
        var simParts: [String] = []
        var keyTimestamps: [(keyCode: UInt16, kanataName: String, label: String, pressTime: UInt64)] = []
        var currentTime: UInt64 = 0

        for key in physicalKeys {
            let tcpName = OverlayKeyboardView.keyCodeToKanataName(key.keyCode)
            let simName = toSimulatorKeyName(tcpName)
            keyTimestamps.append((key.keyCode, tcpName, key.label, currentTime))

            // press, wait 50ms, release, wait 100ms before next key
            simParts.append("d:\(simName) t:50 u:\(simName)")
            currentTime += 50 // release time
            if key != physicalKeys.last {
                simParts.append("t:100")
                currentTime += 100
            }
        }

        let simContent = simParts.joined(separator: " ")
        AppLogger.shared.debug("🗺️ [LayerKeyMapper] Simulating \(physicalKeys.count) keys in batch...")

        // Run single simulation
        let result: SimulationResult
        do {
            result = try await simulatorService.simulateRaw(
                simContent: simContent,
                configPath: configPath
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

        // Parse results: match each input press to its corresponding output
        // Group events by their approximate timestamp window
        for (keyCode, kanataName, label, pressTime) in keyTimestamps {
            // Helper to check if timestamp is within window
            func isNearTime(_ t: UInt64, window: UInt64) -> Bool {
                if t >= pressTime {
                    return t - pressTime < window
                } else {
                    return pressTime - t < window
                }
            }

            // Find input press event at this time
            let inputPress = result.events.first { event in
                if case let .input(t, action, key) = event {
                    return action == .press && key.lowercased() == kanataName.lowercased() && isNearTime(t, window: 10)
                }
                return false
            }

            guard inputPress != nil else {
                // Key wasn't in simulation (shouldn't happen)
                mapping[keyCode] = LayerKeyInfo(
                    displayLabel: label,
                    outputKey: nil,
                    outputKeyCode: nil,
                    isTransparent: false,
                    isLayerSwitch: false
                )
                continue
            }

            // Find output press event at same time window
            let outputPress = result.events.first { event in
                if case let .output(t, action, _) = event {
                    return action == .press && isNearTime(t, window: 60) // Allow some timing slack for tap-hold
                }
                return false
            }

            // Check for layer change at this time
            let layerChange = result.events.first { event in
                if case let .layer(t, _, _) = event {
                    return isNearTime(t, window: 60)
                }
                return false
            }

            if let layerChange, case let .layer(_, _, to) = layerChange {
                // This key switches layers
                mapping[keyCode] = .layerSwitch(displayLabel: to)
            } else if let outputPress, case let .output(_, _, outputKey) = outputPress {
                let displayLabel = kanataKeyToDisplayLabel(outputKey)
                let outputKeyCode = kanataKeyToKeyCode(outputKey)

                if outputKey.lowercased() == kanataName.lowercased() {
                    // Same key - no remapping, but still include for completeness
                    mapping[keyCode] = LayerKeyInfo(
                        displayLabel: displayLabel,
                        outputKey: outputKey,
                        outputKeyCode: outputKeyCode,
                        isTransparent: false,
                        isLayerSwitch: false
                    )
                } else {
                    // Different key - this is a remap!
                    mapping[keyCode] = .mapped(
                        displayLabel: displayLabel,
                        outputKey: outputKey,
                        outputKeyCode: outputKeyCode
                    )
                    AppLogger.shared.debug("🗺️ [LayerKeyMapper] Mapped \(kanataName)(\(keyCode)) -> \(outputKey)(\(displayLabel))")
                }
            } else {
                // No output - key is blocked or produces no output
                mapping[keyCode] = .transparent(fallbackLabel: label)
            }
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

        // Arrow keys
        case "left": return "←"
        case "right": return "→"
        case "up": return "↑"
        case "down": return "↓"

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

    /// Convert Kanata key name to macOS key code
    private func kanataKeyToKeyCode(_ kanataKey: String) -> UInt16? {
        // Reverse lookup using OverlayKeyboardView.keyCodeToKanataName
        let allKeyCodes: [UInt16] = Array(0 ... 127) + [0xFFFF]
        for code in allKeyCodes {
            let name = OverlayKeyboardView.keyCodeToKanataName(code)
            if name.lowercased() == kanataKey.lowercased() {
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
