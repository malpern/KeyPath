import Foundation

// MARK: - QMK Keycode to macOS Virtual KeyCode Mapping

/// Maps QMK keycode name strings to macOS virtual keyCodes (CGKeyCode / kVK_ values).
///
/// QMK basic keycodes correspond directly to HID Usage Page 0x07 codes.
/// macOS uses its own virtual keycode system (defined in Carbon/Events.h as kVK_ constants).
/// This table provides the complete cross-reference.
///
/// Sources:
/// - QMK: https://github.com/qmk/qmk_firmware/blob/master/data/constants/keycodes/keycodes_0.0.1_basic.hjson
/// - macOS: Carbon.framework/HIToolbox/Events.h (kVK_ constants)
enum QMKKeycodeMapping {
    // swiftlint:disable function_body_length

    /// Complete mapping from QMK keycode names to macOS CGKeyCode values (UInt16).
    ///
    /// Includes primary names and all documented QMK aliases.
    /// Keys with no macOS equivalent are omitted (e.g., KC_NO, KC_TRANSPARENT,
    /// locking keys, international keys without standard macOS mapping).
    static let qmkToMacOS: [String: UInt16] = {
        var map: [String: UInt16] = [:]

        /// Helper to register a key with its primary name and aliases
        func add(_ code: UInt16, _ names: String...) {
            for name in names {
                map[name] = code
            }
        }

        // ── Letters ──────────────────────────────────────────────
        // HID 0x04..0x1D → kVK_ANSI_A..Z
        add(0x00, "KC_A") // kVK_ANSI_A
        add(0x0B, "KC_B") // kVK_ANSI_B
        add(0x08, "KC_C") // kVK_ANSI_C
        add(0x02, "KC_D") // kVK_ANSI_D
        add(0x0E, "KC_E") // kVK_ANSI_E
        add(0x03, "KC_F") // kVK_ANSI_F
        add(0x05, "KC_G") // kVK_ANSI_G
        add(0x04, "KC_H") // kVK_ANSI_H
        add(0x22, "KC_I") // kVK_ANSI_I
        add(0x26, "KC_J") // kVK_ANSI_J
        add(0x28, "KC_K") // kVK_ANSI_K
        add(0x25, "KC_L") // kVK_ANSI_L
        add(0x2E, "KC_M") // kVK_ANSI_M
        add(0x2D, "KC_N") // kVK_ANSI_N
        add(0x1F, "KC_O") // kVK_ANSI_O
        add(0x23, "KC_P") // kVK_ANSI_P
        add(0x0C, "KC_Q") // kVK_ANSI_Q
        add(0x0F, "KC_R") // kVK_ANSI_R
        add(0x01, "KC_S") // kVK_ANSI_S
        add(0x11, "KC_T") // kVK_ANSI_T
        add(0x20, "KC_U") // kVK_ANSI_U
        add(0x09, "KC_V") // kVK_ANSI_V
        add(0x0D, "KC_W") // kVK_ANSI_W
        add(0x07, "KC_X") // kVK_ANSI_X
        add(0x10, "KC_Y") // kVK_ANSI_Y
        add(0x06, "KC_Z") // kVK_ANSI_Z

        // ── Numbers ──────────────────────────────────────────────
        // HID 0x1E..0x27 → kVK_ANSI_1..0
        add(0x12, "KC_1") // kVK_ANSI_1
        add(0x13, "KC_2") // kVK_ANSI_2
        add(0x14, "KC_3") // kVK_ANSI_3
        add(0x15, "KC_4") // kVK_ANSI_4
        add(0x17, "KC_5") // kVK_ANSI_5
        add(0x16, "KC_6") // kVK_ANSI_6
        add(0x1A, "KC_7") // kVK_ANSI_7
        add(0x1C, "KC_8") // kVK_ANSI_8
        add(0x19, "KC_9") // kVK_ANSI_9
        add(0x1D, "KC_0") // kVK_ANSI_0

        // ── System / Editing Keys ────────────────────────────────
        add(0x24, "KC_ENTER", "KC_ENT") // kVK_Return
        add(0x35, "KC_ESCAPE", "KC_ESC") // kVK_Escape
        add(0x33, "KC_BACKSPACE", "KC_BSPC") // kVK_Delete (backspace)
        add(0x30, "KC_TAB") // kVK_Tab
        add(0x31, "KC_SPACE", "KC_SPC") // kVK_Space

        // ── Punctuation / Symbols ────────────────────────────────
        add(0x1B, "KC_MINUS", "KC_MINS") // kVK_ANSI_Minus
        add(0x18, "KC_EQUAL", "KC_EQL") // kVK_ANSI_Equal
        add(0x21, "KC_LEFT_BRACKET", "KC_LBRC") // kVK_ANSI_LeftBracket
        add(0x1E, "KC_RIGHT_BRACKET", "KC_RBRC") // kVK_ANSI_RightBracket
        add(0x2A, "KC_BACKSLASH", "KC_BSLS") // kVK_ANSI_Backslash
        add(0x29, "KC_SEMICOLON", "KC_SCLN") // kVK_ANSI_Semicolon
        add(0x27, "KC_QUOTE", "KC_QUOT") // kVK_ANSI_Quote
        add(0x32, "KC_GRAVE", "KC_GRV") // kVK_ANSI_Grave
        add(0x2B, "KC_COMMA", "KC_COMM") // kVK_ANSI_Comma
        add(0x2F, "KC_DOT") // kVK_ANSI_Period
        add(0x2C, "KC_SLASH", "KC_SLSH") // kVK_ANSI_Slash

        // ── Non-US Layout Keys ───────────────────────────────────
        add(0x2A, "KC_NONUS_HASH", "KC_NUHS") // kVK_ANSI_Backslash (ISO # key)
        add(0x0A, "KC_NONUS_BACKSLASH", "KC_NUBS") // kVK_ISO_Section

        // ── Caps Lock ────────────────────────────────────────────
        add(0x39, "KC_CAPS_LOCK", "KC_CAPS", "KC_CAPSLOCK") // kVK_CapsLock

        // ── Function Keys ────────────────────────────────────────
        add(0x7A, "KC_F1") // kVK_F1
        add(0x78, "KC_F2") // kVK_F2
        add(0x63, "KC_F3") // kVK_F3
        add(0x76, "KC_F4") // kVK_F4
        add(0x60, "KC_F5") // kVK_F5
        add(0x61, "KC_F6") // kVK_F6
        add(0x62, "KC_F7") // kVK_F7
        add(0x64, "KC_F8") // kVK_F8
        add(0x65, "KC_F9") // kVK_F9
        add(0x6D, "KC_F10") // kVK_F10
        add(0x67, "KC_F11") // kVK_F11
        add(0x6F, "KC_F12") // kVK_F12
        add(0x69, "KC_F13") // kVK_F13
        add(0x6B, "KC_F14") // kVK_F14
        add(0x71, "KC_F15") // kVK_F15
        add(0x6A, "KC_F16") // kVK_F16
        add(0x40, "KC_F17") // kVK_F17
        add(0x4F, "KC_F18") // kVK_F18
        add(0x50, "KC_F19") // kVK_F19
        add(0x5A, "KC_F20") // kVK_F20
        // F21-F24: no standard macOS kVK_ constants defined

        // ── Print Screen / Scroll Lock / Pause ───────────────────
        // These have no standard macOS virtual keycodes.
        // KC_PRINT_SCREEN (HID 0x46) — F13 is often used as substitute
        // KC_SCROLL_LOCK (HID 0x47) — F14 is often used as substitute
        // KC_PAUSE (HID 0x48) — F15 is often used as substitute

        // ── Navigation ───────────────────────────────────────────
        add(0x72, "KC_INSERT", "KC_INS") // kVK_Help (Insert → Help on Mac)
        add(0x73, "KC_HOME") // kVK_Home
        add(0x74, "KC_PAGE_UP", "KC_PGUP") // kVK_PageUp
        add(0x75, "KC_DELETE", "KC_DEL") // kVK_ForwardDelete
        add(0x77, "KC_END") // kVK_End
        add(0x79, "KC_PAGE_DOWN", "KC_PGDN") // kVK_PageDown

        // ── Arrow Keys ───────────────────────────────────────────
        add(0x7C, "KC_RIGHT", "KC_RGHT") // kVK_RightArrow
        add(0x7B, "KC_LEFT") // kVK_LeftArrow
        add(0x7D, "KC_DOWN") // kVK_DownArrow
        add(0x7E, "KC_UP") // kVK_UpArrow

        // ── Numpad ───────────────────────────────────────────────
        // Note: KC_NUM_LOCK (HID 0x53) maps to kVK_ANSI_KeypadClear on Mac
        add(0x47, "KC_NUM_LOCK", "KC_NUM", "KC_NUMLOCK") // kVK_ANSI_KeypadClear
        add(0x4B, "KC_KP_SLASH", "KC_PSLS") // kVK_ANSI_KeypadDivide
        add(0x43, "KC_KP_ASTERISK", "KC_PAST") // kVK_ANSI_KeypadMultiply
        add(0x4E, "KC_KP_MINUS", "KC_PMNS") // kVK_ANSI_KeypadMinus
        add(0x45, "KC_KP_PLUS", "KC_PPLS") // kVK_ANSI_KeypadPlus
        add(0x4C, "KC_KP_ENTER", "KC_PENT") // kVK_ANSI_KeypadEnter
        add(0x53, "KC_KP_1", "KC_P1") // kVK_ANSI_Keypad1
        add(0x54, "KC_KP_2", "KC_P2") // kVK_ANSI_Keypad2
        add(0x55, "KC_KP_3", "KC_P3") // kVK_ANSI_Keypad3
        add(0x56, "KC_KP_4", "KC_P4") // kVK_ANSI_Keypad4
        add(0x57, "KC_KP_5", "KC_P5") // kVK_ANSI_Keypad5
        add(0x58, "KC_KP_6", "KC_P6") // kVK_ANSI_Keypad6
        add(0x59, "KC_KP_7", "KC_P7") // kVK_ANSI_Keypad7
        add(0x5B, "KC_KP_8", "KC_P8") // kVK_ANSI_Keypad8
        add(0x5C, "KC_KP_9", "KC_P9") // kVK_ANSI_Keypad9
        add(0x52, "KC_KP_0", "KC_P0") // kVK_ANSI_Keypad0
        add(0x41, "KC_KP_DOT", "KC_PDOT") // kVK_ANSI_KeypadDecimal
        add(0x51, "KC_KP_EQUAL", "KC_PEQL") // kVK_ANSI_KeypadEquals

        // ── Application / Context Menu ───────────────────────────
        add(0x6E, "KC_APPLICATION", "KC_APP") // kVK_ContextualMenu

        // ── Modifiers ────────────────────────────────────────────
        add(0x3B, "KC_LEFT_CTRL", "KC_LCTL", "KC_LCTRL") // kVK_Control
        add(0x38, "KC_LEFT_SHIFT", "KC_LSFT", "KC_LSHIFT") // kVK_Shift
        add(0x3A, "KC_LEFT_ALT", "KC_LALT", "KC_LOPT") // kVK_Option
        add(0x37, "KC_LEFT_GUI", "KC_LGUI", "KC_LCMD", "KC_LWIN") // kVK_Command
        add(0x3E, "KC_RIGHT_CTRL", "KC_RCTL", "KC_RCTRL") // kVK_RightControl
        add(0x3C, "KC_RIGHT_SHIFT", "KC_RSFT", "KC_RSHIFT") // kVK_RightShift
        add(0x3D, "KC_RIGHT_ALT", "KC_RALT", "KC_ROPT", "KC_ALGR") // kVK_RightOption
        add(0x36, "KC_RIGHT_GUI", "KC_RGUI", "KC_RCMD", "KC_RWIN") // kVK_RightCommand

        // ── Volume / Mute (macOS has dedicated keyCodes) ─────────
        add(0x48, "KC_AUDIO_VOL_UP", "KC_VOLU", "KC_KB_VOLUME_UP") // kVK_VolumeUp
        add(0x49, "KC_AUDIO_VOL_DOWN", "KC_VOLD", "KC_KB_VOLUME_DOWN") // kVK_VolumeDown
        add(0x4A, "KC_AUDIO_MUTE", "KC_MUTE", "KC_KB_MUTE") // kVK_Mute

        // ── Function Key (Fn) ────────────────────────────────────
        add(0x3F, "KC_FN") // kVK_Function

        // ── Help ─────────────────────────────────────────────────
        add(0x72, "KC_HELP") // kVK_Help

        // ── JIS-specific keys ────────────────────────────────────
        add(0x5D, "KC_INTERNATIONAL_3", "KC_INT3") // kVK_JIS_Yen
        add(0x5E, "KC_INTERNATIONAL_1", "KC_INT1") // kVK_JIS_Underscore
        add(0x5F, "KC_KP_COMMA", "KC_PCMM") // kVK_JIS_KeypadComma
        add(0x66, "KC_LANGUAGE_2", "KC_LNG2") // kVK_JIS_Eisu
        add(0x68, "KC_LANGUAGE_1", "KC_LNG1") // kVK_JIS_Kana

        // ── Media Keys (NX key codes, sent via CGEvent) ──────────
        // These use NX_KEYTYPE_* constants, not kVK_ values.
        // They are handled differently on macOS (via HID system events,
        // not standard CGKeyCode). Included for reference but the
        // values below are the NX key type codes used with
        // NSEvent.addGlobalMonitorForEvents / CGEvent.
        //
        // NX_KEYTYPE_PLAY          = 16
        // NX_KEYTYPE_NEXT          = 17
        // NX_KEYTYPE_PREVIOUS      = 18
        // NX_KEYTYPE_FAST          = 19
        // NX_KEYTYPE_REWIND        = 20
        // NX_KEYTYPE_BRIGHTNESS_UP   = 21  (also 0xBD in QMK)
        // NX_KEYTYPE_BRIGHTNESS_DOWN = 22  (also 0xBE in QMK)
        // NX_KEYTYPE_EJECT         = 14
        //
        // These cannot be represented as standard CGKeyCode values.
        // Use NX system-defined events or IOKit HID posting instead.

        return map
    }()

    // swiftlint:enable function_body_length

    // MARK: - Reverse Lookup

    /// Mapping from macOS CGKeyCode to the primary QMK keycode name.
    static let macOSToQMK: [UInt16: String] = {
        // Build reverse map, preferring the shortest alias
        var reverse: [UInt16: String] = [:]
        for (name, code) in qmkToMacOS {
            if let existing = reverse[code] {
                // Keep the shorter (canonical) name
                if name.count < existing.count {
                    reverse[code] = name
                }
            } else {
                reverse[code] = name
            }
        }
        return reverse
    }()

    // MARK: - HID Usage Code Lookup

    /// Maps HID Usage Page 0x07 usage codes to macOS CGKeyCode values.
    /// This is the underlying mapping that `qmkToMacOS` is built on,
    /// indexed by numeric HID usage code instead of string name.
    /// TODO: Wire up for future HID descriptor-based key identification (not used in current keymap-based flow).
    static let hidUsageToMacOS: [UInt16: UInt16] = [
        // Letters (HID 0x04-0x1D)
        0x04: 0x00, // A
        0x05: 0x0B, // B
        0x06: 0x08, // C
        0x07: 0x02, // D
        0x08: 0x0E, // E
        0x09: 0x03, // F
        0x0A: 0x05, // G
        0x0B: 0x04, // H
        0x0C: 0x22, // I
        0x0D: 0x26, // J
        0x0E: 0x28, // K
        0x0F: 0x25, // L
        0x10: 0x2E, // M
        0x11: 0x2D, // N
        0x12: 0x1F, // O
        0x13: 0x23, // P
        0x14: 0x0C, // Q
        0x15: 0x0F, // R
        0x16: 0x01, // S
        0x17: 0x11, // T
        0x18: 0x20, // U
        0x19: 0x09, // V
        0x1A: 0x0D, // W
        0x1B: 0x07, // X
        0x1C: 0x10, // Y
        0x1D: 0x06, // Z

        // Numbers (HID 0x1E-0x27)
        0x1E: 0x12, // 1
        0x1F: 0x13, // 2
        0x20: 0x14, // 3
        0x21: 0x15, // 4
        0x22: 0x17, // 5
        0x23: 0x16, // 6
        0x24: 0x1A, // 7
        0x25: 0x1C, // 8
        0x26: 0x19, // 9
        0x27: 0x1D, // 0

        // Editing keys
        0x28: 0x24, // Enter → kVK_Return
        0x29: 0x35, // Escape
        0x2A: 0x33, // Backspace → kVK_Delete
        0x2B: 0x30, // Tab
        0x2C: 0x31, // Space

        // Punctuation
        0x2D: 0x1B, // Minus
        0x2E: 0x18, // Equal
        0x2F: 0x21, // Left Bracket
        0x30: 0x1E, // Right Bracket
        0x31: 0x2A, // Backslash
        0x32: 0x2A, // Non-US Hash (same position as backslash on ANSI)
        0x33: 0x29, // Semicolon
        0x34: 0x27, // Quote
        0x35: 0x32, // Grave
        0x36: 0x2B, // Comma
        0x37: 0x2F, // Period
        0x38: 0x2C, // Slash

        // Caps Lock
        0x39: 0x39, // Caps Lock

        // Function keys
        0x3A: 0x7A, // F1
        0x3B: 0x78, // F2
        0x3C: 0x63, // F3
        0x3D: 0x76, // F4
        0x3E: 0x60, // F5
        0x3F: 0x61, // F6
        0x40: 0x62, // F7
        0x41: 0x64, // F8
        0x42: 0x65, // F9
        0x43: 0x6D, // F10
        0x44: 0x67, // F11
        0x45: 0x6F, // F12
        0x46: 0x69, // Print Screen → F13
        0x47: 0x6B, // Scroll Lock → F14
        0x48: 0x71, // Pause → F15

        // Navigation
        0x49: 0x72, // Insert → Help
        0x4A: 0x73, // Home
        0x4B: 0x74, // Page Up
        0x4C: 0x75, // Delete Forward
        0x4D: 0x77, // End
        0x4E: 0x79, // Page Down

        // Arrows
        0x4F: 0x7C, // Right
        0x50: 0x7B, // Left
        0x51: 0x7D, // Down
        0x52: 0x7E, // Up

        // Numpad
        0x53: 0x47, // Num Lock → KeypadClear
        0x54: 0x4B, // KP Slash → KeypadDivide
        0x55: 0x43, // KP Asterisk → KeypadMultiply
        0x56: 0x4E, // KP Minus
        0x57: 0x45, // KP Plus
        0x58: 0x4C, // KP Enter
        0x59: 0x53, // KP 1
        0x5A: 0x54, // KP 2
        0x5B: 0x55, // KP 3
        0x5C: 0x56, // KP 4
        0x5D: 0x57, // KP 5
        0x5E: 0x58, // KP 6
        0x5F: 0x59, // KP 7
        0x60: 0x5B, // KP 8
        0x61: 0x5C, // KP 9
        0x62: 0x52, // KP 0
        0x63: 0x41, // KP Dot → KeypadDecimal

        // Non-US
        0x64: 0x0A, // Non-US Backslash → kVK_ISO_Section

        // Application
        0x65: 0x6E, // Application → ContextualMenu

        // KP Equal
        0x67: 0x51, // KP Equal → KeypadEquals

        // Extended function keys
        0x68: 0x69, // F13
        0x69: 0x6B, // F14
        0x6A: 0x71, // F15
        0x6B: 0x6A, // F16
        0x6C: 0x40, // F17
        0x6D: 0x4F, // F18
        0x6E: 0x50, // F19
        0x6F: 0x5A, // F20

        // Help
        0x75: 0x72, // Help

        // Volume (macOS has dedicated kVK_ for these)
        0x7F: 0x4A, // KB Mute → kVK_Mute
        0x80: 0x48, // KB Volume Up → kVK_VolumeUp
        0x81: 0x49, // KB Volume Down → kVK_VolumeDown

        // JIS keys
        0x87: 0x5E, // International 1 → kVK_JIS_Underscore
        0x89: 0x5D, // International 3 → kVK_JIS_Yen
        0x85: 0x5F, // KP Comma → kVK_JIS_KeypadComma
        0x90: 0x68, // Language 1 → kVK_JIS_Kana
        0x91: 0x66, // Language 2 → kVK_JIS_Eisu

        // Modifiers
        0xE0: 0x3B, // Left Control
        0xE1: 0x38, // Left Shift
        0xE2: 0x3A, // Left Alt/Option
        0xE3: 0x37, // Left GUI/Command
        0xE4: 0x3E, // Right Control
        0xE5: 0x3C, // Right Shift
        0xE6: 0x3D, // Right Alt/Option
        0xE7: 0x36, // Right GUI/Command
    ]
}
