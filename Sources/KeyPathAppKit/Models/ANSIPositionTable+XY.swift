import Foundation

// MARK: - Row-Based Position Mapping

/// Maps QMK keyboard keys to macOS keyCodes using row-based ordering.
///
/// **How it works:**
/// 1. Group keys by y-coordinate into rows (tolerance ±0.4 units)
/// 2. Sort each row left-to-right by x-coordinate
/// 3. Identify logical rows by count (6 rows = TKL, 5 = 60/65%, 4 = 40%)
/// 4. Within each row, assign keyCodes by position index using ANSI templates
/// 5. For the modifier row, anchor on the spacebar (widest key) and map outward
///
/// **Why row-based instead of coordinate matching:**
/// Every QMK keyboard uses different absolute coordinates, but the left-to-right
/// key ORDER within each row is always the same for staggered layouts. The 3rd key
/// in the number row is always "2", regardless of whether it's at x=2.0 or x=2.5.
///
/// **What it handles well:** Standard staggered layouts (60%, 65%, 75%, TKL, full-size)
/// **What it flags as low-quality:** Split, ortho, and exotic layouts
extension ANSIPositionTable {
    /// Key position data passed to the mapper
    struct QMKKeyPosition {
        let x: Double
        let y: Double
        let width: Double
        let index: Int
    }

    /// Result of mapping a single key
    struct KeyMapping {
        let index: Int
        let keyCode: UInt16
        let label: String
    }

    /// Map all QMK keys to macOS keyCodes using row-based ordering.
    /// Returns one KeyMapping per input key, in arbitrary order.
    static func mapKeysByRow(qmkKeys: [QMKKeyPosition]) -> [KeyMapping] {
        guard !qmkKeys.isEmpty else { return [] }

        // Step 1: Group keys into rows by y-coordinate
        let rows = clusterIntoRows(qmkKeys)
        guard !rows.isEmpty else { return [] }

        // Step 2: Identify logical rows from layout structure
        let logicalRows = identifyLogicalRows(rows)

        // Step 3: For each row, sort left-to-right and assign keyCodes
        var result: [KeyMapping] = []
        var usedKeyCodes = Set<UInt16>()

        for (logicalRow, keys) in logicalRows {
            let sorted = keys.sorted(by: { $0.x < $1.x })

            if logicalRow == .modifierRow {
                // Special handling: anchor on spacebar, map outward
                let modMappings = mapModifierRow(sorted, usedKeyCodes: &usedKeyCodes)
                result.append(contentsOf: modMappings)
            } else {
                let template = rowTemplate(for: logicalRow)

                // Split into core and extended (nav cluster) by template core size
                let (coreKeys, extendedKeys) = splitByTemplateSize(sorted, coreSize: template.core.count)

                // Map core keys by position index
                for (pos, key) in coreKeys.enumerated() {
                    if pos < template.core.count {
                        let mapping = template.core[pos]
                        if !usedKeyCodes.contains(mapping.keyCode) {
                            result.append(KeyMapping(index: key.index, keyCode: mapping.keyCode, label: mapping.label))
                            usedKeyCodes.insert(mapping.keyCode)
                            continue
                        }
                    }
                    let placeholder = PhysicalKey.placeholderKeyCodeBase + UInt16(key.index)
                    result.append(KeyMapping(index: key.index, keyCode: placeholder, label: "?"))
                }

                // Map extended keys (nav cluster)
                for (pos, key) in extendedKeys.enumerated() {
                    if pos < template.extended.count {
                        let mapping = template.extended[pos]
                        if !usedKeyCodes.contains(mapping.keyCode) {
                            result.append(KeyMapping(index: key.index, keyCode: mapping.keyCode, label: mapping.label))
                            usedKeyCodes.insert(mapping.keyCode)
                            continue
                        }
                    }
                    let placeholder = PhysicalKey.placeholderKeyCodeBase + UInt16(key.index)
                    result.append(KeyMapping(index: key.index, keyCode: placeholder, label: "?"))
                }
            }
        }

        return result
    }

    // MARK: - Row Clustering

    /// Cluster keys into rows by y-coordinate proximity.
    ///
    /// QMK uses 1.0 = 1 key unit; standard row pitch is 1.0u. The 0.4u tolerance
    /// accommodates staggered layouts where keys in the same row have slight Y offsets
    /// (e.g., standard ANSI stagger ~0.25u between columns). Must stay below 0.5u to
    /// avoid merging adjacent rows on compact keyboards with 0.75u row pitch.
    private static func clusterIntoRows(_ keys: [QMKKeyPosition]) -> [[QMKKeyPosition]] {
        let sorted = keys.sorted(by: { $0.y < $1.y })
        var rows: [[QMKKeyPosition]] = []
        var currentRow: [QMKKeyPosition] = [sorted[0]]
        var currentY = sorted[0].y

        for key in sorted.dropFirst() {
            if abs(key.y - currentY) < 0.4 {
                currentRow.append(key)
            } else {
                rows.append(currentRow)
                currentRow = [key]
                currentY = key.y
            }
        }
        rows.append(currentRow)
        return rows
    }

    // MARK: - Logical Row Identification

    private enum LogicalRow {
        case functionRow
        case numberRow
        case topAlpha
        case homeRow
        case bottomRow
        case modifierRow
    }

    /// Identify which logical row each physical row corresponds to.
    /// Uses row count + structural analysis (y-gaps, function row gaps).
    private static func identifyLogicalRows(
        _ rows: [[QMKKeyPosition]]
    ) -> [(LogicalRow, [QMKKeyPosition])] {
        let rowCount = rows.count

        // Detect function row: look for characteristic gaps between key groups
        // (ESC alone, then F1-F4, F5-F8, F9-F12, then nav) OR y-gap after first row
        let firstRowHasGaps = rowCount >= 6 && hasFunctionRowGaps(rows[0])
        let hasYGapAfterFirst = rowCount >= 2 && {
            let row0MaxY = rows[0].map(\.y).max() ?? 0
            let row1MinY = rows[1].map(\.y).min() ?? 0
            return (row1MinY - row0MaxY) > 0.8
        }()
        let hasFunctionRow = rowCount >= 6 && (firstRowHasGaps || hasYGapAfterFirst)

        let assignments: [LogicalRow]
        if hasFunctionRow || rowCount >= 6 {
            assignments = [.functionRow, .numberRow, .topAlpha, .homeRow, .bottomRow, .modifierRow]
        } else if rowCount == 5 {
            assignments = [.numberRow, .topAlpha, .homeRow, .bottomRow, .modifierRow]
        } else if rowCount == 4 {
            assignments = [.topAlpha, .homeRow, .bottomRow, .modifierRow]
        } else {
            // 3 or fewer rows — assign from bottom up
            let bottomUp: [LogicalRow] = [.modifierRow, .bottomRow, .homeRow, .topAlpha]
            var result: [(LogicalRow, [QMKKeyPosition])] = []
            for (idx, row) in rows.reversed().enumerated() {
                if idx < bottomUp.count {
                    result.insert((bottomUp[idx], row), at: 0)
                }
            }
            return result
        }

        return zip(assignments, rows).map { ($0, $1) }
    }

    /// Check if a row has the characteristic x-gaps of a function row.
    /// Function rows have gaps between ESC and F1, between F4 and F5, between F8 and F9.
    private static func hasFunctionRowGaps(_ row: [QMKKeyPosition]) -> Bool {
        let sorted = row.sorted(by: { $0.x < $1.x })
        guard sorted.count >= 10 else { return false }

        var gapCount = 0
        for i in 1 ..< sorted.count {
            let gap = sorted[i].x - (sorted[i - 1].x + sorted[i - 1].width)
            if gap > 0.3 {
                gapCount += 1
            }
        }
        return gapCount >= 2
    }

    // MARK: - Core/Extended Splitting

    /// Split a sorted row into core keys and extended keys (nav cluster).
    /// Uses the template's core size: first N keys are core, remaining are extended.
    /// This is more robust than gap detection since QMK nav cluster gaps vary (0.25u-1u).
    private static func splitByTemplateSize(
        _ sortedKeys: [QMKKeyPosition],
        coreSize: Int
    ) -> (core: [QMKKeyPosition], extended: [QMKKeyPosition]) {
        if sortedKeys.count <= coreSize {
            return (sortedKeys, [])
        }
        return (Array(sortedKeys[..<coreSize]), Array(sortedKeys[coreSize...]))
    }

    /// Split for the modifier row: find the gap between core modifiers and arrow keys.
    /// Uses gap detection since modifier row key counts vary widely.
    private static func splitAtGap(
        _ sortedKeys: [QMKKeyPosition]
    ) -> (core: [QMKKeyPosition], extended: [QMKKeyPosition]) {
        guard sortedKeys.count > 1 else { return (sortedKeys, []) }

        var maxGap = 0.0
        var maxGapIdx = -1
        for i in 1 ..< sortedKeys.count {
            let prevRight = sortedKeys[i - 1].x + sortedKeys[i - 1].width
            let gap = sortedKeys[i].x - prevRight
            if gap > maxGap {
                maxGap = gap
                maxGapIdx = i
            }
        }

        // Only split if gap is significant (> 0.2u) and at least 4 keys precede it
        if maxGap > 0.2, maxGapIdx >= 4 {
            return (Array(sortedKeys[..<maxGapIdx]), Array(sortedKeys[maxGapIdx...]))
        }
        return (sortedKeys, [])
    }

    // MARK: - Modifier Row (Spacebar-Anchored)

    /// Map the modifier row by finding the spacebar (widest key), then assigning
    /// left-side modifiers and right-side modifiers by position outward from space.
    private static func mapModifierRow(
        _ sorted: [QMKKeyPosition],
        usedKeyCodes: inout Set<UInt16>
    ) -> [KeyMapping] {
        // Separate nav cluster first
        let (coreKeys, extendedKeys) = splitAtGap(sorted)

        // Find spacebar: widest key (must be ≥ 3u to be unambiguous)
        let spaceIdx = coreKeys.enumerated().max(by: { $0.element.width < $1.element.width })?.offset
        guard let spaceIdx, coreKeys[spaceIdx].width >= 2.5 else {
            // Can't identify spacebar — fall back to index-based
            return mapRowByIndex(sorted, template: modRowFull, usedKeyCodes: &usedKeyCodes)
        }

        var result: [KeyMapping] = []
        let leftMods = Array(coreKeys[..<spaceIdx])
        let rightMods = spaceIdx + 1 < coreKeys.count ? Array(coreKeys[(spaceIdx + 1)...]) : []

        // Map left modifiers (rightmost = LCmd, then LAlt, then LCtrl outward)
        let leftTemplates: [(UInt16, String)] = [(59, "⌃"), (58, "⌥"), (55, "⌘")]
        for (i, key) in leftMods.enumerated() {
            // Map from left: position 0 = LCtrl, 1 = LAlt, 2 = LCmd
            // But if there are more or fewer keys, adjust
            let templateIdx: Int = if leftMods.count <= leftTemplates.count {
                // Fewer keys than template: align from the right (closest to space)
                leftTemplates.count - leftMods.count + i
            } else {
                i
            }

            if templateIdx >= 0, templateIdx < leftTemplates.count {
                let mapping = leftTemplates[templateIdx]
                if !usedKeyCodes.contains(mapping.0) {
                    result.append(KeyMapping(index: key.index, keyCode: mapping.0, label: mapping.1))
                    usedKeyCodes.insert(mapping.0)
                    continue
                }
            }
            result.append(KeyMapping(index: key.index, keyCode: PhysicalKey.placeholderKeyCodeBase + UInt16(key.index), label: "?"))
        }

        // Map spacebar
        if !usedKeyCodes.contains(49) {
            result.append(KeyMapping(index: coreKeys[spaceIdx].index, keyCode: 49, label: "␣"))
            usedKeyCodes.insert(49)
        } else {
            result.append(KeyMapping(index: coreKeys[spaceIdx].index, keyCode: PhysicalKey.placeholderKeyCodeBase + UInt16(coreKeys[spaceIdx].index), label: "?"))
        }

        // Map right modifiers: RCmd, RAlt, Fn, RCtrl
        let rightTemplates: [(UInt16, String)] = [(54, "⌘"), (61, "⌥"), (110, "fn"), (62, "⌃")]
        for (i, key) in rightMods.enumerated() {
            if i < rightTemplates.count {
                let mapping = rightTemplates[i]
                if !usedKeyCodes.contains(mapping.0) {
                    result.append(KeyMapping(index: key.index, keyCode: mapping.0, label: mapping.1))
                    usedKeyCodes.insert(mapping.0)
                    continue
                }
            }
            result.append(KeyMapping(index: key.index, keyCode: PhysicalKey.placeholderKeyCodeBase + UInt16(key.index), label: "?"))
        }

        // Map extended keys (arrow keys after gap)
        let arrowTemplates: [(UInt16, String)] = [(123, "◀"), (125, "▼"), (124, "▶")]
        for (i, key) in extendedKeys.enumerated() {
            if i < arrowTemplates.count {
                let mapping = arrowTemplates[i]
                if !usedKeyCodes.contains(mapping.0) {
                    result.append(KeyMapping(index: key.index, keyCode: mapping.0, label: mapping.1))
                    usedKeyCodes.insert(mapping.0)
                    continue
                }
            }
            result.append(KeyMapping(index: key.index, keyCode: PhysicalKey.placeholderKeyCodeBase + UInt16(key.index), label: "?"))
        }

        return result
    }

    /// Fallback: map a row by pure index position
    private static func mapRowByIndex(
        _ keys: [QMKKeyPosition],
        template: [(UInt16, String)],
        usedKeyCodes: inout Set<UInt16>
    ) -> [KeyMapping] {
        var result: [KeyMapping] = []
        for (i, key) in keys.enumerated() {
            if i < template.count {
                let mapping = template[i]
                if !usedKeyCodes.contains(mapping.0) {
                    result.append(KeyMapping(index: key.index, keyCode: mapping.0, label: mapping.1))
                    usedKeyCodes.insert(mapping.0)
                    continue
                }
            }
            result.append(KeyMapping(index: key.index, keyCode: PhysicalKey.placeholderKeyCodeBase + UInt16(key.index), label: "?"))
        }
        return result
    }

    // MARK: - Row Templates

    private struct RowTemplate {
        let core: [(keyCode: UInt16, label: String)]
        let extended: [(keyCode: UInt16, label: String)]
    }

    private static func rowTemplate(for row: LogicalRow) -> RowTemplate {
        switch row {
        case .functionRow: RowTemplate(core: fnRowCore, extended: fnRowExtended)
        case .numberRow: RowTemplate(core: numRowCore, extended: numRowExtended)
        case .topAlpha: RowTemplate(core: topRowCore, extended: topRowExtended)
        case .homeRow: RowTemplate(core: homeRowCore, extended: [])
        case .bottomRow: RowTemplate(core: bottomRowCore, extended: bottomRowExtended)
        case .modifierRow: RowTemplate(core: modRowFull, extended: [])
        }
    }

    /// Function row: ESC, F1-F12
    private static let fnRowCore: [(keyCode: UInt16, label: String)] = [
        (53, "esc"),
        (122, "f1"), (120, "f2"), (99, "f3"), (118, "f4"),
        (96, "f5"), (97, "f6"), (98, "f7"), (100, "f8"),
        (101, "f9"), (109, "f10"), (103, "f11"), (111, "f12"),
    ]

    private static let fnRowExtended: [(keyCode: UInt16, label: String)] = [
        (105, "prt"), (107, "scr"), (113, "pse"),
    ]

    /// Number row: ` 1-9 0 - = Backspace
    private static let numRowCore: [(keyCode: UInt16, label: String)] = [
        (50, "`"),
        (18, "1"), (19, "2"), (20, "3"), (21, "4"), (23, "5"),
        (22, "6"), (26, "7"), (28, "8"), (25, "9"), (29, "0"),
        (27, "-"), (24, "="), (51, "⌫"),
    ]

    private static let numRowExtended: [(keyCode: UInt16, label: String)] = [
        (114, "ins"), (115, "hom"), (116, "pgu"),
    ]

    /// Top alpha: Tab Q-P [ ] backslash
    private static let topRowCore: [(keyCode: UInt16, label: String)] = [
        (48, "⇥"),
        (12, "q"), (13, "w"), (14, "e"), (15, "r"), (17, "t"),
        (16, "y"), (32, "u"), (34, "i"), (31, "o"), (35, "p"),
        (33, "["), (30, "]"), (42, "\\"),
    ]

    private static let topRowExtended: [(keyCode: UInt16, label: String)] = [
        (117, "del"), (119, "end"), (121, "pgd"),
    ]

    /// Home row: CapsLock A-L ; ' Enter
    private static let homeRowCore: [(keyCode: UInt16, label: String)] = [
        (57, "⇪"),
        (0, "a"), (1, "s"), (2, "d"), (3, "f"), (5, "g"),
        (4, "h"), (38, "j"), (40, "k"), (37, "l"), (41, ";"),
        (39, "'"), (36, "↩"),
    ]

    /// Bottom row: LShift Z-/ RShift
    private static let bottomRowCore: [(keyCode: UInt16, label: String)] = [
        (56, "⇧"),
        (6, "z"), (7, "x"), (8, "c"), (9, "v"), (11, "b"),
        (45, "n"), (46, "m"), (43, ","), (47, "."), (44, "/"),
        (60, "⇧"),
    ]

    private static let bottomRowExtended: [(keyCode: UInt16, label: String)] = [
        (126, "▲"),
    ]

    /// Modifier row (full template for fallback when spacebar detection fails)
    private static let modRowFull: [(UInt16, String)] = [
        (59, "⌃"), (58, "⌥"), (55, "⌘"),
        (49, "␣"),
        (54, "⌘"), (61, "⌥"), (110, "fn"), (62, "⌃"),
        (123, "◀"), (125, "▼"), (124, "▶"),
    ]
}
