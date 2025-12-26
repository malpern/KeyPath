import Foundation

/// Standard ANSI keyboard position table
/// Maps (row, col) matrix positions to macOS keyCodes and labels for standard ANSI layouts
/// Used for Tier 2 keyboards (60%, 65%, 75%, 80%, 100%) where physical layout JSON doesn't include keyCode/label
enum ANSIPositionTable {
    /// Standard ANSI key mapping from (row, col) to (keyCode, label)
    /// Row 0: Number row (1 2 3 4 5 6 7 8 9 0 - = Backspace)
    /// Row 1: Top row (Tab q w e r t y u i o p [ ] \)
    /// Row 2: Home row (Caps a s d f g h j k l ; ' Enter)
    /// Row 3: Bottom row (Shift z x c v b n m , . / Shift)
    /// Row 4: Modifier row (Ctrl Alt Cmd Space Cmd Alt Ctrl)
    ///
    /// Note: This assumes standard ANSI layout. Non-standard layouts (HHKB, Alice, etc.) need custom mappings.
    static func keyMapping(row: Int, col: Int) -> (keyCode: UInt16, label: String)? {
        switch (row, col) {
        // Row 0: Number row
        // Standard: ` 1 2 3 4 5 6 7 8 9 0 - = Backspace`
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
        case (0, 12): (51, "⌫") // Backspace (1.5u on some layouts)
        // Row 1: Top row
        // Standard: `Tab q w e r t y u i o p [ ] \`
        case (1, 0): (48, "⇥") // Tab (1.5u on some layouts)
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
        case (1, 13): (42, "\\")
        // Row 2: Home row
        // Standard: `Caps a s d f g h j k l ; ' Enter`
        case (2, 0): (57, "⇪") // Caps Lock (1.75u on some layouts)
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
        case (2, 12): (36, "↩") // Enter (2.25u on some layouts)
        // Row 3: Bottom row
        // Standard: `Shift z x c v b n m , . / Shift`
        case (3, 0): (56, "⇧") // Left Shift (2.25u on some layouts)
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
        case (3, 11): (60, "⇧") // Right Shift (2.75u on some layouts)
        // Row 4: Modifier row
        // Standard ANSI: `Ctrl Win Alt Space Alt Win Menu Ctrl`
        // macOS variant: `Ctrl Option Cmd Space Cmd Option Ctrl`
        case (4, 0): (59, "⌃") // Left Control
        case (4, 1): (58, "⌥") // Left Option/Alt
        case (4, 2): (55, "⌘") // Left Command/Win
        case (4, 3): (49, "␣") // Space (varies by layout, typically 6.25u or 7u)
        case (4, 4): (54, "⌘") // Right Command/Win
        case (4, 5): (61, "⌥") // Right Option/Alt
        case (4, 6): (102, "⌃") // Right Control (if present)
        // Extended keys (for layouts with more keys)
        // Function row (Row -1 or Row 5, depending on layout)
        // Standard ANSI function row: F1-F12 in columns 0-11
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
        // Typically in a cluster below right Shift
        // Common positions vary by layout - handle multiple possible positions
        // Row 3 (bottom row) positions for arrow cluster (65% layouts)
        case (3, 12): (126, "▲") // Up Arrow (65% layouts, after right Shift)
        case (3, 13): (123, "◀") // Left Arrow
        case (3, 14): (125, "▼") // Down Arrow
        case (3, 15): (124, "▶") // Right Arrow
        // Additional navigation keys (for 75% and larger layouts)
        // Positioned above arrow cluster or in separate row
        case (3, 16): (115, "Home")
        case (3, 17): (116, "PgUp")
        case (3, 18): (119, "End")
        case (3, 19): (121, "PgDn")
        // ESC key (for layouts that have it separate from function row)
        case (-1, -1), (0, -1): (53, "esc")
        default:
            nil
        }
    }

    /// Get key mapping with support for non-standard column positions
    /// Some keyboards may have keys in non-standard positions (e.g., split spacebar)
    /// This allows extending the standard table
    static func keyMapping(row: Int, col: Int, customMappings: [((Int, Int), (UInt16, String))] = []) -> (keyCode: UInt16, label: String)? {
        // Check custom mappings first
        if let custom = customMappings.first(where: { $0.0 == (row, col) }) {
            return custom.1
        }
        // Fall back to standard ANSI mapping
        return keyMapping(row: row, col: col)
    }
}
