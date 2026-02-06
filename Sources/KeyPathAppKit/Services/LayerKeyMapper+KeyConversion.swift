import Foundation

extension LayerKeyMapper {
    // MARK: - Key Name Conversion

    /// Convert TCP key name (from OverlayKeyboardView.keyCodeToKanataName) to simulator-compatible name
    /// The simulator uses abbreviated names like "min" instead of "minus"
    func toSimulatorKeyName(_ tcpName: String) -> String {
        switch tcpName.lowercased() {
        // Punctuation keys use abbreviated names in simulator
        case "minus": "min"
        case "equal": "eql"
        case "grave": "grv"
        case "backslash": "bksl"
        case "leftbrace": "lbrc"
        case "rightbrace": "rbrc"
        case "semicolon": "scln"
        case "apostrophe": "apos"
        case "comma": "comm"
        case "dot": "."
        case "slash": "/"
        // Modifiers
        case "leftshift": "lsft"
        case "rightshift": "rsft"
        case "leftmeta": "lmet"
        case "rightmeta": "rmet"
        case "leftalt": "lalt"
        case "rightalt": "ralt"
        case "leftctrl": "lctl"
        case "rightctrl": "rctl"
        case "capslock": "caps"
        // Special keys
        case "backspace": "bspc"
        case "enter": "ret"
        case "space": "spc"
        case "escape": "esc"
        default:
            tcpName
        }
    }

    /// Convert Kanata key name to display label using standard Mac keyboard symbols
    /// Reference: https://support.apple.com/en-us/HT201236
    func kanataKeyToDisplayLabel(_ kanataKey: String) -> String {
        switch kanataKey.lowercased() {
        // Letters
        case let key where key.count == 1 && key.first!.isLetter:
            key.uppercased()
        // Numbers
        case let key where key.count == 1 && key.first!.isNumber:
            key
        // Arrow keys - Mac uses these specific Unicode arrows
        // Handle both kanata names and simulator output symbols (◀▶▲▼)
        case "left", "◀": "←"
        case "right", "▶": "→"
        case "up", "▲": "↑"
        case "down", "▼": "↓"
        // Modifier symbols from simulator (used in combos like Cmd+Arrow)
        // The simulator outputs ‹◆ for left-Cmd, ◆› for right-Cmd, etc.
        case "‹◆", "◆›": "⌘" // Command
        case "‹⎇", "⎇›": "⌥" // Option
        case "‹⇧", "⇧›": "⇧" // Shift
        case "‹⎈", "⎈›": "⌃" // Control
        // Modifiers - Standard Mac symbols
        case "leftshift", "lsft": "⇧" // U+21E7 Upwards White Arrow
        case "rightshift", "rsft": "⇧"
        case "leftmeta", "lmet": "⌘" // U+2318 Place of Interest Sign (Command)
        case "rightmeta", "rmet": "⌘"
        case "leftalt", "lalt": "⌥" // U+2325 Option Key
        case "rightalt", "ralt": "⌥"
        case "leftctrl", "lctl": "⌃" // U+2303 Up Arrowhead (Control)
        case "rightctrl", "rctl": "⌃"
        // Common keys - Standard Mac symbols
        case "space", "spc", "sp": "" // Spacebar: show blank (the physical key shape indicates space)
        case "enter", "ret": "↩" // U+21A9 Return symbol
        case "backspace", "bspc": "⌫" // U+232B Delete to the Left
        case "tab": "⇥" // U+21E5 Rightwards Arrow to Bar
        case "escape", "esc": "⎋" // U+238B Broken Circle with Northwest Arrow (Escape)
        case "capslock", "caps": "⇪" // U+21EA Upwards White Arrow from Bar (Caps Lock)
        case "delete", "del": "⌦" // U+2326 Erase to the Right
        case "fn": "fn" // Function key (no standard symbol)
        // Punctuation - Show actual characters
        case "grave", "grv": "`"
        case "minus", "min": "-"
        case "equal", "eql": "="
        case "leftbrace", "lbrc": "["
        case "rightbrace", "rbrc": "]"
        case "backslash", "bksl": "\\"
        case "semicolon", "scln": ";"
        case "apostrophe", "apos": "'"
        case "comma", "comm": ","
        case "dot", ".": "."
        case "slash", "/": "/"
        // Function keys
        case let key where key.hasPrefix("f") && Int(String(key.dropFirst())) != nil:
            key.uppercased()
        // Navigation keys
        case "home": "↖"
        case "end": "↘"
        case "pageup", "pgup": "⇞"
        case "pagedown", "pgdn": "⇟"
        default:
            // Return as-is if unknown
            kanataKey
        }
    }

    /// Check if a key is a modifier symbol from the simulator
    func isModifierSymbol(_ key: String) -> Bool {
        switch key {
        case "‹◆", "◆›", "‹⎇", "⎇›", "‹⇧", "⇧›", "‹⎈", "⎈›":
            true
        default:
            false
        }
    }

    /// Normalize key names to canonical form for transparent key detection.
    /// Maps simulator symbols and aliases to their base key names.
    nonisolated static func normalizeKeyName(_ key: String) -> String {
        switch key.lowercased() {
        // Arrow symbols from simulator
        case "◀", "←": "left"
        case "▶", "→": "right"
        case "▲", "↑": "up"
        case "▼", "↓": "down"
        // Modifier aliases
        case "‹◆", "◆›", "lmet", "rmet", "cmd", "lcmd", "command", "meta": "lmet"
        case "‹⎇", "⎇›", "lalt", "ralt", "opt", "option": "lalt"
        case "‹⇧", "⇧›", "lsft", "rsft", "lshift", "rshift", "shift": "lsft"
        case "‹⎈", "⎈›", "lctl", "rctl", "lctrl", "rctrl", "ctrl", "control": "lctl"
        // Special keys
        case "ret", "return", "⏎": "enter"
        case "bspc", "␈": "backspace"
        case "spc", "sp", "␠", "␣": "space"
        case "esc": "escape"
        case "caps": "capslock"
        case "del": "delete"
        // Punctuation aliases (simulator abbrevs + symbol forms)
        case "grv", "grave", "`": "grave"
        case "min", "minus", "-", "−": "minus"
        case "eql", "equal", "=": "equal"
        case "lbrc", "leftbrace", "[", "{", "lbrack", "leftbracket": "leftbrace"
        case "rbrc", "rightbrace", "]", "}", "rbrack", "rightbracket": "rightbrace"
        case "bksl", "backslash", "\\": "backslash"
        case "scln", "semicolon", ";": "semicolon"
        case "apos", "apostrophe", "quote", "'": "apostrophe"
        case "comm", "comma", ",": "comma"
        case "dot", "period", ".": "dot"
        case "slash", "slsh", "/": "slash"
        // Tab and fn stay as-is
        case "⇥", "⭾": "tab"
        case "↩": "enter"
        case "⌫": "backspace"
        case "⌦": "delete"
        case "⎋": "escape"
        case "⇪": "capslock"
        default:
            key.lowercased()
        }
    }

    /// Convert Kanata key name to macOS key code
    func kanataKeyToKeyCode(_ kanataKey: String) -> UInt16? {
        // Handle simulator output symbols (arrows)
        let normalizedKey: String = switch kanataKey {
        case "◀": "left"
        case "▶": "right"
        case "▲": "up"
        case "▼": "down"
        default: kanataKey
        }

        // Reverse lookup using OverlayKeyboardView.keyCodeToKanataName
        let allKeyCodes: [UInt16] = Array(0 ... 127) + [0xFFFF]
        for code in allKeyCodes {
            let name = OverlayKeyboardView.keyCodeToKanataName(code)
            if name.lowercased() == normalizedKey.lowercased() {
                return code
            }
        }
        return nil
    }

}
