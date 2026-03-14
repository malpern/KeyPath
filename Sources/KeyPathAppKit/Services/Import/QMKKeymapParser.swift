import Foundation

/// Parses QMK default keymap files (keymap.c or keymap.json) to extract
/// the base layer's keycode assignments in sequential order.
///
/// The sequential order matches the `layout` array in the keyboard's info.json,
/// which is how every QMK tool (Configurator, VIA, Vial) correlates physical
/// key positions with keycode assignments.
enum QMKKeymapParser {
    /// Parse a keymap source (either C or JSON) and return the base layer's keycodes.
    /// - Parameter source: Raw file content (keymap.c or keymap.json)
    /// - Returns: Array of QMK keycode name strings in layout order, or nil if parsing fails
    static func parseBaseLayer(from source: String) -> [String]? {
        // Try JSON first (rare but cleanest format)
        if let jsonResult = parseKeymapJSON(source) {
            return jsonResult
        }
        // Fall back to C parsing (the standard format)
        return parseKeymapC(source)
    }

    // MARK: - keymap.json Parser

    /// Parse a QMK keymap.json file and extract layer 0.
    /// Format: { "layers": [["KC_TAB", "KC_Q", ...], [...]] }
    private static func parseKeymapJSON(_ source: String) -> [String]? {
        guard let data = source.data(using: .utf8) else { return nil }

        struct KeymapJSON: Decodable {
            let layers: [[String]]
        }

        guard let keymap = try? JSONDecoder().decode(KeymapJSON.self, from: data),
              !keymap.layers.isEmpty,
              !keymap.layers[0].isEmpty
        else {
            return nil
        }

        return keymap.layers[0]
    }

    // MARK: - keymap.c Parser

    /// Parse a QMK keymap.c file and extract the first LAYOUT block (base layer).
    ///
    /// Handles:
    /// - LAYOUT_xxx( ... ) with arbitrary whitespace and newlines
    /// - Nested parentheses for compound keycodes like LT(1, KC_SPC)
    /// - C-style comments (// and /* */)
    /// - #define aliases (common patterns like _______ = KC_TRNS)
    private static func parseKeymapC(_ source: String) -> [String]? {
        // Strip block comments first
        let stripped = stripBlockComments(source)

        // Find the first LAYOUT block
        guard let layoutRange = findFirstLayoutBlock(in: stripped) else {
            return nil
        }

        let content = String(stripped[layoutRange])

        // Split into tokens by commas, respecting nested parentheses
        let tokens = splitByCommas(content)

        // Clean up each token
        let keycodes = tokens.compactMap { cleanToken($0) }.filter { !$0.isEmpty }

        guard !keycodes.isEmpty else { return nil }
        return keycodes
    }

    /// Find the first LAYOUT_xxx(...) block in the source and return
    /// the range of content inside the parentheses.
    private static func findFirstLayoutBlock(in source: String) -> Range<String.Index>? {
        // Match LAYOUT followed by optional suffix, then (
        guard let match = source.range(of: #"LAYOUT\w*\s*\("#, options: .regularExpression) else {
            return nil
        }

        // Find the matching closing paren
        let openParen = match.upperBound
        var depth = 1
        var pos = openParen

        while pos < source.endIndex, depth > 0 {
            let ch = source[pos]
            if ch == "(" { depth += 1 }
            else if ch == ")" { depth -= 1 }
            if depth == 0 { break }
            pos = source.index(after: pos)
        }

        guard depth == 0 else { return nil }
        return openParen ..< pos
    }

    /// Split a string by commas, but respect nested parentheses.
    /// "KC_A, LT(1, KC_B), KC_C" → ["KC_A", "LT(1, KC_B)", "KC_C"]
    private static func splitByCommas(_ content: String) -> [String] {
        var tokens: [String] = []
        var current = ""
        var depth = 0

        for ch in content {
            if ch == "(" {
                depth += 1
                current.append(ch)
            } else if ch == ")" {
                depth -= 1
                current.append(ch)
            } else if ch == ",", depth == 0 {
                tokens.append(current)
                current = ""
            } else {
                current.append(ch)
            }
        }
        if !current.isEmpty {
            tokens.append(current)
        }
        return tokens
    }

    /// Clean a single keycode token: strip whitespace, line comments, backslashes.
    private static func cleanToken(_ token: String) -> String? {
        var t = token

        // Remove inline comments (// to end of line within the token)
        if let commentRange = t.range(of: "//") {
            t = String(t[..<commentRange.lowerBound])
        }

        // Remove backslash-newline continuations
        t = t.replacingOccurrences(of: "\\", with: "")

        // Trim whitespace and newlines
        t = t.trimmingCharacters(in: .whitespacesAndNewlines)

        // Skip empty tokens
        guard !t.isEmpty else { return nil }

        return t
    }

    /// Strip C block comments (/* ... */) from source.
    private static func stripBlockComments(_ source: String) -> String {
        var result = ""
        var i = source.startIndex

        while i < source.endIndex {
            let nextIdx = source.index(after: i)

            // Check for /* ... */
            if source[i] == "/", nextIdx < source.endIndex, source[nextIdx] == "*" {
                // Skip until */
                var j = source.index(after: nextIdx)
                while j < source.endIndex {
                    let jNext = source.index(after: j)
                    if source[j] == "*", jNext < source.endIndex, source[jNext] == "/" {
                        i = source.index(after: jNext)
                        break
                    }
                    j = source.index(after: j)
                }
                if j >= source.endIndex { break }
                continue
            }

            // Check for // line comments
            if source[i] == "/", nextIdx < source.endIndex, source[nextIdx] == "/" {
                // Skip until end of line
                var j = nextIdx
                while j < source.endIndex, source[j] != "\n" {
                    j = source.index(after: j)
                }
                i = j
                continue
            }

            result.append(source[i])
            i = source.index(after: i)
        }

        return result
    }

    // MARK: - Compound Keycode Extraction

    /// Extract the base key from a compound QMK keycode expression.
    ///
    /// Examples:
    /// - "KC_A" → "KC_A" (simple)
    /// - "LT(1, KC_SPC)" → "KC_SPC" (layer-tap: base key is 2nd arg)
    /// - "MT(MOD_LCTL, KC_A)" → "KC_A" (mod-tap: base key is 2nd arg)
    /// - "LCTL(KC_C)" → "KC_C" (mod wrapper: base key is the arg)
    /// - "MO(1)" → nil (layer momentary: no base key)
    /// - "KC_NO" → nil (no key)
    /// - "KC_TRNS" / "_______" → nil (transparent)
    /// - "QK_BOOT" → nil (system command)
    static func extractBaseKey(_ keycode: String) -> String? {
        let trimmed = keycode.trimmingCharacters(in: .whitespacesAndNewlines)

        // Transparent / no key
        if trimmed == "_______" || trimmed == "XXXXXXX" || trimmed == "KC_TRNS"
            || trimmed == "KC_TRANSPARENT" || trimmed == "KC_NO"
        {
            return nil
        }

        // Simple keycodes (no parentheses)
        if !trimmed.contains("(") {
            // Layer/system commands without args
            if trimmed.hasPrefix("QK_") || trimmed.hasPrefix("RGB_") || trimmed.hasPrefix("BL_") {
                return nil
            }
            return trimmed
        }

        // Compound keycodes with parentheses
        guard let openParen = trimmed.firstIndex(of: "("),
              let closeParen = trimmed.lastIndex(of: ")")
        else {
            return trimmed // Malformed, return as-is
        }

        let funcName = String(trimmed[..<openParen])
        let argsStr = String(trimmed[trimmed.index(after: openParen) ..< closeParen])

        // Split args by comma (top-level only)
        let args = splitByCommas(argsStr).map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }

        switch funcName {
        // Layer-tap: LT(layer, kc) → base key is kc
        case "LT":
            return args.count >= 2 ? extractBaseKey(args[1]) : nil

        // Mod-tap: MT(mod, kc) → base key is kc
        case "MT":
            return args.count >= 2 ? extractBaseKey(args[1]) : nil

        // Mod wrappers: LCTL(kc), LSFT(kc), etc. → base key is kc
        case "LCTL", "LSFT", "LALT", "LGUI", "LCMD", "LWIN",
             "RCTL", "RSFT", "RALT", "RGUI", "RCMD", "RWIN",
             "HYPR", "MEH", "C", "S", "A", "G",
             "LSA", "RSA", "SGUI", "LCA", "LSG", "LAG", "RSG", "RAG", "RCS":
            return args.count >= 1 ? extractBaseKey(args[0]) : nil

        // Tap-dance: TD(n) → no base key
        case "TD":
            return nil

        // Layer switches: MO(n), TG(n), TO(n), DF(n), TT(n), OSL(n) → no base key
        case "MO", "TG", "TO", "DF", "TT", "OSL":
            return nil

        // One-shot mod: OSM(mod) → no base key
        case "OSM":
            return nil

        default:
            // Unknown function — try to extract last KC_ argument
            if let lastKC = args.last(where: { $0.hasPrefix("KC_") }) {
                return lastKC
            }
            return nil
        }
    }

    // MARK: - Full Resolution Pipeline

    /// Resolve a keymap token to a macOS keyCode and display label.
    /// Returns nil for layer keys, transparent keys, and unknown keycodes.
    static func resolveKeycode(_ token: String) -> (keyCode: UInt16, label: String)? {
        guard let baseKey = extractBaseKey(token) else {
            return nil
        }

        // Look up in the QMK → macOS mapping table
        if let macKeyCode = QMKKeycodeMapping.qmkToMacOS[baseKey] {
            let label = keycodeLabel(baseKey)
            return (macKeyCode, label)
        }

        return nil
    }

    /// Generate a short display label for a QMK keycode name.
    private static func keycodeLabel(_ keycode: String) -> String {
        // Remove KC_ prefix and lowercase for display
        let stripped = keycode.hasPrefix("KC_") ? String(keycode.dropFirst(3)) : keycode

        // Map common names to symbols/short labels
        switch stripped {
        case "SPACE", "SPC": return "␣"
        case "ENTER", "ENT": return "↩"
        case "BACKSPACE", "BSPC": return "⌫"
        case "DELETE", "DEL": return "⌦"
        case "TAB": return "⇥"
        case "ESCAPE", "ESC": return "esc"
        case "CAPS_LOCK", "CAPS", "CAPSLOCK": return "⇪"
        case "LEFT_SHIFT", "LSFT", "LSHIFT": return "⇧"
        case "RIGHT_SHIFT", "RSFT", "RSHIFT": return "⇧"
        case "LEFT_CTRL", "LCTL", "LCTRL": return "⌃"
        case "RIGHT_CTRL", "RCTL", "RCTRL": return "⌃"
        case "LEFT_ALT", "LALT", "LOPT": return "⌥"
        case "RIGHT_ALT", "RALT", "ROPT", "ALGR": return "⌥"
        case "LEFT_GUI", "LGUI", "LCMD", "LWIN": return "⌘"
        case "RIGHT_GUI", "RGUI", "RCMD", "RWIN": return "⌘"
        case "UP": return "▲"
        case "DOWN": return "▼"
        case "LEFT": return "◀"
        case "RIGHT", "RGHT": return "▶"
        case "PAGE_UP", "PGUP": return "pgup"
        case "PAGE_DOWN", "PGDN": return "pgdn"
        case "HOME": return "home"
        case "END": return "end"
        case "INSERT", "INS": return "ins"
        case "PRINT_SCREEN", "PSCR": return "prt"
        case "SCROLL_LOCK", "SCRL": return "scr"
        case "PAUSE", "PAUS", "BRK": return "pse"
        case "NUM_LOCK", "NUM", "NUMLOCK": return "num"
        case "FN": return "fn"
        case "MINUS", "MINS": return "-"
        case "EQUAL", "EQL": return "="
        case "LEFT_BRACKET", "LBRC": return "["
        case "RIGHT_BRACKET", "RBRC": return "]"
        case "BACKSLASH", "BSLS": return "\\"
        case "SEMICOLON", "SCLN": return ";"
        case "QUOTE", "QUOT": return "'"
        case "GRAVE", "GRV": return "`"
        case "COMMA", "COMM": return ","
        case "DOT": return "."
        case "SLASH", "SLSH": return "/"
        case "KP_SLASH", "PSLS": return "/"
        case "KP_ASTERISK", "PAST": return "*"
        case "KP_MINUS", "PMNS": return "-"
        case "KP_PLUS", "PPLS": return "+"
        case "KP_ENTER", "PENT": return "↩"
        case "KP_DOT", "PDOT": return "."
        case "KP_EQUAL", "PEQL": return "="
        case "APPLICATION", "APP": return "▤"
        case "AUDIO_VOL_UP", "VOLU", "KB_VOLUME_UP": return "v+"
        case "AUDIO_VOL_DOWN", "VOLD", "KB_VOLUME_DOWN": return "v-"
        case "AUDIO_MUTE", "MUTE", "KB_MUTE": return "mute"
        // ISO / JIS keys
        case "NONUS_BACKSLASH", "NUBS": return "§"
        case "INTERNATIONAL_3", "INT3": return "¥"
        case "INTERNATIONAL_1", "INT1": return "_"
        case "KP_COMMA", "PCMM": return ","
        case "LANGUAGE_1", "LNG1": return "かな"
        case "LANGUAGE_2", "LNG2": return "英数"
        default:
            // Function keys
            if stripped.hasPrefix("F"), let num = Int(stripped.dropFirst(1)), num >= 1, num <= 24 {
                return stripped.lowercased()
            }
            // Numpad keys
            if stripped.hasPrefix("KP_"), let num = Int(stripped.dropFirst(3)) {
                return "\(num)"
            }
            if stripped.hasPrefix("P"), let num = Int(stripped.dropFirst(1)), num >= 0, num <= 9 {
                return "\(num)"
            }
            // Single character keys (letters, numbers)
            if stripped.count == 1 {
                return stripped.lowercased()
            }
            // Everything else: lowercase and truncate
            return stripped.lowercased().prefix(3).description
        }
    }
}
