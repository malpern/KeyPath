import Foundation

// MARK: - Kanata Behavior Parser

/// Parses KeyPath-generated Kanata syntax back into `MappingBehavior` values.
///
/// This is a **scoped parser** that only understands the syntax we emit, not arbitrary Kanata configs.
/// It's designed for round-tripping: `render(mapping)` → `parse(result)` should produce equivalent behavior.
///
/// ## Supported Syntax
///
/// **Tap-Hold variants:**
/// - `(tap-hold tapTimeout holdTimeout tapAction holdAction)`
/// - `(tap-hold-press tapTimeout holdTimeout tapAction holdAction)`
/// - `(tap-hold-release tapTimeout holdTimeout tapAction holdAction)`
///
/// **Tap-Dance:**
/// - `(tap-dance windowMs (action1 action2 ...))`
///
/// **Macro:**
/// - `(macro key1 key2 ...)`
///
/// ## Limitations
///
/// - Does not parse nested behaviors (e.g., tap-hold inside tap-dance)
/// - Does not handle Kanata's full action syntax (macros, layers, etc.)
/// - Returns `nil` for any unrecognized syntax
public enum KanataBehaviorParser {
    /// Attempt to parse a Kanata action string into a `MappingBehavior`.
    ///
    /// - Parameter action: The Kanata action string (e.g., `"(tap-hold 200 200 a lctl)"`)
    /// - Returns: A `MappingBehavior` if the syntax is recognized, `nil` otherwise.
    ///
    /// Simple keys (e.g., `"esc"`, `"M-c"`) return `nil` since they don't have advanced behavior.
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
            return .tapOrTapDance(.tapDance(tapDance))
        }

        // Try macro
        if let macro = parseMacro(trimmed) {
            return .macro(macro)
        }

        return nil
    }

    // MARK: - Tap-Hold Parsing

    /// Parse tap-hold, tap-hold-press, tap-hold-release, tap-hold-release-keys variants.
    /// Format: (tap-hold[-press|-release|-release-keys] tapTimeout holdTimeout tapAction holdAction [keys])
    private static func parseTapHold(_ action: String) -> DualRoleBehavior? {
        // Match tap-hold variants (order matters - longer variants first)
        let variants = ["tap-hold-release-keys", "tap-hold-press", "tap-hold-release", "tap-hold"]

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

        // Expected: tapTimeout holdTimeout tapAction holdAction [keys]
        guard tokens.count >= 4 else { return nil }

        guard let tapTimeout = parseTimeout(tokens[0], slot: .tap),
              let holdTimeout = parseTimeout(tokens[1], slot: .hold)
        else {
            return nil
        }

        let tapAction = tokens[2]
        let holdAction = tokens[3]

        // Determine flags from variant
        let activateHoldOnOtherKey = variant == "tap-hold-press"
        let quickTap = variant == "tap-hold-release"

        // Parse custom tap keys for tap-hold-release-keys
        var customTapKeys: [String] = []
        if variant == "tap-hold-release-keys", tokens.count >= 5 {
            let keysToken = tokens[4]
            // Keys are in format "(key1 key2 ...)"
            if keysToken.hasPrefix("("), keysToken.hasSuffix(")") {
                let keysBody = String(keysToken.dropFirst().dropLast())
                customTapKeys = keysBody.split(separator: " ").map { String($0) }
            }
        }

        return DualRoleBehavior(
            tapAction: tapAction,
            holdAction: holdAction,
            tapTimeout: tapTimeout,
            holdTimeout: holdTimeout,
            activateHoldOnOtherKey: activateHoldOnOtherKey,
            quickTap: quickTap,
            customTapKeys: customTapKeys
        )
    }

    private enum TimeoutSlot {
        case tap
        case hold
    }

    private static func parseTimeout(_ token: String, slot: TimeoutSlot) -> Int? {
        if let value = Int(token) {
            return value
        }

        switch slot {
        case .tap where token == "$tap-timeout":
            return defaultTapTimeout
        case .hold where token == "$hold-timeout":
            return defaultHoldTimeout
        default:
            return nil
        }
    }

    private static let defaultTapTimeout = 200
    private static let defaultHoldTimeout = 200

    // MARK: - Tap-Dance Parsing

    /// Parse tap-dance syntax.
    /// Format: (tap-dance windowMs (action1 action2 ...))
    private static func parseTapDance(_ action: String) -> TapDanceBehavior? {
        let prefix = "(tap-dance "
        guard action.hasPrefix(prefix) else { return nil }

        // Remove outer parens and "tap-dance "
        let prefixLen = prefix.count // 11 characters
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

        // Create steps with default labels (capitalized to match UI)
        let labels = ["Single Tap", "Double Tap", "Triple Tap", "Quad Tap", "Quint Tap"]
        let steps = actions.enumerated().map { index, action in
            TapDanceStep(
                label: index < labels.count ? labels[index] : "Tap \(index + 1)",
                action: action
            )
        }

        return TapDanceBehavior(windowMs: windowMs, steps: steps)
    }

    // MARK: - Macro Parsing

    /// Parse macro syntax.
    /// Format: (macro key1 key2 ...)
    private static func parseMacro(_ action: String) -> MacroBehavior? {
        let prefix = "(macro "
        guard action.hasPrefix(prefix), action.hasSuffix(")") else { return nil }

        let start = action.index(action.startIndex, offsetBy: prefix.count)
        let end = action.index(before: action.endIndex)
        guard start < end else { return nil }

        let body = String(action[start ..< end]).trimmingCharacters(in: .whitespacesAndNewlines)
        let tokens = tokenize(body)
        guard !tokens.isEmpty else { return nil }

        return MacroBehavior(outputs: tokens, source: .keys)
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
