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

    init(
        id: UUID = UUID(),
        keyCode: UInt16,
        label: String,
        x: Double,
        y: Double,
        width: Double = 1.0,
        height: Double = 1.0
    ) {
        self.id = id
        self.keyCode = keyCode
        self.label = label
        self.x = x
        self.y = y
        self.width = width
        self.height = height
    }
}

/// Represents a complete physical keyboard layout
struct PhysicalLayout {
    let name: String
    let keys: [PhysicalKey]
    let totalWidth: Double // For aspect ratio calculation
    let totalHeight: Double

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
            name: "MacBook US",
            keys: keys,
            totalWidth: targetRightEdge,
            totalHeight: rowSpacing * 5 + standardKeyHeight
        )
    }()
}
