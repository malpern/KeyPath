import KeyPathCore
import SwiftUI

#if os(macOS)
    import AppKit
#endif

// MARK: - Numpad Transform Grid (specialized for numpad layout)

struct NumpadTransformGrid: View {
    let mappings: [KeyMapping]
    @AppStorage(KeymapPreferences.keymapIdKey) private var selectedKeymapId: String = LogicalKeymap.defaultId
    @AppStorage(KeymapPreferences.includePunctuationStoreKey) private var includePunctuationStore: String = "{}"

    private struct DisplayKey: Identifiable, Hashable {
        let keyCode: UInt16
        let canonical: String
        let label: String
        var id: UInt16 {
            keyCode
        }
    }

    /// Right hand numpad keys by physical position
    private static let numpadKeyCodes: [[UInt16]] = [
        [32, 34, 31], // U I O
        [38, 40, 37], // J K L
        [46, 43, 47] // M , .
    ]

    /// Left hand operator keys by physical position
    private static let operatorKeyCodes: [UInt16] = [0, 1, 2, 3, 5] // A S D F G

    private var activeKeymap: LogicalKeymap {
        LogicalKeymap.find(id: selectedKeymapId) ?? .qwertyUS
    }

    private var includePunctuation: Bool {
        KeymapPreferences.includePunctuation(for: selectedKeymapId, store: includePunctuationStore)
    }

    private var numpadKeys: [[DisplayKey]] {
        Self.numpadKeyCodes.map { row in
            row.map(displayKey(for:))
        }
    }

    private var operatorKeys: [DisplayKey] {
        Self.operatorKeyCodes.map(displayKey(for:))
    }

    private var zeroKey: DisplayKey {
        displayKey(for: 45)
    } // N
    private var decimalKey: DisplayKey {
        displayKey(for: 44)
    } // /

    private func displayKey(for keyCode: UInt16) -> DisplayKey {
        let canonical = OverlayKeyboardView.keyCodeToKanataName(keyCode).lowercased()
        let fallback: [String: String] = [
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
            HStack(alignment: .top, spacing: 24) {
                // Left hand - operators
                VStack(alignment: .leading, spacing: 8) {
                    Text("Left Hand")
                        .font(.caption2)
                        .foregroundColor(.secondary)

                    Text("Operators")
                        .font(.caption.weight(.medium))

                    HStack(spacing: 4) {
                        ForEach(operatorKeys) { key in
                            VStack(spacing: 2) {
                                TransformKeycap(label: keycapLabel(key.label), isHighlighted: true, isInput: true)
                                Image(systemName: "arrow.down")
                                    .font(.caption2)
                                    .foregroundColor(.secondary)
                                TransformKeycap(
                                    label: outputFor(key.canonical) ?? keycapLabel(key.label),
                                    isHighlighted: true,
                                    isInput: false
                                )
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
                            ForEach(numpadKeys, id: \.self) { row in
                                HStack(spacing: 3) {
                                    ForEach(row) { key in
                                        TransformKeycap(label: keycapLabel(key.label), isHighlighted: true, isInput: true)
                                    }
                                }
                            }
                            // Zero row
                            HStack(spacing: 3) {
                                TransformKeycap(label: keycapLabel(zeroKey.label), isHighlighted: true, isInput: true)
                                TransformKeycap(label: keycapLabel(decimalKey.label), isHighlighted: true, isInput: true)
                            }
                        }

                        Image(systemName: "arrow.right")
                            .font(.title3)
                            .foregroundColor(.secondary)

                        // Output side (numpad)
                        VStack(spacing: 3) {
                            ForEach(numpadKeys.indices, id: \.self) { rowIndex in
                                HStack(spacing: 3) {
                                    ForEach(numpadKeys[rowIndex]) { key in
                                        TransformKeycap(
                                            label: outputFor(key.canonical) ?? "?",
                                            isHighlighted: true,
                                            isInput: false
                                        )
                                    }
                                }
                            }
                            // Zero row
                            HStack(spacing: 3) {
                                TransformKeycap(
                                    label: outputFor(zeroKey.canonical) ?? "0",
                                    isHighlighted: true,
                                    isInput: false
                                )
                                TransformKeycap(
                                    label: outputFor(decimalKey.canonical) ?? ".",
                                    isHighlighted: true,
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
        .padding(16)
        .background(
            RoundedRectangle(cornerRadius: 10)
                .fill(Color(NSColor.controlBackgroundColor).opacity(0.5))
        )
    }
}
