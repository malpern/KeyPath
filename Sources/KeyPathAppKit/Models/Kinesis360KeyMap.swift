import Foundation

/// Key mapping for Kinesis Advantage 360 stock QWERTY layout
/// Maps matrix positions (row, col) from the QMK layout JSON to macOS key codes and labels
///
/// Matrix layout reference from ZMK default keymap:
/// - Columns 0-6: Left main keys
/// - Columns 7-9: Left thumb cluster
/// - Columns 11-13: Right thumb cluster
/// - Columns 14-20: Right main keys
enum Kinesis360KeyMap {
    /// Mapping from (row, col) to (keyCode, label)
    /// Returns nil for positions without keys
    static func keyMapping(row: Int, col: Int) -> (keyCode: UInt16, label: String)? {
        switch (row, col) {
        // Row 0: Number row
        // Left: = 1 2 3 4 5 Layer
        case (0, 0): (24, "=") // Equals
        case (0, 1): (18, "1")
        case (0, 2): (19, "2")
        case (0, 3): (20, "3")
        case (0, 4): (21, "4")
        case (0, 5): (23, "5")
        case (0, 6): (0xFFFF, "Lyr") // Layer key (no macOS equivalent)
        // Right: Fn 6 7 8 9 0 -
        case (0, 14): (0xFFFF, "Fn") // Function (no direct equivalent)
        case (0, 15): (22, "6")
        case (0, 16): (26, "7")
        case (0, 17): (28, "8")
        case (0, 18): (25, "9")
        case (0, 19): (29, "0")
        case (0, 20): (27, "-") // Minus
        // Row 1: QWERTY top row
        // Left: Tab Q W E R T
        case (1, 0): (48, "⇥") // Tab
        case (1, 1): (12, "q")
        case (1, 2): (13, "w")
        case (1, 3): (14, "e")
        case (1, 4): (15, "r")
        case (1, 5): (17, "t")
        case (1, 6): nil // No key in JSON
        // Right: Y U I O P \
        case (1, 14): (16, "y")
        case (1, 15): (32, "u")
        case (1, 16): (34, "i")
        case (1, 17): (31, "o")
        case (1, 18): (35, "p")
        case (1, 19): (42, "\\") // Backslash
        case (1, 20): nil // No key in JSON
        // Row 2: Home row + thumb cluster upper row
        // Left: Esc A S D F G
        case (2, 0): (53, "esc")
        case (2, 1): (0, "a")
        case (2, 2): (1, "s")
        case (2, 3): (2, "d")
        case (2, 4): (3, "f")
        case (2, 5): (5, "g")
        case (2, 6): nil // No key in JSON
        // Left thumb cluster (row 2)
        case (2, 8): (59, "⌃") // Control
        case (2, 9): (58, "⌥") // Option/Alt
        // Right thumb cluster (row 2)
        case (2, 11): (55, "⌘") // Command
        case (2, 12): (59, "⌃") // Control
        // Right: H J K L ; '
        case (2, 14): (4, "h")
        case (2, 15): (38, "j")
        case (2, 16): (40, "k")
        case (2, 17): (37, "l")
        case (2, 18): (41, ";")
        case (2, 19): (39, "'") // Quote
        case (2, 20): nil // No key in JSON
        // Row 3: Bottom alpha row + thumb cluster middle row
        // Left: Shift Z X C V B
        case (3, 0): (56, "⇧") // Left Shift
        case (3, 1): (6, "z")
        case (3, 2): (7, "x")
        case (3, 3): (8, "c")
        case (3, 4): (9, "v")
        case (3, 5): (11, "b")
        // Left thumb cluster (row 3)
        case (3, 9): (51, "⌫") // Backspace
        // Right thumb cluster (row 3)
        case (3, 11): (36, "↩") // Enter/Return
        // Right: N M , . / Shift
        case (3, 15): (45, "n")
        case (3, 16): (46, "m")
        case (3, 17): (43, ",")
        case (3, 18): (47, ".")
        case (3, 19): (44, "/")
        case (3, 20): (60, "⇧") // Right Shift
        // Row 4: Function row + thumb cluster bottom row
        // Left: Fn ` Caps ← →
        case (4, 0): (0xFFFF, "Fn") // Function (Kinesis layer)
        case (4, 1): (50, "`") // Grave/Tilde
        case (4, 2): (57, "⇪") // Caps Lock
        case (4, 3): (123, "◀") // Left Arrow
        case (4, 4): (124, "▶") // Right Arrow
        // Left thumb cluster (row 4) - tall 2u keys
        case (4, 7): (115, "Home")
        case (4, 8): (116, "PgUp")
        case (4, 9): (117, "Del") // Delete
        // Right thumb cluster (row 4) - tall 2u keys
        case (4, 11): (49, "␣") // Space
        case (4, 12): (119, "End")
        case (4, 13): (121, "PgDn")
        // Right: ↑ ↓ [ ] Fn
        case (4, 16): (126, "▲") // Up Arrow
        case (4, 17): (125, "▼") // Down Arrow
        case (4, 18): (33, "[")
        case (4, 19): (30, "]")
        case (4, 20): (0xFFFF, "Fn") // Function
        default:
            nil
        }
    }
}
