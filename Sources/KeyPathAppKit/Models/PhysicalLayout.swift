import Foundation

/// Represents a single physical key on a keyboard layout
struct PhysicalKey: Identifiable, Hashable {
    let id: UUID
    let keyCode: UInt16 // CGEvent key code (matches KeyboardCapture)
    let label: String // Display label ("A", "Shift", "⌘", "🔅")
    let x: Double // In keyboard units (0-based)
    let y: Double
    let width: Double // 1.0 = standard key
    let height: Double
    let rotation: Double // Rotation in degrees (for ergonomic keyboards)

    init(
        id: UUID = UUID(),
        keyCode: UInt16,
        label: String,
        x: Double,
        y: Double,
        width: Double = 1.0,
        height: Double = 1.0,
        rotation: Double = 0.0
    ) {
        self.id = id
        self.keyCode = keyCode
        self.label = label
        self.x = x
        self.y = y
        self.width = width
        self.height = height
        self.rotation = rotation
    }
}

/// Represents a complete physical keyboard layout
struct PhysicalLayout: Identifiable {
    let id: String // Unique identifier: "macbook-us", "kinesis-360"
    let name: String // Display name: "MacBook US", "Kinesis Advantage 360"
    let keys: [PhysicalKey]
    let totalWidth: Double // For aspect ratio calculation
    let totalHeight: Double

    /// Registry of all known layouts
    // swiftformat:disable:next redundantSelf
    static let all: [PhysicalLayout] = [macBookUS, kinesisAdvantage360]

    /// Find a layout by its identifier
    static func find(id: String) -> PhysicalLayout? {
        all.first { $0.id == id }
    }

    static let macBookUS: PhysicalLayout = {
        var keys: [PhysicalKey] = []
        var currentX = 0.0
        let keySpacing = 0.08 // Gap between keys (tighter like real MacBook)
        let rowSpacing = 1.1 // Vertical spacing between row centers
        let standardKeyWidth = 1.0
        let standardKeyHeight = 1.0

        // Target right edge (from number row: 13 standard + 1.5 delete + 13 gaps)
        let targetRightEdge = 13 * (standardKeyWidth + keySpacing) + 1.5

        // Row 0: ESC + Function Keys + Touch ID (same height as standard keys)
        // ESC is same width as Tab (1.5), Touch ID is same width as ~ key (1.0)
        let escWidth = 1.5
        let touchIdWidth = standardKeyWidth // Same width as ~ key
        let functionRowAvailable = targetRightEdge - escWidth - keySpacing - touchIdWidth - keySpacing
        let functionKeyWidth = (functionRowAvailable - 11 * keySpacing) / 12

        // ESC key (same size as tab)
        keys.append(PhysicalKey(
            keyCode: 53,
            label: "esc",
            x: 0.0,
            y: 0.0,
            width: escWidth,
            height: standardKeyHeight
        ))
        currentX = escWidth + keySpacing

        // Function keys F1-F12
        let functionKeys: [(UInt16, String)] = [
            (122, "F1"), (120, "F2"), (99, "F3"), (118, "F4"),
            (96, "F5"), (97, "F6"), (98, "F7"), (100, "F8"),
            (101, "F9"), (109, "F10"), (103, "F11"), (111, "F12")
        ]
        for (keyCode, label) in functionKeys {
            keys.append(PhysicalKey(
                keyCode: keyCode,
                label: label,
                x: currentX,
                y: 0.0,
                width: functionKeyWidth,
                height: standardKeyHeight
            ))
            currentX += functionKeyWidth + keySpacing
        }

        // Touch ID key (same width as backslash key)
        keys.append(PhysicalKey(
            keyCode: 0xFFFF, // No real keycode for Touch ID
            label: "🔒",
            x: currentX,
            y: 0.0,
            width: touchIdWidth,
            height: standardKeyHeight
        ))

        // Row 1: Number Row - defines the keyboard width
        let numberRow: [(UInt16, String, Double)] = [
            (50, "`", standardKeyWidth),
            (18, "1", standardKeyWidth), (19, "2", standardKeyWidth),
            (20, "3", standardKeyWidth), (21, "4", standardKeyWidth),
            (23, "5", standardKeyWidth), (22, "6", standardKeyWidth),
            (26, "7", standardKeyWidth), (28, "8", standardKeyWidth),
            (25, "9", standardKeyWidth), (29, "0", standardKeyWidth),
            (27, "-", standardKeyWidth), (24, "=", standardKeyWidth),
            (51, "⌫", 1.5) // Delete
        ]
        currentX = 0.0
        for (keyCode, label, width) in numberRow {
            keys.append(PhysicalKey(
                keyCode: keyCode, label: label, x: currentX,
                y: rowSpacing, width: width, height: standardKeyHeight
            ))
            currentX += width + keySpacing
        }

        // Row 2: QWERTY row (tab 1.5 + 12 standard + backslash to align)
        let backslashWidth = targetRightEdge - (1.5 + keySpacing + 12 * (standardKeyWidth + keySpacing))
        let topRow: [(UInt16, String, Double)] = [
            (48, "⇥", 1.5), // Tab
            (12, "q", standardKeyWidth), (13, "w", standardKeyWidth),
            (14, "e", standardKeyWidth), (15, "r", standardKeyWidth),
            (17, "t", standardKeyWidth), (16, "y", standardKeyWidth),
            (32, "u", standardKeyWidth), (34, "i", standardKeyWidth),
            (31, "o", standardKeyWidth), (35, "p", standardKeyWidth),
            (33, "[", standardKeyWidth), (30, "]", standardKeyWidth),
            (42, "\\", backslashWidth)
        ]
        currentX = 0.0
        for (keyCode, label, width) in topRow {
            keys.append(PhysicalKey(
                keyCode: keyCode, label: label, x: currentX,
                y: rowSpacing * 2, width: width, height: standardKeyHeight
            ))
            currentX += width + keySpacing
        }

        // Row 3: Home row (caps 1.8 + 11 standard + return to align)
        let capsWidth = 1.8
        let returnWidth = targetRightEdge - (capsWidth + keySpacing + 11 * (standardKeyWidth + keySpacing))
        let middleRow: [(UInt16, String, Double)] = [
            (57, "⇪", capsWidth), // Caps Lock
            (0, "a", standardKeyWidth), (1, "s", standardKeyWidth),
            (2, "d", standardKeyWidth), (3, "f", standardKeyWidth),
            (5, "g", standardKeyWidth), (4, "h", standardKeyWidth),
            (38, "j", standardKeyWidth), (40, "k", standardKeyWidth),
            (37, "l", standardKeyWidth), (41, ";", standardKeyWidth),
            (39, "'", standardKeyWidth),
            (36, "↩", returnWidth) // Return - sized to align right edge
        ]
        currentX = 0.0
        for (keyCode, label, width) in middleRow {
            keys.append(PhysicalKey(
                keyCode: keyCode, label: label, x: currentX,
                y: rowSpacing * 3, width: width, height: standardKeyHeight
            ))
            currentX += width + keySpacing
        }

        // Row 4: Bottom row - both shifts same width for symmetry
        let shiftWidth = 2.35
        let bottomRow: [(UInt16, String, Double)] = [
            (56, "⇧", shiftWidth), // Left Shift
            (6, "z", standardKeyWidth), (7, "x", standardKeyWidth),
            (8, "c", standardKeyWidth), (9, "v", standardKeyWidth),
            (11, "b", standardKeyWidth), (45, "n", standardKeyWidth),
            (46, "m", standardKeyWidth), (43, ",", standardKeyWidth),
            (47, ".", standardKeyWidth), (44, "/", standardKeyWidth),
            (60, "⇧", shiftWidth) // Right Shift - same width as left
        ]
        currentX = 0.0
        for (keyCode, label, width) in bottomRow {
            keys.append(PhysicalKey(
                keyCode: keyCode, label: label, x: currentX,
                y: rowSpacing * 4, width: width, height: standardKeyHeight
            ))
            currentX += width + keySpacing
        }

        // Row 5: Modifiers first, then position arrows relative to where modifiers end
        let row5Top = rowSpacing * 5
        let fnWidth = standardKeyWidth // Same as Z key
        let ctrlWidth = standardKeyWidth // Same as Z key
        let optWidth = standardKeyWidth // Same as Z key (both left and right)
        let cmdWidth = 1.35

        // Arrow cluster dimensions (narrower keys and tighter spacing for right margin)
        let arrowKeyHeight = 0.45
        let arrowKeyGap = 0.1
        let arrowKeyWidth = 0.9 // Narrower than standard to create right margin
        let arrowKeySpacing = 0.04 // Tighter than standard keySpacing (0.08)
        let arrowRightMargin = 0.15 // Match visual spacing of shift row
        let arrowClusterWidth = 3 * arrowKeyWidth + 2 * arrowKeySpacing + arrowRightMargin

        // Calculate spacebar: total width minus left mods, right mods, and arrow cluster
        let leftModsWidth = fnWidth + keySpacing + ctrlWidth + keySpacing + optWidth + keySpacing + cmdWidth + keySpacing
        let rightModsWidth = cmdWidth + keySpacing + optWidth + keySpacing
        let spacebarWidth = targetRightEdge - leftModsWidth - rightModsWidth - arrowClusterWidth

        let modifierRow: [(UInt16, String, Double)] = [
            (63, "fn", fnWidth),
            (59, "⌃", ctrlWidth),
            (58, "⌥", optWidth),
            (55, "⌘", cmdWidth),
            (49, " ", spacebarWidth),
            (54, "⌘", cmdWidth),
            (61, "⌥", optWidth)
        ]
        currentX = 0.0
        for (keyCode, label, width) in modifierRow {
            keys.append(PhysicalKey(
                keyCode: keyCode, label: label, x: currentX,
                y: row5Top, width: width, height: standardKeyHeight
            ))
            currentX += width + keySpacing
        }

        // Arrow cluster: positioned relative to where modifiers end (currentX is now right after right Option + keySpacing)
        let arrowXStart = currentX

        // Up arrow - center column, upper half of modifier row space
        keys.append(PhysicalKey(
            keyCode: 126, label: "▲",
            x: arrowXStart + arrowKeyWidth + arrowKeySpacing,
            y: row5Top,
            width: arrowKeyWidth, height: arrowKeyHeight
        ))

        // Left, Down, Right - lower half of modifier row space (with gap)
        let lowerArrowY = row5Top + arrowKeyHeight + arrowKeyGap
        keys.append(PhysicalKey(
            keyCode: 123, label: "◀",
            x: arrowXStart, y: lowerArrowY,
            width: arrowKeyWidth, height: arrowKeyHeight
        ))
        keys.append(PhysicalKey(
            keyCode: 125, label: "▼",
            x: arrowXStart + arrowKeyWidth + arrowKeySpacing, y: lowerArrowY,
            width: arrowKeyWidth, height: arrowKeyHeight
        ))
        keys.append(PhysicalKey(
            keyCode: 124, label: "▶",
            x: arrowXStart + 2 * (arrowKeyWidth + arrowKeySpacing), y: lowerArrowY,
            width: arrowKeyWidth, height: arrowKeyHeight
        ))

        return PhysicalLayout(
            id: "macbook-us",
            name: "MacBook US",
            keys: keys,
            totalWidth: targetRightEdge,
            totalHeight: rowSpacing * 5 + standardKeyHeight
        )
    }()

    // MARK: - Kinesis Advantage 360

    /// Kinesis Advantage 360 split ergonomic keyboard layout
    /// Physical layout from: https://github.com/nickcoutsos/keymap-editor-contrib/blob/main/keyboard-data/adv360pro.json
    /// Key mapping based on stock QWERTY layout from ZMK default keymap
    static let kinesisAdvantage360: PhysicalLayout = {
        var keys: [PhysicalKey] = []

        // The Kinesis 360 has a split layout with:
        // - Main key wells on left and right (cols 0-6 and 14-20 in the matrix)
        // - Thumb clusters in the center with rotated keys (cols 7-9 and 11-13)
        // - A gap between the halves for the split
        //
        // Stock QWERTY layout from ZMK default:
        // Row 0: = 1 2 3 4 5 [Layer] | [Fn] 6 7 8 9 0 -
        // Row 1: Tab Q W E R T | Y U I O P \
        // Row 2: Esc A S D F G [Ctrl Alt Cmd Ctrl] H J K L ; '
        // Row 3: Shift Z X C V B | N M , . / Shift
        // Row 4: Fn ` Caps ← → [Home PgUp Bksp Del] | [Enter End PgDn] Space ↑ ↓ [ ] Fn

        // Gap between left and right halves (in key units)
        let splitGap = 3.5

        // Helper to offset right-half keys
        func rightX(_ baseX: Double) -> Double { baseX + splitGap + 7.0 }

        // Row 0: Number row
        // Left: = 1 2 3 4 5 Layer
        keys.append(PhysicalKey(keyCode: 24, label: "=", x: 0, y: 0.25, width: 1.25))
        keys.append(PhysicalKey(keyCode: 18, label: "1", x: 1.25, y: 0.25))
        keys.append(PhysicalKey(keyCode: 19, label: "2", x: 2.25, y: 0))
        keys.append(PhysicalKey(keyCode: 20, label: "3", x: 3.25, y: 0))
        keys.append(PhysicalKey(keyCode: 21, label: "4", x: 4.25, y: 0))
        keys.append(PhysicalKey(keyCode: 23, label: "5", x: 5.25, y: 0))
        keys.append(PhysicalKey(keyCode: 0xFFFF, label: "Lyr", x: 6.25, y: 0))

        // Right: Fn 6 7 8 9 0 -
        keys.append(PhysicalKey(keyCode: 0xFFFF, label: "Fn", x: rightX(0), y: 0))
        keys.append(PhysicalKey(keyCode: 22, label: "6", x: rightX(1), y: 0))
        keys.append(PhysicalKey(keyCode: 26, label: "7", x: rightX(2), y: 0))
        keys.append(PhysicalKey(keyCode: 28, label: "8", x: rightX(3), y: 0))
        keys.append(PhysicalKey(keyCode: 25, label: "9", x: rightX(4), y: 0))
        keys.append(PhysicalKey(keyCode: 29, label: "0", x: rightX(5), y: 0.25))
        keys.append(PhysicalKey(keyCode: 27, label: "-", x: rightX(6), y: 0.25, width: 1.25))

        // Row 1: QWERTY top row
        // Left: Tab Q W E R T
        keys.append(PhysicalKey(keyCode: 48, label: "⇥", x: 0, y: 1.25, width: 1.25))
        keys.append(PhysicalKey(keyCode: 12, label: "q", x: 1.25, y: 1.25))
        keys.append(PhysicalKey(keyCode: 13, label: "w", x: 2.25, y: 1))
        keys.append(PhysicalKey(keyCode: 14, label: "e", x: 3.25, y: 1))
        keys.append(PhysicalKey(keyCode: 15, label: "r", x: 4.25, y: 1))
        keys.append(PhysicalKey(keyCode: 17, label: "t", x: 5.25, y: 1))

        // Right: Y U I O P \
        keys.append(PhysicalKey(keyCode: 16, label: "y", x: rightX(0), y: 1))
        keys.append(PhysicalKey(keyCode: 32, label: "u", x: rightX(1), y: 1))
        keys.append(PhysicalKey(keyCode: 34, label: "i", x: rightX(2), y: 1))
        keys.append(PhysicalKey(keyCode: 31, label: "o", x: rightX(3), y: 1))
        keys.append(PhysicalKey(keyCode: 35, label: "p", x: rightX(4), y: 1))
        keys.append(PhysicalKey(keyCode: 42, label: "\\", x: rightX(5), y: 1.25, width: 1.25))

        // Row 2: Home row
        // Left: Esc A S D F G
        keys.append(PhysicalKey(keyCode: 53, label: "esc", x: 0, y: 2.25, width: 1.25))
        keys.append(PhysicalKey(keyCode: 0, label: "a", x: 1.25, y: 2.25))
        keys.append(PhysicalKey(keyCode: 1, label: "s", x: 2.25, y: 2))
        keys.append(PhysicalKey(keyCode: 2, label: "d", x: 3.25, y: 2))
        keys.append(PhysicalKey(keyCode: 3, label: "f", x: 4.25, y: 2))
        keys.append(PhysicalKey(keyCode: 5, label: "g", x: 5.25, y: 2))

        // Right: H J K L ; '
        keys.append(PhysicalKey(keyCode: 4, label: "h", x: rightX(0), y: 2))
        keys.append(PhysicalKey(keyCode: 38, label: "j", x: rightX(1), y: 2))
        keys.append(PhysicalKey(keyCode: 40, label: "k", x: rightX(2), y: 2))
        keys.append(PhysicalKey(keyCode: 37, label: "l", x: rightX(3), y: 2))
        keys.append(PhysicalKey(keyCode: 41, label: ";", x: rightX(4), y: 2))
        keys.append(PhysicalKey(keyCode: 39, label: "'", x: rightX(5), y: 2.25, width: 1.25))

        // Row 3: Bottom alpha row
        // Left: Shift Z X C V B
        keys.append(PhysicalKey(keyCode: 56, label: "⇧", x: 0, y: 3.25, width: 1.25))
        keys.append(PhysicalKey(keyCode: 6, label: "z", x: 1.25, y: 3.25))
        keys.append(PhysicalKey(keyCode: 7, label: "x", x: 2.25, y: 3))
        keys.append(PhysicalKey(keyCode: 8, label: "c", x: 3.25, y: 3))
        keys.append(PhysicalKey(keyCode: 9, label: "v", x: 4.25, y: 3))
        keys.append(PhysicalKey(keyCode: 11, label: "b", x: 5.25, y: 3))

        // Right: N M , . / Shift
        keys.append(PhysicalKey(keyCode: 45, label: "n", x: rightX(0), y: 3))
        keys.append(PhysicalKey(keyCode: 46, label: "m", x: rightX(1), y: 3))
        keys.append(PhysicalKey(keyCode: 43, label: ",", x: rightX(2), y: 3))
        keys.append(PhysicalKey(keyCode: 47, label: ".", x: rightX(3), y: 3))
        keys.append(PhysicalKey(keyCode: 44, label: "/", x: rightX(4), y: 3))
        keys.append(PhysicalKey(keyCode: 60, label: "⇧", x: rightX(5), y: 3.25, width: 1.25))

        // Row 4: Function row
        // Left: Fn ` Caps ← →
        keys.append(PhysicalKey(keyCode: 0xFFFF, label: "Fn", x: 0, y: 4.25, width: 1.25))
        keys.append(PhysicalKey(keyCode: 50, label: "`", x: 1.25, y: 4.25))
        keys.append(PhysicalKey(keyCode: 57, label: "⇪", x: 2.25, y: 4))
        keys.append(PhysicalKey(keyCode: 123, label: "◀", x: 3.25, y: 4))
        keys.append(PhysicalKey(keyCode: 124, label: "▶", x: 4.25, y: 4))

        // Right: Space ↑ ↓ [ ] Fn
        keys.append(PhysicalKey(keyCode: 49, label: "␣", x: rightX(1), y: 4))
        keys.append(PhysicalKey(keyCode: 126, label: "▲", x: rightX(2), y: 4))
        keys.append(PhysicalKey(keyCode: 125, label: "▼", x: rightX(3), y: 4))
        keys.append(PhysicalKey(keyCode: 33, label: "[", x: rightX(4), y: 4))
        keys.append(PhysicalKey(keyCode: 30, label: "]", x: rightX(5), y: 4.25))
        keys.append(PhysicalKey(keyCode: 0xFFFF, label: "Fn", x: rightX(6), y: 4.25, width: 1.25))

        // Thumb clusters
        // Left thumb cluster (rotated +15°)
        let leftThumbX = 5.75
        keys.append(PhysicalKey(keyCode: 59, label: "⌃", x: leftThumbX + 1, y: 3.25, rotation: 15)) // Ctrl
        keys.append(PhysicalKey(keyCode: 58, label: "⌥", x: leftThumbX + 2, y: 3.25, rotation: 15)) // Alt
        keys.append(PhysicalKey(keyCode: 115, label: "Home", x: leftThumbX, y: 4.25, height: 2, rotation: 15))
        keys.append(PhysicalKey(keyCode: 116, label: "PgUp", x: leftThumbX + 1, y: 4.25, height: 2, rotation: 15))
        keys.append(PhysicalKey(keyCode: 51, label: "⌫", x: leftThumbX + 2, y: 5.25, rotation: 15)) // Backspace
        keys.append(PhysicalKey(keyCode: 117, label: "Del", x: leftThumbX + 1, y: 5.25, rotation: 15))

        // Right thumb cluster (rotated -15°)
        let rightThumbX = rightX(-2.5)
        keys.append(PhysicalKey(keyCode: 55, label: "⌘", x: rightThumbX, y: 3.25, rotation: -15)) // Cmd
        keys.append(PhysicalKey(keyCode: 59, label: "⌃", x: rightThumbX + 1, y: 3.25, rotation: -15)) // Ctrl
        keys.append(PhysicalKey(keyCode: 36, label: "↩", x: rightThumbX, y: 5.25, rotation: -15)) // Enter
        keys.append(PhysicalKey(keyCode: 119, label: "End", x: rightThumbX + 1, y: 4.25, height: 2, rotation: -15))
        keys.append(PhysicalKey(keyCode: 121, label: "PgDn", x: rightThumbX + 2, y: 4.25, height: 2, rotation: -15))
        keys.append(PhysicalKey(keyCode: 49, label: "␣", x: rightThumbX + 1, y: 5.25, rotation: -15)) // Space

        // Calculate total dimensions
        let totalWidth = rightX(5) + 1.25 // Right edge of rightmost key (wide key at position 5)
        let totalHeight = 7.25 // Accounts for thumb cluster extension

        return PhysicalLayout(
            id: "kinesis-360",
            name: "Kinesis Advantage 360",
            keys: keys,
            totalWidth: totalWidth,
            totalHeight: totalHeight
        )
    }()
}
