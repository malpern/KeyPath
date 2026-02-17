import KeyPathCore
import SwiftUI

#if os(macOS)
    import AppKit
#endif

// MARK: - Keyboard Transform Grid (Input -> Output) - Static version

struct KeyboardTransformGrid: View {
    let mappings: [KeyMapping]
    @AppStorage(KeymapPreferences.keymapIdKey) private var selectedKeymapId: String = LogicalKeymap.defaultId
    @AppStorage(KeymapPreferences.includePunctuationStoreKey) private var includePunctuationStore: String = "{}"

    private struct DisplayKey: Identifiable {
        let keyCode: UInt16
        let canonical: String
        let label: String
        var id: UInt16 { keyCode }
    }

    private static let keyboardRowKeyCodes: [[UInt16]] = [
        [12, 13, 14, 15, 17, 16, 32, 34, 31, 35],
        [0, 1, 2, 3, 5, 4, 38, 40, 37, 41],
        [6, 7, 8, 9, 11, 45, 46, 43, 47, 44]
    ]

    private var activeKeymap: LogicalKeymap {
        LogicalKeymap.find(id: selectedKeymapId) ?? .qwertyUS
    }

    private var includePunctuation: Bool {
        KeymapPreferences.includePunctuation(for: selectedKeymapId, store: includePunctuationStore)
    }

    private var keyboardRows: [[DisplayKey]] {
        Self.keyboardRowKeyCodes.map { row in
            row.map(displayKey(for:))
        }
    }

    private func displayKey(for keyCode: UInt16) -> DisplayKey {
        let canonical = OverlayKeyboardView.keyCodeToKanataName(keyCode).lowercased()
        let fallback: [String: String] = [
            "semicolon": ";",
            "comma": ",",
            "dot": ".",
            "slash": "/"
        ]
        let label = activeKeymap.label(for: keyCode, includeExtraKeys: includePunctuation)
            ?? fallback[canonical]
            ?? canonical
        return DisplayKey(keyCode: keyCode, canonical: canonical, label: label)
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

                    ForEach(keyboardRows.indices, id: \.self) { rowIndex in
                        let row = keyboardRows[rowIndex]
                        HStack(spacing: 3) {
                            // Stagger for realistic keyboard look
                            if rowIndex == 1 {
                                Spacer().frame(width: 8)
                            } else if rowIndex == 2 {
                                Spacer().frame(width: 16)
                            }

                            ForEach(row) { key in
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

                    ForEach(keyboardRows.indices, id: \.self) { rowIndex in
                        let row = keyboardRows[rowIndex]
                        HStack(spacing: 3) {
                            // Match stagger
                            if rowIndex == 1 {
                                Spacer().frame(width: 8)
                            } else if rowIndex == 2 {
                                Spacer().frame(width: 16)
                            }

                            ForEach(row) { key in
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
