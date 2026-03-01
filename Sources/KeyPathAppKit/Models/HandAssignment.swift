import Foundation

/// Assigns keyboard keys to left/right hands for opposite-hand activation in HRM.
///
/// Used to generate Kanata `defhands` blocks. The assignment is position-based
/// (first 5 columns = left, last 5 = right), so it works for any logical keymap
/// (QWERTY, Dvorak, Colemak, etc.) without change.
struct HandAssignment: Equatable, Sendable {
    /// QWERTY scancode names for left-hand keys (3 rows × 5 columns)
    let leftKeys: [String]

    /// QWERTY scancode names for right-hand keys (3 rows × 5 columns)
    let rightKeys: [String]

    /// Default QWERTY hand assignment (standard 5/5 column split)
    static let qwertyDefault = HandAssignment(
        leftKeys: [
            "q", "w", "e", "r", "t",
            "a", "s", "d", "f", "g",
            "z", "x", "c", "v", "b"
        ],
        rightKeys: [
            "y", "u", "i", "o", "p",
            "h", "j", "k", "l", ";",
            "n", "m", ",", ".", "/"
        ]
    )

    /// Derive hand assignment from a physical keyboard layout.
    ///
    /// - **Standard keyboards**: Uses the fixed keyCode column arrays from `LogicalKeymap` —
    ///   first 5 keyCodes per row = left hand, last 5 = right hand.
    /// - **Split keyboards**: Detects the x-coordinate gap between halves (gap > 2.0 units).
    ///   Keys left of gap midpoint = left, rest = right.
    /// - **Fallback**: If gap detection fails, uses the standard 5/5 column split.
    static func derive(from layout: PhysicalLayout) -> HandAssignment {
        // Check if this is a split/ergonomic layout by looking for a gap
        if let gapAssignment = deriveSplitLayout(from: layout) {
            return gapAssignment
        }

        // Standard keyboard: use position-based 5/5 column split via keyCodes
        return qwertyDefault
    }

    /// Attempt to derive hand assignment from a split keyboard layout by detecting the gap.
    private static func deriveSplitLayout(from layout: PhysicalLayout) -> HandAssignment? {
        // Only consider the 30 alpha keys (3 rows × 10 keys)
        let alphaKeyCodes = Set(allAlphaKeyCodes)
        let alphaKeys = layout.keys.filter { alphaKeyCodes.contains($0.keyCode) }

        guard alphaKeys.count >= 20 else { return nil }

        // Sort alpha keys by their visual X position
        let sortedByX = alphaKeys.sorted { $0.visualX < $1.visualX }

        // Find the largest gap between adjacent keys
        var maxGap = 0.0
        var gapMidpoint = 0.0
        for i in 0 ..< sortedByX.count - 1 {
            let rightEdge = sortedByX[i].visualX + sortedByX[i].width
            let leftEdge = sortedByX[i + 1].visualX
            let gap = leftEdge - rightEdge
            if gap > maxGap {
                maxGap = gap
                gapMidpoint = (rightEdge + leftEdge) / 2.0
            }
        }

        // Only use gap detection if the gap is significant (> 2.0 units = clearly split)
        guard maxGap > 2.0 else { return nil }

        // Build QWERTY label lookup: keyCode → QWERTY label
        let qwertyLabels = LogicalKeymap.qwertyUS.coreLabels

        var leftKeys: [String] = []
        var rightKeys: [String] = []

        for key in alphaKeys {
            guard let label = qwertyLabels[key.keyCode] else { continue }
            if key.visualX + key.width / 2.0 < gapMidpoint {
                leftKeys.append(label)
            } else {
                rightKeys.append(label)
            }
        }

        // Validate we got a reasonable split
        guard !leftKeys.isEmpty, !rightKeys.isEmpty else { return nil }

        // Sort to canonical order (top row → home → bottom, left to right within each)
        leftKeys = sortByQwertyOrder(leftKeys)
        rightKeys = sortByQwertyOrder(rightKeys)

        return HandAssignment(leftKeys: leftKeys, rightKeys: rightKeys)
    }

    /// Sort keys into canonical QWERTY order (top row L→R, home row L→R, bottom row L→R)
    private static func sortByQwertyOrder(_ keys: [String]) -> [String] {
        let order = qwertyOrder
        return keys.sorted { (order[$0] ?? 99) < (order[$1] ?? 99) }
    }

    /// QWERTY position order for canonical sorting
    private static let qwertyOrder: [String: Int] = {
        let rows: [[String]] = [
            ["q", "w", "e", "r", "t", "y", "u", "i", "o", "p"],
            ["a", "s", "d", "f", "g", "h", "j", "k", "l", ";"],
            ["z", "x", "c", "v", "b", "n", "m", ",", ".", "/"]
        ]
        var order: [String: Int] = [:]
        var index = 0
        for row in rows {
            for key in row {
                order[key] = index
                index += 1
            }
        }
        return order
    }()

    /// All 30 alpha key keyCodes (top + home + bottom rows)
    private static let allAlphaKeyCodes: [UInt16] = [
        // Top row: q w e r t y u i o p
        12, 13, 14, 15, 17, 16, 32, 34, 31, 35,
        // Home row: a s d f g h j k l ;
        0, 1, 2, 3, 5, 4, 38, 40, 37, 41,
        // Bottom row: z x c v b n m , . /
        6, 7, 8, 9, 11, 45, 46, 43, 47, 44
    ]
}
