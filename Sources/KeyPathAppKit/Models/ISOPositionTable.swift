import Foundation

/// Standard ISO keyboard position table
/// Maps (row, col) matrix positions to macOS keyCodes and labels for standard ISO layouts
/// ISO differs from ANSI in: L-shaped Enter key, extra IntlBackslash key between Left Shift and Z
enum ISOPositionTable {
    /// Standard ISO key mapping from (row, col) to (keyCode, label)
    /// Row 0: Number row (same as ANSI)
    /// Row 1: Top row (same as ANSI)
    /// Row 2: Home row (Caps a s d f g h j k l ; ' Enter - L-shaped)
    /// Row 3: Bottom row (Shift IntlBackslash z x c v b n m , . / Shift)
    /// Row 4: Modifier row (same as ANSI)
    ///
    /// Key differences from ANSI:
    /// - Enter key is L-shaped (spans 2 rows, typically 1.25u wide, 2.25u tall)
    /// - Extra IntlBackslash key (keycode 10) between Left Shift and Z
    /// - Left Shift is shorter (typically 1.25u) to accommodate IntlBackslash
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
        
        // Row 1: Top row (same as ANSI)
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
        case (1, 13): (42, "\\")
        
        // Row 2: Home row - ISO has L-shaped Enter
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
        // ISO Enter is L-shaped - spans row 2 and row 3
        // Some layouts define it as a single key at (2, 12), others split it across (2, 12) and (3, 13)
        // We map both positions to Enter keycode (36) for compatibility with all ISO layouts
        case (2, 12): (36, "↩") // Enter (L-shaped, top part or full key depending on layout)
        case (2, 13): (36, "↩") // Enter (L-shaped, continuation - some layouts use this)
        
        // Row 3: Bottom row - ISO has IntlBackslash between Shift and Z
        case (3, 0): (56, "⇧") // Left Shift (shorter than ANSI, typically 1.25u)
        case (3, 1): (10, "§") // IntlBackslash (ISO-specific key, § on UK, < on German, etc.)
        case (3, 2): (6, "z")
        case (3, 3): (7, "x")
        case (3, 4): (8, "c")
        case (3, 5): (9, "v")
        case (3, 6): (11, "b")
        case (3, 7): (45, "n")
        case (3, 8): (46, "m")
        case (3, 9): (43, ",")
        case (3, 10): (47, ".")
        case (3, 11): (44, "/")
        case (3, 12): (60, "⇧") // Right Shift
        // ISO Enter continuation (L-shaped, bottom part)
        // This position is used when Enter spans both row 2 and row 3
        case (3, 13): (36, "↩") // Enter (L-shaped, bottom part - when Enter is split across rows)
        
        // Row 4: Modifier row (same as ANSI)
        case (4, 0): (59, "⌃") // Left Control
        case (4, 1): (58, "⌥") // Left Option/Alt
        case (4, 2): (55, "⌘") // Left Command/Win
        case (4, 3): (49, "␣") // Space
        case (4, 4): (54, "⌘") // Right Command/Win
        case (4, 5): (61, "⌥") // Right Option/Alt
        case (4, 6): (102, "⌃") // Right Control
        
        // Function row (same as ANSI)
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
        case (3, 14): (126, "▲") // Up Arrow
        case (3, 15): (123, "◀") // Left Arrow
        case (3, 16): (125, "▼") // Down Arrow
        case (3, 17): (124, "▶") // Right Arrow
        
        // Navigation keys
        case (3, 18): (115, "Home")
        case (3, 19): (116, "PgUp")
        case (3, 20): (119, "End")
        case (3, 21): (121, "PgDn")
        
        // ESC key
        case (-1, -1), (0, -1): (53, "esc")
        
        default:
            nil
        }
    }
    
    /// Get key mapping with support for custom mappings
    static func keyMapping(row: Int, col: Int, customMappings: [((Int, Int), (UInt16, String))] = []) -> (keyCode: UInt16, label: String)? {
        // Check custom mappings first
        if let custom = customMappings.first(where: { $0.0 == (row, col) }) {
            return custom.1
        }
        // Fall back to standard ISO mapping
        return keyMapping(row: row, col: col)
    }
}
