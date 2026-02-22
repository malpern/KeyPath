import Foundation
import KeyPathCore
import KeyPathDaemonLifecycle
import Network

extension KanataConfiguration {
    /// Formats collection blocks into keyboard-shaped, padded rows for readability.
    enum KeyboardGridFormatter {
        /// Simple 60%/MacBook ANSI-ish layout expressed in Kanata key names
        private static let layoutRows: [[String]] = [
            ["esc", "f1", "f2", "f3", "f4", "f5", "f6", "f7", "f8", "f9", "f10", "f11", "f12", "del"],
            ["grv", "1", "2", "3", "4", "5", "6", "7", "8", "9", "0", "min", "eql", "bspc"],
            ["tab", "q", "w", "e", "r", "t", "y", "u", "i", "o", "p", "[", "]", "\\"],
            ["caps", "a", "s", "d", "f", "g", "h", "j", "k", "l", ";", "'", "ret"],
            ["lsft", "z", "x", "c", "v", "b", "n", "m", ",", ".", "/", "rsft"],
            ["lctl", "lalt", "lmet", "spc", "rmet", "ralt", "rctl"]
        ]

        private static let order: [String: Int] = {
            var idx: [String: Int] = [:]
            for (rowIndex, row) in layoutRows.enumerated() {
                for (colIndex, key) in row.enumerated() {
                    idx[key] = rowIndex * 100 + colIndex // wide spacing to keep row priority
                }
            }
            return idx
        }()

        static func renderDefsrc(_ block: CollectionBlock) -> [String] {
            guard !block.entries.isEmpty else {
                return block.metadata + ["  ;; (no mappings)"]
            }
            let sorted = sortEntries(block.entries)
            let body = renderGridLines(sorted) { $0.sourceKey }
            return block.metadata + body
        }

        static func renderLayer(
            _ block: CollectionBlock,
            valueProvider: (LayerEntry) -> String
        ) -> [String] {
            guard !block.entries.isEmpty else {
                return block.metadata + ["  ;; (no mappings)"]
            }
            let sorted = sortEntries(block.entries)
            let body = renderGridLines(sorted, valueProvider: valueProvider)
            return block.metadata + body
        }

        private static func sortEntries(_ entries: [LayerEntry]) -> [LayerEntry] {
            entries.sorted { lhs, rhs in
                let l = order[lhs.sourceKey] ?? Int.max
                let r = order[rhs.sourceKey] ?? Int.max
                if l == r {
                    return lhs.sourceKey < rhs.sourceKey
                }
                return l < r
            }
        }

        /// The index of the spacebar row in `layoutRows`.
        private static let spacebarRowIndex = 5

        /// Render entries grouped into physical rows; rows without entries are skipped.
        private static func renderGridLines(
            _ entries: [LayerEntry],
            valueProvider: (LayerEntry) -> String
        ) -> [String] {
            // spcTokenIndex tracks which token in the spacebar row corresponds to "spc"
            var rows: [(tokens: [String], spcTokenIndex: Int?)] = []
            var remaining = entries

            for (rowIndex, layoutRow) in layoutRows.enumerated() {
                var tokens: [String] = []
                var spcIdx: Int?
                for key in layoutRow {
                    if let idx = remaining.firstIndex(where: { $0.sourceKey == key }) {
                        let entry = remaining.remove(at: idx)
                        if rowIndex == spacebarRowIndex, key == "spc" {
                            spcIdx = tokens.count
                        }
                        tokens.append(valueProvider(entry))
                    }
                }
                if !tokens.isEmpty {
                    rows.append((tokens, spcIdx))
                }
            }

            // Anything not in the known layout gets appended in a trailing row
            if !remaining.isEmpty {
                rows.append((remaining.map { valueProvider($0) }, nil))
            }

            return rows.map { row in
                if let spcIdx = row.spcTokenIndex {
                    return "  " + padSpacebarRow(row.tokens, spcTokenIndex: spcIdx)
                }
                return "  " + padRow(row.tokens)
            }
        }

        private static func padRow(_ tokens: [String]) -> String {
            let width = tokens.map(\.count).max() ?? 0
            let padded = tokens.map { token in
                token.padding(toLength: width, withPad: " ", startingAt: 0)
            }
            return padded.joined(separator: " ")
        }

        /// Pad the spacebar row with extra whitespace around `spc` to represent
        /// the physical spacebar width (matching jtroo's canonical formatting).
        private static func padSpacebarRow(_ tokens: [String], spcTokenIndex: Int) -> String {
            let width = tokens.map(\.count).max() ?? 0
            let spacePad = String(repeating: " ", count: width * 2 + 2)
            var result: [String] = []
            for (i, token) in tokens.enumerated() {
                let padded = token.padding(toLength: width, withPad: " ", startingAt: 0)
                if i == spcTokenIndex {
                    result.append(spacePad + padded + spacePad)
                } else {
                    result.append(padded)
                }
            }
            return result.joined(separator: " ")
        }
    }
}
