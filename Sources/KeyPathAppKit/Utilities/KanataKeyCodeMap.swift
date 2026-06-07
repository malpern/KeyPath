import Foundation

enum KanataKeyCodeMap {
    private static let nameToKeyCode: [String: UInt16] = [
        // Row 3: Home row (ASDF...)
        "a": 0, "s": 1, "d": 2, "f": 3, "h": 4, "g": 5,
        // Row 4: Bottom row (ZXCV...)
        "z": 6, "x": 7, "c": 8, "v": 9, "b": 11,
        // Row 2: Top row (QWERTY...)
        "q": 12, "w": 13, "e": 14, "r": 15, "y": 16, "t": 17,
        // Row 1: Number row
        "1": 18, "2": 19, "3": 20, "4": 21, "6": 22, "5": 23,
        "equal": 24, "9": 25, "7": 26, "minus": 27, "8": 28, "0": 29,
        // More top row keys
        "rightbrace": 30, "o": 31, "u": 32, "leftbrace": 33, "i": 34, "p": 35,
        // Home row continued
        "enter": 36, "ret": 36, "return": 36,
        "l": 37, "j": 38, "apostrophe": 39, "k": 40,
        "semicolon": 41, "scln": 41, ";": 41, "backslash": 42,
        // Bottom row continued
        "comma": 43, "slash": 44, "n": 45, "m": 46, "dot": 47,
        // Special keys
        "tab": 48, "space": 49, "spc": 49, "grave": 50, "grv": 50,
        "backspace": 51, "bspc": 51, "esc": 53, "escape": 53,
        // Modifiers
        "rightmeta": 54, "rmet": 54, "leftmeta": 55, "lmet": 55,
        "leftshift": 56, "lsft": 56, "capslock": 57, "caps": 57,
        "leftalt": 58, "lalt": 58, "leftctrl": 59, "lctl": 59,
        "rightshift": 60, "rsft": 60, "rightalt": 61, "ralt": 61,
        "fn": 63,
        // Function keys
        "f5": 96, "f6": 97, "f7": 98, "f3": 99, "f8": 100, "f9": 101,
        "f11": 103, "f10": 109, "f12": 111, "f4": 118, "f2": 120, "f1": 122,
        // Arrow keys
        "left": 123, "right": 124, "down": 125, "up": 126,
        // Navigation keys
        "home": 115,
        "pageup": 116, "pgup": 116,
        "del": 117, "delete": 117,
        "end": 119,
        "pagedown": 121, "pgdn": 121,
        "help": 114, "insert": 114,
        // Extended function keys
        "f13": 105,
        "f14": 107,
        "f15": 113,
        "f16": 106,
        "f17": 64,
        "f18": 79,
        "f19": 80,
        // Right Control
        "rightctrl": 102, "rctl": 102,
        // ISO key (between Left Shift and Z on ISO keyboards)
        "intlbackslash": 10,
        // ABNT2 key (between slash and right shift on Brazilian keyboards)
        "intlro": 94,
        // Korean language keys
        "hangeul": 104, "hanja": 104
    ]

    nonisolated static func keyCode(for name: String) -> UInt16? {
        nameToKeyCode[name.lowercased()]
    }

    /// Maps CGEvent key codes to OsCode display names used by Kanata TCP events.
    nonisolated static func overlayName(for keyCode: UInt16) -> String {
        switch keyCode {
        // Row 3: Home row (ASDF...)
        case 0: "a"
        case 1: "s"
        case 2: "d"
        case 3: "f"
        case 4: "h"
        case 5: "g"
        // Row 4: Bottom row (ZXCV...)
        case 6: "z"
        case 7: "x"
        case 8: "c"
        case 9: "v"
        case 11: "b"
        // Row 2: Top row (QWERTY...)
        case 12: "q"
        case 13: "w"
        case 14: "e"
        case 15: "r"
        case 16: "y"
        case 17: "t"
        // Row 1: Number row
        case 18: "1"
        case 19: "2"
        case 20: "3"
        case 21: "4"
        case 22: "6"
        case 23: "5"
        case 24: "equal"
        case 25: "9"
        case 26: "7"
        case 27: "minus"
        case 28: "8"
        case 29: "0"
        // More top row keys
        case 30: "rightbrace"
        case 31: "o"
        case 32: "u"
        case 33: "leftbrace"
        case 34: "i"
        case 35: "p"
        // Home row continued
        case 36: "enter"
        case 37: "l"
        case 38: "j"
        case 39: "apostrophe"
        case 40: "k"
        case 41: "semicolon"
        case 42: "backslash"
        // Bottom row continued
        case 43: "comma"
        case 44: "slash"
        case 45: "n"
        case 46: "m"
        case 47: "dot"
        // Special keys
        case 48: "tab"
        case 49: "space"
        case 50: "grave"
        case 51: "backspace"
        case 53: "esc"
        // Modifiers
        case 54: "rightmeta"
        case 55: "leftmeta"
        case 56: "leftshift"
        case 57: "capslock"
        case 58: "leftalt"
        case 59: "leftctrl"
        case 60: "rightshift"
        case 61: "rightalt"
        case 63: "fn"
        // Function keys
        case 96: "f5"
        case 97: "f6"
        case 98: "f7"
        case 99: "f3"
        case 100: "f8"
        case 101: "f9"
        case 103: "f11"
        case 109: "f10"
        case 111: "f12"
        case 118: "f4"
        case 120: "f2"
        case 122: "f1"
        // Arrow keys
        case 123: "left"
        case 124: "right"
        case 125: "down"
        case 126: "up"
        // ISO key (between Left Shift and Z on ISO keyboards)
        case 10: "intlbackslash"
        // ABNT2 extra key (between slash and right shift on Brazilian keyboards)
        case 94: "intlro"
        // Korean language toggle keys
        case 104: "hangeul"
        // Navigation keys
        case 115: "home"
        case 116: "pageup"
        case 117: "del"
        case 119: "end"
        case 121: "pagedown"
        case 114: "help"
        // Extended function keys
        case 64: "f17"
        case 79: "f18"
        case 80: "f19"
        case 102: "rightctrl"
        case 105: "f13"
        case 106: "f16"
        case 107: "f14"
        case 113: "f15"
        default:
            "unknown-\(keyCode)"
        }
    }
}
