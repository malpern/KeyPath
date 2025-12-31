import Foundation

// MARK: - Kanata Behavior Renderer

/// Renders `MappingBehavior` values to Kanata configuration syntax.
public enum KanataBehaviorRenderer {
    /// Render a mapping's behavior (or simple output) to Kanata syntax.
    /// - Parameters:
    ///   - mapping: The key mapping to render.
    ///   - hyperLinkedLayers: Layers that should be activated when "hyper" is triggered.
    /// - Returns: Kanata action string (e.g., `(tap-hold 200 200 a lctl)` or just `esc`).
    public static func render(_ mapping: KeyMapping, hyperLinkedLayers: [String] = []) -> String {
        guard let behavior = mapping.behavior else {
            // No advanced behavior—fall back to simple output rendering
            return KanataKeyConverter.convertToKanataSequence(mapping.output)
        }

        switch behavior {
        case let .dualRole(dr):
            return renderDualRole(dr, hyperLinkedLayers: hyperLinkedLayers)
        case let .tapDance(td):
            return renderTapDance(td, hyperLinkedLayers: hyperLinkedLayers)
        }
    }

    // MARK: - Dual Role

    /// Render a dual-role (tap-hold) behavior.
    /// Chooses the appropriate Kanata variant based on flags.
    private static func renderDualRole(_ dr: DualRoleBehavior, hyperLinkedLayers: [String]) -> String {
        let tapAction = convertAction(dr.tapAction, hyperLinkedLayers: hyperLinkedLayers)
        let holdAction = convertAction(dr.holdAction, hyperLinkedLayers: hyperLinkedLayers)
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
    private static func renderTapDance(_ td: TapDanceBehavior, hyperLinkedLayers: [String]) -> String {
        guard !td.steps.isEmpty else {
            // Edge case: empty steps—return passthrough
            return "_"
        }

        let actions = td.steps.map { step in
            convertAction(step.action, hyperLinkedLayers: hyperLinkedLayers)
        }

        // Kanata tap-dance syntax: (tap-dance timeout (action1 action2 ...))
        return "(tap-dance \(td.windowMs) (\(actions.joined(separator: " "))))"
    }

    // MARK: - Action Conversion

    /// Convert an action string to Kanata syntax.
    /// Handles special keywords (hyper, meh) and multi-key combinations.
    private static func convertAction(_ action: String, hyperLinkedLayers: [String]) -> String {
        let trimmed = action.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()

        // Special keyword: "hyper" = Cmd+Ctrl+Alt+Shift
        // If hyperLinkedLayers is set, also activate those layers during hyper hold
        if trimmed == "hyper" {
            if hyperLinkedLayers.isEmpty {
                return "(multi lctl lmet lalt lsft)"
            } else {
                // Include layer-while-held and fake key notifications for each linked layer
                var components = ["lctl", "lmet", "lalt", "lsft"]
                for layerName in hyperLinkedLayers {
                    components.append("(layer-while-held \(layerName))")
                    components.append("(on-press-fakekey kp-layer-\(layerName)-enter tap)")
                    components.append("(on-release-fakekey kp-layer-\(layerName)-exit tap)")
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
