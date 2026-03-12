#!/usr/bin/env swift
// Standalone script to generate JSON layout files from the procedural MacBook layout definitions.
// Run: swift Scripts/generate-layout-json.swift
// Output: Sources/KeyPathAppKit/Resources/Keyboards/macbook-*.json

import Foundation

// MARK: - Minimal PhysicalKey for serialization

struct KeyJSON: Codable {
    let keyCode: UInt16
    let label: String
    let x: Double
    let y: Double
    let width: Double
    let height: Double
    let rotation: Double?
    let rotationPivotX: Double?
    let rotationPivotY: Double?
    let shiftLabel: String?
    let subLabel: String?
    let tertiaryLabel: String?
}

struct LayoutJSON: Codable {
    let id: String
    let name: String
    let keys: [KeyJSON]
    let totalWidth: Double?
    let totalHeight: Double?
}

// MARK: - Key builder helper

struct KeyBuilder {
    var keys: [KeyJSON] = []

    mutating func add(
        keyCode: UInt16, label: String,
        x: Double, y: Double,
        width: Double = 1.0, height: Double = 1.0,
        rotation: Double = 0.0,
        rotationPivotX: Double? = nil, rotationPivotY: Double? = nil,
        shiftLabel: String? = nil, subLabel: String? = nil, tertiaryLabel: String? = nil
    ) {
        keys.append(KeyJSON(
            keyCode: keyCode, label: label, x: x, y: y,
            width: width, height: height,
            rotation: rotation == 0 ? nil : rotation,
            rotationPivotX: rotationPivotX, rotationPivotY: rotationPivotY,
            shiftLabel: shiftLabel, subLabel: subLabel, tertiaryLabel: tertiaryLabel
        ))
    }
}

// MARK: - MacBook US

func buildMacBookUS() -> LayoutJSON {
    var b = KeyBuilder()
    var currentX = 0.0
    let keySpacing = 0.08
    let rowSpacing = 1.1
    let standardKeyWidth = 1.0
    let standardKeyHeight = 1.0
    let targetRightEdge = 13 * (standardKeyWidth + keySpacing) + 1.5

    // Row 0
    let escWidth = 1.5
    let touchIdWidth = standardKeyWidth
    let functionRowAvailable = targetRightEdge - escWidth - keySpacing - touchIdWidth - keySpacing
    let functionKeyWidth = (functionRowAvailable - 11 * keySpacing) / 12

    b.add(keyCode: 53, label: "esc", x: 0.0, y: 0.0, width: escWidth, height: standardKeyHeight)
    currentX = escWidth + keySpacing

    let functionKeys: [(UInt16, String)] = [
        (122, "F1"), (120, "F2"), (99, "F3"), (118, "F4"),
        (96, "F5"), (97, "F6"), (98, "F7"), (100, "F8"),
        (101, "F9"), (109, "F10"), (103, "F11"), (111, "F12")
    ]
    for (keyCode, label) in functionKeys {
        b.add(keyCode: keyCode, label: label, x: currentX, y: 0.0, width: functionKeyWidth, height: standardKeyHeight)
        currentX += functionKeyWidth + keySpacing
    }
    b.add(keyCode: 0xFFFF, label: "🔒", x: currentX, y: 0.0, width: touchIdWidth, height: standardKeyHeight)

    // Row 1: Number Row
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
        b.add(keyCode: keyCode, label: label, x: currentX, y: rowSpacing, width: width, height: standardKeyHeight)
        currentX += width + keySpacing
    }

    // Row 2: QWERTY row
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
        b.add(keyCode: keyCode, label: label, x: currentX, y: rowSpacing * 2, width: width, height: standardKeyHeight)
        currentX += width + keySpacing
    }

    // Row 3: Home row
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
        b.add(keyCode: keyCode, label: label, x: currentX, y: rowSpacing * 3, width: width, height: standardKeyHeight)
        currentX += width + keySpacing
    }

    // Row 4: Bottom row
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
        b.add(keyCode: keyCode, label: label, x: currentX, y: rowSpacing * 4, width: width, height: standardKeyHeight)
        currentX += width + keySpacing
    }

    // Row 5: Modifiers + arrows
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
        b.add(keyCode: keyCode, label: label, x: currentX, y: row5Top, width: width, height: standardKeyHeight)
        currentX += width + keySpacing
    }

    let arrowXStart = currentX
    b.add(keyCode: 126, label: "▲", x: arrowXStart + arrowKeyWidth + arrowKeySpacing, y: row5Top, width: arrowKeyWidth, height: arrowKeyHeight)
    let lowerArrowY = row5Top + arrowKeyHeight + arrowKeyGap
    b.add(keyCode: 123, label: "◀", x: arrowXStart, y: lowerArrowY, width: arrowKeyWidth, height: arrowKeyHeight)
    b.add(keyCode: 125, label: "▼", x: arrowXStart + arrowKeyWidth + arrowKeySpacing, y: lowerArrowY, width: arrowKeyWidth, height: arrowKeyHeight)
    b.add(keyCode: 124, label: "▶", x: arrowXStart + 2 * (arrowKeyWidth + arrowKeySpacing), y: lowerArrowY, width: arrowKeyWidth, height: arrowKeyHeight)

    return LayoutJSON(id: "macbook-us", name: "MacBook US", keys: b.keys, totalWidth: nil, totalHeight: nil)
}

// MARK: - MacBook JIS

func buildMacBookJIS() -> LayoutJSON {
    var b = KeyBuilder()
    var currentX = 0.0
    let keySpacing = 0.08
    let rowSpacing = 1.1
    let standardKeyWidth = 1.0
    let standardKeyHeight = 1.0
    let targetRightEdge = 13 * (standardKeyWidth + keySpacing) + 1.5

    // Row 0
    let escWidth = 1.5
    let touchIdWidth = standardKeyWidth
    let functionRowAvailable = targetRightEdge - escWidth - keySpacing - touchIdWidth - keySpacing
    let functionKeyWidth = (functionRowAvailable - 11 * keySpacing) / 12

    b.add(keyCode: 53, label: "esc", x: 0.0, y: 0.0, width: escWidth, height: standardKeyHeight)
    currentX = escWidth + keySpacing

    let functionKeys: [(UInt16, String)] = [
        (122, "F1"), (120, "F2"), (99, "F3"), (118, "F4"),
        (96, "F5"), (97, "F6"), (98, "F7"), (100, "F8"),
        (101, "F9"), (109, "F10"), (103, "F11"), (111, "F12")
    ]
    for (keyCode, label) in functionKeys {
        b.add(keyCode: keyCode, label: label, x: currentX, y: 0.0, width: functionKeyWidth, height: standardKeyHeight)
        currentX += functionKeyWidth + keySpacing
    }
    b.add(keyCode: 0xFFFF, label: "🔒", x: currentX, y: 0.0, width: touchIdWidth, height: standardKeyHeight)

    // Row 1: Number Row - JIS
    let deleteWidthJIS = 1.0
    let yenWidth = standardKeyWidth
    currentX = 0.0
    let jisNumberRowKeys: [(UInt16, String, Double, String?, String?)] = [
        (50, "半角", standardKeyWidth, "全角", nil),
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
        b.add(keyCode: keyCode, label: label, x: currentX, y: rowSpacing, width: width, height: standardKeyHeight, shiftLabel: shiftLabel, subLabel: subLabel)
        currentX += width + keySpacing
    }

    // Row 2: QWERTY row
    let tabWidth = 1.5
    let enterWidth = 1.9

    let qwertyAlphaWidth = (targetRightEdge - tabWidth - enterWidth - 13 * keySpacing) / 12

    b.add(keyCode: 48, label: "⇥", x: 0.0, y: rowSpacing * 2, width: tabWidth, height: standardKeyHeight)
    currentX = tabWidth + keySpacing

    let jisTopRowKeys: [(UInt16, String, String?, String?)] = [
        (12, "q", nil, "た"), (13, "w", nil, "て"), (14, "e", nil, "い"),
        (15, "r", nil, "す"), (17, "t", nil, "か"), (16, "y", nil, "ん"),
        (32, "u", nil, "な"), (34, "i", nil, "に"), (31, "o", nil, "ら"),
        (35, "p", nil, "せ"), (33, "@", "`", "゛"), (30, "[", "{", "゜")
    ]
    for (keyCode, label, shiftLabel, subLabel) in jisTopRowKeys {
        b.add(keyCode: keyCode, label: label, x: currentX, y: rowSpacing * 2, width: qwertyAlphaWidth, height: standardKeyHeight, shiftLabel: shiftLabel, subLabel: subLabel)
        currentX += qwertyAlphaWidth + keySpacing
    }

    // Row 3: Home row
    let controlWidth = 1.8
    let homeRowAlphaWidth = (targetRightEdge - controlWidth - enterWidth - 12 * keySpacing) / 11

    let jisHomeRowKeys: [(UInt16, String, Double, String?, String?)] = [
        (59, "⌃", controlWidth, nil, nil),
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
        b.add(keyCode: keyCode, label: label, x: currentX, y: rowSpacing * 3, width: width, height: standardKeyHeight, shiftLabel: shiftLabel, subLabel: subLabel)
        currentX += width + keySpacing
    }

    // L-shaped Enter key
    b.add(keyCode: 36, label: "↩", x: currentX, y: rowSpacing * 2, width: enterWidth, height: standardKeyHeight * 2 + keySpacing)

    // Row 4: Bottom row
    let leftShiftWidth = 2.1
    let rightShiftWidthJIS = 2.1
    let underscoreWidth = standardKeyWidth
    let bottomAlphaWidth = (targetRightEdge - leftShiftWidth - rightShiftWidthJIS - underscoreWidth - 12 * keySpacing) / 10

    let jisBottomRowKeys: [(UInt16, String, Double, String?, String?)] = [
        (56, "⇧", leftShiftWidth, nil, nil),
        (6, "z", bottomAlphaWidth, nil, "つ"), (7, "x", bottomAlphaWidth, nil, "さ"),
        (8, "c", bottomAlphaWidth, nil, "そ"), (9, "v", bottomAlphaWidth, nil, "ひ"),
        (11, "b", bottomAlphaWidth, nil, "こ"), (45, "n", bottomAlphaWidth, nil, "み"),
        (46, "m", bottomAlphaWidth, nil, "も"), (43, ",", bottomAlphaWidth, "<", "ね"),
        (47, ".", bottomAlphaWidth, ">", "る"), (44, "/", bottomAlphaWidth, "?", "め"),
        (94, "_", underscoreWidth, nil, "ろ"),
        (60, "⇧", rightShiftWidthJIS, nil, nil)
    ]
    currentX = 0.0
    for (keyCode, label, width, shiftLabel, subLabel) in jisBottomRowKeys {
        b.add(keyCode: keyCode, label: label, x: currentX, y: rowSpacing * 4, width: width, height: standardKeyHeight, shiftLabel: shiftLabel, subLabel: subLabel)
        currentX += width + keySpacing
    }

    // Row 5: Modifiers
    let row5Top = rowSpacing * 5
    let capsWidth = standardKeyWidth
    let optWidth = standardKeyWidth
    let cmdWidth = 1.2
    let eisuWidth = 1.3
    let kanaWidth = 1.3
    let fnWidth = standardKeyWidth

    let arrowKeyHeight = 0.45
    let arrowKeyGap = 0.1
    let arrowKeyWidth = 0.9
    let arrowKeySpacing2 = 0.04
    let arrowRightMargin = 0.15
    let arrowClusterWidth = 3 * arrowKeyWidth + 2 * arrowKeySpacing2 + arrowRightMargin

    let leftModsWidth = capsWidth + keySpacing + optWidth + keySpacing + cmdWidth + keySpacing + eisuWidth + keySpacing
    let rightModsWidth = kanaWidth + keySpacing + cmdWidth + keySpacing + fnWidth + keySpacing
    let spacebarWidthJIS = targetRightEdge - leftModsWidth - rightModsWidth - arrowClusterWidth

    let modifierRowJIS: [(UInt16, String, Double)] = [
        (57, "⇪", capsWidth), (58, "⌥", optWidth), (55, "⌘", cmdWidth),
        (102, "英数", eisuWidth), (49, " ", spacebarWidthJIS),
        (104, "かな", kanaWidth), (54, "⌘", cmdWidth), (63, "fn", fnWidth)
    ]
    currentX = 0.0
    for (keyCode, label, width) in modifierRowJIS {
        b.add(keyCode: keyCode, label: label, x: currentX, y: row5Top, width: width, height: standardKeyHeight)
        currentX += width + keySpacing
    }

    let arrowXStart = currentX
    b.add(keyCode: 126, label: "▲", x: arrowXStart + arrowKeyWidth + arrowKeySpacing2, y: row5Top, width: arrowKeyWidth, height: arrowKeyHeight)
    let lowerArrowY = row5Top + arrowKeyHeight + arrowKeyGap
    b.add(keyCode: 123, label: "◀", x: arrowXStart, y: lowerArrowY, width: arrowKeyWidth, height: arrowKeyHeight)
    b.add(keyCode: 125, label: "▼", x: arrowXStart + arrowKeyWidth + arrowKeySpacing2, y: lowerArrowY, width: arrowKeyWidth, height: arrowKeyHeight)
    b.add(keyCode: 124, label: "▶", x: arrowXStart + 2 * (arrowKeyWidth + arrowKeySpacing2), y: lowerArrowY, width: arrowKeyWidth, height: arrowKeyHeight)

    return LayoutJSON(id: "macbook-jis", name: "MacBook JIS", keys: b.keys, totalWidth: nil, totalHeight: nil)
}

// MARK: - MacBook ISO

func buildMacBookISO() -> LayoutJSON {
    var b = KeyBuilder()
    var currentX = 0.0
    let keySpacing = 0.08
    let rowSpacing = 1.1
    let standardKeyWidth = 1.0
    let standardKeyHeight = 1.0
    let targetRightEdge = 13 * (standardKeyWidth + keySpacing) + 1.5

    // Row 0
    let escWidth = 1.5
    let touchIdWidth = standardKeyWidth
    let functionRowAvailable = targetRightEdge - escWidth - keySpacing - touchIdWidth - keySpacing
    let functionKeyWidth = (functionRowAvailable - 11 * keySpacing) / 12

    b.add(keyCode: 53, label: "esc", x: 0.0, y: 0.0, width: escWidth, height: standardKeyHeight)
    currentX = escWidth + keySpacing

    let functionKeys: [(UInt16, String)] = [
        (122, "F1"), (120, "F2"), (99, "F3"), (118, "F4"),
        (96, "F5"), (97, "F6"), (98, "F7"), (100, "F8"),
        (101, "F9"), (109, "F10"), (103, "F11"), (111, "F12")
    ]
    for (keyCode, label) in functionKeys {
        b.add(keyCode: keyCode, label: label, x: currentX, y: 0.0, width: functionKeyWidth, height: standardKeyHeight)
        currentX += functionKeyWidth + keySpacing
    }
    b.add(keyCode: 0xFFFF, label: "🔒", x: currentX, y: 0.0, width: touchIdWidth, height: standardKeyHeight)

    // Row 1: Number Row
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
        b.add(keyCode: keyCode, label: label, x: currentX, y: rowSpacing, width: width, height: standardKeyHeight)
        currentX += width + keySpacing
    }

    // Row 2: QWERTY row
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
        b.add(keyCode: keyCode, label: label, x: currentX, y: rowSpacing * 2, width: width, height: standardKeyHeight)
        currentX += width + keySpacing
    }

    // Row 3: Home row
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
        b.add(keyCode: keyCode, label: label, x: currentX, y: rowSpacing * 3, width: width, height: standardKeyHeight)
        currentX += width + keySpacing
    }

    // Row 4: Bottom row - ISO
    let leftShiftWidthISO = 1.27
    let rightShiftWidthISO = 2.27
    let bottomRowISO: [(UInt16, String, Double)] = [
        (56, "⇧", leftShiftWidthISO),
        (10, "§", standardKeyWidth),
        (6, "z", standardKeyWidth), (7, "x", standardKeyWidth),
        (8, "c", standardKeyWidth), (9, "v", standardKeyWidth),
        (11, "b", standardKeyWidth), (45, "n", standardKeyWidth),
        (46, "m", standardKeyWidth), (43, ",", standardKeyWidth),
        (47, ".", standardKeyWidth), (44, "/", standardKeyWidth),
        (60, "⇧", rightShiftWidthISO)
    ]
    currentX = 0.0
    for (keyCode, label, width) in bottomRowISO {
        b.add(keyCode: keyCode, label: label, x: currentX, y: rowSpacing * 4, width: width, height: standardKeyHeight)
        currentX += width + keySpacing
    }

    // Row 5: Modifiers
    let row5Top = rowSpacing * 5
    let fnWidth = standardKeyWidth
    let ctrlWidth = standardKeyWidth
    let optWidth = standardKeyWidth
    let cmdWidth = 1.35

    let arrowKeyHeight = 0.45
    let arrowKeyGap = 0.1
    let arrowKeyWidth = 0.9
    let arrowKeySpacing2 = 0.04
    let arrowRightMargin = 0.15
    let arrowClusterWidth = 3 * arrowKeyWidth + 2 * arrowKeySpacing2 + arrowRightMargin

    let leftModsWidth = fnWidth + keySpacing + ctrlWidth + keySpacing + optWidth + keySpacing + cmdWidth + keySpacing
    let rightModsWidth = cmdWidth + keySpacing + optWidth + keySpacing
    let spacebarWidth = targetRightEdge - leftModsWidth - rightModsWidth - arrowClusterWidth

    let modifierRow: [(UInt16, String, Double)] = [
        (63, "fn", fnWidth), (59, "⌃", ctrlWidth), (58, "⌥", optWidth),
        (55, "⌘", cmdWidth), (49, " ", spacebarWidth),
        (54, "⌘", cmdWidth), (61, "⌥", optWidth)
    ]
    currentX = 0.0
    for (keyCode, label, width) in modifierRow {
        b.add(keyCode: keyCode, label: label, x: currentX, y: row5Top, width: width, height: standardKeyHeight)
        currentX += width + keySpacing
    }

    let arrowXStart = currentX
    b.add(keyCode: 126, label: "▲", x: arrowXStart + arrowKeyWidth + arrowKeySpacing2, y: row5Top, width: arrowKeyWidth, height: arrowKeyHeight)
    let lowerArrowY = row5Top + arrowKeyHeight + arrowKeyGap
    b.add(keyCode: 123, label: "◀", x: arrowXStart, y: lowerArrowY, width: arrowKeyWidth, height: arrowKeyHeight)
    b.add(keyCode: 125, label: "▼", x: arrowXStart + arrowKeyWidth + arrowKeySpacing2, y: lowerArrowY, width: arrowKeyWidth, height: arrowKeyHeight)
    b.add(keyCode: 124, label: "▶", x: arrowXStart + 2 * (arrowKeyWidth + arrowKeySpacing2), y: lowerArrowY, width: arrowKeyWidth, height: arrowKeyHeight)

    return LayoutJSON(id: "macbook-iso", name: "MacBook ISO", keys: b.keys, totalWidth: nil, totalHeight: nil)
}

// MARK: - MacBook ABNT2

func buildMacBookABNT2() -> LayoutJSON {
    var b = KeyBuilder()
    var currentX = 0.0
    let keySpacing = 0.08
    let rowSpacing = 1.1
    let standardKeyWidth = 1.0
    let standardKeyHeight = 1.0
    let targetRightEdge = 13 * (standardKeyWidth + keySpacing) + 1.5

    // Row 0
    let escWidth = 1.5
    let touchIdWidth = standardKeyWidth
    let functionRowAvailable = targetRightEdge - escWidth - keySpacing - touchIdWidth - keySpacing
    let functionKeyWidth = (functionRowAvailable - 11 * keySpacing) / 12

    b.add(keyCode: 53, label: "esc", x: 0.0, y: 0.0, width: escWidth, height: standardKeyHeight)
    currentX = escWidth + keySpacing

    let functionKeys: [(UInt16, String)] = [
        (122, "F1"), (120, "F2"), (99, "F3"), (118, "F4"),
        (96, "F5"), (97, "F6"), (98, "F7"), (100, "F8"),
        (101, "F9"), (109, "F10"), (103, "F11"), (111, "F12")
    ]
    for (keyCode, label) in functionKeys {
        b.add(keyCode: keyCode, label: label, x: currentX, y: 0.0, width: functionKeyWidth, height: standardKeyHeight)
        currentX += functionKeyWidth + keySpacing
    }
    b.add(keyCode: 0xFFFF, label: "🔒", x: currentX, y: 0.0, width: touchIdWidth, height: standardKeyHeight)

    // Row 1: Number Row
    let numberRow: [(UInt16, String, Double)] = [
        (50, "'", standardKeyWidth),
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
        b.add(keyCode: keyCode, label: label, x: currentX, y: rowSpacing, width: width, height: standardKeyHeight)
        currentX += width + keySpacing
    }

    // Row 2: QWERTY row
    let backslashWidth = targetRightEdge - (1.5 + keySpacing + 12 * (standardKeyWidth + keySpacing))
    let topRow: [(UInt16, String, Double)] = [
        (48, "⇥", 1.5),
        (12, "q", standardKeyWidth), (13, "w", standardKeyWidth),
        (14, "e", standardKeyWidth), (15, "r", standardKeyWidth),
        (17, "t", standardKeyWidth), (16, "y", standardKeyWidth),
        (32, "u", standardKeyWidth), (34, "i", standardKeyWidth),
        (31, "o", standardKeyWidth), (35, "p", standardKeyWidth),
        (33, "´", standardKeyWidth), (30, "[", standardKeyWidth),
        (42, "]", backslashWidth)
    ]
    currentX = 0.0
    for (keyCode, label, width) in topRow {
        b.add(keyCode: keyCode, label: label, x: currentX, y: rowSpacing * 2, width: width, height: standardKeyHeight)
        currentX += width + keySpacing
    }

    // Row 3: Home row
    let capsWidth = 1.8
    let returnWidth = targetRightEdge - (capsWidth + keySpacing + 11 * (standardKeyWidth + keySpacing))
    let middleRow: [(UInt16, String, Double)] = [
        (57, "⇪", capsWidth),
        (0, "a", standardKeyWidth), (1, "s", standardKeyWidth),
        (2, "d", standardKeyWidth), (3, "f", standardKeyWidth),
        (5, "g", standardKeyWidth), (4, "h", standardKeyWidth),
        (38, "j", standardKeyWidth), (40, "k", standardKeyWidth),
        (37, "l", standardKeyWidth), (41, "ç", standardKeyWidth),
        (39, "~", standardKeyWidth),
        (36, "↩", returnWidth)
    ]
    currentX = 0.0
    for (keyCode, label, width) in middleRow {
        b.add(keyCode: keyCode, label: label, x: currentX, y: rowSpacing * 3, width: width, height: standardKeyHeight)
        currentX += width + keySpacing
    }

    // Row 4: Bottom row - ABNT2
    let leftShiftWidthABNT2 = 1.27
    let rightShiftWidthABNT2 = 1.27
    let bottomRowABNT2: [(UInt16, String, Double)] = [
        (56, "⇧", leftShiftWidthABNT2),
        (10, "\\", standardKeyWidth),
        (6, "z", standardKeyWidth), (7, "x", standardKeyWidth),
        (8, "c", standardKeyWidth), (9, "v", standardKeyWidth),
        (11, "b", standardKeyWidth), (45, "n", standardKeyWidth),
        (46, "m", standardKeyWidth), (43, ",", standardKeyWidth),
        (47, ".", standardKeyWidth), (44, ";", standardKeyWidth),
        (94, "/", standardKeyWidth),
        (60, "⇧", rightShiftWidthABNT2)
    ]
    currentX = 0.0
    for (keyCode, label, width) in bottomRowABNT2 {
        b.add(keyCode: keyCode, label: label, x: currentX, y: rowSpacing * 4, width: width, height: standardKeyHeight)
        currentX += width + keySpacing
    }

    // Row 5: Modifiers
    let row5Top = rowSpacing * 5
    let fnWidth = standardKeyWidth
    let ctrlWidth = standardKeyWidth
    let optWidth = standardKeyWidth
    let cmdWidth = 1.35

    let arrowKeyHeight = 0.45
    let arrowKeyGap = 0.1
    let arrowKeyWidth = 0.9
    let arrowKeySpacing2 = 0.04
    let arrowRightMargin = 0.15
    let arrowClusterWidth = 3 * arrowKeyWidth + 2 * arrowKeySpacing2 + arrowRightMargin

    let leftModsWidth = fnWidth + keySpacing + ctrlWidth + keySpacing + optWidth + keySpacing + cmdWidth + keySpacing
    let rightModsWidth = cmdWidth + keySpacing + optWidth + keySpacing
    let spacebarWidth = targetRightEdge - leftModsWidth - rightModsWidth - arrowClusterWidth

    let modifierRow: [(UInt16, String, Double)] = [
        (63, "fn", fnWidth), (59, "⌃", ctrlWidth), (58, "⌥", optWidth),
        (55, "⌘", cmdWidth), (49, " ", spacebarWidth),
        (54, "⌘", cmdWidth), (61, "⌥", optWidth)
    ]
    currentX = 0.0
    for (keyCode, label, width) in modifierRow {
        b.add(keyCode: keyCode, label: label, x: currentX, y: row5Top, width: width, height: standardKeyHeight)
        currentX += width + keySpacing
    }

    let arrowXStart = currentX
    b.add(keyCode: 126, label: "▲", x: arrowXStart + arrowKeyWidth + arrowKeySpacing2, y: row5Top, width: arrowKeyWidth, height: arrowKeyHeight)
    let lowerArrowY = row5Top + arrowKeyHeight + arrowKeyGap
    b.add(keyCode: 123, label: "◀", x: arrowXStart, y: lowerArrowY, width: arrowKeyWidth, height: arrowKeyHeight)
    b.add(keyCode: 125, label: "▼", x: arrowXStart + arrowKeyWidth + arrowKeySpacing2, y: lowerArrowY, width: arrowKeyWidth, height: arrowKeyHeight)
    b.add(keyCode: 124, label: "▶", x: arrowXStart + 2 * (arrowKeyWidth + arrowKeySpacing2), y: lowerArrowY, width: arrowKeyWidth, height: arrowKeyHeight)

    return LayoutJSON(id: "macbook-abnt2", name: "MacBook ABNT2", keys: b.keys, totalWidth: nil, totalHeight: nil)
}

// MARK: - MacBook Korean

func buildMacBookKorean() -> LayoutJSON {
    var b = KeyBuilder()
    var currentX = 0.0
    let keySpacing = 0.08
    let rowSpacing = 1.1
    let standardKeyWidth = 1.0
    let standardKeyHeight = 1.0
    let targetRightEdge = 13 * (standardKeyWidth + keySpacing) + 1.5

    // Row 0
    let escWidth = 1.5
    let touchIdWidth = standardKeyWidth
    let functionRowAvailable = targetRightEdge - escWidth - keySpacing - touchIdWidth - keySpacing
    let functionKeyWidth = (functionRowAvailable - 11 * keySpacing) / 12

    b.add(keyCode: 53, label: "esc", x: 0.0, y: 0.0, width: escWidth, height: standardKeyHeight)
    currentX = escWidth + keySpacing

    let functionKeys: [(UInt16, String)] = [
        (122, "F1"), (120, "F2"), (99, "F3"), (118, "F4"),
        (96, "F5"), (97, "F6"), (98, "F7"), (100, "F8"),
        (101, "F9"), (109, "F10"), (103, "F11"), (111, "F12")
    ]
    for (keyCode, label) in functionKeys {
        b.add(keyCode: keyCode, label: label, x: currentX, y: 0.0, width: functionKeyWidth, height: standardKeyHeight)
        currentX += functionKeyWidth + keySpacing
    }
    b.add(keyCode: 0xFFFF, label: "🔒", x: currentX, y: 0.0, width: touchIdWidth, height: standardKeyHeight)

    // Row 1: Number Row
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
        b.add(keyCode: keyCode, label: label, x: currentX, y: rowSpacing, width: width, height: standardKeyHeight)
        currentX += width + keySpacing
    }

    // Row 2: QWERTY row
    let backslashWidth = targetRightEdge - (1.5 + keySpacing + 12 * (standardKeyWidth + keySpacing))
    let topRow: [(UInt16, String, Double)] = [
        (48, "⇥", 1.5),
        (12, "q", standardKeyWidth), (13, "w", standardKeyWidth),
        (14, "e", standardKeyWidth), (15, "r", standardKeyWidth),
        (17, "t", standardKeyWidth), (16, "y", standardKeyWidth),
        (32, "u", standardKeyWidth), (34, "i", standardKeyWidth),
        (31, "o", standardKeyWidth), (35, "p", standardKeyWidth),
        (33, "[", standardKeyWidth), (30, "]", standardKeyWidth),
        (42, "₩", backslashWidth)
    ]
    currentX = 0.0
    for (keyCode, label, width) in topRow {
        b.add(keyCode: keyCode, label: label, x: currentX, y: rowSpacing * 2, width: width, height: standardKeyHeight)
        currentX += width + keySpacing
    }

    // Row 3: Home row
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
        b.add(keyCode: keyCode, label: label, x: currentX, y: rowSpacing * 3, width: width, height: standardKeyHeight)
        currentX += width + keySpacing
    }

    // Row 4: Bottom row
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
        b.add(keyCode: keyCode, label: label, x: currentX, y: rowSpacing * 4, width: width, height: standardKeyHeight)
        currentX += width + keySpacing
    }

    // Row 5: Modifiers - Korean
    let row5Top = rowSpacing * 5
    let fnWidth = standardKeyWidth
    let ctrlWidth = standardKeyWidth
    let optWidth = standardKeyWidth
    let cmdWidth = 1.25
    let langKeyWidth = 0.9

    let arrowKeyHeight = 0.45
    let arrowKeyGap = 0.1
    let arrowKeyWidth = 0.9
    let arrowKeySpacing2 = 0.04
    let arrowRightMargin = 0.15
    let arrowClusterWidth = 3 * arrowKeyWidth + 2 * arrowKeySpacing2 + arrowRightMargin

    let leftModsWidth = fnWidth + keySpacing + ctrlWidth + keySpacing + optWidth + keySpacing + cmdWidth + keySpacing + langKeyWidth + keySpacing
    let rightModsWidth = langKeyWidth + keySpacing + cmdWidth + keySpacing + optWidth + keySpacing
    let spacebarWidth = targetRightEdge - leftModsWidth - rightModsWidth - arrowClusterWidth

    currentX = 0.0
    b.add(keyCode: 63, label: "fn", x: currentX, y: row5Top, width: fnWidth, height: standardKeyHeight)
    currentX += fnWidth + keySpacing
    b.add(keyCode: 59, label: "⌃", x: currentX, y: row5Top, width: ctrlWidth, height: standardKeyHeight)
    currentX += ctrlWidth + keySpacing
    b.add(keyCode: 58, label: "⌥", x: currentX, y: row5Top, width: optWidth, height: standardKeyHeight)
    currentX += optWidth + keySpacing
    b.add(keyCode: 55, label: "⌘", x: currentX, y: row5Top, width: cmdWidth, height: standardKeyHeight)
    currentX += cmdWidth + keySpacing
    b.add(keyCode: 104, label: "한자", x: currentX, y: row5Top, width: langKeyWidth, height: standardKeyHeight)
    currentX += langKeyWidth + keySpacing
    b.add(keyCode: 49, label: " ", x: currentX, y: row5Top, width: spacebarWidth, height: standardKeyHeight)
    currentX += spacebarWidth + keySpacing
    b.add(keyCode: 102, label: "한/영", x: currentX, y: row5Top, width: langKeyWidth, height: standardKeyHeight)
    currentX += langKeyWidth + keySpacing
    b.add(keyCode: 54, label: "⌘", x: currentX, y: row5Top, width: cmdWidth, height: standardKeyHeight)
    currentX += cmdWidth + keySpacing
    b.add(keyCode: 61, label: "⌥", x: currentX, y: row5Top, width: optWidth, height: standardKeyHeight)
    currentX += optWidth + keySpacing

    let arrowXStart = currentX
    b.add(keyCode: 126, label: "▲", x: arrowXStart + arrowKeyWidth + arrowKeySpacing2, y: row5Top, width: arrowKeyWidth, height: arrowKeyHeight)
    let lowerArrowY = row5Top + arrowKeyHeight + arrowKeyGap
    b.add(keyCode: 123, label: "◀", x: arrowXStart, y: lowerArrowY, width: arrowKeyWidth, height: arrowKeyHeight)
    b.add(keyCode: 125, label: "▼", x: arrowXStart + arrowKeyWidth + arrowKeySpacing2, y: lowerArrowY, width: arrowKeyWidth, height: arrowKeyHeight)
    b.add(keyCode: 124, label: "▶", x: arrowXStart + 2 * (arrowKeyWidth + arrowKeySpacing2), y: lowerArrowY, width: arrowKeyWidth, height: arrowKeyHeight)

    return LayoutJSON(id: "macbook-korean", name: "MacBook Korean", keys: b.keys, totalWidth: nil, totalHeight: nil)
}

// MARK: - Main

let layouts: [(String, LayoutJSON)] = [
    ("macbook-us", buildMacBookUS()),
    ("macbook-jis", buildMacBookJIS()),
    ("macbook-iso", buildMacBookISO()),
    ("macbook-abnt2", buildMacBookABNT2()),
    ("macbook-korean", buildMacBookKorean())
]

let encoder = JSONEncoder()
encoder.outputFormatting = [.prettyPrinted, .sortedKeys]

let scriptDir = URL(fileURLWithPath: #filePath).deletingLastPathComponent()
let outputDir = scriptDir.deletingLastPathComponent()
    .appendingPathComponent("Sources/KeyPathAppKit/Resources/Keyboards")

for (filename, layout) in layouts {
    let data = try encoder.encode(layout)
    let url = outputDir.appendingPathComponent("\(filename).json")
    try data.write(to: url)
    print("Wrote \(url.lastPathComponent) (\(data.count) bytes, \(layout.keys.count) keys)")
}

print("Done! Generated \(layouts.count) layout JSON files.")
