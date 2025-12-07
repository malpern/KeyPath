import Foundation

/// Validates custom rules and provides autocomplete suggestions for key names
public enum CustomRuleValidator {
    // MARK: - Valid Key Sets

    /// All valid Kanata key names (lowercase, canonical form)
    public static let validKanataKeys: Set<String> = {
        var keys = Set<String>()

        // Letters a-z
        for char in "abcdefghijklmnopqrstuvwxyz" {
            keys.insert(String(char))
        }

        // Numbers 0-9
        for char in "0123456789" {
            keys.insert(String(char))
        }

        // Function keys
        for i in 1 ... 20 {
            keys.insert("f\(i)")
        }

        // Special keys
        keys.formUnion([
            // Modifiers
            "caps", "lsft", "rsft", "lctl", "rctl", "lalt", "ralt", "lmet", "rmet",
            // Navigation
            "left", "right", "up", "down", "home", "end", "pgup", "pgdn",
            // Editing
            "spc", "ret", "tab", "esc", "bspc", "del", "ins",
            // Punctuation
            "grv", "min", "eql", "lbrc", "rbrc", "bsls", "scln", "quot", "comm", "dot", "slsh",
            "lpar", "rpar",
            // Media/System (macOS)
            "brdn", "brup", "prev", "pp", "next", "mute", "vold", "volu",
            // Special
            "f18", "f19", "f20",
            // Numpad
            "kp0", "kp1", "kp2", "kp3", "kp4", "kp5", "kp6", "kp7", "kp8", "kp9",
            "kprt", "kppl", "kpmn", "kpas", "kpsl", "kpdot"
        ])

        return keys
    }()

    /// User-friendly aliases that map to canonical Kanata keys
    public static let keyAliases: [String: String] = [
        // Caps Lock
        "capslock": "caps",
        "caps lock": "caps",
        "capslk": "caps",

        // Space
        "space": "spc",
        "spacebar": "spc",

        // Enter/Return
        "enter": "ret",
        "return": "ret",

        // Escape
        "escape": "esc",

        // Backspace
        "backspace": "bspc",

        // Delete
        "delete": "del",

        // Modifiers
        "cmd": "lmet",
        "command": "lmet",
        "lcmd": "lmet",
        "rcmd": "rmet",
        "leftcmd": "lmet",
        "rightcmd": "rmet",
        "left command": "lmet",
        "right command": "rmet",
        "ctrl": "lctl",
        "control": "lctl",
        "lctrl": "lctl",
        "rctrl": "rctl",
        "left control": "lctl",
        "right control": "rctl",
        "shift": "lsft",
        "lshift": "lsft",
        "rshift": "rsft",
        "left shift": "lsft",
        "right shift": "rsft",
        "alt": "lalt",
        "option": "lalt",
        "opt": "lalt",
        "left option": "lalt",
        "right option": "ralt",

        // Navigation
        "pageup": "pgup",
        "page up": "pgup",
        "pagedown": "pgdn",
        "page down": "pgdn",
        "insert": "ins",

        // Punctuation
        "grave": "grv",
        "backtick": "grv",
        "minus": "min",
        "hyphen": "min",
        "equals": "eql",
        "equal": "eql",
        "leftbracket": "lbrc",
        "rightbracket": "rbrc",
        "backslash": "bsls",
        "semicolon": "scln",
        "quote": "quot",
        "apostrophe": "quot",
        "comma": "comm",
        "period": "dot",
        "slash": "slsh",
        "forwardslash": "slsh",

        // Parentheses
        "(": "lpar",
        ")": "rpar",

        // Media
        "play": "pp",
        "pause": "pp",
        "playpause": "pp",
        "play/pause": "pp",
        "previous": "prev",
        "next track": "next",
        "prev track": "prev",
        "volume up": "volu",
        "volume down": "vold",
        "brightness up": "brup",
        "brightness down": "brdn"
    ]

    /// Keys commonly used as autocomplete suggestions (sorted by frequency of use)
    public static let commonKeys: [String] = [
        "caps", "esc", "tab", "ret", "spc", "bspc", "del",
        "lmet", "rmet", "lctl", "rctl", "lsft", "rsft", "lalt", "ralt",
        "left", "right", "up", "down", "home", "end", "pgup", "pgdn",
        "f1", "f2", "f3", "f4", "f5", "f6", "f7", "f8", "f9", "f10", "f11", "f12",
        "f18", "f19", "f20",
        "brdn", "brup", "prev", "pp", "next", "mute", "vold", "volu"
    ]

    // MARK: - Validation

    /// Validation error types
    public enum ValidationError: LocalizedError, Equatable {
        case emptyInput
        case emptyOutput
        case emptyTitle
        case invalidInputKey(String)
        case invalidOutputKey(String)
        case selfMapping
        case conflict(with: String, key: String)

        public var errorDescription: String? {
            switch self {
            case .emptyInput:
                "Input key cannot be empty"
            case .emptyOutput:
                "Output key cannot be empty"
            case .emptyTitle:
                "Title cannot be empty"
            case let .invalidInputKey(key):
                "Invalid input key: '\(key)'"
            case let .invalidOutputKey(key):
                "Invalid output key: '\(key)'"
            case .selfMapping:
                "Input and output are the same (rule has no effect)"
            case let .conflict(name, key):
                "Conflicts with '\(name)' on key '\(key)'"
            }
        }
    }

    /// Validate a custom rule
    /// - Parameter rule: The rule to validate
    /// - Returns: Array of validation errors (empty if valid)
    public static func validate(_ rule: CustomRule) -> [ValidationError] {
        var errors: [ValidationError] = []

        errors.append(contentsOf: validateKeys(input: rule.input, output: rule.output))

        // If we already have empties, skip further checks
        guard errors.allSatisfy({ $0 != .emptyInput && $0 != .emptyOutput }) else { return errors }

        // Check for self-mapping (again after normalization to cover aliases)
        let normalizedInput = normalizeKey(rule.input)
        let normalizedOutput = normalizeKey(rule.output)
        if normalizedInput == normalizedOutput {
            errors.append(.selfMapping)
        }

        return errors
    }

    /// Validate a simple input/output pair shared by multiple models.
    public static func validateKeys(input: String, output: String) -> [ValidationError] {
        var errors: [ValidationError] = []

        let trimmedInput = input.trimmingCharacters(in: .whitespacesAndNewlines)
        let trimmedOutput = output.trimmingCharacters(in: .whitespacesAndNewlines)

        if trimmedInput.isEmpty {
            errors.append(.emptyInput)
        }
        if trimmedOutput.isEmpty {
            errors.append(.emptyOutput)
        }

        if !errors.isEmpty {
            return errors
        }

        // Validate input - now supports multi-key (chords/sequences)
        let inputTokens = tokenize(trimmedInput)
        for token in inputTokens where !isValidKeyOrModified(token) {
            errors.append(.invalidInputKey(token))
        }

        // Validate output - supports multi-key sequences
        let outputTokens = tokenize(trimmedOutput)
        for token in outputTokens where !isValidKeyOrModified(token) {
            errors.append(.invalidOutputKey(token))
        }

        // Self-mapping check only applies for single-key inputs
        if inputTokens.count == 1 && outputTokens.count == 1 {
            let normalizedInput = normalizeKey(trimmedInput)
            let normalizedOutput = normalizeKey(trimmedOutput)
            if normalizedInput == normalizedOutput {
                errors.append(.selfMapping)
            }
        }

        return errors
    }

    /// Check if a string is a valid Kanata key name
    public static func isValidKey(_ key: String) -> Bool {
        let normalized = key.lowercased().trimmingCharacters(in: .whitespacesAndNewlines)

        // Check if it's in the valid keys set
        if validKanataKeys.contains(normalized) {
            return true
        }

        // Check if it's a known alias
        if keyAliases[normalized] != nil {
            return true
        }

        // Single characters are valid
        if normalized.count == 1 {
            return true
        }

        return false
    }

    /// Check if a string is a valid key or a key with modifier prefix (e.g., M-right)
    public static func isValidKeyOrModified(_ key: String) -> Bool {
        let modifierPrefixes = ["M-S-", "C-S-", "A-S-", "M-", "A-", "C-", "S-"]

        for prefix in modifierPrefixes {
            if key.hasPrefix(prefix) {
                let baseKey = String(key.dropFirst(prefix.count))
                return isValidKey(baseKey)
            }
        }

        return isValidKey(key)
    }

    /// Tokenize an output string into individual keys
    public static func tokenize(_ output: String) -> [String] {
        output.components(separatedBy: .whitespacesAndNewlines)
            .map { $0.trimmingCharacters(in: .whitespaces) }
            .filter { !$0.isEmpty }
    }

    /// Normalize a key name to its canonical Kanata form
    public static func normalizeKey(_ key: String) -> String {
        let lowercased = key.lowercased().trimmingCharacters(in: .whitespacesAndNewlines)

        // Check for alias
        if let canonical = keyAliases[lowercased] {
            return canonical
        }

        // Check if it's already a valid key
        if validKanataKeys.contains(lowercased) {
            return lowercased
        }

        // Return as-is for single chars or unknown keys
        return lowercased
    }

    // MARK: - Conflict Detection

    /// Check for conflicts with existing custom rules
    /// - Parameters:
    ///   - rule: The rule to check
    ///   - existingRules: Other custom rules to check against
    /// - Returns: Conflict error if found, nil otherwise
    public static func checkConflict(
        for rule: CustomRule,
        against existingRules: [CustomRule]
    ) -> ValidationError? {
        let normalizedInput = normalizeKey(rule.input)

        for existing in existingRules where existing.isEnabled && existing.id != rule.id {
            let existingNormalized = normalizeKey(existing.input)
            if normalizedInput == existingNormalized {
                return .conflict(with: existing.displayTitle, key: normalizedInput)
            }
        }

        return nil
    }

    /// Validate a rule including conflict checking
    /// - Parameters:
    ///   - rule: The rule to validate
    ///   - existingRules: Other custom rules to check for conflicts
    /// - Returns: Array of validation errors (empty if valid)
    public static func validate(
        _ rule: CustomRule,
        existingRules: [CustomRule]
    ) -> [ValidationError] {
        var errors = validate(rule)

        // Check for conflicts with existing rules
        if rule.isEnabled, let conflict = checkConflict(for: rule, against: existingRules) {
            errors.append(conflict)
        }

        return errors
    }

    // MARK: - Autocomplete

    /// Get autocomplete suggestions for a partial key input
    /// - Parameter prefix: The partial input typed by the user
    /// - Returns: Array of suggested key names, sorted by relevance
    public static func suggestions(for prefix: String) -> [String] {
        let lowercased = prefix.lowercased().trimmingCharacters(in: .whitespacesAndNewlines)

        if lowercased.isEmpty {
            return commonKeys
        }

        var results: [(key: String, priority: Int)] = []

        // Check common keys first (higher priority)
        for key in commonKeys where key.hasPrefix(lowercased) {
            results.append((key, 0))
        }

        // Check all valid keys
        for key in validKanataKeys where key.hasPrefix(lowercased) && !commonKeys.contains(key) {
            results.append((key, 1))
        }

        // Check aliases (show canonical form)
        for (alias, canonical) in keyAliases where alias.hasPrefix(lowercased) {
            if !results.contains(where: { $0.key == canonical }) {
                results.append((canonical, 2))
            }
        }

        // Sort by priority then alphabetically
        return results.sorted { a, b in
            if a.priority != b.priority {
                return a.priority < b.priority
            }
            return a.key < b.key
        }.map(\.key)
    }

    /// Get a correction suggestion for an invalid key
    /// - Parameter key: The invalid key name
    /// - Returns: A suggested correction, if one can be found
    public static func suggestCorrection(for key: String) -> String? {
        let lowercased = key.lowercased().trimmingCharacters(in: .whitespacesAndNewlines)

        // Check if it's an alias
        if let canonical = keyAliases[lowercased] {
            return canonical
        }

        // Find closest match using simple prefix matching
        let suggestions = suggestions(for: lowercased)
        return suggestions.first
    }
}
