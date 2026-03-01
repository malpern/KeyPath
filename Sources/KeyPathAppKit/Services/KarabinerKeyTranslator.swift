import Foundation

/// Translates Karabiner-Elements key codes to Kanata key names.
/// Pure stateless utility — all methods are static.
enum KarabinerKeyTranslator {
    // MARK: - Key Code Translation

    /// Translate a Karabiner `key_code` to a Kanata key name.
    /// Returns `nil` for unknown or untranslatable keys.
    static func toKanata(_ karabinerKey: String) -> String? {
        keyCodeMap[karabinerKey]
    }

    /// Translate a Karabiner modifier name to a Kanata modifier.
    static func modifierToKanata(_ modifier: String) -> String? {
        modifierMap[modifier]
    }

    /// Translate a Karabiner `consumer_key_code` to a Kanata key name.
    static func consumerKeyToKanata(_ key: String) -> String? {
        consumerKeyMap[key]
    }

    /// Build a Kanata key expression from a key code and optional modifiers.
    /// E.g., key="a", modifiers=["left_command", "left_shift"] → "C-S-a"
    static func toKanataExpression(keyCode: String, modifiers: [String] = []) -> String? {
        guard let kanataKey = toKanata(keyCode) else { return nil }

        if modifiers.isEmpty {
            return kanataKey
        }

        let prefix = modifiers.compactMap { modifierPrefix($0) }.joined()
        if prefix.isEmpty {
            return kanataKey
        }
        return "\(prefix)\(kanataKey)"
    }

    /// Build a Kanata key expression from a consumer key code and optional modifiers.
    static func consumerKeyToKanataExpression(keyCode: String, modifiers: [String] = []) -> String? {
        guard let kanataKey = consumerKeyToKanata(keyCode) else { return nil }

        if modifiers.isEmpty {
            return kanataKey
        }

        let prefix = modifiers.compactMap { modifierPrefix($0) }.joined()
        if prefix.isEmpty {
            return kanataKey
        }
        return "\(prefix)\(kanataKey)"
    }

    /// Get the Kanata modifier prefix (e.g., "C-" for command, "S-" for shift).
    private static func modifierPrefix(_ modifier: String) -> String? {
        modifierPrefixMap[modifier]
    }

    // MARK: - Translation Tables

    /// Karabiner key_code → Kanata key name
    private static let keyCodeMap: [String: String] = [
        // Letters
        "a": "a", "b": "b", "c": "c", "d": "d", "e": "e",
        "f": "f", "g": "g", "h": "h", "i": "i", "j": "j",
        "k": "k", "l": "l", "m": "m", "n": "n", "o": "o",
        "p": "p", "q": "q", "r": "r", "s": "s", "t": "t",
        "u": "u", "v": "v", "w": "w", "x": "x", "y": "y",
        "z": "z",

        // Numbers
        "1": "1", "2": "2", "3": "3", "4": "4", "5": "5",
        "6": "6", "7": "7", "8": "8", "9": "9", "0": "0",

        // Function keys
        "f1": "f1", "f2": "f2", "f3": "f3", "f4": "f4",
        "f5": "f5", "f6": "f6", "f7": "f7", "f8": "f8",
        "f9": "f9", "f10": "f10", "f11": "f11", "f12": "f12",
        "f13": "f13", "f14": "f14", "f15": "f15", "f16": "f16",
        "f17": "f17", "f18": "f18", "f19": "f19", "f20": "f20",

        // Navigation
        "return_or_enter": "ret",
        "escape": "esc",
        "delete_or_backspace": "bspc",
        "delete_forward": "del",
        "tab": "tab",
        "spacebar": "spc",
        "up_arrow": "up",
        "down_arrow": "down",
        "left_arrow": "left",
        "right_arrow": "right",
        "page_up": "pgup",
        "page_down": "pgdn",
        "home": "home",
        "end": "end",

        // Symbols
        "hyphen": "min",
        "equal_sign": "eql",
        "open_bracket": "lbrc",
        "close_bracket": "rbrc",
        "backslash": "bsls",
        "non_us_pound": "nuhs",
        "semicolon": "scln",
        "quote": "apo",
        "grave_accent_and_tilde": "grv",
        "comma": "comm",
        "period": "dot",
        "slash": "slsh",
        "non_us_backslash": "nubs",

        // Modifiers (as input keys, not as modifier flags)
        "caps_lock": "caps",
        "left_shift": "lsft",
        "right_shift": "rsft",
        "left_control": "lctl",
        "right_control": "rctl",
        "left_option": "lalt",
        "right_option": "ralt",
        "left_command": "lmet",
        "right_command": "rmet",
        "fn": "fn",

        // Keypad
        "keypad_num_lock": "nlck",
        "keypad_slash": "kp/",
        "keypad_asterisk": "kp*",
        "keypad_hyphen": "kp-",
        "keypad_plus": "kp+",
        "keypad_enter": "kprt",
        "keypad_1": "kp1",
        "keypad_2": "kp2",
        "keypad_3": "kp3",
        "keypad_4": "kp4",
        "keypad_5": "kp5",
        "keypad_6": "kp6",
        "keypad_7": "kp7",
        "keypad_8": "kp8",
        "keypad_9": "kp9",
        "keypad_0": "kp0",
        "keypad_period": "kp.",
        "keypad_equal_sign": "kp=",

        // Special
        "print_screen": "prnt",
        "scroll_lock": "slck",
        "pause": "pause",
        "insert": "ins",
        "application": "menu",
        "power": "power",

        // International
        "international1": "intl1",
        "international2": "intl2",
        "international3": "intl3",
        "international4": "intl4",
        "international5": "intl5",
        "lang1": "lang1",
        "lang2": "lang2",
    ]

    /// Karabiner modifier → Kanata modifier name (for holdAction and output modifiers)
    private static let modifierMap: [String: String] = [
        "left_shift": "lsft",
        "right_shift": "rsft",
        "left_control": "lctl",
        "right_control": "rctl",
        "left_option": "lalt",
        "right_option": "ralt",
        "left_command": "lmet",
        "right_command": "rmet",
        "shift": "lsft",
        "control": "lctl",
        "option": "lalt",
        "command": "lmet",
        "fn": "fn",
        "caps_lock": "caps",
        "any": "any",
    ]

    /// Karabiner modifier → Kanata prefix for key expressions (e.g., "C-" for command)
    private static let modifierPrefixMap: [String: String] = [
        "left_shift": "S-",
        "right_shift": "S-",
        "left_control": "C-",
        "right_control": "C-",
        "left_option": "A-",
        "right_option": "AG-",
        "left_command": "M-",
        "right_command": "M-",
        "shift": "S-",
        "control": "C-",
        "option": "A-",
        "command": "M-",
    ]

    /// Karabiner consumer_key_code → Kanata key name
    private static let consumerKeyMap: [String: String] = [
        // Media controls
        "display_brightness_decrement": "bldn",
        "display_brightness_increment": "blup",
        "mission_control": "f3",
        "spotlight": "f4",
        "dictation": "f5",
        "launchpad": "f4",
        "rewind": "prev",
        "play_or_pause": "pp",
        "fast_forward": "next",
        "mute": "mute",
        "volume_decrement": "vold",
        "volume_increment": "volu",
        "eject": "ejct",

        // Additional media keys
        "al_terminal_lock_or_screensaver": "slck",
        "scan_previous_track": "prev",
        "scan_next_track": "next",
    ]
}
