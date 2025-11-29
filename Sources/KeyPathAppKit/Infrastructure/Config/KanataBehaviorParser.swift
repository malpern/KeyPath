import Foundation

// MARK: - Kanata Behavior Parser

/// Parses KeyPath-generated Kanata syntax back into `MappingBehavior` values.
/// This is a scoped parser that only understands the syntax we emit, not arbitrary Kanata configs.
public enum KanataBehaviorParser {

    /// Attempt to parse a Kanata action string into a MappingBehavior.
    /// Returns nil if the string is a simple key (no behavior) or unrecognized syntax.
    public static func parse(_ action: String) -> MappingBehavior? {
        let trimmed = action.trimmingCharacters(in: .whitespacesAndNewlines)

        // Must start with ( to be a complex action
        guard trimmed.hasPrefix("(") else {
            return nil
        }

        // Try tap-hold variants
        if let dualRole = parseTapHold(trimmed) {
            return .dualRole(dualRole)
        }

        // Try tap-dance
        if let tapDance = parseTapDance(trimmed) {
            return .tapDance(tapDance)
        }

        return nil
    }

    // MARK: - Tap-Hold Parsing

    /// Parse tap-hold, tap-hold-press, tap-hold-release variants.
    /// Format: (tap-hold[-press|-release] tapTimeout holdTimeout tapAction holdAction)
    private static func parseTapHold(_ action: String) -> DualRoleBehavior? {
        // Match tap-hold variants
        let variants = ["tap-hold-press", "tap-hold-release", "tap-hold"]

        for variant in variants {
            if action.hasPrefix("(\(variant) ") {
                return parseTapHoldBody(action, variant: variant)
            }
        }

        return nil
    }

    private static func parseTapHoldBody(_ action: String, variant: String) -> DualRoleBehavior? {
        // Remove outer parens and variant name
        let prefixLen = variant.count + 2 // "(" + variant + " "
        guard action.count > prefixLen + 1 else { return nil }

        let start = action.index(action.startIndex, offsetBy: prefixLen)
        let end = action.index(action.endIndex, offsetBy: -1) // Remove trailing ")"
        guard start < end else { return nil }

        let body = String(action[start ..< end])
        let tokens = tokenize(body)

        // Expected: tapTimeout holdTimeout tapAction holdAction
        guard tokens.count >= 4 else { return nil }

        guard let tapTimeout = Int(tokens[0]),
              let holdTimeout = Int(tokens[1]) else {
            return nil
        }

        let tapAction = tokens[2]
        let holdAction = tokens[3]

        // Determine flags from variant
        let activateHoldOnOtherKey = variant == "tap-hold-press"
        let quickTap = variant == "tap-hold-release"

        return DualRoleBehavior(
            tapAction: tapAction,
            holdAction: holdAction,
            tapTimeout: tapTimeout,
            holdTimeout: holdTimeout,
            activateHoldOnOtherKey: activateHoldOnOtherKey,
            quickTap: quickTap
        )
    }

    // MARK: - Tap-Dance Parsing

    /// Parse tap-dance syntax.
    /// Format: (tap-dance windowMs (action1 action2 ...))
    private static func parseTapDance(_ action: String) -> TapDanceBehavior? {
        guard action.hasPrefix("(tap-dance ") else { return nil }

        // Remove outer parens and "tap-dance "
        let prefixLen = 12 // "(tap-dance "
        guard action.count > prefixLen + 1 else { return nil }

        let start = action.index(action.startIndex, offsetBy: prefixLen)
        let end = action.index(action.endIndex, offsetBy: -1)
        guard start < end else { return nil }

        let body = String(action[start ..< end])

        // Find the window value (first token before the nested paren list)
        guard let spaceIndex = body.firstIndex(of: " ") else { return nil }
        let windowStr = String(body[..<spaceIndex])
        guard let windowMs = Int(windowStr) else { return nil }

        // Find the nested action list
        let remainder = String(body[body.index(after: spaceIndex)...]).trimmingCharacters(in: .whitespaces)
        guard remainder.hasPrefix("("), remainder.hasSuffix(")") else { return nil }

        // Extract actions from nested list
        let actionsStart = remainder.index(after: remainder.startIndex)
        let actionsEnd = remainder.index(before: remainder.endIndex)
        guard actionsStart < actionsEnd else { return nil }

        let actionsBody = String(remainder[actionsStart ..< actionsEnd])
        let actions = tokenize(actionsBody)

        guard !actions.isEmpty else { return nil }

        // Create steps with default labels
        let labels = ["Single tap", "Double tap", "Triple tap", "Quad tap", "Quint tap"]
        let steps = actions.enumerated().map { index, action in
            TapDanceStep(
                label: index < labels.count ? labels[index] : "Tap \(index + 1)",
                action: action
            )
        }

        return TapDanceBehavior(windowMs: windowMs, steps: steps)
    }

    // MARK: - Tokenizer

    /// Simple tokenizer that handles nested parens as single tokens.
    private static func tokenize(_ input: String) -> [String] {
        var tokens: [String] = []
        var current = ""
        var depth = 0

        for char in input {
            if char == "(" {
                depth += 1
                current.append(char)
            } else if char == ")" {
                depth -= 1
                current.append(char)
                if depth == 0, !current.isEmpty {
                    tokens.append(current.trimmingCharacters(in: .whitespaces))
                    current = ""
                }
            } else if char.isWhitespace, depth == 0 {
                if !current.isEmpty {
                    tokens.append(current.trimmingCharacters(in: .whitespaces))
                    current = ""
                }
            } else {
                current.append(char)
            }
        }

        if !current.isEmpty {
            tokens.append(current.trimmingCharacters(in: .whitespaces))
        }

        return tokens.filter { !$0.isEmpty }
    }
}

