import Foundation

// MARK: - Layout Preferences Keys

/// UserDefaults/AppStorage keys for physical layout preferences
enum LayoutPreferences {
    /// Key for storing the selected physical keyboard layout ID
    static let layoutIdKey = "overlayLayoutId"

    /// Default layout ID when none is set
    static let defaultLayoutId = "macbook-us"

    /// Key for enabling QMK keyboard search (default: false)
    static let qmkSearchEnabledKey = "qmkSearchEnabled"
}

// MARK: - Layout Categories

/// Categories for organizing physical keyboard layouts in the UI
enum LayoutCategory: String, CaseIterable, Identifiable {
    case usStandard = "US Standard"
    case international = "International"
    case ergonomic = "Ergonomic / Split"
    case custom = "Custom"

    var id: String { rawValue }

    var displayName: String { rawValue }
}

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
    let rotationPivotX: Double? // Rotation pivot X (for QMK rotation)
    let rotationPivotY: Double? // Rotation pivot Y (for QMK rotation)

    // MARK: - Multi-Legend Support (JIS/ISO)

    /// Shifted character legend (top position on keycap)
    /// Example: "!" for the "1" key, "@" for "2", etc.
    let shiftLabel: String?

    /// Sub-label for alternate input (front/bottom-right on keycap)
    /// Example: Hiragana characters on JIS keyboards ("ぬ" on "1" key)
    let subLabel: String?

    /// Tertiary label for additional legends (front/bottom-left on keycap)
    /// Example: Additional symbols or alternate character sets
    let tertiaryLabel: String?

    /// Whether this key has multi-legend content requiring special rendering
    var hasMultipleLegends: Bool {
        shiftLabel != nil || subLabel != nil || tertiaryLabel != nil
    }

    init(
        id: UUID = UUID(),
        keyCode: UInt16,
        label: String,
        x: Double,
        y: Double,
        width: Double = 1.0,
        height: Double = 1.0,
        rotation: Double = 0.0,
        rotationPivotX: Double? = nil,
        rotationPivotY: Double? = nil,
        shiftLabel: String? = nil,
        subLabel: String? = nil,
        tertiaryLabel: String? = nil
    ) {
        self.id = id
        self.keyCode = keyCode
        self.label = label
        self.x = x
        self.y = y
        self.width = width
        self.height = height
        self.rotation = rotation
        self.rotationPivotX = rotationPivotX
        self.rotationPivotY = rotationPivotY
        self.shiftLabel = shiftLabel
        self.subLabel = subLabel
        self.tertiaryLabel = tertiaryLabel
    }

    /// Computed visual position after applying rotation transform
    /// For keys with rotation, the x/y in QMK format are pre-rotation coordinates
    /// that need to be rotated around the pivot point (rx, ry)
    var visualX: Double {
        guard rotation != 0, let rx = rotationPivotX, let ry = rotationPivotY else {
            return x
        }
        // Translate to pivot origin, rotate, translate back
        let relX = x + width / 2 - rx // Use key center
        let relY = y + height / 2 - ry
        let radians = rotation * .pi / 180
        let rotatedX = relX * cos(radians) - relY * sin(radians)
        return rotatedX + rx - width / 2
    }

    var visualY: Double {
        guard rotation != 0, let rx = rotationPivotX, let ry = rotationPivotY else {
            return y
        }
        // Translate to pivot origin, rotate, translate back
        let relX = x + width / 2 - rx // Use key center
        let relY = y + height / 2 - ry
        let radians = rotation * .pi / 180
        let rotatedY = relX * sin(radians) + relY * cos(radians)
        return rotatedY + ry - height / 2
    }
}

/// Represents a complete physical keyboard layout
struct PhysicalLayout: Identifiable {
    let id: String // Unique identifier: "macbook-us", "kinesis-360"
    let name: String // Display name: "MacBook US", "Kinesis Advantage 360"
    let keys: [PhysicalKey]
    let totalWidth: Double // For aspect ratio calculation
    let totalHeight: Double

    /// Initialize with explicit dimensions
    init(id: String, name: String, keys: [PhysicalKey], totalWidth: Double, totalHeight: Double) {
        self.id = id
        self.name = name
        self.keys = keys
        self.totalWidth = totalWidth
        self.totalHeight = totalHeight
    }

    /// Initialize with auto-computed dimensions from keys
    init(id: String, name: String, keys: [PhysicalKey]) {
        self.id = id
        self.name = name
        self.keys = keys

        // Compute dimensions from key positions (using visual positions for rotated keys)
        var maxX = 0.0
        var maxY = 0.0
        for key in keys {
            let keyRight = key.visualX + key.width
            let keyBottom = key.visualY + key.height
            maxX = max(maxX, keyRight)
            maxY = max(maxY, keyBottom)
        }
        totalWidth = maxX
        totalHeight = maxY
    }

    // MARK: - Layout Registry

    /// US Standard layouts (ANSI-based)
    static let usLayouts: [PhysicalLayout] = [
        macBookUS,
        ansi100Percent,
        ansi80Percent,
        ansi75Percent,
        ansi65Percent,
        ansi60Percent,
        ansi40Percent,
        hhkb
    ]

    /// International layouts (ISO, JIS, ABNT2, Korean)
    static let internationalLayouts: [PhysicalLayout] = [
        macBookISO,
        macBookJIS,
        macBookABNT2,
        macBookKorean
    ]

    /// Ergonomic and split keyboards
    static let ergonomicLayouts: [PhysicalLayout] = [
        kinesisAdvantage360,
        corne,
        sofle,
        ferrisSweep,
        cornix
    ]

    // MARK: - Custom Layouts Cache

    /// Cache for custom layouts to avoid blocking UI thread
    /// Thread-safe using a lock for concurrent access
    private static let cacheLock = NSLock()
    private nonisolated(unsafe) static var _cachedCustomLayouts: [PhysicalLayout]?
    private nonisolated(unsafe) static var _cacheTimestamp: Date?
    private static let cacheTTL: TimeInterval = 5.0 // 5 second cache TTL

    /// Custom imported layouts (loaded from UserDefaults)
    /// Note: Uses caching to avoid blocking UI thread. Call `invalidateCustomLayoutCache()` after importing.
    static var customLayouts: [PhysicalLayout] {
        cacheLock.lock()
        defer { cacheLock.unlock() }

        // Check cache freshness
        if let cached = _cachedCustomLayouts,
           let timestamp = _cacheTimestamp,
           Date().timeIntervalSince(timestamp) < cacheTTL {
            return cached
        }

        // Load custom layouts synchronously from storage
        let store = CustomLayoutStore.load()

        let layouts: [PhysicalLayout] = store.layouts.compactMap { storedLayout -> PhysicalLayout? in
            // Determine keycode mapping type from variant
            let keyMappingType: KeyMappingType = if let variant = storedLayout.layoutVariant?.lowercased(), variant.contains("iso") {
                .iso
            } else {
                .ansi
            }

            // Choose keycode mapping function
            let keyMapping: (Int, Int) -> (keyCode: UInt16, label: String)? = switch keyMappingType {
            case .ansi:
                ANSIPositionTable.keyMapping(row:col:)
            case .iso:
                ISOPositionTable.keyMapping(row:col:)
            }

            // Re-parse the layout from stored JSON
            guard let layout = QMKLayoutParser.parse(
                data: storedLayout.layoutJSON,
                keyMapping: keyMapping,
                idOverride: "custom-\(storedLayout.id)",
                nameOverride: storedLayout.name
            ) else {
                return nil
            }

            return layout
        }

        // Update cache
        _cachedCustomLayouts = layouts
        _cacheTimestamp = Date()

        return layouts
    }

    /// Invalidate the custom layouts cache (call after importing/deleting layouts)
    static func invalidateCustomLayoutCache() {
        cacheLock.lock()
        defer { cacheLock.unlock() }
        _cachedCustomLayouts = nil
        _cacheTimestamp = nil
    }

    /// Registry of all known layouts (US first, then International, then Ergonomic, then Custom)
    // swiftformat:disable:next redundantSelf
    static var all: [PhysicalLayout] {
        usLayouts + internationalLayouts + ergonomicLayouts + customLayouts
    }

    /// Get layouts grouped by category for UI display
    /// Order: US Standard (no header), Ergonomic, International, Custom
    static func layoutsByCategory() -> [(category: LayoutCategory, layouts: [PhysicalLayout])] {
        [
            (.usStandard, usLayouts),
            (.ergonomic, ergonomicLayouts),
            (.international, internationalLayouts),
            (.custom, customLayouts)
        ]
    }

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

        // Use auto-computed dimensions from actual key positions
        return PhysicalLayout(
            id: "macbook-us",
            name: "MacBook US",
            keys: keys
        )
    }()

    // MARK: - MacBook JIS (Japanese)

    /// MacBook JIS (Japanese Industrial Standard) keyboard layout
    /// Key differences from US: shorter spacebar, L-shaped enter, extra keys for Japanese input
    static let macBookJIS: PhysicalLayout = {
        var keys: [PhysicalKey] = []
        var currentX = 0.0
        let keySpacing = 0.08
        let rowSpacing = 1.1
        let standardKeyWidth = 1.0
        let standardKeyHeight = 1.0

        // Target right edge (same as US for consistency)
        let targetRightEdge = 13 * (standardKeyWidth + keySpacing) + 1.5

        // Row 0: ESC + Function Keys + Touch ID (same as US)
        let escWidth = 1.5
        let touchIdWidth = standardKeyWidth
        let functionRowAvailable = targetRightEdge - escWidth - keySpacing - touchIdWidth - keySpacing
        let functionKeyWidth = (functionRowAvailable - 11 * keySpacing) / 12

        keys.append(PhysicalKey(
            keyCode: 53,
            label: "esc",
            x: 0.0,
            y: 0.0,
            width: escWidth,
            height: standardKeyHeight
        ))
        currentX = escWidth + keySpacing

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

        keys.append(PhysicalKey(
            keyCode: 0xFFFF,
            label: "🔒",
            x: currentX,
            y: 0.0,
            width: touchIdWidth,
            height: standardKeyHeight
        ))

        // Row 1: Number Row - JIS with multi-legend support
        // Each key has: main label, shift label (top), sub label (hiragana)
        // Layout: 半角 1 2 3 4 5 6 7 8 9 0 - ^ ¥ ⌫
        let deleteWidthJIS = 1.0 // Narrower than US (was 1.5)
        let yenWidth = standardKeyWidth
        currentX = 0.0

        // JIS number row with proper multi-legend data
        // Format: (keyCode, mainLabel, width, shiftLabel, subLabel)
        let jisNumberRowKeys: [(UInt16, String, Double, String?, String?)] = [
            (50, "半角", standardKeyWidth, "全角", nil), // Hankaku/Zenkaku toggle
            (18, "1", standardKeyWidth, "!", "ぬ"),
            (19, "2", standardKeyWidth, "\"", "ふ"),
            (20, "3", standardKeyWidth, "#", "あ"),
            (21, "4", standardKeyWidth, "$", "う"),
            (23, "5", standardKeyWidth, "%", "え"),
            (22, "6", standardKeyWidth, "&", "お"),
            (26, "7", standardKeyWidth, "'", "や"),
            (28, "8", standardKeyWidth, "(", "ゆ"),
            (25, "9", standardKeyWidth, ")", "よ"),
            (29, "0", standardKeyWidth, nil, "わ"),
            (27, "-", standardKeyWidth, "=", "ほ"),
            (24, "^", standardKeyWidth, "~", "へ"),
            (93, "¥", yenWidth, "|", nil),
            (51, "⌫", deleteWidthJIS, nil, nil)
        ]
        for (keyCode, label, width, shiftLabel, subLabel) in jisNumberRowKeys {
            keys.append(PhysicalKey(
                keyCode: keyCode, label: label, x: currentX,
                y: rowSpacing, width: width, height: standardKeyHeight,
                shiftLabel: shiftLabel, subLabel: subLabel
            ))
            currentX += width + keySpacing
        }

        // Row 2: QWERTY row - JIS layout
        // QWERTY row must leave room for enter key on right (same width as home row enter)
        let tabWidth = 1.5
        let enterWidth = 1.9 // Wide enter (bottom of L-shape) - defined early for both rows

        // QWERTY row: tab + 12 alpha keys + enter width (rows must align)
        let qwertyAlphaWidth = (targetRightEdge - tabWidth - enterWidth - 13 * keySpacing) / 12

        keys.append(PhysicalKey(
            keyCode: 48, label: "⇥", x: 0.0,
            y: rowSpacing * 2, width: tabWidth, height: standardKeyHeight
        ))
        currentX = tabWidth + keySpacing

        // JIS QWERTY row with hiragana
        let jisTopRowKeys: [(UInt16, String, String?, String?)] = [
            (12, "q", nil, "た"),
            (13, "w", nil, "て"),
            (14, "e", nil, "い"),
            (15, "r", nil, "す"),
            (17, "t", nil, "か"),
            (16, "y", nil, "ん"),
            (32, "u", nil, "な"),
            (34, "i", nil, "に"),
            (31, "o", nil, "ら"),
            (35, "p", nil, "せ"),
            (33, "@", "`", "゛"),
            (30, "[", "{", "゜")
        ]
        for (keyCode, label, shiftLabel, subLabel) in jisTopRowKeys {
            keys.append(PhysicalKey(
                keyCode: keyCode, label: label, x: currentX,
                y: rowSpacing * 2, width: qwertyAlphaWidth, height: standardKeyHeight,
                shiftLabel: shiftLabel, subLabel: subLabel
            ))
            currentX += qwertyAlphaWidth + keySpacing
        }

        // Row 3: Home row - JIS has CONTROL on left, L-shaped ENTER on right
        // The enter key is wider here (bottom of L) and extends UP into QWERTY row
        let controlWidth = 1.8

        // Home row: control + 11 alpha keys + enter (enterWidth defined above)
        let homeRowAlphaWidth = (targetRightEdge - controlWidth - enterWidth - 12 * keySpacing) / 11

        // JIS home row: Control + 11 alpha keys
        let jisHomeRowKeys: [(UInt16, String, Double, String?, String?)] = [
            (59, "⌃", controlWidth, nil, nil), // Control key (NOT caps lock!)
            (0, "a", homeRowAlphaWidth, nil, "ち"),
            (1, "s", homeRowAlphaWidth, nil, "と"),
            (2, "d", homeRowAlphaWidth, nil, "し"),
            (3, "f", homeRowAlphaWidth, nil, "は"),
            (5, "g", homeRowAlphaWidth, nil, "き"),
            (4, "h", homeRowAlphaWidth, nil, "く"),
            (38, "j", homeRowAlphaWidth, nil, "ま"),
            (40, "k", homeRowAlphaWidth, nil, "の"),
            (37, "l", homeRowAlphaWidth, nil, "り"),
            (41, ";", homeRowAlphaWidth, "+", "れ"),
            (39, ":", homeRowAlphaWidth, "*", "け"),
            (42, "]", homeRowAlphaWidth, "}", "む")
        ]
        currentX = 0.0
        for (keyCode, label, width, shiftLabel, subLabel) in jisHomeRowKeys {
            keys.append(PhysicalKey(
                keyCode: keyCode, label: label, x: currentX,
                y: rowSpacing * 3, width: width, height: standardKeyHeight,
                shiftLabel: shiftLabel, subLabel: subLabel
            ))
            currentX += width + keySpacing
        }

        // L-shaped Enter key - positioned at home row, extends UP into QWERTY row
        // This creates the visual appearance of an L-shape (wider at bottom)
        keys.append(PhysicalKey(
            keyCode: 36, label: "↩", x: currentX,
            y: rowSpacing * 2, // Start at QWERTY row level
            width: enterWidth,
            height: standardKeyHeight * 2 + keySpacing // Span 2 rows
        ))

        // Row 4: Bottom row - shift, Z-/ keys, _ (ro), shift
        let leftShiftWidth = 2.1
        let rightShiftWidthJIS = 2.1
        let underscoreWidth = standardKeyWidth
        // Calculate alpha width: total - shifts - underscore - spacing
        let bottomAlphaWidth = (targetRightEdge - leftShiftWidth - rightShiftWidthJIS - underscoreWidth - 12 * keySpacing) / 10

        let jisBottomRowKeys: [(UInt16, String, Double, String?, String?)] = [
            (56, "⇧", leftShiftWidth, nil, nil),
            (6, "z", bottomAlphaWidth, nil, "つ"),
            (7, "x", bottomAlphaWidth, nil, "さ"),
            (8, "c", bottomAlphaWidth, nil, "そ"),
            (9, "v", bottomAlphaWidth, nil, "ひ"),
            (11, "b", bottomAlphaWidth, nil, "こ"),
            (45, "n", bottomAlphaWidth, nil, "み"),
            (46, "m", bottomAlphaWidth, nil, "も"),
            (43, ",", bottomAlphaWidth, "<", "ね"),
            (47, ".", bottomAlphaWidth, ">", "る"),
            (44, "/", bottomAlphaWidth, "?", "め"),
            (94, "_", underscoreWidth, nil, "ろ"),
            (60, "⇧", rightShiftWidthJIS, nil, nil)
        ]
        currentX = 0.0
        for (keyCode, label, width, shiftLabel, subLabel) in jisBottomRowKeys {
            keys.append(PhysicalKey(
                keyCode: keyCode, label: label, x: currentX,
                y: rowSpacing * 4, width: width, height: standardKeyHeight,
                shiftLabel: shiftLabel, subLabel: subLabel
            ))
            currentX += width + keySpacing
        }

        // Row 5: Modifier row - JIS has caps, option, command, 英数, space, かな, command, fn, arrows
        let row5Top = rowSpacing * 5
        let capsWidth = standardKeyWidth // Caps lock moved here on JIS
        let optWidth = standardKeyWidth
        let cmdWidth = 1.2
        let eisuWidth = 1.3 // 英数 key
        let kanaWidth = 1.3 // かな key
        let fnWidth = standardKeyWidth

        // Arrow cluster (same as US)
        let arrowKeyHeight = 0.45
        let arrowKeyGap = 0.1
        let arrowKeyWidth = 0.9
        let arrowKeySpacing = 0.04
        let arrowRightMargin = 0.15
        let arrowClusterWidth = 3 * arrowKeyWidth + 2 * arrowKeySpacing + arrowRightMargin

        // Calculate spacebar: JIS spacebar is shorter due to 英数 and かな keys
        // JIS modifier row: caps, option, command, 英数, space, かな, command, fn, arrows
        // Note: Control moved to home row on JIS, caps moved here
        let leftModsWidth = capsWidth + keySpacing + optWidth + keySpacing + cmdWidth + keySpacing + eisuWidth + keySpacing
        let rightModsWidth = kanaWidth + keySpacing + cmdWidth + keySpacing + fnWidth + keySpacing
        let spacebarWidthJIS = targetRightEdge - leftModsWidth - rightModsWidth - arrowClusterWidth

        let modifierRowJIS: [(UInt16, String, Double)] = [
            (57, "⇪", capsWidth), // Caps lock moved here on JIS
            (58, "⌥", optWidth),
            (55, "⌘", cmdWidth),
            (102, "英数", eisuWidth), // Eisuu key (JIS specific)
            (49, " ", spacebarWidthJIS),
            (104, "かな", kanaWidth), // Kana key (JIS specific)
            (54, "⌘", cmdWidth),
            (63, "fn", fnWidth) // fn key on right side for JIS
        ]
        currentX = 0.0
        for (keyCode, label, width) in modifierRowJIS {
            keys.append(PhysicalKey(
                keyCode: keyCode, label: label, x: currentX,
                y: row5Top, width: width, height: standardKeyHeight
            ))
            currentX += width + keySpacing
        }

        // Arrow cluster (same positioning logic as US)
        let arrowXStart = currentX

        keys.append(PhysicalKey(
            keyCode: 126, label: "▲",
            x: arrowXStart + arrowKeyWidth + arrowKeySpacing,
            y: row5Top,
            width: arrowKeyWidth, height: arrowKeyHeight
        ))

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

        // Use auto-computed dimensions from actual key positions
        return PhysicalLayout(
            id: "macbook-jis",
            name: "MacBook JIS",
            keys: keys
        )
    }()

    // MARK: - MacBook ISO

    /// MacBook ISO (International) keyboard layout
    /// Key differences from US: extra IntlBackslash key between Left Shift and Z,
    /// shorter left shift to accommodate the extra key
    static let macBookISO: PhysicalLayout = {
        var keys: [PhysicalKey] = []
        var currentX = 0.0
        let keySpacing = 0.08 // Gap between keys (tighter like real MacBook)
        let rowSpacing = 1.1 // Vertical spacing between row centers
        let standardKeyWidth = 1.0
        let standardKeyHeight = 1.0

        // Target right edge (from number row: 13 standard + 1.5 delete + 13 gaps)
        let targetRightEdge = 13 * (standardKeyWidth + keySpacing) + 1.5

        // Row 0: ESC + Function Keys + Touch ID (same as US)
        let escWidth = 1.5
        let touchIdWidth = standardKeyWidth
        let functionRowAvailable = targetRightEdge - escWidth - keySpacing - touchIdWidth - keySpacing
        let functionKeyWidth = (functionRowAvailable - 11 * keySpacing) / 12

        keys.append(PhysicalKey(
            keyCode: 53,
            label: "esc",
            x: 0.0,
            y: 0.0,
            width: escWidth,
            height: standardKeyHeight
        ))
        currentX = escWidth + keySpacing

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

        keys.append(PhysicalKey(
            keyCode: 0xFFFF,
            label: "🔒",
            x: currentX,
            y: 0.0,
            width: touchIdWidth,
            height: standardKeyHeight
        ))

        // Row 1: Number Row (same as US)
        let numberRow: [(UInt16, String, Double)] = [
            (50, "`", standardKeyWidth),
            (18, "1", standardKeyWidth), (19, "2", standardKeyWidth),
            (20, "3", standardKeyWidth), (21, "4", standardKeyWidth),
            (23, "5", standardKeyWidth), (22, "6", standardKeyWidth),
            (26, "7", standardKeyWidth), (28, "8", standardKeyWidth),
            (25, "9", standardKeyWidth), (29, "0", standardKeyWidth),
            (27, "-", standardKeyWidth), (24, "=", standardKeyWidth),
            (51, "⌫", 1.5)
        ]
        currentX = 0.0
        for (keyCode, label, width) in numberRow {
            keys.append(PhysicalKey(
                keyCode: keyCode, label: label, x: currentX,
                y: rowSpacing, width: width, height: standardKeyHeight
            ))
            currentX += width + keySpacing
        }

        // Row 2: QWERTY row (same as US)
        let backslashWidth = targetRightEdge - (1.5 + keySpacing + 12 * (standardKeyWidth + keySpacing))
        let topRow: [(UInt16, String, Double)] = [
            (48, "⇥", 1.5),
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

        // Row 3: Home row (same as US)
        let capsWidth = 1.8
        let returnWidth = targetRightEdge - (capsWidth + keySpacing + 11 * (standardKeyWidth + keySpacing))
        let middleRow: [(UInt16, String, Double)] = [
            (57, "⇪", capsWidth),
            (0, "a", standardKeyWidth), (1, "s", standardKeyWidth),
            (2, "d", standardKeyWidth), (3, "f", standardKeyWidth),
            (5, "g", standardKeyWidth), (4, "h", standardKeyWidth),
            (38, "j", standardKeyWidth), (40, "k", standardKeyWidth),
            (37, "l", standardKeyWidth), (41, ";", standardKeyWidth),
            (39, "'", standardKeyWidth),
            (36, "↩", returnWidth)
        ]
        currentX = 0.0
        for (keyCode, label, width) in middleRow {
            keys.append(PhysicalKey(
                keyCode: keyCode, label: label, x: currentX,
                y: rowSpacing * 3, width: width, height: standardKeyHeight
            ))
            currentX += width + keySpacing
        }

        // Row 4: Bottom row - ISO has shorter left shift and extra IntlBackslash key
        // US: leftShift(2.35) + 10keys + rightShift(2.35) + 11gaps = 15.58
        // ISO: leftShift(1.27) + intlBackslash(1.0) + 10keys + rightShift(2.35) + 12gaps = 15.66
        // Adjust right shift to match US row width: 2.35 - 0.08 = 2.27
        let leftShiftWidthISO = 1.27 // Shorter than US (2.35) to make room for IntlBackslash
        let rightShiftWidthISO = 2.27 // Slightly narrower to compensate for extra gap
        let bottomRowISO: [(UInt16, String, Double)] = [
            (56, "⇧", leftShiftWidthISO),
            (10, "§", standardKeyWidth), // IntlBackslash key (§ on UK, < on German, etc.)
            (6, "z", standardKeyWidth), (7, "x", standardKeyWidth),
            (8, "c", standardKeyWidth), (9, "v", standardKeyWidth),
            (11, "b", standardKeyWidth), (45, "n", standardKeyWidth),
            (46, "m", standardKeyWidth), (43, ",", standardKeyWidth),
            (47, ".", standardKeyWidth), (44, "/", standardKeyWidth),
            (60, "⇧", rightShiftWidthISO)
        ]
        currentX = 0.0
        for (keyCode, label, width) in bottomRowISO {
            keys.append(PhysicalKey(
                keyCode: keyCode, label: label, x: currentX,
                y: rowSpacing * 4, width: width, height: standardKeyHeight
            ))
            currentX += width + keySpacing
        }

        // Row 5: Modifiers (same as US)
        let row5Top = rowSpacing * 5
        let fnWidth = standardKeyWidth
        let ctrlWidth = standardKeyWidth
        let optWidth = standardKeyWidth
        let cmdWidth = 1.35

        let arrowKeyHeight = 0.45
        let arrowKeyGap = 0.1
        let arrowKeyWidth = 0.9
        let arrowKeySpacing = 0.04
        let arrowRightMargin = 0.15
        let arrowClusterWidth = 3 * arrowKeyWidth + 2 * arrowKeySpacing + arrowRightMargin

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

        // Arrow cluster (same as US)
        let arrowXStart = currentX

        keys.append(PhysicalKey(
            keyCode: 126, label: "▲",
            x: arrowXStart + arrowKeyWidth + arrowKeySpacing,
            y: row5Top,
            width: arrowKeyWidth, height: arrowKeyHeight
        ))

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
            id: "macbook-iso",
            name: "MacBook ISO",
            keys: keys
        )
    }()

    // MARK: - MacBook ABNT2 (Brazilian)

    /// MacBook ABNT2 (Brazilian Portuguese) keyboard layout
    /// Key differences from ISO:
    /// - Extra key between right shift and slash (the "/" key moves there)
    /// - Shorter right shift to accommodate the extra key
    /// - Extra key on number row (cedilla/acute accent area)
    static let macBookABNT2: PhysicalLayout = {
        var keys: [PhysicalKey] = []
        var currentX = 0.0
        let keySpacing = 0.08
        let rowSpacing = 1.1
        let standardKeyWidth = 1.0
        let standardKeyHeight = 1.0

        let targetRightEdge = 13 * (standardKeyWidth + keySpacing) + 1.5

        // Row 0: ESC + Function Keys + Touch ID (same as US/ISO)
        let escWidth = 1.5
        let touchIdWidth = standardKeyWidth
        let functionRowAvailable = targetRightEdge - escWidth - keySpacing - touchIdWidth - keySpacing
        let functionKeyWidth = (functionRowAvailable - 11 * keySpacing) / 12

        keys.append(PhysicalKey(
            keyCode: 53,
            label: "esc",
            x: 0.0,
            y: 0.0,
            width: escWidth,
            height: standardKeyHeight
        ))
        currentX = escWidth + keySpacing

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

        keys.append(PhysicalKey(
            keyCode: 0xFFFF,
            label: "🔒",
            x: currentX,
            y: 0.0,
            width: touchIdWidth,
            height: standardKeyHeight
        ))

        // Row 1: Number Row (same as US/ISO)
        let numberRow: [(UInt16, String, Double)] = [
            (50, "'", standardKeyWidth), // Apostrophe position on ABNT2
            (18, "1", standardKeyWidth), (19, "2", standardKeyWidth),
            (20, "3", standardKeyWidth), (21, "4", standardKeyWidth),
            (23, "5", standardKeyWidth), (22, "6", standardKeyWidth),
            (26, "7", standardKeyWidth), (28, "8", standardKeyWidth),
            (25, "9", standardKeyWidth), (29, "0", standardKeyWidth),
            (27, "-", standardKeyWidth), (24, "=", standardKeyWidth),
            (51, "⌫", 1.5)
        ]
        currentX = 0.0
        for (keyCode, label, width) in numberRow {
            keys.append(PhysicalKey(
                keyCode: keyCode, label: label, x: currentX,
                y: rowSpacing, width: width, height: standardKeyHeight
            ))
            currentX += width + keySpacing
        }

        // Row 2: QWERTY row (same as US/ISO)
        let backslashWidth = targetRightEdge - (1.5 + keySpacing + 12 * (standardKeyWidth + keySpacing))
        let topRow: [(UInt16, String, Double)] = [
            (48, "⇥", 1.5),
            (12, "q", standardKeyWidth), (13, "w", standardKeyWidth),
            (14, "e", standardKeyWidth), (15, "r", standardKeyWidth),
            (17, "t", standardKeyWidth), (16, "y", standardKeyWidth),
            (32, "u", standardKeyWidth), (34, "i", standardKeyWidth),
            (31, "o", standardKeyWidth), (35, "p", standardKeyWidth),
            (33, "´", standardKeyWidth), (30, "[", standardKeyWidth), // Acute accent on ABNT2
            (42, "]", backslashWidth)
        ]
        currentX = 0.0
        for (keyCode, label, width) in topRow {
            keys.append(PhysicalKey(
                keyCode: keyCode, label: label, x: currentX,
                y: rowSpacing * 2, width: width, height: standardKeyHeight
            ))
            currentX += width + keySpacing
        }

        // Row 3: Home row (same as US/ISO)
        let capsWidth = 1.8
        let returnWidth = targetRightEdge - (capsWidth + keySpacing + 11 * (standardKeyWidth + keySpacing))
        let middleRow: [(UInt16, String, Double)] = [
            (57, "⇪", capsWidth),
            (0, "a", standardKeyWidth), (1, "s", standardKeyWidth),
            (2, "d", standardKeyWidth), (3, "f", standardKeyWidth),
            (5, "g", standardKeyWidth), (4, "h", standardKeyWidth),
            (38, "j", standardKeyWidth), (40, "k", standardKeyWidth),
            (37, "l", standardKeyWidth), (41, "ç", standardKeyWidth), // Cedilla on ABNT2
            (39, "~", standardKeyWidth),
            (36, "↩", returnWidth)
        ]
        currentX = 0.0
        for (keyCode, label, width) in middleRow {
            keys.append(PhysicalKey(
                keyCode: keyCode, label: label, x: currentX,
                y: rowSpacing * 3, width: width, height: standardKeyHeight
            ))
            currentX += width + keySpacing
        }

        // Row 4: Bottom row - ABNT2 has extra key between slash and right shift
        // Like ISO but with extra key at right side
        let leftShiftWidthABNT2 = 1.27 // Same as ISO
        let rightShiftWidthABNT2 = 1.27 // Shorter than ISO to fit extra key
        let bottomRowABNT2: [(UInt16, String, Double)] = [
            (56, "⇧", leftShiftWidthABNT2),
            (10, "\\", standardKeyWidth), // Backslash key (like ISO IntlBackslash)
            (6, "z", standardKeyWidth), (7, "x", standardKeyWidth),
            (8, "c", standardKeyWidth), (9, "v", standardKeyWidth),
            (11, "b", standardKeyWidth), (45, "n", standardKeyWidth),
            (46, "m", standardKeyWidth), (43, ",", standardKeyWidth),
            (47, ".", standardKeyWidth), (44, ";", standardKeyWidth), // Semicolon on ABNT2
            (94, "/", standardKeyWidth), // Extra ABNT2 key (slash)
            (60, "⇧", rightShiftWidthABNT2)
        ]
        currentX = 0.0
        for (keyCode, label, width) in bottomRowABNT2 {
            keys.append(PhysicalKey(
                keyCode: keyCode, label: label, x: currentX,
                y: rowSpacing * 4, width: width, height: standardKeyHeight
            ))
            currentX += width + keySpacing
        }

        // Row 5: Modifiers (same as US/ISO)
        let row5Top = rowSpacing * 5
        let fnWidth = standardKeyWidth
        let ctrlWidth = standardKeyWidth
        let optWidth = standardKeyWidth
        let cmdWidth = 1.35

        let arrowKeyHeight = 0.45
        let arrowKeyGap = 0.1
        let arrowKeyWidth = 0.9
        let arrowKeySpacing = 0.04
        let arrowRightMargin = 0.15
        let arrowClusterWidth = 3 * arrowKeyWidth + 2 * arrowKeySpacing + arrowRightMargin

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

        // Arrow cluster (same as US/ISO)
        let arrowXStart = currentX

        keys.append(PhysicalKey(
            keyCode: 126, label: "▲",
            x: arrowXStart + arrowKeyWidth + arrowKeySpacing,
            y: row5Top,
            width: arrowKeyWidth, height: arrowKeyHeight
        ))

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
            id: "macbook-abnt2",
            name: "MacBook ABNT2",
            keys: keys
        )
    }()

    // MARK: - MacBook Korean (KS)

    /// MacBook Korean Standard keyboard layout
    /// Similar to ANSI but with Han/Eng toggle key and different spacebar arrangement
    static let macBookKorean: PhysicalLayout = {
        var keys: [PhysicalKey] = []
        var currentX = 0.0
        let keySpacing = 0.08
        let rowSpacing = 1.1
        let standardKeyWidth = 1.0
        let standardKeyHeight = 1.0

        let targetRightEdge = 13 * (standardKeyWidth + keySpacing) + 1.5

        // Row 0: ESC + Function Keys + Touch ID (same as US)
        let escWidth = 1.5
        let touchIdWidth = standardKeyWidth
        let functionRowAvailable = targetRightEdge - escWidth - keySpacing - touchIdWidth - keySpacing
        let functionKeyWidth = (functionRowAvailable - 11 * keySpacing) / 12

        keys.append(PhysicalKey(
            keyCode: 53,
            label: "esc",
            x: 0.0,
            y: 0.0,
            width: escWidth,
            height: standardKeyHeight
        ))
        currentX = escWidth + keySpacing

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

        keys.append(PhysicalKey(
            keyCode: 0xFFFF,
            label: "🔒",
            x: currentX,
            y: 0.0,
            width: touchIdWidth,
            height: standardKeyHeight
        ))

        // Row 1: Number Row (same as US)
        let numberRow: [(UInt16, String, Double)] = [
            (50, "`", standardKeyWidth),
            (18, "1", standardKeyWidth), (19, "2", standardKeyWidth),
            (20, "3", standardKeyWidth), (21, "4", standardKeyWidth),
            (23, "5", standardKeyWidth), (22, "6", standardKeyWidth),
            (26, "7", standardKeyWidth), (28, "8", standardKeyWidth),
            (25, "9", standardKeyWidth), (29, "0", standardKeyWidth),
            (27, "-", standardKeyWidth), (24, "=", standardKeyWidth),
            (51, "⌫", 1.5)
        ]
        currentX = 0.0
        for (keyCode, label, width) in numberRow {
            keys.append(PhysicalKey(
                keyCode: keyCode, label: label, x: currentX,
                y: rowSpacing, width: width, height: standardKeyHeight
            ))
            currentX += width + keySpacing
        }

        // Row 2: QWERTY row (same as US)
        let backslashWidth = targetRightEdge - (1.5 + keySpacing + 12 * (standardKeyWidth + keySpacing))
        let topRow: [(UInt16, String, Double)] = [
            (48, "⇥", 1.5),
            (12, "q", standardKeyWidth), (13, "w", standardKeyWidth),
            (14, "e", standardKeyWidth), (15, "r", standardKeyWidth),
            (17, "t", standardKeyWidth), (16, "y", standardKeyWidth),
            (32, "u", standardKeyWidth), (34, "i", standardKeyWidth),
            (31, "o", standardKeyWidth), (35, "p", standardKeyWidth),
            (33, "[", standardKeyWidth), (30, "]", standardKeyWidth),
            (42, "₩", backslashWidth) // Won symbol on Korean keyboards
        ]
        currentX = 0.0
        for (keyCode, label, width) in topRow {
            keys.append(PhysicalKey(
                keyCode: keyCode, label: label, x: currentX,
                y: rowSpacing * 2, width: width, height: standardKeyHeight
            ))
            currentX += width + keySpacing
        }

        // Row 3: Home row (same as US)
        let capsWidth = 1.8
        let returnWidth = targetRightEdge - (capsWidth + keySpacing + 11 * (standardKeyWidth + keySpacing))
        let middleRow: [(UInt16, String, Double)] = [
            (57, "⇪", capsWidth),
            (0, "a", standardKeyWidth), (1, "s", standardKeyWidth),
            (2, "d", standardKeyWidth), (3, "f", standardKeyWidth),
            (5, "g", standardKeyWidth), (4, "h", standardKeyWidth),
            (38, "j", standardKeyWidth), (40, "k", standardKeyWidth),
            (37, "l", standardKeyWidth), (41, ";", standardKeyWidth),
            (39, "'", standardKeyWidth),
            (36, "↩", returnWidth)
        ]
        currentX = 0.0
        for (keyCode, label, width) in middleRow {
            keys.append(PhysicalKey(
                keyCode: keyCode, label: label, x: currentX,
                y: rowSpacing * 3, width: width, height: standardKeyHeight
            ))
            currentX += width + keySpacing
        }

        // Row 4: Bottom row (same as US)
        let shiftWidth = 2.35
        let bottomRow: [(UInt16, String, Double)] = [
            (56, "⇧", shiftWidth),
            (6, "z", standardKeyWidth), (7, "x", standardKeyWidth),
            (8, "c", standardKeyWidth), (9, "v", standardKeyWidth),
            (11, "b", standardKeyWidth), (45, "n", standardKeyWidth),
            (46, "m", standardKeyWidth), (43, ",", standardKeyWidth),
            (47, ".", standardKeyWidth), (44, "/", standardKeyWidth),
            (60, "⇧", shiftWidth)
        ]
        currentX = 0.0
        for (keyCode, label, width) in bottomRow {
            keys.append(PhysicalKey(
                keyCode: keyCode, label: label, x: currentX,
                y: rowSpacing * 4, width: width, height: standardKeyHeight
            ))
            currentX += width + keySpacing
        }

        // Row 5: Modifiers - Korean has Han/Eng key instead of some modifiers
        // Spacebar is slightly shorter to accommodate language toggle keys
        let row5Top = rowSpacing * 5
        let fnWidth = standardKeyWidth
        let ctrlWidth = standardKeyWidth
        let optWidth = standardKeyWidth
        let cmdWidth = 1.25 // Slightly narrower
        let langKeyWidth = 0.9 // Korean language toggle keys

        let arrowKeyHeight = 0.45
        let arrowKeyGap = 0.1
        let arrowKeyWidth = 0.9
        let arrowKeySpacing = 0.04
        let arrowRightMargin = 0.15
        let arrowClusterWidth = 3 * arrowKeyWidth + 2 * arrowKeySpacing + arrowRightMargin

        let leftModsWidth = fnWidth + keySpacing + ctrlWidth + keySpacing + optWidth + keySpacing + cmdWidth + keySpacing + langKeyWidth + keySpacing
        let rightModsWidth = langKeyWidth + keySpacing + cmdWidth + keySpacing + optWidth + keySpacing
        let spacebarWidth = targetRightEdge - leftModsWidth - rightModsWidth - arrowClusterWidth

        // Korean layout: fn, ctrl, opt, cmd, 한자, [space], 한/영, cmd, opt
        currentX = 0.0

        keys.append(PhysicalKey(keyCode: 63, label: "fn", x: currentX, y: row5Top, width: fnWidth, height: standardKeyHeight))
        currentX += fnWidth + keySpacing

        keys.append(PhysicalKey(keyCode: 59, label: "⌃", x: currentX, y: row5Top, width: ctrlWidth, height: standardKeyHeight))
        currentX += ctrlWidth + keySpacing

        keys.append(PhysicalKey(keyCode: 58, label: "⌥", x: currentX, y: row5Top, width: optWidth, height: standardKeyHeight))
        currentX += optWidth + keySpacing

        keys.append(PhysicalKey(keyCode: 55, label: "⌘", x: currentX, y: row5Top, width: cmdWidth, height: standardKeyHeight))
        currentX += cmdWidth + keySpacing

        // Hanja key (keycode 104 on some systems, using placeholder)
        keys.append(PhysicalKey(keyCode: 104, label: "한자", x: currentX, y: row5Top, width: langKeyWidth, height: standardKeyHeight))
        currentX += langKeyWidth + keySpacing

        keys.append(PhysicalKey(keyCode: 49, label: " ", x: currentX, y: row5Top, width: spacebarWidth, height: standardKeyHeight))
        currentX += spacebarWidth + keySpacing

        // Han/Eng toggle key (keycode 102 on some systems, using placeholder)
        keys.append(PhysicalKey(keyCode: 102, label: "한/영", x: currentX, y: row5Top, width: langKeyWidth, height: standardKeyHeight))
        currentX += langKeyWidth + keySpacing

        keys.append(PhysicalKey(keyCode: 54, label: "⌘", x: currentX, y: row5Top, width: cmdWidth, height: standardKeyHeight))
        currentX += cmdWidth + keySpacing

        keys.append(PhysicalKey(keyCode: 61, label: "⌥", x: currentX, y: row5Top, width: optWidth, height: standardKeyHeight))
        currentX += optWidth + keySpacing

        // Arrow cluster (same as US)
        let arrowXStart = currentX

        keys.append(PhysicalKey(
            keyCode: 126, label: "▲",
            x: arrowXStart + arrowKeyWidth + arrowKeySpacing,
            y: row5Top,
            width: arrowKeyWidth, height: arrowKeyHeight
        ))

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
            id: "macbook-korean",
            name: "MacBook Korean",
            keys: keys
        )
    }()

    // MARK: - Kinesis Advantage 360

    /// Kinesis Advantage 360 split ergonomic keyboard layout
    /// Physical layout parsed from: Resources/Keyboards/adv360pro.json
    /// Key mappings (keyCode + label) are embedded in JSON (Tier 1 keyboard)
    /// Optional Swift overrides available via Kinesis360KeyMap.swift for custom behavior
    static let kinesisAdvantage360: PhysicalLayout = {
        // Try to load from bundled JSON first
        // JSON contains keyCode and label for all keys (Tier 1 format)
        // Fallback to Kinesis360KeyMap.keyMapping for any keys missing from JSON
        if let layout = QMKLayoutParser.loadFromBundle(
            filename: "adv360pro",
            keyMapping: Kinesis360KeyMap.keyMapping, // Optional override for Tier 1 customization
            idOverride: "kinesis-360",
            nameOverride: "Kinesis Advantage 360"
        ) {
            return layout
        }

        // Fallback to a minimal layout if JSON parsing fails
        // This should never happen in production, but provides graceful degradation
        print("PhysicalLayout: Failed to load Kinesis 360 from JSON, using fallback")
        return PhysicalLayout(
            id: "kinesis-360",
            name: "Kinesis Advantage 360",
            keys: [],
            totalWidth: 18.75,
            totalHeight: 7.25
        )
    }()

    // MARK: - Standard ANSI Layouts (Tier 2)

    /// 40% ANSI keyboard layout
    /// Physical layout from JSON, key mappings auto-generated from ANSI position table
    static let ansi40Percent: PhysicalLayout = {
        if let layout = QMKLayoutParser.loadFromBundle(
            filename: "ansi-40",
            keyMapping: ANSIPositionTable.keyMapping,
            idOverride: "ansi-40",
            nameOverride: "40% ANSI"
        ) {
            return layout
        }
        print("PhysicalLayout: Failed to load 40% ANSI from JSON, using fallback")
        return PhysicalLayout(
            id: "ansi-40",
            name: "40% ANSI",
            keys: [],
            totalWidth: 15.0,
            totalHeight: 5.0
        )
    }()

    /// 60% ANSI keyboard layout
    /// Physical layout from JSON, key mappings auto-generated from ANSI position table
    static let ansi60Percent: PhysicalLayout = {
        if let layout = QMKLayoutParser.loadFromBundle(
            filename: "ansi-60",
            keyMapping: ANSIPositionTable.keyMapping,
            idOverride: "ansi-60",
            nameOverride: "60% ANSI"
        ) {
            return layout
        }
        print("PhysicalLayout: Failed to load 60% ANSI from JSON, using fallback")
        return PhysicalLayout(
            id: "ansi-60",
            name: "60% ANSI",
            keys: [],
            totalWidth: 15.0,
            totalHeight: 5.0
        )
    }()

    /// 65% ANSI keyboard layout (includes arrow keys)
    /// Physical layout from JSON, key mappings auto-generated from ANSI position table
    static let ansi65Percent: PhysicalLayout = {
        if let layout = QMKLayoutParser.loadFromBundle(
            filename: "ansi-65",
            keyMapping: ANSIPositionTable.keyMapping,
            idOverride: "ansi-65",
            nameOverride: "65% ANSI"
        ) {
            return layout
        }
        print("PhysicalLayout: Failed to load 65% ANSI from JSON, using fallback")
        return PhysicalLayout(
            id: "ansi-65",
            name: "65% ANSI",
            keys: [],
            totalWidth: 18.0,
            totalHeight: 5.0
        )
    }()

    /// 75% ANSI keyboard layout (compact function row, no numpad)
    /// Physical layout from JSON, key mappings auto-generated from ANSI position table
    static let ansi75Percent: PhysicalLayout = {
        if let layout = QMKLayoutParser.loadFromBundle(
            filename: "ansi-75",
            keyMapping: ANSIPositionTable.keyMapping,
            idOverride: "ansi-75",
            nameOverride: "75% ANSI"
        ) {
            return layout
        }
        print("PhysicalLayout: Failed to load 75% ANSI from JSON, using fallback")
        return PhysicalLayout(
            id: "ansi-75",
            name: "75% ANSI",
            keys: [],
            totalWidth: 24.0,
            totalHeight: 6.0
        )
    }()

    /// 80% ANSI keyboard layout (TKL - Tenkeyless, full function row, no numpad)
    /// Physical layout from JSON, key mappings auto-generated from ANSI position table
    static let ansi80Percent: PhysicalLayout = {
        if let layout = QMKLayoutParser.loadFromBundle(
            filename: "ansi-80",
            keyMapping: ANSIPositionTable.keyMapping,
            idOverride: "ansi-80",
            nameOverride: "80% ANSI (TKL)"
        ) {
            return layout
        }
        print("PhysicalLayout: Failed to load 80% ANSI from JSON, using fallback")
        return PhysicalLayout(
            id: "ansi-80",
            name: "80% ANSI (TKL)",
            keys: [],
            totalWidth: 24.0,
            totalHeight: 6.0
        )
    }()

    /// 100% ANSI keyboard layout (full size with numpad)
    /// Physical layout from JSON, key mappings auto-generated from ANSI position table
    static let ansi100Percent: PhysicalLayout = {
        if let layout = QMKLayoutParser.loadFromBundle(
            filename: "ansi-100",
            keyMapping: ANSIPositionTable.keyMapping,
            idOverride: "ansi-100",
            nameOverride: "100% ANSI (Full Size)"
        ) {
            return layout
        }
        print("PhysicalLayout: Failed to load 100% ANSI from JSON, using fallback")
        return PhysicalLayout(
            id: "ansi-100",
            name: "100% ANSI (Full Size)",
            keys: [],
            totalWidth: 24.0,
            totalHeight: 6.0
        )
    }()

    // MARK: - Enthusiast Keyboards (Tier 2)

    /// HHKB (Happy Hacking Keyboard) layout
    /// Physical layout from JSON, key mappings auto-generated from ANSI position table
    static let hhkb: PhysicalLayout = {
        if let layout = QMKLayoutParser.loadFromBundle(
            filename: "hhkb",
            keyMapping: ANSIPositionTable.keyMapping,
            idOverride: "hhkb",
            nameOverride: "HHKB (Happy Hacking Keyboard)"
        ) {
            return layout
        }
        print("PhysicalLayout: Failed to load HHKB from JSON, using fallback")
        return PhysicalLayout(
            id: "hhkb",
            name: "HHKB (Happy Hacking Keyboard)",
            keys: [],
            totalWidth: 17.0,
            totalHeight: 5.0
        )
    }()

    /// Corne (crkbd) split ergonomic keyboard layout
    /// Physical layout from JSON, key mappings auto-generated from ANSI position table
    /// Split keyboard with 3x6+3 layout (3 rows, 6 columns per half, 3 thumb keys)
    static let corne: PhysicalLayout = {
        if let layout = QMKLayoutParser.loadFromBundle(
            filename: "corne",
            keyMapping: ANSIPositionTable.keyMapping,
            idOverride: "corne",
            nameOverride: "Corne (crkbd)"
        ) {
            return layout
        }
        print("PhysicalLayout: Failed to load Corne from JSON, using fallback")
        return PhysicalLayout(
            id: "corne",
            name: "Corne (crkbd)",
            keys: [],
            totalWidth: 15.0,
            totalHeight: 5.0
        )
    }()

    /// Sofle split ergonomic keyboard layout
    /// Physical layout from JSON, key mappings auto-generated from ANSI position table
    /// Split keyboard with 6x4+5 layout (6 columns, 4 rows per half, 5 thumb keys)
    static let sofle: PhysicalLayout = {
        if let layout = QMKLayoutParser.loadFromBundle(
            filename: "sofle",
            keyMapping: ANSIPositionTable.keyMapping,
            idOverride: "sofle",
            nameOverride: "Sofle"
        ) {
            return layout
        }
        print("PhysicalLayout: Failed to load Sofle from JSON, using fallback")
        return PhysicalLayout(
            id: "sofle",
            name: "Sofle",
            keys: [],
            totalWidth: 15.0,
            totalHeight: 5.0
        )
    }()

    /// Ferris Sweep split ergonomic keyboard layout
    /// Physical layout from JSON, key mappings auto-generated from ANSI position table
    /// Minimalist split keyboard with 34 keys total (5x3+2 per half)
    static let ferrisSweep: PhysicalLayout = {
        if let layout = QMKLayoutParser.loadFromBundle(
            filename: "ferris-sweep",
            keyMapping: ANSIPositionTable.keyMapping,
            idOverride: "ferris-sweep",
            nameOverride: "Ferris Sweep"
        ) {
            return layout
        }
        print("PhysicalLayout: Failed to load Ferris Sweep from JSON, using fallback")
        return PhysicalLayout(
            id: "ferris-sweep",
            name: "Ferris Sweep",
            keys: [],
            totalWidth: 12.0,
            totalHeight: 5.0
        )
    }()

    /// Cornix split ergonomic keyboard layout
    /// Physical layout from JSON, key mappings auto-generated from ANSI position table
    /// Split keyboard similar to Corne/Sofle family
    static let cornix: PhysicalLayout = {
        if let layout = QMKLayoutParser.loadFromBundle(
            filename: "cornix",
            keyMapping: ANSIPositionTable.keyMapping,
            idOverride: "cornix",
            nameOverride: "Cornix LP Split Wireless"
        ) {
            return layout
        }
        print("PhysicalLayout: Failed to load Cornix from JSON, using fallback")
        return PhysicalLayout(
            id: "cornix",
            name: "Cornix LP Split Wireless",
            keys: [],
            totalWidth: 15.0,
            totalHeight: 5.0
        )
    }()
}
