import Foundation

/// Standard JIS keyboard position table
/// Maps (row, col) matrix positions to macOS keyCodes and labels for standard JIS layouts
/// JIS differs from ANSI/ISO in: L-shaped Enter, Yen key, Underscore key, Kana/Eisu keys, shorter spacebar
enum JISPositionTable {
    /// Standard JIS key mapping from (row, col) to (keyCode, label)
    /// Row 0: Number row (same as ANSI)
    /// Row 1: Top row (same as ANSI, plus Yen key)
    /// Row 2: Home row (Caps a s d f g h j k l ; ' Enter - L-shaped)
    /// Row 3: Bottom row (Shift z x c v b n m , . / Underscore Shift)
    /// Row 4: Modifier row (Ctrl Option Cmd Eisu Space Kana Cmd Option Ctrl)
    ///
    /// Key differences from ANSI:
    /// - Enter key is L-shaped (spans 2 rows, like ISO)
    /// - Yen key (kVK_JIS_Yen = 0x5D) replaces backslash position
    /// - Underscore key (kVK_JIS_Underscore = 0x5E) between / and Right Shift
    /// - Kana key (kVK_JIS_Kana = 0x68) right of Space
    /// - Eisu key (kVK_JIS_Eisu = 0x66) left of Space
    /// - Shorter spacebar to accommodate Kana/Eisu keys
    static func keyMapping(row: Int, col: Int) -> (keyCode: UInt16, label: String)? {
        switch (row, col) {
        // Row 0: Number row (same as ANSI)
        case (0, 0): (18, "1")
        case (0, 1): (19, "2")
        case (0, 2): (20, "3")
        case (0, 3): (21, "4")
        case (0, 4): (23, "5")
        case (0, 5): (22, "6")
        case (0, 6): (26, "7")
        case (0, 7): (28, "8")
        case (0, 8): (25, "9")
        case (0, 9): (29, "0")
        case (0, 10): (27, "-")
        case (0, 11): (24, "=")
        case (0, 12): (51, "⌫") // Backspace
        // Row 1: Top row - JIS has Yen key instead of backslash
        case (1, 0): (48, "⇥") // Tab
        case (1, 1): (12, "q")
        case (1, 2): (13, "w")
        case (1, 3): (14, "e")
        case (1, 4): (15, "r")
        case (1, 5): (17, "t")
        case (1, 6): (16, "y")
        case (1, 7): (32, "u")
        case (1, 8): (34, "i")
        case (1, 9): (31, "o")
        case (1, 10): (35, "p")
        case (1, 11): (33, "[")
        case (1, 12): (30, "]")
        case (1, 13): (0x5D, "¥") // Yen key (kVK_JIS_Yen)
        // Row 2: Home row - JIS has L-shaped Enter (like ISO)
        case (2, 0): (57, "⇪") // Caps Lock
        case (2, 1): (0, "a")
        case (2, 2): (1, "s")
        case (2, 3): (2, "d")
        case (2, 4): (3, "f")
        case (2, 5): (5, "g")
        case (2, 6): (4, "h")
        case (2, 7): (38, "j")
        case (2, 8): (40, "k")
        case (2, 9): (37, "l")
        case (2, 10): (41, ";")
        case (2, 11): (39, "'")
        case (2, 12): (36, "↩") // Enter (L-shaped, top part)
        case (2, 13): (36, "↩") // Enter (L-shaped, continuation)
        // Row 3: Bottom row - JIS has Underscore key between / and Right Shift
        case (3, 0): (56, "⇧") // Left Shift
        case (3, 1): (6, "z")
        case (3, 2): (7, "x")
        case (3, 3): (8, "c")
        case (3, 4): (9, "v")
        case (3, 5): (11, "b")
        case (3, 6): (45, "n")
        case (3, 7): (46, "m")
        case (3, 8): (43, ",")
        case (3, 9): (47, ".")
        case (3, 10): (44, "/")
        case (3, 11): (0x5E, "_") // Underscore key (kVK_JIS_Underscore)
        case (3, 12): (60, "⇧") // Right Shift
        // Row 4: Modifier row - JIS has Eisu and Kana keys flanking shorter spacebar
        case (4, 0): (59, "⌃") // Left Control
        case (4, 1): (58, "⌥") // Left Option/Alt
        case (4, 2): (55, "⌘") // Left Command/Win
        case (4, 3): (0x66, "英数") // Eisu key (kVK_JIS_Eisu)
        case (4, 4): (49, "␣") // Space (shorter than ANSI)
        case (4, 5): (0x68, "かな") // Kana key (kVK_JIS_Kana)
        case (4, 6): (54, "⌘") // Right Command/Win
        case (4, 7): (61, "⌥") // Right Option/Alt
        case (4, 8): (102, "⌃") // Right Control
        // Function row (same as ANSI/ISO)
        case (-1, 0), (5, 0): (122, "f1")
        case (-1, 1), (5, 1): (120, "f2")
        case (-1, 2), (5, 2): (99, "f3")
        case (-1, 3), (5, 3): (118, "f4")
        case (-1, 4), (5, 4): (96, "f5")
        case (-1, 5), (5, 5): (97, "f6")
        case (-1, 6), (5, 6): (98, "f7")
        case (-1, 7), (5, 7): (100, "f8")
        case (-1, 8), (5, 8): (101, "f9")
        case (-1, 9), (5, 9): (109, "f10")
        case (-1, 10), (5, 10): (103, "f11")
        case (-1, 11), (5, 11): (111, "f12")
        // Arrow keys (for 65% and larger layouts)
        case (3, 13): (126, "▲") // Up Arrow
        case (3, 14): (123, "◀") // Left Arrow
        case (3, 15): (125, "▼") // Down Arrow
        case (3, 16): (124, "▶") // Right Arrow
        // Navigation keys
        case (3, 17): (115, "Home")
        case (3, 18): (116, "PgUp")
        case (3, 19): (119, "End")
        case (3, 20): (121, "PgDn")
        // ESC key
        case (-1, -1), (0, -1): (53, "esc")
        default:
            nil
        }
    }

}
