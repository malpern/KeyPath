import Foundation
import KeyPathCore

extension LayerKeyMapper {
    // MARK: - Key Mapping via Simulator

    /// Result from parsing raw simulation events for a single key
    private struct RawSimulationResult {
        let input: String
        let outputs: [String]
        let isTransparent: Bool
    }

    /// Parse raw simulation events to extract output keys for a single key tap.
    /// Uses JSON mode (--json) to correctly capture all outputs from multi actions,
    /// unlike --key-mapping mode which only returns the first output.
    /// - Parameters:
    ///   - simName: The simulator key name that was pressed
    ///   - events: The simulation events from JSON mode
    /// - Returns: RawSimulationResult with all output keys, or nil if no outputs found
    private func parseRawSimulationEvents(simName: String, events: [SimEvent]) -> RawSimulationResult? {
        // Capture all output key presses from the simulation.
        // For tap-hold keys, tap outputs fire at the moment of release, so we can't just
        // track outputs while the input is held - we need to capture all output presses.
        // Since we simulate one key at a time, all outputs belong to that key's action.
        var pressedOutputs = Set<String>()
        var allPressedOutputs: [String] = [] // Preserve order for primary key detection

        for event in events {
            switch event {
            case let .output(t: _, action: action, key: key):
                if action == .press {
                    let lowerKey = key.lowercased()
                    if !pressedOutputs.contains(lowerKey) {
                        allPressedOutputs.append(lowerKey)
                    }
                    pressedOutputs.insert(lowerKey)
                }
            default:
                continue
            }
        }

        if allPressedOutputs.isEmpty {
            return nil
        }

        // Check if this is a transparent key (input == output with no other keys)
        // Normalize both to handle simulator symbol aliases (e.g., "◀" for "left")
        let normalizedInput = Self.normalizeKeyName(simName.lowercased())
        let normalizedOutput = allPressedOutputs.count == 1 ? Self.normalizeKeyName(allPressedOutputs[0]) : nil
        let isTransparent = normalizedOutput != nil && normalizedOutput == normalizedInput

        return RawSimulationResult(
            input: simName,
            outputs: allPressedOutputs,
            isTransparent: isTransparent
        )
    }

    /// Build mapping using simulator's raw JSON mode to correctly capture multi actions.
    /// Each key is simulated independently to avoid tap-hold interference.
    /// This is slower but accurate - handles aliases, tap-hold, forks, macros, etc.
    /// - Parameters:
    ///   - layer: The layer name to build mapping for
    ///   - configPath: Path to the kanata config file
    ///   - layout: The physical keyboard layout to use for mapping
    ///   - keyToCollection: Map of key names to collection UUIDs (for collection ownership tracking)
    func buildMappingWithSimulator(
        for layer: String,
        configPath: String,
        layout: PhysicalLayout,
        keyToCollection: [String: UUID] = [:],
        activatorKeys: Set<String> = []
    ) async throws -> [UInt16: LayerKeyInfo] {
        var mapping: [UInt16: LayerKeyInfo] = [:]

        // Get all physical keys from the provided layout
        let physicalKeys = layout.keys
            .filter { $0.keyCode != 0xFFFF } // Skip sentinel keys (e.g., Touch ID, Kinesis Layer/Fn)
            .filter { !OverlayKeyboardView.keyCodeToKanataName($0.keyCode).starts(with: "unknown") }

        let startLayer = layer.lowercased() == "base" ? "base" : layer.lowercased()
        AppLogger.shared.debug("🗺️ [LayerKeyMapper] Simulating \(physicalKeys.count) keys individually for layer '\(startLayer)'...")

        // Simulate each key independently to avoid tap-hold interference
        // Run in parallel for performance
        // Use raw JSON mode to correctly capture all outputs from multi actions
        let results = await withTaskGroup(of: (UInt16, String, String, SimulationResult?).self) { group in
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
                        let result = try await self.simulatorService.simulateRaw(
                            simContent: simContent,
                            configPath: configPath,
                            startLayer: startLayer
                        )
                        return (keyCode, label, simName, result)
                    } catch {
                        AppLogger.shared.debug("🗺️ [LayerKeyMapper] Simulation failed for \(simName): \(error)")
                        return (keyCode, label, simName, nil)
                    }
                }
            }

            var collected: [(UInt16, String, String, SimulationResult?)] = []
            for await result in group {
                collected.append(result)
            }
            return collected
        }

        // Process results
        for (keyCode, fallbackLabel, simName, result) in results {
            // Look up collection ownership for this key
            let collectionId = keyToCollection[simName]
            let isActivatorKey = activatorKeys.contains(simName.lowercased())

            // Debug: Log raw simulation result for A key (keyCode 0)
            if keyCode == 0 {
                if let result {
                    let outputEvents = result.events.compactMap { event -> String? in
                        if case let .output(_, action, key) = event, action == .press { return key }
                        return nil
                    }
                    AppLogger.shared.info("🔍 [LayerKeyMapper] keyCode 0 (a) simulation: outputs=\(outputEvents)")
                } else {
                    AppLogger.shared.info("🔍 [LayerKeyMapper] keyCode 0 (a) simulation: FAILED (nil result)")
                }
            }

            guard let result else {
                if isActivatorKey {
                    mapping[keyCode] = .layerSwitch(displayLabel: fallbackLabel, collectionId: collectionId)
                    continue
                }
                // Simulation failed - use physical label
                mapping[keyCode] = LayerKeyInfo(
                    displayLabel: fallbackLabel,
                    outputKey: nil,
                    outputKeyCode: nil,
                    isTransparent: false,
                    isLayerSwitch: false,
                    collectionId: collectionId
                )
                continue
            }

            // Parse events to extract outputs
            guard let parsed = parseRawSimulationEvents(simName: simName, events: result.events) else {
                if isActivatorKey {
                    mapping[keyCode] = .layerSwitch(displayLabel: fallbackLabel, collectionId: collectionId)
                    continue
                }
                // No outputs found
                // On non-base layers: this means the key is transparent (XX)
                // On base layer: use physical label (shouldn't happen, but handle gracefully)
                let isTransparent = startLayer.lowercased() != "base"
                mapping[keyCode] = LayerKeyInfo(
                    displayLabel: fallbackLabel,
                    outputKey: nil,
                    outputKeyCode: nil,
                    isTransparent: isTransparent,
                    isLayerSwitch: false,
                    collectionId: collectionId
                )
                if isTransparent {
                    AppLogger.shared.debug("🔍 [LayerKeyMapper] \(simName)(\(keyCode)) is transparent (XX) on '\(startLayer)'")
                }
                continue
            }

            if isActivatorKey {
                mapping[keyCode] = .layerSwitch(displayLabel: fallbackLabel, collectionId: collectionId)
                continue
            }

            // Check for app launch mappings (push-msg "launch:...")
            if let appIdentifier = extractAppLaunchMapping(from: parsed.outputs) {
                mapping[keyCode] = .appLaunch(appIdentifier: appIdentifier, collectionId: collectionId)
                AppLogger.shared.debug("🚀 [LayerKeyMapper] Mapped \(parsed.input)(\(keyCode)) -> AppLaunch(\(appIdentifier))")
                continue
            }

            // Check for system action mappings (push-msg "system:...")
            if let systemAction = extractSystemActionMapping(from: parsed.outputs) {
                mapping[keyCode] = .systemAction(
                    action: systemAction,
                    description: systemActionDisplayLabel(systemAction),
                    collectionId: collectionId
                )
                AppLogger.shared.debug("⚙️ [LayerKeyMapper] Mapped \(parsed.input)(\(keyCode)) -> SystemAction(\(systemAction))")
                continue
            }

            // Check if output is a URL mapping
            if let urlMapping = extractURLMapping(from: parsed.outputs) {
                mapping[keyCode] = .webURL(url: urlMapping, collectionId: collectionId)
                AppLogger.shared.debug("🌐 [LayerKeyMapper] Mapped \(parsed.input)(\(keyCode)) -> URL(\(urlMapping))")
                continue
            }

            // Check if this is a layer switch (outputs contain kp-layer- prefix)
            let isLayerSwitch = parsed.outputs.contains { $0.lowercased().contains("kp-layer-") }
            if isLayerSwitch {
                mapping[keyCode] = .layerSwitch(displayLabel: fallbackLabel, collectionId: collectionId)
                AppLogger.shared.debug("🔀 [LayerKeyMapper] Mapped \(parsed.input)(\(keyCode)) -> LayerSwitch (collection: \(collectionId?.uuidString ?? "none"))")
                continue
            }

            if parsed.isTransparent {
                // Key passes through unchanged
                let outputKey = parsed.outputs.first
                let outputKeyCode = outputKey.flatMap(kanataKeyToKeyCode)

                // Transparent keys usually should not claim collection ownership.
                // Exception: explicit identity mappings keep collectionId so nav-layer styling can reflect ownership.
                mapping[keyCode] = LayerKeyInfo(
                    displayLabel: fallbackLabel,
                    outputKey: outputKey,
                    outputKeyCode: outputKeyCode,
                    isTransparent: true,
                    isLayerSwitch: false,
                    collectionId: collectionId
                )
            } else if parsed.outputs.allSatisfy({ $0.lowercased() == "xx" }) {
                // Explicitly blocked key (XX) should render blank in the overlay
                mapping[keyCode] = LayerKeyInfo(
                    displayLabel: "",
                    outputKey: nil,
                    outputKeyCode: nil,
                    isTransparent: false,
                    isLayerSwitch: false,
                    collectionId: collectionId
                )
            } else if parsed.outputs.isEmpty {
                // No explicit mapping - fall back to physical key label
                // This happens for keys that aren't defined in the config
                mapping[keyCode] = .transparent(fallbackLabel: fallbackLabel, collectionId: collectionId)
            } else {
                // Convert all outputs to display labels using labelForOutputKeys for Hyper/Meh detection
                let outputSet = Set(parsed.outputs)
                let finalLabel = Self.labelForOutputKeys(outputSet, displayForKey: kanataKeyToDisplayLabel)
                    ?? parsed.outputs.map { kanataKeyToDisplayLabel($0) }.joined()

                // Find primary output key for dual highlighting (first non-modifier)
                var primaryOutputKey: String?
                var primaryOutputKeyCode: UInt16?
                for output in parsed.outputs {
                    if !isModifierSymbol(output) {
                        primaryOutputKey = output
                        primaryOutputKeyCode = kanataKeyToKeyCode(output)
                        break
                    }
                }
                // Special-case spacebar: ensure display label stays blank
                let normalizedInput = parsed.input.lowercased()
                let normalizedOutputs = parsed.outputs.map { $0.lowercased() }
                let isSpaceInput = ["space", "spacebar", "spc", "sp"].contains(normalizedInput)
                let isSpaceOnlyOutput = Set(normalizedOutputs).isSubset(of: ["space", "spacebar", "spc", "sp"])
                let displayLabel = (isSpaceInput || isSpaceOnlyOutput) ? "" : finalLabel
                let outputKey = primaryOutputKey ?? parsed.outputs.first

                if let outputKey {
                    mapping[keyCode] = .mapped(
                        displayLabel: displayLabel,
                        outputKey: outputKey,
                        outputKeyCode: primaryOutputKeyCode,
                        collectionId: collectionId
                    )
                    if outputKey.uppercased() != parsed.input.uppercased() {
                        AppLogger.shared.debug("🗺️ [LayerKeyMapper] Mapped \(parsed.input)(\(keyCode)) -> \(outputKey)(\(displayLabel))")
                    }
                } else {
                    mapping[keyCode] = LayerKeyInfo(
                        displayLabel: displayLabel,
                        outputKey: nil,
                        outputKeyCode: nil,
                        isTransparent: false,
                        isLayerSwitch: false,
                        collectionId: collectionId
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
    func buildFallbackMapping(layout: PhysicalLayout) -> [UInt16: LayerKeyInfo] {
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
                isLayerSwitch: false,
                collectionId: nil
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
           ["space", "spacebar", "spc", "sp"].contains(only)
        {
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
}
