import KeyPathCore
import SwiftUI

#if os(macOS)
    import AppKit
#endif

// MARK: - Animated Keyboard Transform Grid (with magic move)

struct TransformDisplayKey: Identifiable, Hashable {
    let keyCode: UInt16
    let canonical: String
    let label: String
    var id: UInt16 { keyCode }
}

/// A keyboard visualization where symbols animate ("magic move") between positions
/// when switching presets. Symbols are rendered in an overlay layer and animate
/// to their target keycap positions, creating a playful shuffling effect.
struct AnimatedKeyboardTransformGrid: View {
    let mappings: [KeyMapping]
    var namespace: Namespace.ID
    var enableAnimation: Bool = false // Only animate after user interaction
    @AppStorage(KeymapPreferences.keymapIdKey) private var selectedKeymapId: String = LogicalKeymap.defaultId
    @AppStorage(KeymapPreferences.includePunctuationStoreKey) private var includePunctuationStore: String = "{}"

    private static let keyboardRowKeyCodes: [[UInt16]] = [
        [18, 19, 20, 21, 23, 22, 26, 28, 25, 29],
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

    private var keyboardRows: [[TransformDisplayKey]] {
        Self.keyboardRowKeyCodes.map { row in
            row.map(displayKey(for:))
        }
    }

    private var allKeys: [TransformDisplayKey] {
        keyboardRows.flatMap { $0 }
    }

    private func displayKey(for keyCode: UInt16) -> TransformDisplayKey {
        let canonical = OverlayKeyboardView.keyCodeToKanataName(keyCode).lowercased()
        let fallback: [String: String] = [
            "minus": "-",
            "equal": "=",
            "semicolon": ";",
            "comma": ",",
            "dot": ".",
            "slash": "/"
        ]
        let label = activeKeymap.label(for: keyCode, includeExtraKeys: includePunctuation)
            ?? fallback[canonical]
            ?? canonical
        return TransformDisplayKey(keyCode: keyCode, canonical: canonical, label: label)
    }

    private func keycapLabel(_ label: String) -> String {
        label.count == 1 ? label.uppercased() : label
    }

    private func outputFor(_ canonicalInput: String) -> String? {
        mappings.first { $0.input.lowercased() == canonicalInput.lowercased() }?.description
    }

    /// Get all unique symbols and their target key positions
    private var symbolPositions: [(symbol: String, keyIndex: Int)] {
        var result: [(String, Int)] = []
        for (index, key) in allKeys.enumerated() {
            if let symbol = outputFor(key.canonical) {
                result.append((symbol, index))
            }
        }
        return result
    }

    var body: some View {
        let _ = symbolPositions // Keep computed for future layout tuning
        VStack(spacing: 8) {
            HStack(alignment: .center, spacing: 16) {
                // Input keyboard (static)
                InputKeyboardGrid(
                    keyboardRows: keyboardRows,
                    outputFor: outputFor,
                    keycapLabel: keycapLabel
                )

                // Arrow
                Image(systemName: "arrow.right")
                    .font(.title3)
                    .foregroundColor(.secondary)

                // Output keyboard with animated symbols overlay
                OutputKeyboardWithAnimatedSymbols(
                    keyboardRows: keyboardRows,
                    mappings: mappings,
                    namespace: namespace,
                    enableAnimation: enableAnimation,
                    keycapLabel: keycapLabel
                )
            }

            // Physical position note
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

// MARK: - Input Keyboard Grid (static)

struct InputKeyboardGrid: View {
    let keyboardRows: [[TransformDisplayKey]]
    let outputFor: (String) -> String?
    let keycapLabel: (String) -> String

    var body: some View {
        VStack(alignment: .leading, spacing: 2) {
            Text("Physical Position")
                .font(.caption2)
                .foregroundColor(.secondary)
                .padding(.bottom, 2)

            ForEach(keyboardRows.indices, id: \.self) { rowIndex in
                let row = keyboardRows[rowIndex]
                HStack(spacing: 3) {
                    // Keyboard stagger: number=0, qwerty=0, home=8, bottom=16
                    if rowIndex == 2 { Spacer().frame(width: 8) } else if rowIndex == 3 { Spacer().frame(width: 16) }

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
    }
}

// MARK: - Output Keyboard with Animated Symbols

/// The output keyboard renders keycap backgrounds, then overlays animated symbols.
/// Symbols track their target position and animate when it changes.
struct OutputKeyboardWithAnimatedSymbols: View {
    let keyboardRows: [[TransformDisplayKey]]
    let mappings: [KeyMapping]
    var namespace: Namespace.ID
    var enableAnimation: Bool = false // Only animate after user interaction
    let keycapLabel: (String) -> String

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
           let frame = keycapFrames[targetKey]
        {
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
                    ForEach(keyboardRows.indices, id: \.self) { rowIndex in
                        let row = keyboardRows[rowIndex]
                        HStack(spacing: 3) {
                            // Keyboard stagger: number=0, qwerty=0, home=8, bottom=16
                            if rowIndex == 2 { Spacer().frame(width: 8) } else if rowIndex == 3 { Spacer().frame(width: 16) }

                            ForEach(row) { key in
                                let hasMapping = outputFor(key.canonical) != nil
                                KeycapSlot(
                                    key: key.canonical,
                                    displayLabel: keycapLabel(key.label),
                                    hasMapping: hasMapping
                                )
                                .background(
                                    GeometryReader { geo in
                                        Color.clear.preference(
                                            key: KeycapFramePreference.self,
                                            value: [key.canonical: geo.frame(in: .named("outputKeyboard"))]
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
    let displayLabel: String
    let hasMapping: Bool

    var body: some View {
        ZStack {
            RoundedRectangle(cornerRadius: 4)
                .fill(hasMapping ? Color.accentColor.opacity(0.15) : Color(NSColor.controlBackgroundColor))
            RoundedRectangle(cornerRadius: 4)
                .stroke(hasMapping ? Color.accentColor.opacity(0.5) : Color.secondary.opacity(0.2), lineWidth: 1)

            // Show key label only if no mapping (symbols rendered in overlay)
            if !hasMapping {
                Text(displayLabel)
                    .font(.caption.monospaced())
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
            .font(.caption.monospaced().weight(.semibold))
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

// MARK: - Keycap Frame Preference Key

struct KeycapFramePreference: PreferenceKey {
    nonisolated(unsafe) static var defaultValue: [String: CGRect] = [:]
    static func reduce(value: inout [String: CGRect], nextValue: () -> [String: CGRect]) {
        value.merge(nextValue()) { $1 }
    }
}
