import Foundation

/// Unified formatter for converting kanata key names to display symbols.
///
/// Consolidates duplicate key formatting logic from:
/// - MapperViewModel.formatKeyForDisplay
/// - KeyboardVisualizationViewModel.singleKeyDisplayLabel
///
/// ## Usage
/// ```swift
/// let symbol = KeyDisplayFormatter.symbol(for: "leftmeta") // "⌘"
/// let display = KeyDisplayFormatter.format("lctl") // "⌃"
/// ```
public enum KeyDisplayFormatter {
    // MARK: - Primary Symbols

    /// Map of kanata key names to display symbols
    private static let symbolMap: [String: String] = [
        // Modifier keys
        "leftmeta": "⌘",
        "rightmeta": "⌘",
        "lmet": "⌘",
        "rmet": "⌘",
        "cmd": "⌘",
        "command": "⌘",

        "leftalt": "⌥",
        "rightalt": "⌥",
        "lalt": "⌥",
        "ralt": "⌥",
        "alt": "⌥",
        "opt": "⌥",
        "option": "⌥",

        "leftshift": "⇧",
        "rightshift": "⇧",
        "lsft": "⇧",
        "rsft": "⇧",
        "shift": "⇧",

        "leftctrl": "⌃",
        "rightctrl": "⌃",
        "lctl": "⌃",
        "rctl": "⌃",
        "ctrl": "⌃",
        "control": "⌃",

        "capslock": "⇪",
        "caps": "⇪",

        // Composite modifiers
        "hyper": "✦",
        "meh": "◆",

        // Special keys
        "space": "⎵",
        "spc": "⎵",
        "sp": "⎵",
        "⎵": "⎵",

        "enter": "↩",
        "ret": "↩",
        "return": "↩",

        "tab": "⇥",
        "⭾": "⇥",

        "backspace": "⌫",
        "bspc": "⌫",

        "delete": "⌦",
        "del": "⌦",

        "esc": "⎋",
        "escape": "⎋",

        // Arrow keys
        "left": "←",
        "right": "→",
        "up": "↑",
        "down": "↓",
        "arrowleft": "←",
        "arrowright": "→",
        "arrowup": "↑",
        "arrowdown": "↓",
        "←": "←",
        "→": "→",
        "↑": "↑",
        "↓": "↓",

        // Function/Globe key - keep as "fn" so keycap views can render SF Symbol
        "fn": "fn",
        "function": "fn",

        // Punctuation
        "grave": "`",
        "grv": "`",
        "minus": "-",
        "min": "-",
        "equal": "=",
        "eql": "=",
        "leftbrace": "[",
        "lbrc": "[",
        "rightbrace": "]",
        "rbrc": "]",
        "backslash": "\\",
        "bksl": "\\",
        "semicolon": ";",
        "scln": ";",
        "apostrophe": "'",
        "apos": "'",
        "comma": ",",
        "comm": ",",
        "dot": ".",
        "slash": "/"
    ]

    // MARK: - Public API

    /// Get the display symbol for a kanata key name.
    ///
    /// - Parameter key: The kanata key name (e.g., "leftmeta", "lctl", "a")
    /// - Returns: The display symbol if found in the mapping, nil otherwise
    public static func symbol(for key: String) -> String? {
        symbolMap[key.lowercased()]
    }

    /// Format a kanata key name for display.
    ///
    /// - Parameter key: The kanata key name
    /// - Returns: The display symbol if mapped, or the key uppercased for letters,
    ///            or the key itself for other characters
    public static func format(_ key: String) -> String {
        let normalized = key.lowercased().trimmingCharacters(in: .whitespaces)

        // Check symbol map first
        if let symbol = symbolMap[normalized] {
            return symbol
        }

        // Single letters -> uppercase
        if normalized.count == 1, let char = normalized.first, char.isLetter {
            return normalized.uppercased()
        }

        // Single digits -> as-is
        if normalized.count == 1, let char = normalized.first, char.isNumber {
            return normalized
        }

        // Fallback: uppercase the key
        return key.uppercased()
    }

    /// Format a key output for tap-hold display labels.
    ///
    /// - Parameter output: The output key string (may contain multiple keys)
    /// - Returns: The display label, or nil if empty/unmappable
    public static func tapHoldLabel(for output: String) -> String? {
        let trimmed = output.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return nil }

        let normalized = trimmed.lowercased()

        // Handle multi-key outputs (modifier combos)
        let parts = normalized
            .split(whereSeparator: { $0 == " " || $0 == "+" })
            .map(String.init)

        if parts.count > 1 {
            // Check for Hyper (Ctrl+Cmd+Alt+Shift)
            let partSet = Set(parts)
            let hyperSet: Set<String> = ["lctl", "lmet", "lalt", "lsft"]
            let mehSet: Set<String> = ["lctl", "lalt", "lsft"]

            if partSet.isSuperset(of: hyperSet) { return "✦" }
            if partSet.isSuperset(of: mehSet) { return "◆" }

            // Build label from parts
            let labels = parts.compactMap { singleKeyLabel($0) }
            return labels.isEmpty ? nil : labels.joined()
        }

        return singleKeyLabel(normalized)
    }

    /// Get display label for a single key.
    ///
    /// - Parameter key: The normalized (lowercased) key name
    /// - Returns: The display label, or nil for space/empty
    private static func singleKeyLabel(_ key: String) -> String? {
        // Special case: space returns empty (no label needed)
        if key == "space" || key == "spc" || key == "sp" {
            return ""
        }

        if let symbol = symbolMap[key] {
            return symbol
        }

        // Single letter -> uppercase
        if key.count == 1, let char = key.first, char.isLetter {
            return key.uppercased()
        }

        // Single digit -> as-is
        if key.count == 1, let char = key.first, char.isNumber {
            return key
        }

        // Unknown key -> return as-is if non-empty
        return key.isEmpty ? nil : key
    }
}
