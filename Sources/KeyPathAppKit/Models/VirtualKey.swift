import Foundation

/// Represents a virtual key defined in a Kanata configuration
/// via `defvirtualkeys` or `deffakekeys`
public struct VirtualKey: Identifiable, Sendable, Equatable {
    public let id: String // The key name
    public let name: String
    public let action: String // The raw action definition
    public let source: VirtualKeySource

    public enum VirtualKeySource: String, Sendable {
        case virtualkeys = "defvirtualkeys"
        case fakekeys = "deffakekeys"
    }

    public init(name: String, action: String, source: VirtualKeySource) {
        id = name
        self.name = name
        self.action = action
        self.source = source
    }
}

// MARK: - Virtual Key Parser

public enum VirtualKeyParser {
    /// Extract all virtual keys from a Kanata configuration string
    /// Parses both `defvirtualkeys` and `deffakekeys` blocks
    public static func parse(config: String) -> [VirtualKey] {
        var keys: [VirtualKey] = []

        // Parse defvirtualkeys blocks
        keys.append(contentsOf: parseBlock(config: config, blockType: "defvirtualkeys", source: .virtualkeys))

        // Parse deffakekeys blocks
        keys.append(contentsOf: parseBlock(config: config, blockType: "deffakekeys", source: .fakekeys))

        return keys
    }

    /// Parse a specific block type (defvirtualkeys or deffakekeys)
    private static func parseBlock(config: String, blockType: String, source: VirtualKey.VirtualKeySource) -> [VirtualKey] {
        var keys: [VirtualKey] = []

        // Find all occurrences of the block
        // Pattern: (defvirtualkeys ... )
        let pattern = "\\(\(blockType)\\s+([^)]+)\\)"
        guard let regex = try? NSRegularExpression(pattern: pattern, options: [.dotMatchesLineSeparators]) else {
            return []
        }

        let range = NSRange(config.startIndex..., in: config)
        let matches = regex.matches(in: config, options: [], range: range)

        for match in matches {
            guard let contentRange = Range(match.range(at: 1), in: config) else { continue }
            let content = String(config[contentRange])

            // Parse key definitions from the block content
            // Each definition is: name (action...)
            let definitions = parseDefinitions(content)
            for (name, action) in definitions {
                keys.append(VirtualKey(name: name, action: action, source: source))
            }
        }

        return keys
    }

    /// Parse individual key definitions from block content
    /// Format: name (action) or name action
    private static func parseDefinitions(_ content: String) -> [(name: String, action: String)] {
        var definitions: [(String, String)] = []
        var remaining = content.trimmingCharacters(in: .whitespacesAndNewlines)

        while !remaining.isEmpty {
            // Skip whitespace
            remaining = remaining.trimmingCharacters(in: .whitespacesAndNewlines)
            if remaining.isEmpty { break }

            // Extract the name (identifier before space or paren)
            guard let nameEnd = remaining.firstIndex(where: { $0.isWhitespace || $0 == "(" }) else {
                break
            }
            let name = String(remaining[..<nameEnd]).trimmingCharacters(in: .whitespacesAndNewlines)
            remaining = String(remaining[nameEnd...]).trimmingCharacters(in: .whitespaces)

            if remaining.isEmpty || name.isEmpty { break }

            // Extract the action
            let action: String
            if remaining.first == "(" {
                // Action is a parenthesized expression - find matching close paren
                if let actionEnd = findMatchingParen(remaining) {
                    action = String(remaining[...actionEnd])
                    remaining = String(remaining[remaining.index(after: actionEnd)...])
                } else {
                    break
                }
            } else {
                // Action is a simple token
                if let actionEnd = remaining.firstIndex(where: { $0.isWhitespace || $0.isNewline }) {
                    action = String(remaining[..<actionEnd])
                    remaining = String(remaining[actionEnd...])
                } else {
                    action = remaining
                    remaining = ""
                }
            }

            if !name.isEmpty, !action.isEmpty {
                definitions.append((name, action))
            }
        }

        return definitions
    }

    /// Find the index of the closing paren that matches the opening paren at position 0
    private static func findMatchingParen(_ str: String) -> String.Index? {
        guard str.first == "(" else { return nil }

        var depth = 0
        for (index, char) in str.enumerated() {
            if char == "(" {
                depth += 1
            } else if char == ")" {
                depth -= 1
                if depth == 0 {
                    return str.index(str.startIndex, offsetBy: index)
                }
            }
        }
        return nil
    }
}
