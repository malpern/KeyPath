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

    init(
        displayLabel: String,
        outputKey: String?,
        outputKeyCode: UInt16?,
        isTransparent: Bool,
        isLayerSwitch: Bool,
        appLaunchIdentifier: String? = nil,
        systemActionIdentifier: String? = nil,
        urlIdentifier: String? = nil
    ) {
        self.displayLabel = displayLabel
        self.outputKey = outputKey
        self.outputKeyCode = outputKeyCode
        self.isTransparent = isTransparent
        self.isLayerSwitch = isLayerSwitch
        self.appLaunchIdentifier = appLaunchIdentifier
        self.systemActionIdentifier = systemActionIdentifier
        self.urlIdentifier = urlIdentifier
    }

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

    /// Creates info for an app launch action
    /// - Parameter appIdentifier: The app name or bundle ID
    /// - Note: displayLabel is set to the app identifier for consumers that need text
    ///         (like Mapper), while appLaunchIdentifier enables icon rendering
    static func appLaunch(appIdentifier: String) -> LayerKeyInfo {
        LayerKeyInfo(
            displayLabel: appIdentifier, // Use app name as display label
            outputKey: nil,
            outputKeyCode: nil,
            isTransparent: false,
            isLayerSwitch: false,
            appLaunchIdentifier: appIdentifier
        )
    }

    /// Creates info for a system action (DND, Spotlight, etc.)
    /// - Parameters:
    ///   - action: The system action name (e.g., "dnd", "spotlight")
    ///   - description: Human-readable description for display
    static func systemAction(action: String, description: String) -> LayerKeyInfo {
        LayerKeyInfo(
            displayLabel: description,
            outputKey: nil,
            outputKeyCode: nil,
            isTransparent: false,
            isLayerSwitch: false,
            appLaunchIdentifier: nil,
            systemActionIdentifier: action
        )
    }

    /// Creates info for a generic push-msg action
    /// - Parameter message: The message content for display
    static func pushMsg(message: String) -> LayerKeyInfo {
        LayerKeyInfo(
            displayLabel: message,
            outputKey: nil,
            outputKeyCode: nil,
            isTransparent: false,
            isLayerSwitch: false,
            appLaunchIdentifier: nil
        )
    }

    /// Creates info for a web URL action
    /// - Parameter url: The URL to open (e.g., "github.com", "https://example.com")
    /// - Note: displayLabel is set to the domain for text display,
    ///         while urlIdentifier enables favicon rendering
    static func webURL(url: String) -> LayerKeyInfo {
        let displayDomain = extractDomain(from: url)
        return LayerKeyInfo(
            displayLabel: displayDomain,
            outputKey: nil,
            outputKeyCode: nil,
            isTransparent: false,
            isLayerSwitch: false,
            appLaunchIdentifier: nil,
            systemActionIdentifier: nil,
            urlIdentifier: url
        )
    }

    /// Extract domain from URL for display purposes
    /// - Parameter url: The full URL
    /// - Returns: Just the domain portion (e.g., "github.com" from "https://github.com/user/repo")
    private static func extractDomain(from url: String) -> String {
        let cleaned = url
            .replacingOccurrences(of: "https://", with: "")
            .replacingOccurrences(of: "http://", with: "")
        return cleaned.components(separatedBy: "/").first ?? url
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
    ///   - layout: The physical keyboard layout to use for mapping
    /// - Returns: Dictionary mapping physical key codes to their layer-specific info
    func getMapping(for layer: String, configPath: String, layout: PhysicalLayout) async throws -> [UInt16: LayerKeyInfo] {
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

        // Use batch simulation for accurate key mapping
        // This handles aliases, tap-hold, forks, macros, etc.
        let mapping = try await buildMappingWithSimulator(for: normalizedLayer, configPath: configPath, layout: layout)

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
    func prebuildAllLayers(_ layerNames: [String], configPath: String, layout: PhysicalLayout) async {
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
                        let mapping = try await self.buildMappingWithSimulator(for: layer, configPath: configPath, layout: layout)
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
    /// - Parameters:
    ///   - layer: The layer name to build mapping for
    ///   - configPath: Path to the kanata config file
    ///   - layout: The physical keyboard layout to use for mapping
    private func buildMappingWithSimulator(for layer: String, configPath: String, layout: PhysicalLayout) async throws -> [UInt16: LayerKeyInfo] {
        var mapping: [UInt16: LayerKeyInfo] = [:]

        // Get all physical keys from the provided layout
        let physicalKeys = layout.keys
            .filter { $0.keyCode != 0xFFFF } // Skip sentinel keys (e.g., Touch ID, Kinesis Layer/Fn)
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

            // Check for app launch mappings (push-msg "launch:...")
            if let appIdentifier = extractAppLaunchMapping(from: keyMapping.outputs) {
                mapping[keyCode] = .appLaunch(appIdentifier: appIdentifier)
                AppLogger.shared.debug("🚀 [LayerKeyMapper] Mapped \(keyMapping.input)(\(keyCode)) -> AppLaunch(\(appIdentifier))")
                continue
            }

            // Check for system action mappings (push-msg "system:...")
            if let systemAction = extractSystemActionMapping(from: keyMapping.outputs) {
                mapping[keyCode] = .systemAction(
                    action: systemAction,
                    description: systemActionDisplayLabel(systemAction)
                )
                AppLogger.shared.debug("⚙️ [LayerKeyMapper] Mapped \(keyMapping.input)(\(keyCode)) -> SystemAction(\(systemAction))")
                continue
            }

            // Check if output is a URL mapping
            if let urlMapping = extractURLMapping(from: keyMapping.outputs) {
                mapping[keyCode] = .webURL(url: urlMapping)
                AppLogger.shared.debug("🌐 [LayerKeyMapper] Mapped \(keyMapping.input)(\(keyCode)) -> URL(\(urlMapping))")
                continue
            }

            if keyMapping.transparent {
                // Key passes through unchanged
                mapping[keyCode] = .transparent(fallbackLabel: fallbackLabel)
            } else if keyMapping.outputs.allSatisfy({ $0.lowercased() == "xx" }) {
                // Explicitly blocked key (XX) should render blank in the overlay
                mapping[keyCode] = LayerKeyInfo(
                    displayLabel: "",
                    outputKey: nil,
                    outputKeyCode: nil,
                    isTransparent: false,
                    isLayerSwitch: false
                )
            } else if keyMapping.outputs.isEmpty {
                // No explicit mapping - fall back to physical key label
                // This happens for keys that aren't defined in the config
                mapping[keyCode] = .transparent(fallbackLabel: fallbackLabel)
            } else {
                // Convert all outputs to display labels using labelForOutputKeys for Hyper/Meh detection
                let outputSet = Set(keyMapping.outputs.map { $0.lowercased() })
                let finalLabel = Self.labelForOutputKeys(outputSet, displayForKey: kanataKeyToDisplayLabel)
                    ?? keyMapping.outputs.map { kanataKeyToDisplayLabel($0) }.joined()

                // Find primary output key for dual highlighting
                var primaryOutputKey: String?
                var primaryOutputKeyCode: UInt16?
                for output in keyMapping.outputs {
                    if !isModifierSymbol(output) {
                        primaryOutputKey = output
                        primaryOutputKeyCode = kanataKeyToKeyCode(output)
                        break
                    }
                }
                // Special-case spacebar: ensure display label stays blank
                let normalizedInput = keyMapping.input.lowercased()
                let normalizedOutputs = keyMapping.outputs.map { $0.lowercased() }
                let isSpaceInput = ["space", "spacebar", "spc", "sp"].contains(normalizedInput)
                let isSpaceOnlyOutput = Set(normalizedOutputs).isSubset(of: ["space", "spacebar", "spc", "sp"])
                let displayLabel = (isSpaceInput || isSpaceOnlyOutput) ? "" : finalLabel
                let outputKey = primaryOutputKey ?? keyMapping.outputs.first

                if let outputKey {
                    mapping[keyCode] = .mapped(
                        displayLabel: displayLabel,
                        outputKey: outputKey,
                        outputKeyCode: primaryOutputKeyCode
                    )
                    if outputKey.uppercased() != keyMapping.input.uppercased() {
                        AppLogger.shared.debug("🗺️ [LayerKeyMapper] Mapped \(keyMapping.input)(\(keyCode)) -> \(outputKey)(\(displayLabel))")
                    }
                } else {
                    mapping[keyCode] = LayerKeyInfo(
                        displayLabel: displayLabel,
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
        guard FeatureFlags.simulatorAndVirtualKeysEnabled else {
            AppLogger.shared.debug("🔒 [LayerKeyMapper] Simulator disabled; skipping holdDisplayLabel")
            return nil
        }
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

        // Track net pressed output keys between the input press and its release.
        var trackingOutputs = false
        var pressedOutputs = Set<String>()
        var lastNonEmptyOutputs = Set<String>()

        for event in result.events {
            switch event {
            case let .input(_, action, _):
                if action == .press {
                    // Start tracking as soon as the simulated key is pressed. The simulator may
                    // use display-style symbols (e.g. "⇪" for caps) instead of the simulator
                    // name ("caps"), so key-matching is brittle. We only simulate one key per
                    // run, so tracking from the first press is safe and avoids alias issues.
                    trackingOutputs = true
                } else if action == .release {
                    // Stop tracking at input release; hold outputs should be active just before this.
                    trackingOutputs = false
                    // Preserve the last known non-empty set when we stop tracking
                    if !pressedOutputs.isEmpty {
                        lastNonEmptyOutputs = pressedOutputs
                    }
                }
            case let .output(_, action, key) where trackingOutputs:
                if action == .press {
                    pressedOutputs.insert(key.lowercased())
                } else if action == .release {
                    pressedOutputs.remove(key.lowercased())
                }
                if !pressedOutputs.isEmpty {
                    lastNonEmptyOutputs = pressedOutputs
                }
            default:
                continue
            }
        }

        let keySet = !pressedOutputs.isEmpty ? pressedOutputs : lastNonEmptyOutputs
        AppLogger.shared.info("🔒 [LayerKeyMapper] holdDisplayLabel outputs=\(Array(keySet)) keyCode=\(keyCode) sim=\(simName)")
        if keySet.isEmpty {
            let outputEvents = result.events.compactMap { event -> (UInt64, String, String)? in
                if case let .output(t, action, key) = event {
                    return (t, String(describing: action), key)
                }
                return nil
            }
            AppLogger.shared.info("🔒 [LayerKeyMapper] holdDisplayLabel no outputs, raw output events=\(outputEvents)")
            // Fallback to first output press if we didn't catch any net presses
            if let firstOutput = result.events.compactMap({ event -> String? in
                if case let .output(_, action, key) = event, action == .press { return key }
                return nil
            }).first {
                return kanataKeyToDisplayLabel(firstOutput)
            }
            return nil
        }

        return Self.labelForOutputKeys(keySet, displayForKey: kanataKeyToDisplayLabel)
    }

    /// Build a mapping that mirrors physical key labels without simulator output.
    /// - Parameter layout: The physical keyboard layout to use for mapping
    private func buildFallbackMapping(layout: PhysicalLayout) -> [UInt16: LayerKeyInfo] {
        var mapping: [UInt16: LayerKeyInfo] = [:]

        let physicalKeys = layout.keys
            .filter { $0.keyCode != 0xFFFF } // Skip sentinel keys (e.g., Touch ID, Kinesis Layer/Fn)
            .filter { !OverlayKeyboardView.keyCodeToKanataName($0.keyCode).starts(with: "unknown") }

        for key in physicalKeys {
            mapping[key.keyCode] = LayerKeyInfo(
                displayLabel: key.label,
                outputKey: nil,
                outputKeyCode: nil,
                isTransparent: false,
                isLayerSwitch: false
            )
        }

        AppLogger.shared.info("🗺️ [LayerKeyMapper] Built fallback mapping: \(mapping.count) keys")
        return mapping
    }

    /// Map a set of output key names (lowercased) to a display label, with Hyper/Meh detection.
    /// - Parameters:
    ///   - outputs: set of output key names (e.g., ["lctl","lmet","lalt","lsft"])
    ///   - displayForKey: converter from kanata key name to display label (e.g., "lmet" -> "⌘")
    /// - Returns: display label or nil if empty
    static func labelForOutputKeys(
        _ outputs: Set<String>,
        displayForKey: (String) -> String
    ) -> String? {
        if outputs.isEmpty { return nil }

        // Normalize modifier aliases and be tolerant of naming variants
        let normalizedSet: Set<String> = Set(outputs.map { key in
            switch key {
            case "cmd", "lcmd", "command", "lcommand", "meta": "lmet"
            case "rmet": "lmet"
            case "lctrl", "ctrl", "control", "lcontrol": "lctl"
            case "rctl", "rctrl", "rcontrol": "lctl"
            case "ralt": "lalt"
            case "rsft", "rshift", "shift": "lsft"
            // Simulator-specific left-side modifier symbols (‹…›)
            case "‹⎈": "lctl" // Control
            case "‹◆": "lmet" // Command
            case "‹⎇": "lalt" // Option
            case "‹⇧": "lsft" // Shift
            default: key
            }
        })

        // Hyper detection (Ctrl+Cmd+Alt+Shift)
        let hyperSet: Set<String> = ["lctl", "lmet", "lalt", "lsft"]
        if normalizedSet.isSuperset(of: hyperSet) || normalizedSet.isSuperset(of: Set(["lctl", "lmet", "lalt", "lshift"])) {
            return "✦"
        }
        // Meh detection (Ctrl+Alt+Shift)
        let mehSet: Set<String> = ["lctl", "lalt", "lsft"]
        if normalizedSet.isSuperset(of: mehSet) {
            return "◆"
        }

        // Spacebar output should render blank
        if normalizedSet.count == 1, let only = normalizedSet.first,
           ["space", "spacebar", "spc", "sp"].contains(only) {
            return ""
        }

        if normalizedSet.count == 1, let only = normalizedSet.first {
            let label = displayForKey(only).trimmingCharacters(in: .whitespacesAndNewlines)
            return label.isEmpty ? "" : label
        }

        // Fallback: join display labels for combo
        let labels = normalizedSet
            .map { displayForKey($0) }
            .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { !$0.isEmpty }
            .sorted()
        return labels.isEmpty ? "" : labels.joined()
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
        case "space", "spc", "sp": "" // Spacebar: show blank (the physical key shape indicates space)
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

    /// Extract URL from push-msg output if present
    /// Returns URL string if output contains "open:...", nil otherwise
    nonisolated func extractURLMapping(from outputs: [String]) -> String? {
        for output in outputs {
            for candidate in pushMsgCandidates(from: output) {
                // Direct match: "open:github.com" (from push-msg in simulator output)
                if candidate.hasPrefix("open:") {
                    let url = String(candidate.dropFirst(5)) // Remove "open:"
                    return url.isEmpty ? nil : url
                }

                // Also check for full push-msg format (in case simulator returns it verbatim)
                // Pattern: (push-msg "open:...")
                let pattern = #"push-msg\s+"open:([^"]+)""#
                if let regex = try? NSRegularExpression(pattern: pattern),
                   let match = regex.firstMatch(in: candidate, range: NSRange(candidate.startIndex..., in: candidate)),
                   let urlRange = Range(match.range(at: 1), in: candidate) {
                    return String(candidate[urlRange])
                }
            }
        }
        return nil
    }

    /// Extract app identifier from push-msg output if present
    /// Returns app identifier string if output contains "launch:...", nil otherwise
    nonisolated func extractAppLaunchMapping(from outputs: [String]) -> String? {
        for output in outputs {
            for candidate in pushMsgCandidates(from: output) {
                if let action = extractKeyPathAction(from: candidate),
                   action.action.lowercased() == "launch",
                   let target = action.target {
                    return target
                }

                if candidate.lowercased().hasPrefix("launch:") {
                    let appId = String(candidate.dropFirst("launch:".count))
                    return appId.isEmpty ? nil : appId
                }
            }
        }
        return nil
    }

    /// Extract system action identifier from push-msg output if present
    /// Returns system action string if output contains "system:...", nil otherwise
    nonisolated func extractSystemActionMapping(from outputs: [String]) -> String? {
        for output in outputs {
            for candidate in pushMsgCandidates(from: output) {
                if let action = extractKeyPathAction(from: candidate),
                   action.action.lowercased() == "system",
                   let target = action.target {
                    return target
                }

                if candidate.lowercased().hasPrefix("system:") {
                    let actionId = String(candidate.dropFirst("system:".count))
                    return actionId.isEmpty ? nil : actionId
                }
            }
        }
        return nil
    }

    /// Extract the payload from push-msg outputs, returning candidates to inspect.
    private nonisolated func pushMsgCandidates(from output: String) -> [String] {
        let trimmed = output.trimmingCharacters(in: .whitespaces)
        var candidates: [String] = [trimmed]

        let pattern = #"push-msg\s+"([^"]+)""#
        if let regex = try? NSRegularExpression(pattern: pattern),
           let match = regex.firstMatch(in: trimmed, range: NSRange(trimmed.startIndex..., in: trimmed)),
           let payloadRange = Range(match.range(at: 1), in: trimmed) {
            candidates.append(String(trimmed[payloadRange]))
        }

        return candidates
    }

    /// Extract a keypath:// action and target from a string (e.g., keypath://launch/Obsidian)
    private nonisolated func extractKeyPathAction(from value: String) -> (action: String, target: String?)? {
        guard let url = URL(string: value),
              url.scheme?.lowercased() == "keypath",
              let action = url.host, !action.isEmpty
        else {
            return nil
        }

        let rawPathComponents = url.pathComponents.filter { $0 != "/" && !$0.isEmpty }
        let target = rawPathComponents.first?.removingPercentEncoding ?? rawPathComponents.first
        return (action: action, target: target)
    }

    /// Human-readable label for system actions (matches overlay + mapper naming)
    private nonisolated func systemActionDisplayLabel(_ action: String) -> String {
        switch action.lowercased() {
        case "dnd", "do-not-disturb", "donotdisturb", "focus":
            "Do Not Disturb"
        case "spotlight":
            "Spotlight"
        case "dictation":
            "Dictation"
        case "mission-control", "missioncontrol":
            "Mission Control"
        case "launchpad":
            "Launchpad"
        case "notification-center", "notificationcenter":
            "Notification Center"
        case "siri":
            "Siri"
        default:
            action.capitalized
        }
    }
}
