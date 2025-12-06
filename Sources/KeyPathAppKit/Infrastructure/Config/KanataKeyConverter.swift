import Foundation

// MARK: - Key Conversion Utilities

/// Utility enum for converting keys between KeyPath and Kanata formats.
///
/// This converter handles the translation between user-friendly key names
/// (like "caps lock", "command") and Kanata's internal key format (like "caps", "lmet").
///
/// # Usage
/// ```swift
/// let kanataKey = KanataKeyConverter.convertToKanataKey("caps lock")  // "caps"
/// let sequence = KanataKeyConverter.convertToKanataSequence("cmd space")  // "(lmet spc)"
/// ```
public enum KanataKeyConverter {
    /// Convert KeyPath key to Kanata key format for use inside macros.
    ///
    /// Inside macros:
    /// - Chord syntax like `M-right` requires UPPERCASE modifier prefixes
    /// - Bare digit keys (0-9) are parsed as millisecond delays, so must use Digit0-Digit9
    ///
    /// - Parameter input: The key name to convert
    /// - Returns: The Kanata-formatted key name suitable for macro context
    public static func convertToKanataKeyForMacro(_ input: String) -> String {
        // Known modifier prefixes that must remain uppercase in macro context
        // Order matters - check longer prefixes first
        let modifierPrefixes = ["M-S-", "C-S-", "A-S-", "M-", "A-", "C-", "S-"]

        for prefix in modifierPrefixes {
            if input.hasPrefix(prefix) {
                // Preserve uppercase prefix, convert base key (with forMacro for digits)
                let baseKey = String(input.dropFirst(prefix.count))
                let convertedBase = convertToKanataKey(baseKey, forMacro: true)
                return prefix + convertedBase
            }
        }

        // No modifier prefix - use standard conversion with forMacro flag
        return convertToKanataKey(input, forMacro: true)
    }

    /// Convert KeyPath input key to Kanata key format.
    ///
    /// - Parameter input: The key name to convert (e.g., "caps lock", "command", "space")
    /// - Parameter forMacro: If true, converts digit keys to their Kanata names (e.g., "1" → "Digit1")
    ///                       since bare numbers in macros are interpreted as millisecond delays
    /// - Returns: The Kanata-formatted key name (e.g., "caps", "lmet", "spc")
    public static func convertToKanataKey(_ input: String, forMacro: Bool = false) -> String {
        let lowercased = input.lowercased()

        // Check if we have a specific mapping
        if let mapped = keyMap[lowercased] {
            return mapped
        }

        // For single characters
        if lowercased.count == 1 {
            // IMPORTANT: In macros, bare digit keys (0-9) are parsed as millisecond delays
            // We must use their full key names (Digit0-Digit9) instead
            if forMacro, let char = lowercased.first, char.isNumber {
                return "Digit\(char)"
            }
            return lowercased
        }

        // For multi-character tokens in macro context that are purely numeric (e.g., "10", "200")
        // These would be parsed as delays, so we need to split into individual Digit keys
        // Return a space-separated sequence that the caller can embed in the macro
        if forMacro, !input.isEmpty, input.allSatisfy({ $0.isNumber }) {
            let digitKeys = input.map { "Digit\($0)" }
            return digitKeys.joined(separator: " ")
        }

        // For tokens that would break Kanata syntax, replace parens explicitly
        if lowercased.contains("(") { return "lpar" }
        if lowercased.contains(")") { return "rpar" }

        // For function keys and others, return as-is but lowercased
        return lowercased
    }

    /// Convert KeyPath output sequence to Kanata output format.
    ///
    /// Handles single keys, key sequences, and text to type:
    /// - Single key: `"escape"` → `"esc"`
    /// - Key sequence: `"cmd space"` → `"(lmet spc)"`
    /// - Text to type: `"hello"` → `"(macro h e l l o)"`
    ///
    /// - Parameter output: The output sequence to convert
    /// - Returns: The Kanata-formatted output
    public static func convertToKanataSequence(_ output: String) -> String {
        let trimmed = output.trimmingCharacters(in: .whitespacesAndNewlines)

        // Split on any whitespace
        let tokens = trimmed.components(separatedBy: .whitespacesAndNewlines).filter { !$0.isEmpty }

        // No tokens -> nothing to emit (avoid indexing empty array)
        if tokens.isEmpty {
            return ""
        }

        // Multiple whitespace-separated tokens (e.g., "1 2 3 4") → macro sequence
        if tokens.count > 1 {
            // Use convertToKanataKeyForMacro to preserve uppercase modifier prefixes
            let kanataKeys = tokens.map { convertToKanataKeyForMacro($0) }
            return "(macro \(kanataKeys.joined(separator: " ")))"
        }

        // Single token - check if it's a text sequence to type (e.g., "123", "hello")
        let singleToken = tokens[0]

        // If it's a multi-character string that looks like text to type (not a key name)
        // Convert to macro for typing each character
        if singleToken.count > 1, shouldConvertToMacro(singleToken) {
            // Split into individual characters and convert each to a key
            // Use convertToKanataKeyForMacro to handle digits (0-9 → Digit0-Digit9)
            let characters = Array(singleToken)
            let keys = characters.map { convertToKanataKeyForMacro(String($0)) }
            return "(macro \(keys.joined(separator: " ")))"
        }

        // Single key output (not in a macro)
        // Handle modifier prefixes separately to preserve uppercase (M-, A-, C-, S-)
        let modifierPrefixes = ["M-S-", "C-S-", "A-S-", "M-", "A-", "C-", "S-"]
        for prefix in modifierPrefixes {
            if singleToken.hasPrefix(prefix) {
                let baseKey = String(singleToken.dropFirst(prefix.count))
                let convertedBase = convertToKanataKey(baseKey, forMacro: false)
                return prefix + convertedBase
            }
        }
        // No modifier prefix - standard conversion (digits are fine as bare numbers outside macros)
        return convertToKanataKey(singleToken, forMacro: false)
    }

    // MARK: - Private Helpers

    /// Key mapping from user-friendly names to Kanata key codes
    private static let keyMap: [String: String] = [
        "caps": "caps",
        "capslock": "caps",
        "caps lock": "caps",
        "space": "spc",
        "spacebar": "spc",
        "enter": "ret",
        "return": "ret",
        "tab": "tab",
        "escape": "esc",
        "esc": "esc",
        "backspace": "bspc",
        "delete": "del",
        "cmd": "lmet",
        "command": "lmet",
        "lcmd": "lmet",
        "rcmd": "rmet",
        "leftcmd": "lmet",
        "rightcmd": "rmet",
        "left command": "lmet",
        "right command": "rmet",
        "left shift": "lsft",
        "lshift": "lsft",
        "right shift": "rsft",
        "rshift": "rsft",
        "left control": "lctl",
        "lctrl": "lctl",
        "ctrl": "lctl",
        "right control": "rctl",
        "rctrl": "rctl",
        "left option": "lalt",
        "lalt": "lalt",
        "right option": "ralt",
        "ralt": "ralt",
        "(": "lpar",
        ")": "rpar",
        // Punctuation keys - must be converted to kanata's abbreviated names
        "apostrophe": "'",
        "semicolon": ";",
        "comma": ",",
        "dot": ".",
        "period": ".",
        "slash": "/",
        "minus": "min",
        "equal": "eql",
        "equals": "eql",
        "grave": "grv",
        "backslash": "\\",
        "leftbrace": "[",
        "rightbrace": "]",
        "leftbracket": "[",
        "rightbracket": "]"
    ]

    /// Determine if a string should be converted to a macro (typed character by character)
    /// vs treated as a single key name like "escape" or "tab"
    private static func shouldConvertToMacro(_ token: String) -> Bool {
        // Check for Kanata modifier prefixes (e.g., A-right, M-left, C-S-a)
        // These should NOT be converted to macros - they are valid Kanata modified key outputs
        let modifierPattern = #"^(A-|M-|C-|S-|RA-|RM-|RC-|RS-|AG-)+"#
        if let regex = try? NSRegularExpression(pattern: modifierPattern, options: .caseInsensitive) {
            let range = NSRange(token.startIndex..., in: token)
            if regex.firstMatch(in: token, options: [], range: range) != nil {
                return false
            }
        }

        // If it's a known key name, don't convert to macro
        if knownKeyNames.contains(token.lowercased()) {
            return false
        }

        // If it contains multiple alphanumeric characters or symbols, treat as text to type
        return token.count > 1
    }

    /// Known key names that shouldn't be split into macros
    private static let knownKeyNames: Set<String> = [
        "escape", "esc", "return", "ret", "enter",
        "backspace", "bspc", "delete", "del",
        "tab", "space", "spc",
        "capslock", "caps", "capslk",
        "leftshift", "lsft", "rightshift", "rsft",
        "leftctrl", "lctl", "rightctrl", "rctl", "ctrl",
        "leftalt", "lalt", "rightalt", "ralt",
        "leftmeta", "lmet", "rightmeta", "rmet",
        "leftcmd", "rightcmd", "cmd", "command", "lcmd", "rcmd",
        "up", "down", "left", "right",
        "home", "end", "pageup", "pgup", "pagedown", "pgdn",
        "f1", "f2", "f3", "f4", "f5", "f6",
        "f7", "f8", "f9", "f10", "f11", "f12", "f13", "f14", "f15",
        "f16", "f17", "f18", "f19", "f20",
        // Kanata media/system outputs
        "brdn", "brup", "mission_control", "launchpad",
        "prev", "pp", "next", "mute", "vold", "volu"
    ]
}
