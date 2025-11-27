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
        let keySpacing = 0.1 // Gap between keys
        let rowSpacing = 1.2 // Vertical spacing between row centers
        let standardKeyWidth = 1.0
        let standardKeyHeight = 1.0

        // Row 0: Function Keys (F1-F12)
        // F1=122, F2=120, F3=99, F4=118, F5=96, F6=97, F7=98, F8=100, F9=101, F10=109, F11=103, F12=111
        let functionKeys: [(UInt16, String)] = [
            (122, "🔅"), // F1 - Brightness Down
            (120, "🔆"), // F2 - Brightness Up
            (99, "F3"), // F3 - Mission Control
            (118, "F4"), // F4 - Spotlight
            (96, "F5"), // F5 - Keyboard Backlight Down
            (97, "F6"), // F6 - Keyboard Backlight Up
            (98, "⏮"), // F7 - Previous Track
            (100, "⏯"), // F8 - Play/Pause
            (101, "⏭"), // F9 - Next Track
            (109, "🔇"), // F10 - Mute
            (103, "🔉"), // F11 - Volume Down
            (111, "🔊") // F12 - Volume Up
        ]
        currentX = 0.0
        for (keyCode, label) in functionKeys {
            keys.append(PhysicalKey(
                keyCode: keyCode,
                label: label,
                x: currentX,
                y: 0.0,
                width: standardKeyWidth,
                height: standardKeyHeight
            ))
            currentX += standardKeyWidth + keySpacing
        }

        // Row 1: Number Row
        // `=50, 1=18, 2=19, 3=20, 4=21, 5=23, 6=22, 7=26, 8=28, 9=25, 0=29, -=27, ==24, delete=51
        let numberRow: [(UInt16, String, Double)] = [
            (50, "`", standardKeyWidth),
            (18, "1", standardKeyWidth),
            (19, "2", standardKeyWidth),
            (20, "3", standardKeyWidth),
            (21, "4", standardKeyWidth),
            (23, "5", standardKeyWidth),
            (22, "6", standardKeyWidth),
            (26, "7", standardKeyWidth),
            (28, "8", standardKeyWidth),
            (25, "9", standardKeyWidth),
            (29, "0", standardKeyWidth),
            (27, "-", standardKeyWidth),
            (24, "=", standardKeyWidth),
            (51, "⌫", 1.5) // Delete - wider
        ]
        currentX = 0.0
        for (keyCode, label, width) in numberRow {
            keys.append(PhysicalKey(
                keyCode: keyCode,
                label: label,
                x: currentX,
                y: rowSpacing,
                width: width,
                height: standardKeyHeight
            ))
            currentX += width + keySpacing
        }

        // Row 2: QWERTY Top
        // tab=48, q=12, w=13, e=14, r=15, t=17, y=16, u=32, i=34, o=31, p=35, [=33, ]=30, \=42
        let topRow: [(UInt16, String, Double)] = [
            (48, "⇥", 1.5), // Tab - wider
            (12, "q", standardKeyWidth),
            (13, "w", standardKeyWidth),
            (14, "e", standardKeyWidth),
            (15, "r", standardKeyWidth),
            (17, "t", standardKeyWidth),
            (16, "y", standardKeyWidth),
            (32, "u", standardKeyWidth),
            (34, "i", standardKeyWidth),
            (31, "o", standardKeyWidth),
            (35, "p", standardKeyWidth),
            (33, "[", standardKeyWidth),
            (30, "]", standardKeyWidth),
            (42, "\\", standardKeyWidth)
        ]
        currentX = 0.0
        for (keyCode, label, width) in topRow {
            keys.append(PhysicalKey(
                keyCode: keyCode,
                label: label,
                x: currentX,
                y: rowSpacing * 2,
                width: width,
                height: standardKeyHeight
            ))
            currentX += width + keySpacing
        }

        // Row 3: QWERTY Middle
        // caps=57, a=0, s=1, d=2, f=3, g=5, h=4, j=38, k=40, l=37, ;=41, '=39, return=36
        let middleRow: [(UInt16, String, Double)] = [
            (57, "⇪", 1.75), // Caps Lock - wider
            (0, "a", standardKeyWidth),
            (1, "s", standardKeyWidth),
            (2, "d", standardKeyWidth),
            (3, "f", standardKeyWidth),
            (5, "g", standardKeyWidth),
            (4, "h", standardKeyWidth),
            (38, "j", standardKeyWidth),
            (40, "k", standardKeyWidth),
            (37, "l", standardKeyWidth),
            (41, ";", standardKeyWidth),
            (39, "'", standardKeyWidth),
            (36, "↩", 2.25) // Return - extra wide
        ]
        currentX = 0.0
        for (keyCode, label, width) in middleRow {
            keys.append(PhysicalKey(
                keyCode: keyCode,
                label: label,
                x: currentX,
                y: rowSpacing * 3,
                width: width,
                height: standardKeyHeight
            ))
            currentX += width + keySpacing
        }

        // Row 4: QWERTY Bottom
        // shift=56 (left), z=6, x=7, c=8, v=9, b=11, n=45, m=46, ,=43, .=47, /=44, shift=60 (right)
        let bottomRow: [(UInt16, String, Double)] = [
            (56, "⇧", 2.25), // Left Shift - wider
            (6, "z", standardKeyWidth),
            (7, "x", standardKeyWidth),
            (8, "c", standardKeyWidth),
            (9, "v", standardKeyWidth),
            (11, "b", standardKeyWidth),
            (45, "n", standardKeyWidth),
            (46, "m", standardKeyWidth),
            (43, ",", standardKeyWidth),
            (47, ".", standardKeyWidth),
            (44, "/", standardKeyWidth),
            (60, "⇧", 2.75) // Right Shift - extra wide
        ]
        currentX = 0.0
        for (keyCode, label, width) in bottomRow {
            keys.append(PhysicalKey(
                keyCode: keyCode,
                label: label,
                x: currentX,
                y: rowSpacing * 4,
                width: width,
                height: standardKeyHeight
            ))
            currentX += width + keySpacing
        }

        // Row 5: Modifiers
        // control=59 (left), option=58 (left), command=55 (left), space=49, command=54 (right), option=61 (right), fn=63
        let modifierRow: [(UInt16, String, Double)] = [
            (59, "⌃", 1.25), // Left Control
            (58, "⌥", 1.25), // Left Option
            (55, "⌘", 1.25), // Left Command
            (49, "␣", 4.0), // Space - extra wide
            (54, "⌘", 1.25), // Right Command
            (61, "⌥", 1.25), // Right Option
            (63, "fn", 1.0) // Function
        ]
        currentX = 0.0
        for (keyCode, label, width) in modifierRow {
            keys.append(PhysicalKey(
                keyCode: keyCode,
                label: label,
                x: currentX,
                y: rowSpacing * 5,
                width: width,
                height: standardKeyHeight
            ))
            currentX += width + keySpacing
        }

        // Row 6: Arrow Cluster (positioned below right Shift)
        // Up=126, Down=125, Left=123, Right=124
        // Position: x starts around 11.0u (after right shift), y at rowSpacing * 6
        let arrowXStart = 11.0 // Approximate position below right shift
        let arrowY: Double = rowSpacing * 6

        // Top row: Up arrow
        keys.append(PhysicalKey(
            keyCode: 126,
            label: "↑",
            x: arrowXStart + standardKeyWidth + keySpacing,
            y: arrowY,
            width: standardKeyWidth,
            height: standardKeyHeight
        ))

        // Bottom row: Left, Down, Right
        let arrowKeys: [(UInt16, String)] = [
            (123, "←"), // Left
            (125, "↓"), // Down
            (124, "→") // Right
        ]
        currentX = arrowXStart
        for (keyCode, label) in arrowKeys {
            keys.append(PhysicalKey(
                keyCode: keyCode,
                label: label,
                x: currentX,
                y: arrowY + standardKeyHeight + keySpacing,
                width: standardKeyWidth,
                height: standardKeyHeight
            ))
            currentX += standardKeyWidth + keySpacing
        }

        // Calculate total dimensions
        let maxX = keys.map { $0.x + $0.width }.max() ?? 15.0
        let maxY = keys.map { $0.y + $0.height }.max() ?? 8.5

        return PhysicalLayout(
            name: "MacBook US",
            keys: keys,
            totalWidth: maxX,
            totalHeight: maxY
        )
    }()
}
