import Foundation

// MARK: - Kanata Behavior Renderer

/// Renders `MappingBehavior` values to Kanata configuration syntax.
public enum KanataBehaviorRenderer {
    /// Render a mapping's behavior (or simple output) to Kanata syntax.
    /// - Parameters:
    ///   - mapping: The key mapping to render.
    /// - Returns: Kanata action string (e.g., `(tap-hold 200 200 a lctl)` or just `esc`).
    public static func render(_ mapping: KeyMapping) -> String {
        guard let behavior = mapping.behavior else {
            // No advanced behavior—fall back to simple output rendering
            return KanataKeyConverter.convertToKanataSequence(mapping.output)
        }

        switch behavior {
        case let .dualRole(dr):
            return renderDualRole(dr)
        case let .tapDance(td):
            return renderTapDance(td)
        }
    }

    // MARK: - Dual Role

    /// Render a dual-role (tap-hold) behavior.
    /// Chooses the appropriate Kanata variant based on flags.
    private static func renderDualRole(_ dr: DualRoleBehavior) -> String {
        let tapAction = convertAction(dr.tapAction)
        let holdAction = convertAction(dr.holdAction)
        let tapTimeout = dr.tapTimeout
        let holdTimeout = dr.holdTimeout

        // Choose variant based on flags (priority: activateHoldOnOtherKey > quickTap > customTapKeys > basic)
        if dr.activateHoldOnOtherKey {
            // tap-hold-press: hold triggers on any other key press
            return "(tap-hold-press \(tapTimeout) \(holdTimeout) \(tapAction) \(holdAction))"
        } else if dr.quickTap {
            // tap-hold-release: hold triggers on release of another key
            return "(tap-hold-release \(tapTimeout) \(holdTimeout) \(tapAction) \(holdAction))"
        } else if !dr.customTapKeys.isEmpty {
            // tap-hold-release-keys: early tap on specific keys
            let keys = dr.customTapKeys.map { KanataKeyConverter.convertToKanataKey($0) }.joined(separator: " ")
            return "(tap-hold-release-keys \(tapTimeout) \(holdTimeout) \(tapAction) \(holdAction) (\(keys)))"
        } else {
            // Basic tap-hold: pure timeout-based
            return "(tap-hold \(tapTimeout) \(holdTimeout) \(tapAction) \(holdAction))"
        }
    }

    // MARK: - Tap Dance

    /// Render a tap-dance behavior.
    /// Format: `(tap-dance timeout (action1 action2 ...))`
    private static func renderTapDance(_ td: TapDanceBehavior) -> String {
        guard !td.steps.isEmpty else {
            // Edge case: empty steps—return passthrough
            return "_"
        }

        let actions = td.steps.map { step in
            convertAction(step.action)
        }

        // Kanata tap-dance syntax: (tap-dance timeout (action1 action2 ...))
        return "(tap-dance \(td.windowMs) (\(actions.joined(separator: " "))))"
    }

    // MARK: - Action Conversion

    /// Convert an action string to Kanata syntax.
    /// Handles special keywords (hyper, meh) and multi-key combinations.
    private static func convertAction(_ action: String) -> String {
        let trimmed = action.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()

        // Special keyword: "hyper" = Cmd+Ctrl+Alt+Shift
        if trimmed == "hyper" {
            return "(multi lctl lmet lalt lsft)"
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
