import Foundation

// MARK: - Hyper Linked Layer Info

/// Information about a layer that should be activated when Hyper is triggered
public struct HyperLinkedLayerInfo: Equatable, Sendable {
    public let layerName: String
    public let triggerMode: HyperTriggerMode

    public init(layerName: String, triggerMode: HyperTriggerMode = .hold) {
        self.layerName = layerName
        self.triggerMode = triggerMode
    }
}

// MARK: - Kanata Behavior Renderer

/// Renders `MappingBehavior` values to Kanata configuration syntax.
public enum KanataBehaviorRenderer {
    /// Render a mapping's behavior (or simple output) to Kanata syntax.
    /// - Parameters:
    ///   - mapping: The key mapping to render.
    ///   - hyperLinkedLayers: Layers that should be activated when "hyper" is triggered (legacy).
    /// - Returns: Kanata action string (e.g., `(tap-hold 200 200 a lctl)` or just `esc`).
    public static func render(_ mapping: KeyMapping, hyperLinkedLayers: [String] = []) -> String {
        // Convert legacy format to new format (default to hold mode)
        let layerInfos = hyperLinkedLayers.map { HyperLinkedLayerInfo(layerName: $0) }
        return render(mapping, hyperLinkedLayerInfos: layerInfos)
    }

    /// Render a mapping's behavior (or simple output) to Kanata syntax.
    /// - Parameters:
    ///   - mapping: The key mapping to render.
    ///   - hyperLinkedLayerInfos: Layers with trigger mode info for "hyper" activation.
    /// - Returns: Kanata action string (e.g., `(tap-hold 200 200 a lctl)` or just `esc`).
    public static func render(_ mapping: KeyMapping, hyperLinkedLayerInfos: [HyperLinkedLayerInfo]) -> String {
        guard let behavior = mapping.behavior else {
            // No advanced behavior—fall back to simple output rendering
            return KanataKeyConverter.convertToKanataSequence(mapping.output)
        }

        switch behavior {
        case let .dualRole(dr):
            return renderDualRole(dr, hyperLinkedLayerInfos: hyperLinkedLayerInfos)
        case let .tapOrTapDance(tapOrTap):
            return renderTapOrTapDance(tapOrTap, mapping: mapping, hyperLinkedLayerInfos: hyperLinkedLayerInfos)
        case let .macro(macro):
            return renderMacro(macro)
        case let .chord(ch):
            return renderChord(ch, hyperLinkedLayerInfos: hyperLinkedLayerInfos)
        }
    }

    // MARK: - Chord

    /// Render a chord behavior.
    /// Note: Chords in Kanata require special handling - they need a defchords block.
    /// For individual mappings, we return an alias reference that must be defined
    /// in a defchords section elsewhere in the config.
    private static func renderChord(_ ch: ChordBehavior, hyperLinkedLayerInfos _: [HyperLinkedLayerInfo]) -> String {
        // For chord behavior, we return an alias that references the chord
        // The actual defchords definition must be generated separately
        // Format: @chord-{groupName}
        // This allows the chord to be referenced in deflayer while the
        // defchords block is generated at config level
        "@\(ch.groupName)"
    }

    /// Generate a defchords block for a chord behavior.
    /// This should be called by the config generator to create the chord definition.
    /// Format: (defchords groupname timeout (key1 key2 ...) output)
    public static func renderChordDefinition(_ ch: ChordBehavior, hyperLinkedLayerInfos: [HyperLinkedLayerInfo] = []) -> String {
        let keys = ch.keys.map { KanataKeyConverter.convertToKanataKey($0) }.joined(separator: " ")
        let output = convertAction(ch.output, hyperLinkedLayerInfos: hyperLinkedLayerInfos)
        return "(defchords \(ch.groupName) \(ch.timeout)\n  (\(keys)) \(output)\n)"
    }

    // MARK: - Dual Role

    /// Render a dual-role (tap-hold) behavior.
    /// Chooses the appropriate Kanata variant based on flags.
    private static func renderDualRole(_ dr: DualRoleBehavior, hyperLinkedLayerInfos: [HyperLinkedLayerInfo]) -> String {
        // Split linked layers by trigger mode so tap/hold behave as configured.
        let tapLinkedLayers = hyperLinkedLayerInfos.filter { $0.triggerMode == .tap }

        // Tap-mode layers should be available even when hyper is produced by a hold action
        // (e.g., Caps Lock tap=Esc, hold=Hyper). Pass all linked layers to holdAction.
        let tapAction = convertAction(dr.tapAction, hyperLinkedLayerInfos: tapLinkedLayers)
        let holdAction = convertAction(dr.holdAction, hyperLinkedLayerInfos: hyperLinkedLayerInfos)
        let tapTimeout = dr.tapTimeout
        let holdTimeout = dr.holdTimeout

        // Use variables for timeouts if they match defaults, otherwise use literal values
        // This allows users to customize timing via defvar while preserving custom values
        let tapTimeoutStr = tapTimeout == 200 ? "$tap-timeout" : "\(tapTimeout)"
        let holdTimeoutStr = holdTimeout == 200 ? "$hold-timeout" : "\(holdTimeout)"

        // Choose variant based on flags (priority: activateHoldOnOtherKey > quickTap > customTapKeys > basic)
        if dr.activateHoldOnOtherKey {
            // tap-hold-press: hold triggers on any other key press
            return "(tap-hold-press \(tapTimeoutStr) \(holdTimeoutStr) \(tapAction) \(holdAction))"
        } else if dr.quickTap {
            // tap-hold-release: hold triggers on release of another key
            return "(tap-hold-release \(tapTimeoutStr) \(holdTimeoutStr) \(tapAction) \(holdAction))"
        } else if !dr.customTapKeys.isEmpty {
            // tap-hold-release-keys: early tap on specific keys
            let keys = dr.customTapKeys.map { KanataKeyConverter.convertToKanataKey($0) }.joined(separator: " ")
            return "(tap-hold-release-keys \(tapTimeoutStr) \(holdTimeoutStr) \(tapAction) \(holdAction) (\(keys)))"
        } else {
            // Basic tap-hold: pure timeout-based
            return "(tap-hold \(tapTimeoutStr) \(holdTimeoutStr) \(tapAction) \(holdAction))"
        }
    }

    // MARK: - Tap Dance

    /// Render a tap-dance behavior.
    /// Format: `(tap-dance timeout (action1 action2 ...))`
    private static func renderTapDance(_ td: TapDanceBehavior, hyperLinkedLayerInfos: [HyperLinkedLayerInfo]) -> String {
        guard !td.steps.isEmpty else {
            // Edge case: empty steps—return passthrough
            return "_"
        }

        let actions = td.steps.map { step in
            convertAction(step.action, hyperLinkedLayerInfos: hyperLinkedLayerInfos)
        }

        // Kanata tap-dance syntax: (tap-dance timeout (action1 action2 ...))
        return "(tap-dance \(td.windowMs) (\(actions.joined(separator: " "))))"
    }

    // MARK: - Tap or Tap-Dance

    private static func renderTapOrTapDance(
        _ behavior: TapOrTapDanceBehavior,
        mapping: KeyMapping,
        hyperLinkedLayerInfos: [HyperLinkedLayerInfo]
    ) -> String {
        switch behavior {
        case .tap:
            return KanataKeyConverter.convertToKanataSequence(mapping.output)
        case let .tapDance(tapDance):
            return renderTapDance(tapDance, hyperLinkedLayerInfos: hyperLinkedLayerInfos)
        }
    }

    // MARK: - Macro

    private static func renderMacro(_ macro: MacroBehavior) -> String {
        let outputs = macro.effectiveOutputs
        guard !outputs.isEmpty else { return "_" }

        if macro.source == .text, let text = macro.text, !text.isEmpty {
            switch TextToKanataKeyMapper.map(text: text) {
            case let .success(keys):
                return "(macro \(keys.joined(separator: " ")))"
            case .failure:
                return "_"
            }
        }

        let keys = outputs.map { KanataKeyConverter.convertToKanataKeyForMacro($0) }
        return "(macro \(keys.joined(separator: " ")))"
    }

    // MARK: - Action Conversion

    /// Convert an action string to Kanata syntax.
    /// Handles special keywords (hyper, meh) and multi-key combinations.
    private static func convertAction(_ action: String, hyperLinkedLayerInfos: [HyperLinkedLayerInfo]) -> String {
        let trimmed = action.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()

        // Special keyword: "hyper" = Cmd+Ctrl+Alt+Shift
        // If hyperLinkedLayerInfos is set, also activate those layers during hyper hold/tap
        if trimmed == "hyper" {
            if hyperLinkedLayerInfos.isEmpty {
                return "(multi lctl lmet lalt lsft)"
            } else {
                // Include layer activation and fake key notifications for each linked layer
                var components = ["lctl", "lmet", "lalt", "lsft"]
                for layerInfo in hyperLinkedLayerInfos {
                    let layerName = layerInfo.layerName
                    switch layerInfo.triggerMode {
                    case .hold:
                        // Hold mode: layer stays active while hyper is held
                        components.append("(layer-while-held \(layerName))")
                        components.append("(on-press-fakekey kp-layer-\(layerName)-enter tap)")
                        components.append("(on-release-fakekey kp-layer-\(layerName)-exit tap)")
                    case .tap:
                        // Tap mode: one-shot layer that deactivates after next key press
                        // Using one-shot-press with 5 second timeout (deactivates on any key or timeout).
                        // Ensure fakekey/modifier presses don't consume the one-shot activation.
                        components.append("(on-press-fakekey kp-layer-\(layerName)-enter tap)")
                        components.append("(one-shot-pause-processing 10)")
                        components.append("(one-shot-press 5000 (layer-while-held \(layerName)))")
                    }
                }
                return "(multi \(components.joined(separator: " ")))"
            }
        }

        // Special keyword: "meh" = Ctrl+Alt+Shift (no Cmd)
        if trimmed == "meh" {
            return "(multi lctl lalt lsft)"
        }

        // Check for space-separated tokens (multi-key action)
        let tokens = action.trimmingCharacters(in: .whitespacesAndNewlines)
            .components(separatedBy: .whitespaces)
            .filter { !$0.isEmpty }

        if tokens.count > 1 {
            // Multiple keys - wrap in (multi ...)
            let kanataKeys = tokens.map { KanataKeyConverter.convertToKanataKey($0) }
            return "(multi \(kanataKeys.joined(separator: " ")))"
        }

        // Single key - use standard conversion
        return KanataKeyConverter.convertToKanataKey(action)
    }
}
