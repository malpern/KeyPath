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
        case (0, 0): return (24, "=")    // Equals
        case (0, 1): return (18, "1")
        case (0, 2): return (19, "2")
        case (0, 3): return (20, "3")
        case (0, 4): return (21, "4")
        case (0, 5): return (23, "5")
        case (0, 6): return (0xFFFF, "Lyr") // Layer key (no macOS equivalent)

        // Right: Fn 6 7 8 9 0 -
        case (0, 14): return (0xFFFF, "Fn") // Function (no direct equivalent)
        case (0, 15): return (22, "6")
        case (0, 16): return (26, "7")
        case (0, 17): return (28, "8")
        case (0, 18): return (25, "9")
        case (0, 19): return (29, "0")
        case (0, 20): return (27, "-")   // Minus

        // Row 1: QWERTY top row
        // Left: Tab Q W E R T
        case (1, 0): return (48, "⇥")    // Tab
        case (1, 1): return (12, "q")
        case (1, 2): return (13, "w")
        case (1, 3): return (14, "e")
        case (1, 4): return (15, "r")
        case (1, 5): return (17, "t")
        case (1, 6): return nil          // No key in JSON

        // Right: Y U I O P \
        case (1, 14): return (16, "y")
        case (1, 15): return (32, "u")
        case (1, 16): return (34, "i")
        case (1, 17): return (31, "o")
        case (1, 18): return (35, "p")
        case (1, 19): return (42, "\\")  // Backslash
        case (1, 20): return nil         // No key in JSON

        // Row 2: Home row + thumb cluster upper row
        // Left: Esc A S D F G
        case (2, 0): return (53, "esc")
        case (2, 1): return (0, "a")
        case (2, 2): return (1, "s")
        case (2, 3): return (2, "d")
        case (2, 4): return (3, "f")
        case (2, 5): return (5, "g")
        case (2, 6): return nil          // No key in JSON

        // Left thumb cluster (row 2)
        case (2, 8): return (59, "⌃")    // Control
        case (2, 9): return (58, "⌥")    // Option/Alt

        // Right thumb cluster (row 2)
        case (2, 11): return (55, "⌘")   // Command
        case (2, 12): return (59, "⌃")   // Control

        // Right: H J K L ; '
        case (2, 14): return (4, "h")
        case (2, 15): return (38, "j")
        case (2, 16): return (40, "k")
        case (2, 17): return (37, "l")
        case (2, 18): return (41, ";")
        case (2, 19): return (39, "'")   // Quote
        case (2, 20): return nil         // No key in JSON

        // Row 3: Bottom alpha row + thumb cluster middle row
        // Left: Shift Z X C V B
        case (3, 0): return (56, "⇧")    // Left Shift
        case (3, 1): return (6, "z")
        case (3, 2): return (7, "x")
        case (3, 3): return (8, "c")
        case (3, 4): return (9, "v")
        case (3, 5): return (11, "b")

        // Left thumb cluster (row 3)
        case (3, 9): return (51, "⌫")    // Backspace

        // Right thumb cluster (row 3)
        case (3, 11): return (36, "↩")   // Enter/Return

        // Right: N M , . / Shift
        case (3, 15): return (45, "n")
        case (3, 16): return (46, "m")
        case (3, 17): return (43, ",")
        case (3, 18): return (47, ".")
        case (3, 19): return (44, "/")
        case (3, 20): return (60, "⇧")   // Right Shift

        // Row 4: Function row + thumb cluster bottom row
        // Left: Fn ` Caps ← →
        case (4, 0): return (0xFFFF, "Fn") // Function (Kinesis layer)
        case (4, 1): return (50, "`")     // Grave/Tilde
        case (4, 2): return (57, "⇪")     // Caps Lock
        case (4, 3): return (123, "◀")    // Left Arrow
        case (4, 4): return (124, "▶")    // Right Arrow

        // Left thumb cluster (row 4) - tall 2u keys
        case (4, 7): return (115, "Home")
        case (4, 8): return (116, "PgUp")
        case (4, 9): return (117, "Del")  // Delete

        // Right thumb cluster (row 4) - tall 2u keys
        case (4, 11): return (49, "␣")    // Space
        case (4, 12): return (119, "End")
        case (4, 13): return (121, "PgDn")

        // Right: ↑ ↓ [ ] Fn
        case (4, 16): return (126, "▲")    // Up Arrow
        case (4, 17): return (125, "▼")    // Down Arrow
        case (4, 18): return (33, "[")
        case (4, 19): return (30, "]")
        case (4, 20): return (0xFFFF, "Fn") // Function

        default:
            return nil
        }
    }
}
