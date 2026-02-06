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

        /// Render entries grouped into physical rows; rows without entries are skipped.
        private static func renderGridLines(
            _ entries: [LayerEntry],
            valueProvider: (LayerEntry) -> String
        ) -> [String] {
            var rows: [[String]] = []
            var remaining = entries

            for layoutRow in layoutRows {
                var tokens: [String] = []
                for key in layoutRow {
                    if let idx = remaining.firstIndex(where: { $0.sourceKey == key }) {
                        let entry = remaining.remove(at: idx)
                        tokens.append(valueProvider(entry))
                    }
                }
                if !tokens.isEmpty {
                    rows.append(tokens)
                }
            }

            // Anything not in the known layout gets appended in a trailing row
            if !remaining.isEmpty {
                rows.append(remaining.map { valueProvider($0) })
            }

            return rows.map { "  " + padRow($0) }
        }

        private static func padRow(_ tokens: [String]) -> String {
            let width = tokens.map(\.count).max() ?? 0
            let padded = tokens.map { token in
                token.padding(toLength: width, withPad: " ", startingAt: 0)
            }
            return padded.joined(separator: " ")
        }
    }
}
