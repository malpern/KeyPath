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
        let tapAction = KanataKeyConverter.convertToKanataKey(dr.tapAction)
        let holdAction = KanataKeyConverter.convertToKanataKey(dr.holdAction)
        let tapTimeout = dr.tapTimeout
        let holdTimeout = dr.holdTimeout

        // Choose variant based on flags
        let variant = if dr.activateHoldOnOtherKey {
            // tap-hold-press: hold triggers on any other key press
            "tap-hold-press"
        } else if dr.quickTap {
            // tap-hold-release: hold triggers on release of another key
            "tap-hold-release"
        } else {
            // Basic tap-hold: pure timeout-based
            "tap-hold"
        }

        return "(\(variant) \(tapTimeout) \(holdTimeout) \(tapAction) \(holdAction))"
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
            KanataKeyConverter.convertToKanataKey(step.action)
        }

        // Kanata tap-dance syntax: (tap-dance timeout (action1 action2 ...))
        return "(tap-dance \(td.windowMs) (\(actions.joined(separator: " "))))"
    }
}
