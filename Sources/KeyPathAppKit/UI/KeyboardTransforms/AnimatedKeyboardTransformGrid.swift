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
    let x: Double
    let y: Double
    var id: UInt16 {
        keyCode
    }
}

struct TransformRowModel: Identifiable, Hashable {
    let id: Int
    let keys: [TransformDisplayKey]
    let indent: CGFloat
}

/// A keyboard visualization where symbols animate ("magic move") between positions
/// when switching presets. Symbols are rendered in an overlay layer and animate
/// to their target keycap positions, creating a playful shuffling effect.
struct AnimatedKeyboardTransformGrid: View {
    let mappings: [KeyMapping]
    var namespace: Namespace.ID
    var enableAnimation: Bool = false // Only animate after user interaction
    @AppStorage(LayoutPreferences.layoutIdKey) private var selectedLayoutId: String = LayoutPreferences.defaultLayoutId
    @AppStorage(KeymapPreferences.keymapIdKey) private var selectedKeymapId: String = LogicalKeymap.defaultId
    @AppStorage(KeymapPreferences.includePunctuationStoreKey) private var includePunctuationStore: String = "{}"

    private var activeKeymap: LogicalKeymap {
        .resolve(id: selectedKeymapId)
    }

    private var activeLayout: PhysicalLayout {
        PhysicalLayout.find(id: selectedLayoutId) ?? .macBookUS
    }

    private var includePunctuation: Bool {
        KeymapPreferences.includePunctuation(for: selectedKeymapId, store: includePunctuationStore)
    }

    private var keyboardRows: [TransformRowModel] {
        let desiredKeys: Set<String> = [
            "1", "2", "3", "4", "5", "6", "7", "8", "9", "0",
            "q", "w", "e", "r", "t", "y", "u", "i", "o", "p",
            "a", "s", "d", "f", "g", "h", "j", "k", "l", "semicolon",
            "z", "x", "c", "v", "b", "n", "m", "comma", "dot", "slash"
        ]

        let keys = activeLayout.keys.compactMap { key -> TransformDisplayKey? in
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
            return TransformRowModel(
                id: index,
                keys: row,
                indent: CGFloat(max(0, rowMinX - minRowX)) * keyPitch
            )
        }
    }

    private var allKeys: [TransformDisplayKey] {
        keyboardRows.flatMap(\.keys)
    }

    private func displayKey(for key: PhysicalKey, canonical: String) -> TransformDisplayKey {
        let fallback: [String: String] = [
            "minus": "-",
            "equal": "=",
            "semicolon": ";",
            "comma": ",",
            "dot": ".",
            "slash": "/"
        ]
        let label = activeKeymap.label(for: key.keyCode, includeExtraKeys: includePunctuation)
            ?? fallback[canonical]
            ?? canonical
        return TransformDisplayKey(
            keyCode: key.keyCode,
            canonical: canonical,
            label: label,
            x: key.visualX,
            y: key.visualY
        )
    }

    private func groupKeysIntoRows(_ keys: [TransformDisplayKey]) -> [[TransformDisplayKey]] {
        let sorted = keys.sorted {
            if abs($0.y - $1.y) > 0.01 {
                return $0.y < $1.y
            }
            return $0.x < $1.x
        }

        let rowThreshold = 0.6
        var rows: [[TransformDisplayKey]] = []
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
    let keyboardRows: [TransformRowModel]
    let outputFor: (String) -> String?
    let keycapLabel: (String) -> String

    var body: some View {
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
    }
}

// MARK: - Output Keyboard with Animated Symbols

/// The output keyboard renders keycap backgrounds, then overlays animated symbols.
/// Symbols track their target position and animate when it changes.
struct OutputKeyboardWithAnimatedSymbols: View {
    let keyboardRows: [TransformRowModel]
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
                    ForEach(keyboardRows) { row in
                        HStack(spacing: 3) {
                            Spacer().frame(width: row.indent)

                            ForEach(row.keys) { key in
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

struct KeycapFramePreference: @preconcurrency PreferenceKey {
    @MainActor static var defaultValue: [String: CGRect] = [:]
    static func reduce(value: inout [String: CGRect], nextValue: () -> [String: CGRect]) {
        value.merge(nextValue()) { $1 }
    }
}
