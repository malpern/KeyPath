import KeyPathCore
import SwiftUI

#if os(macOS)
    import AppKit
#endif

// MARK: - Animated Keyboard Transform Grid (with magic move)

/// A keyboard visualization where symbols animate ("magic move") between positions
/// when switching presets. Symbols are rendered in an overlay layer and animate
/// to their target keycap positions, creating a playful shuffling effect.
struct AnimatedKeyboardTransformGrid: View {
    let mappings: [KeyMapping]
    var namespace: Namespace.ID
    var enableAnimation: Bool = false // Only animate after user interaction

    /// Standard QWERTY layout rows (including number row for Mirrored preset)
    private static let keyboardRows: [[String]] = [
        ["1", "2", "3", "4", "5", "6", "7", "8", "9", "0"],
        ["q", "w", "e", "r", "t", "y", "u", "i", "o", "p"],
        ["a", "s", "d", "f", "g", "h", "j", "k", "l", ";"],
        ["z", "x", "c", "v", "b", "n", "m", ",", ".", "/"]
    ]

    /// All keys as flat array for position calculation
    private static let allKeys: [String] = keyboardRows.flatMap { $0 }

    private func outputFor(_ input: String) -> String? {
        mappings.first { $0.input.lowercased() == input.lowercased() }?.description
    }

    /// Get all unique symbols and their target key positions
    private var symbolPositions: [(symbol: String, keyIndex: Int)] {
        var result: [(String, Int)] = []
        for (index, key) in Self.allKeys.enumerated() {
            if let symbol = outputFor(key) {
                result.append((symbol, index))
            }
        }
        return result
    }

    var body: some View {
        VStack(spacing: 8) {
            HStack(alignment: .center, spacing: 16) {
                // Input keyboard (static)
                InputKeyboardGrid(keyboardRows: Self.keyboardRows, outputFor: outputFor)

                // Arrow
                Image(systemName: "arrow.right")
                    .font(.title3)
                    .foregroundColor(.secondary)

                // Output keyboard with animated symbols overlay
                OutputKeyboardWithAnimatedSymbols(
                    keyboardRows: Self.keyboardRows,
                    mappings: mappings,
                    namespace: namespace,
                    enableAnimation: enableAnimation
                )
            }

            // Physical position note
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

// MARK: - Input Keyboard Grid (static)

struct InputKeyboardGrid: View {
    let keyboardRows: [[String]]
    let outputFor: (String) -> String?

    var body: some View {
        VStack(alignment: .leading, spacing: 2) {
            Text("Physical Position")
                .font(.caption2)
                .foregroundColor(.secondary)
                .padding(.bottom, 2)

            ForEach(Array(keyboardRows.enumerated()), id: \.offset) { rowIndex, row in
                HStack(spacing: 3) {
                    // Keyboard stagger: number=0, qwerty=0, home=8, bottom=16
                    if rowIndex == 2 { Spacer().frame(width: 8) } else if rowIndex == 3 { Spacer().frame(width: 16) }

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
    }
}

// MARK: - Output Keyboard with Animated Symbols

/// The output keyboard renders keycap backgrounds, then overlays animated symbols.
/// Symbols track their target position and animate when it changes.
struct OutputKeyboardWithAnimatedSymbols: View {
    let keyboardRows: [[String]]
    let mappings: [KeyMapping]
    var namespace: Namespace.ID
    var enableAnimation: Bool = false // Only animate after user interaction

    /// Track keycap positions using preference key
    @State private var keycapFrames: [String: CGRect] = [:]

    private func outputFor(_ input: String) -> String? {
        mappings.first { $0.input.lowercased() == input.lowercased() }?.description
    }

    /// Build symbol -> target key mapping
    private var symbolTargets: [String: String] {
        var result: [String: String] = [:]
        for mapping in mappings {
            if let desc = mapping.description {
                result[desc] = mapping.input.lowercased()
            }
        }
        return result
    }

    /// All unique symbols across all possible presets (so they persist between changes)
    private static let allSymbols = [
        "!", "@", "#", "$", "%", "^", "&", "*", "(", ")",
        "~", "`", "-", "=", "+", "[", "]", "{", "}", "|",
        "\\", "_", "/", "?", "'", "\"", ":", ";", "<", ">"
    ]

    /// Default "parking" position for symbols not in current mapping
    /// Places them off the bottom of the keyboard area
    private var parkingFrame: CGRect {
        CGRect(x: 100, y: -50, width: 22, height: 22)
    }

    /// Get the target frame for a symbol - either its mapped key position or the parking area
    private func targetFrameFor(_ symbol: String) -> CGRect {
        if let targetKey = symbolTargets[symbol],
           let frame = keycapFrames[targetKey] {
            return frame
        }
        return parkingFrame
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 2) {
            Text("Becomes")
                .font(.caption2)
                .foregroundColor(.secondary)
                .padding(.bottom, 2)

            // Keycap slots + symbol overlay
            ZStack(alignment: .topLeading) {
                // Layer 1: Keycap backgrounds (stable slots)
                VStack(alignment: .leading, spacing: 2) {
                    ForEach(Array(keyboardRows.enumerated()), id: \.offset) { rowIndex, row in
                        HStack(spacing: 3) {
                            // Keyboard stagger: number=0, qwerty=0, home=8, bottom=16
                            if rowIndex == 2 { Spacer().frame(width: 8) } else if rowIndex == 3 { Spacer().frame(width: 16) }

                            ForEach(row, id: \.self) { key in
                                let hasMapping = outputFor(key) != nil
                                KeycapSlot(key: key, hasMapping: hasMapping)
                                    .background(
                                        GeometryReader { geo in
                                            Color.clear.preference(
                                                key: KeycapFramePreference.self,
                                                value: [key: geo.frame(in: .named("outputKeyboard"))]
                                            )
                                        }
                                    )
                            }
                        }
                    }
                }

                // Layer 2: Animated symbols (floating overlay)
                // IMPORTANT: Always render ALL symbols to enable animation.
                // Symbols not in current mapping are hidden but still present in view tree.
                ForEach(Self.allSymbols, id: \.self) { symbol in
                    FloatingSymbol(
                        symbol: symbol,
                        targetFrame: targetFrameFor(symbol),
                        isVisible: symbolTargets[symbol] != nil,
                        namespace: namespace,
                        enableAnimation: enableAnimation
                    )
                }
            }
            .coordinateSpace(name: "outputKeyboard")
            .onPreferenceChange(KeycapFramePreference.self) { frames in
                keycapFrames = frames
            }
        }
    }
}

// MARK: - Keycap Slot (empty background)

struct KeycapSlot: View {
    let key: String
    let hasMapping: Bool

    var body: some View {
        ZStack {
            RoundedRectangle(cornerRadius: 4)
                .fill(hasMapping ? Color.accentColor.opacity(0.15) : Color(NSColor.controlBackgroundColor))
            RoundedRectangle(cornerRadius: 4)
                .stroke(hasMapping ? Color.accentColor.opacity(0.5) : Color.secondary.opacity(0.2), lineWidth: 1)

            // Show key label only if no mapping (symbols rendered in overlay)
            if !hasMapping {
                Text(key.uppercased())
                    .font(.system(size: 11, weight: .regular, design: .monospaced))
                    .foregroundColor(.secondary)
            }
        }
        .frame(width: 22, height: 22)
    }
}

// MARK: - Floating Symbol (animates to target position)

/// A symbol that floats above the keyboard and animates to its target keycap.
/// Each symbol has randomized spring parameters for a playful shuffling effect.
/// Symbols not in the current mapping are hidden but remain in the view tree for animation.
struct FloatingSymbol: View {
    let symbol: String
    let targetFrame: CGRect
    let isVisible: Bool
    var namespace: Namespace.ID
    var enableAnimation: Bool = false // Only animate after user interaction

    /// Randomized animation parameters (seeded by symbol for consistency)
    private var springResponse: Double {
        0.3 + Double(abs(symbol.hashValue) % 100) / 500.0 // 0.30-0.50s
    }

    private var dampingFraction: Double {
        0.6 + Double(abs(symbol.hashValue >> 8) % 100) / 500.0 // 0.60-0.80
    }

    private var wobbleAngle: Double {
        Double(abs(symbol.hashValue >> 16) % 25) - 12.0 // -12° to +12°
    }

    /// Animation to use - nil when disabled (prevents "rain down" on view appear)
    private var positionAnimation: Animation? {
        enableAnimation ? .spring(response: springResponse, dampingFraction: dampingFraction) : nil
    }

    @State private var rotation: Angle = .zero
    @State private var scale: CGFloat = 1.0
    @State private var wasVisible: Bool = false

    var body: some View {
        Text(symbol)
            .font(.system(size: 11, weight: .semibold, design: .monospaced))
            .foregroundColor(.accentColor)
            .frame(width: 22, height: 22)
            .scaleEffect(scale)
            .rotationEffect(rotation)
            .opacity(isVisible ? 1.0 : 0.0)
            .position(x: targetFrame.midX, y: targetFrame.midY)
            .animation(positionAnimation, value: targetFrame)
            .animation(positionAnimation, value: isVisible)
            .onChange(of: targetFrame) { _, _ in
                if isVisible, enableAnimation {
                    triggerWobble()
                }
            }
            .onChange(of: isVisible) { _, newVisible in
                if newVisible, !wasVisible, enableAnimation {
                    // Symbol just became visible - trigger entrance wobble
                    triggerWobble()
                }
                wasVisible = newVisible
            }
    }

    private func triggerWobble() {
        rotation = .degrees(wobbleAngle)
        scale = 1.15
        withAnimation(.spring(response: springResponse, dampingFraction: dampingFraction)) {
            rotation = .zero
            scale = 1.0
        }
    }
}

// MARK: - Inset Back Plane

/// A container that creates an inset "back plane" effect for expanded content.
/// Uses an inner shadow and subtle gradient to create depth.
struct InsetBackPlane<Content: View>: View {
    @ViewBuilder let content: Content

    var body: some View {
        content
            .padding(.horizontal, 8)
            .padding(.vertical, 4)
            .background(
                RoundedRectangle(cornerRadius: 8)
                    .fill(Color(NSColor.windowBackgroundColor).opacity(0.6))
                    .overlay(
                        RoundedRectangle(cornerRadius: 8)
                            .strokeBorder(
                                LinearGradient(
                                    colors: [
                                        Color.black.opacity(0.15),
                                        Color.clear,
                                        Color.white.opacity(0.05)
                                    ],
                                    startPoint: .top,
                                    endPoint: .bottom
                                ),
                                lineWidth: 1
                            )
                    )
                    .shadow(color: Color.black.opacity(0.1), radius: 2, x: 0, y: 1)
            )
            .padding(.horizontal, 12)
            .padding(.top, 4)
            .padding(.bottom, 8)
    }
}

// MARK: - Keycap Frame Preference Key

struct KeycapFramePreference: PreferenceKey {
    nonisolated(unsafe) static var defaultValue: [String: CGRect] = [:]
    static func reduce(value: inout [String: CGRect], nextValue: () -> [String: CGRect]) {
        value.merge(nextValue()) { $1 }
    }
}

// MARK: - Keyboard Transform Grid (Input → Output) - Static version

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

// MARK: - Transform Keycap

struct TransformKeycap: View {
    let label: String
    let isHighlighted: Bool
    let isInput: Bool

    var body: some View {
        Text(label)
            .font(.system(size: 11, weight: isHighlighted ? .semibold : .regular, design: .monospaced))
            .frame(width: 22, height: 22)
            .foregroundColor(isHighlighted ? (isInput ? .primary : .accentColor) : .secondary)
            .background(
                RoundedRectangle(cornerRadius: 4)
                    .fill(isHighlighted && !isInput ? Color.accentColor.opacity(0.15) : Color(NSColor.controlBackgroundColor))
            )
            .overlay(
                RoundedRectangle(cornerRadius: 4)
                    .stroke(isHighlighted ? (isInput ? Color.primary.opacity(0.3) : Color.accentColor.opacity(0.5)) : Color.secondary.opacity(0.2), lineWidth: 1)
            )
    }
}

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
