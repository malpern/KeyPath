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

        // Row 0: Function Keys (smaller, evenly spaced across keyboard width)
        let functionKeyWidth = (targetRightEdge - 11 * keySpacing) / 12
        let functionKeys: [(UInt16, String)] = [
            (122, "F1"), (120, "F2"), (99, "F3"), (118, "F4"),
            (96, "F5"), (97, "F6"), (98, "F7"), (100, "F8"),
            (101, "F9"), (109, "F10"), (103, "F11"), (111, "F12")
        ]
        currentX = 0.0
        for (keyCode, label) in functionKeys {
            keys.append(PhysicalKey(
                keyCode: keyCode,
                label: label,
                x: currentX,
                y: 0.0,
                width: functionKeyWidth,
                height: 0.6 // Shorter function keys
            ))
            currentX += functionKeyWidth + keySpacing
        }

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

        // Row 4: Bottom row - right shift shortened for arrow cluster
        let leftShiftWidth = 2.35
        let arrowClusterWidth = 3 * standardKeyWidth + 2 * keySpacing // 3 arrows + 2 gaps
        // Ensure right shift width is always positive (min 1.0) to prevent SwiftUI layout crashes
        let calculatedRightShift = targetRightEdge - (leftShiftWidth + keySpacing + 10 * (standardKeyWidth + keySpacing)) - arrowClusterWidth
        let rightShiftWidth = max(1.0, calculatedRightShift)
        let bottomRow: [(UInt16, String, Double)] = [
            (56, "⇧", leftShiftWidth), // Left Shift
            (6, "z", standardKeyWidth), (7, "x", standardKeyWidth),
            (8, "c", standardKeyWidth), (9, "v", standardKeyWidth),
            (11, "b", standardKeyWidth), (45, "n", standardKeyWidth),
            (46, "m", standardKeyWidth), (43, ",", standardKeyWidth),
            (47, ".", standardKeyWidth), (44, "/", standardKeyWidth),
            (60, "⇧", rightShiftWidth) // Right Shift - narrower for arrows
        ]
        currentX = 0.0
        for (keyCode, label, width) in bottomRow {
            keys.append(PhysicalKey(
                keyCode: keyCode, label: label, x: currentX,
                y: rowSpacing * 4, width: width, height: standardKeyHeight
            ))
            currentX += width + keySpacing
        }

        // Arrow cluster: positioned from the RIGHT EDGE like real MacBook
        // Arrow keys are half-height with a small gap between top and bottom rows
        let arrowKeyHeight = 0.45
        let arrowKeyGap = 0.1 // Gap between up arrow and down/left/right arrows
        let arrowKeyWidth = standardKeyWidth

        // Position arrow cluster at right edge of keyboard, aligned with modifier row
        let arrowXStart = targetRightEdge - arrowClusterWidth
        let row5Top = rowSpacing * 5 // Same Y as modifier row

        // Up arrow - center column, upper half of modifier row space
        keys.append(PhysicalKey(
            keyCode: 126, label: "↑",
            x: arrowXStart + arrowKeyWidth + keySpacing,
            y: row5Top,
            width: arrowKeyWidth, height: arrowKeyHeight
        ))

        // Left, Down, Right - lower half of modifier row space (with gap)
        let lowerArrowY = row5Top + arrowKeyHeight + arrowKeyGap
        keys.append(PhysicalKey(
            keyCode: 123, label: "←",
            x: arrowXStart, y: lowerArrowY,
            width: arrowKeyWidth, height: arrowKeyHeight
        ))
        keys.append(PhysicalKey(
            keyCode: 125, label: "↓",
            x: arrowXStart + arrowKeyWidth + keySpacing, y: lowerArrowY,
            width: arrowKeyWidth, height: arrowKeyHeight
        ))
        keys.append(PhysicalKey(
            keyCode: 124, label: "→",
            x: arrowXStart + 2 * (arrowKeyWidth + keySpacing), y: lowerArrowY,
            width: arrowKeyWidth, height: arrowKeyHeight
        ))

        // Row 5: Modifiers - sized to END where arrow cluster BEGINS
        // (row5Top already defined above for arrow cluster)
        // Real MacBook: fn narrow, control/option same width, command wider
        let fnWidth = 1.0
        let ctrlWidth = 1.1
        let optWidth = 1.1
        let cmdWidth = 1.35

        // Calculate spacebar to fill the middle, leaving room for right modifiers
        let leftModsWidth = fnWidth + keySpacing + ctrlWidth + keySpacing + optWidth + keySpacing + cmdWidth + keySpacing
        let rightModsWidth = cmdWidth + keySpacing + optWidth + keySpacing
        let availableForSpace = arrowXStart - leftModsWidth - rightModsWidth
        let spacebarWidth = availableForSpace

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

        return PhysicalLayout(
            name: "MacBook US",
            keys: keys,
            totalWidth: targetRightEdge,
            totalHeight: rowSpacing * 5 + standardKeyHeight
        )
    }()
}

