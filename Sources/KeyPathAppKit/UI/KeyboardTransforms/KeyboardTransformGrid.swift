import KeyPathCore
import SwiftUI

#if os(macOS)
    import AppKit
#endif

// MARK: - Keyboard Transform Grid (Input -> Output) - Static version

struct KeyboardTransformGrid: View {
    let mappings: [KeyMapping]
    @AppStorage(LayoutPreferences.layoutIdKey) private var selectedLayoutId: String = LayoutPreferences.defaultLayoutId
    @AppStorage(KeymapPreferences.keymapIdKey) private var selectedKeymapId: String = LogicalKeymap.defaultId
    @AppStorage(KeymapPreferences.includePunctuationStoreKey) private var includePunctuationStore: String = "{}"

    private struct DisplayKey: Identifiable {
        let keyCode: UInt16
        let canonical: String
        let label: String
        let x: Double
        let y: Double
        var id: UInt16 {
            keyCode
        }
    }

    private struct RowModel: Identifiable {
        let id: Int
        let keys: [DisplayKey]
        let indent: CGFloat
    }

    private var activeKeymap: LogicalKeymap {
        LogicalKeymap.find(id: selectedKeymapId) ?? .qwertyUS
    }

    private var activeLayout: PhysicalLayout {
        PhysicalLayout.find(id: selectedLayoutId) ?? .macBookUS
    }

    private var includePunctuation: Bool {
        KeymapPreferences.includePunctuation(for: selectedKeymapId, store: includePunctuationStore)
    }

    private var keyboardRows: [RowModel] {
        let desiredKeys: Set<String> = [
            "q", "w", "e", "r", "t", "y", "u", "i", "o", "p",
            "a", "s", "d", "f", "g", "h", "j", "k", "l", "semicolon",
            "z", "x", "c", "v", "b", "n", "m", "comma", "dot", "slash"
        ]

        let keys = activeLayout.keys.compactMap { key -> DisplayKey? in
            guard key.keyCode != PhysicalKey.unmappedKeyCode else { return nil }
            let canonical = OverlayKeyboardView.keyCodeToKanataName(key.keyCode).lowercased()
            guard desiredKeys.contains(canonical) else { return nil }
            return displayKey(for: key, canonical: canonical)
        }

        let grouped = groupKeysIntoRows(keys)
        let minRowX = grouped
            .compactMap { $0.first?.x }
            .min() ?? 0
        let keyPitch: CGFloat = 25

        return grouped.enumerated().map { index, row in
            let rowMinX = row.first?.x ?? minRowX
            return RowModel(
                id: index,
                keys: row,
                indent: CGFloat(max(0, rowMinX - minRowX)) * keyPitch
            )
        }
    }

    private func displayKey(for key: PhysicalKey, canonical: String) -> DisplayKey {
        let fallback: [String: String] = [
            "semicolon": ";",
            "comma": ",",
            "dot": ".",
            "slash": "/"
        ]
        let label = activeKeymap.label(for: key.keyCode, includeExtraKeys: includePunctuation)
            ?? fallback[canonical]
            ?? canonical
        return DisplayKey(
            keyCode: key.keyCode,
            canonical: canonical,
            label: label,
            x: key.visualX,
            y: key.visualY
        )
    }

    private func groupKeysIntoRows(_ keys: [DisplayKey]) -> [[DisplayKey]] {
        let sorted = keys.sorted {
            if abs($0.y - $1.y) > 0.01 {
                return $0.y < $1.y
            }
            return $0.x < $1.x
        }

        let rowThreshold = 0.6
        var rows: [[DisplayKey]] = []
        var rowAnchors: [Double] = []

        for key in sorted {
            if let lastIndex = rowAnchors.indices.last, abs(key.y - rowAnchors[lastIndex]) <= rowThreshold {
                rows[lastIndex].append(key)
            } else {
                rows.append([key])
                rowAnchors.append(key.y)
            }
        }

        return rows
            .map { $0.sorted { $0.x < $1.x } }
            .filter { !$0.isEmpty }
    }

    private func outputFor(_ canonicalInput: String) -> String? {
        mappings.first { $0.input.lowercased() == canonicalInput.lowercased() }?.description
    }

    private func keycapLabel(_ label: String) -> String {
        label.count == 1 ? label.uppercased() : label
    }

    var body: some View {
        VStack(spacing: 8) {
            HStack(alignment: .center, spacing: 16) {
                // Input keyboard
                VStack(alignment: .leading, spacing: 2) {
                    Text("Physical Position")
                        .font(.caption2)
                        .foregroundColor(.secondary)
                        .padding(.bottom, 2)

                    ForEach(keyboardRows) { row in
                        HStack(spacing: 3) {
                            Spacer().frame(width: row.indent)

                            ForEach(row.keys) { key in
                                let hasMapping = outputFor(key.canonical) != nil
                                TransformKeycap(
                                    label: keycapLabel(key.label),
                                    isHighlighted: hasMapping,
                                    isInput: true
                                )
                            }
                        }
                    }
                }

                // Arrow
                Image(systemName: "arrow.right")
                    .font(.title3)
                    .foregroundColor(.secondary)

                // Output keyboard
                VStack(alignment: .leading, spacing: 2) {
                    Text("Becomes")
                        .font(.caption2)
                        .foregroundColor(.secondary)
                        .padding(.bottom, 2)

                    ForEach(keyboardRows) { row in
                        HStack(spacing: 3) {
                            Spacer().frame(width: row.indent)

                            ForEach(row.keys) { key in
                                let output = outputFor(key.canonical)
                                TransformKeycap(
                                    label: output ?? keycapLabel(key.label),
                                    isHighlighted: output != nil,
                                    isInput: false
                                )
                            }
                        }
                    }
                }
            }

            // Physical position note for alternative layout users
            Text("Keys are shown by physical position using the selected keymap labels.")
                .font(.caption2)
                .foregroundStyle(.tertiary)
        }
        .padding(12)
        .background(
            RoundedRectangle(cornerRadius: 10)
                .fill(Color(NSColor.controlBackgroundColor).opacity(0.5))
        )
    }
}
