import KeyPathCore
import SwiftUI

#if os(macOS)
    import AppKit
#endif

// MARK: - Keyboard Transform Grid (Input -> Output) - Static version

struct KeyboardTransformGrid: View {
    let mappings: [KeyMapping]

    /// Standard QWERTY layout rows (letters only for cleaner display)
    private static let keyboardRows: [[String]] = [
        ["q", "w", "e", "r", "t", "y", "u", "i", "o", "p"],
        ["a", "s", "d", "f", "g", "h", "j", "k", "l", ";"],
        ["z", "x", "c", "v", "b", "n", "m", ",", ".", "/"]
    ]

    private func outputFor(_ input: String) -> String? {
        mappings.first { $0.input.lowercased() == input.lowercased() }?.description
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

                    ForEach(Array(Self.keyboardRows.enumerated()), id: \.offset) { rowIndex, row in
                        HStack(spacing: 3) {
                            // Stagger for realistic keyboard look
                            if rowIndex == 1 {
                                Spacer().frame(width: 8)
                            } else if rowIndex == 2 {
                                Spacer().frame(width: 16)
                            }

                            ForEach(row, id: \.self) { key in
                                let hasMapping = outputFor(key) != nil
                                TransformKeycap(
                                    label: key.uppercased(),
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

                    ForEach(Array(Self.keyboardRows.enumerated()), id: \.offset) { rowIndex, row in
                        HStack(spacing: 3) {
                            // Match stagger
                            if rowIndex == 1 {
                                Spacer().frame(width: 8)
                            } else if rowIndex == 2 {
                                Spacer().frame(width: 16)
                            }

                            ForEach(row, id: \.self) { key in
                                let output = outputFor(key)
                                TransformKeycap(
                                    label: output ?? key.uppercased(),
                                    isHighlighted: output != nil,
                                    isInput: false
                                )
                            }
                        }
                    }
                }
            }

            // Physical position note for alternative layout users
            Text("Keys labeled by physical position (QWERTY). Works with any keyboard layout.")
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
