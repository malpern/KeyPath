import KeyPathCore
import SwiftUI

#if os(macOS)
    import AppKit
#endif

// MARK: - Numpad Transform Grid (specialized for numpad layout)

struct NumpadTransformGrid: View {
    let mappings: [KeyMapping]

    /// Right hand numpad keys
    private static let numpadKeys: [[String]] = [
        ["u", "i", "o"],
        ["j", "k", "l"],
        ["m", ",", "."]
    ]

    /// Left hand operator keys
    private static let operatorKeys: [String] = ["a", "s", "d", "f", "g"]

    private func outputFor(_ input: String) -> String? {
        mappings.first { $0.input.lowercased() == input.lowercased() }?.description
    }

    var body: some View {
        VStack(spacing: 8) {
            HStack(alignment: .top, spacing: 24) {
                // Left hand - operators
                VStack(alignment: .leading, spacing: 8) {
                    Text("Left Hand")
                        .font(.caption2)
                        .foregroundColor(.secondary)

                    Text("Operators")
                        .font(.caption.weight(.medium))

                    HStack(spacing: 4) {
                        ForEach(Self.operatorKeys, id: \.self) { key in
                            VStack(spacing: 2) {
                                TransformKeycap(label: key.uppercased(), isHighlighted: true, isInput: true)
                                Image(systemName: "arrow.down")
                                    .font(.system(size: 8))
                                    .foregroundColor(.secondary)
                                TransformKeycap(label: outputFor(key) ?? key, isHighlighted: true, isInput: false)
                            }
                        }
                    }
                }

                Divider()
                    .frame(height: 100)

                // Right hand - numpad
                VStack(alignment: .leading, spacing: 8) {
                    Text("Right Hand")
                        .font(.caption2)
                        .foregroundColor(.secondary)

                    HStack(alignment: .center, spacing: 12) {
                        // Input side
                        VStack(spacing: 3) {
                            ForEach(Self.numpadKeys, id: \.self) { row in
                                HStack(spacing: 3) {
                                    ForEach(row, id: \.self) { key in
                                        TransformKeycap(label: key.uppercased(), isHighlighted: true, isInput: true)
                                    }
                                }
                            }
                            // Zero row
                            HStack(spacing: 3) {
                                TransformKeycap(label: "N", isHighlighted: true, isInput: true)
                                TransformKeycap(label: "/", isHighlighted: true, isInput: true)
                            }
                        }

                        Image(systemName: "arrow.right")
                            .font(.title3)
                            .foregroundColor(.secondary)

                        // Output side (numpad)
                        VStack(spacing: 3) {
                            ForEach(Array(Self.numpadKeys.enumerated()), id: \.offset) { _, row in
                                HStack(spacing: 3) {
                                    ForEach(row, id: \.self) { key in
                                        TransformKeycap(label: outputFor(key) ?? "?", isHighlighted: true, isInput: false)
                                    }
                                }
                            }
                            // Zero row
                            HStack(spacing: 3) {
                                TransformKeycap(label: outputFor("n") ?? "0", isHighlighted: true, isInput: false)
                                TransformKeycap(label: outputFor("/") ?? ".", isHighlighted: true, isInput: false)
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
        .padding(16)
        .background(
            RoundedRectangle(cornerRadius: 10)
                .fill(Color(NSColor.controlBackgroundColor).opacity(0.5))
        )
    }
}
