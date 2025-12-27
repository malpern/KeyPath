import AppKit
import KeyPathCore
import SwiftUI

struct EscKeyLeftInsetPreferenceKey: PreferenceKey {
    static let defaultValue: CGFloat = 0

    static func reduce(value: inout CGFloat, nextValue: () -> CGFloat) {
        value = nextValue()
    }
}

/// Keyboard view for the live overlay.
/// Renders a full keyboard layout with keys highlighting based on key codes.
struct OverlayKeyboardView: View {
    let layout: PhysicalLayout
    let keymap: LogicalKeymap
    let includeKeymapPunctuation: Bool
    let pressedKeyCodes: Set<UInt16>
    var isDarkMode: Bool = false
    var fadeAmount: CGFloat = 0 // 0 = fully visible, 1 = fully faded (global overlay fade)
    var keyFadeAmounts: [UInt16: CGFloat] = [:] // Per-key fade amounts for release animation
    var currentLayerName: String = "base"
    var isLoadingLayerMap: Bool = false
    /// Key mapping for current layer: keyCode -> LayerKeyInfo
    var layerKeyMap: [UInt16: LayerKeyInfo] = [:]
    /// Effective pressed key codes (includes remapped outputs for dual highlighting)
    var effectivePressedKeyCodes: Set<UInt16> = []
    /// Key codes to emphasize (highlight with accent color for layer hints)
    var emphasizedKeyCodes: Set<UInt16> = []
    /// Hold labels for tap-hold keys in hold state: keyCode -> display label
    var holdLabels: [UInt16: String] = [:]
    /// Callback when a key is clicked (not dragged) - for opening Mapper
    var onKeyClick: ((PhysicalKey, LayerKeyInfo?) -> Void)?

    /// Track caps lock state from system
    @State private var isCapsLockOn: Bool = NSEvent.modifierFlags.contains(.capsLock)

    // Note: keycapFrames removed - we now calculate frames directly from layout
    /// Whether initial render is complete (enables animation for subsequent changes)
    /// Set to true asynchronously after onAppear, so the first render positions keys
    /// without animation, but all subsequent keymap changes animate.
    @State private var initialRenderComplete: Bool = false
    /// Previous keymap ID for detecting changes (used for wobble trigger)
    @State private var previousKeymapId: String = ""

    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    /// Selected colorway ID from user preferences
    @AppStorage("overlayColorwayId") private var selectedColorwayId: String = GMKColorway.default.id

    /// The active GMK colorway
    private var activeColorway: GMKColorway {
        GMKColorway.find(id: selectedColorwayId) ?? .default
    }

    /// Size of a standard 1u key in points
    private let keyUnitSize: CGFloat = 32
    /// Gap between keys
    private let keyGap: CGFloat = 2

    /// Build mapping from label → keyCode for the current keymap
    /// Used to determine which keycap a floating label should animate to
    private var labelToKeyCode: [String: UInt16] {
        var result: [String: UInt16] = [:]
        for key in layout.keys {
            let label = keymap.displayLabel(for: key, includeExtraKeys: includeKeymapPunctuation)
            // Use uppercase for consistent matching
            result[label.uppercased()] = key.keyCode
        }
        return result
    }

    /// All labels that can appear on the keyboard (letters + numbers + punctuation)
    private static let allLabels: [String] = {
        // Letters A-Z
        let letters = (65 ... 90).map { String(UnicodeScalar($0)) }
        // Numbers 0-9
        let numbers = (0 ... 9).map { String($0) }
        // Common punctuation
        let punctuation = [";", "'", ",", ".", "/", "[", "]", "\\", "`", "-", "="]
        return letters + numbers + punctuation
    }()

    var body: some View {
        GeometryReader { geometry in
            let scale = calculateScale(for: geometry.size)
            let keys = layout.keys
            let escLeftInset = OverlayKeyboardView.escLeftInset(
                for: layout,
                scale: scale,
                keyUnitSize: keyUnitSize,
                keyGap: keyGap
            )
            ZStack(alignment: .topLeading) {
                // Layer 1: Keycap backgrounds (stable positions)
                ForEach(keys, id: \.id) { key in
                    keyView(key: key, scale: scale)
                }

                // Layer 2: Floating labels (animate between keycap positions)
                // Labels are ALWAYS visible when in current keymap (like the working symbol animation).
                // The enableAnimation flag controls whether position changes animate.
                // Note: frames are calculated directly from layout, no GeometryReader needed.
                // Skip floating labels for non-standard legend styles (dots show circles, not letters)
                if !reduceMotion, activeColorway.legendStyle == .standard {
                    ForEach(Self.allLabels, id: \.self) { label in
                        FloatingKeymapLabel(
                            label: label,
                            targetFrame: targetFrameFor(label, scale: scale),
                            // Visible when label exists in current keymap
                            isVisible: labelToKeyCode[label] != nil,
                            scale: scale,
                            colorway: activeColorway,
                            // Enable animation after initial render (prevents animation on drawer open)
                            enableAnimation: initialRenderComplete
                        )
                    }
                }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .preference(key: EscKeyLeftInsetPreferenceKey.self, value: escLeftInset)
        }
        .aspectRatio(layout.totalWidth / layout.totalHeight, contentMode: .fit)
        .onChange(of: effectivePressedKeyCodes) { _, _ in
            // Update caps lock state when any key changes (captures toggle)
            isCapsLockOn = NSEvent.modifierFlags.contains(.capsLock)
        }
        .onChange(of: keymap.id) { oldValue, newValue in
            guard oldValue != newValue else { return }
            previousKeymapId = newValue
        }
        .onAppear {
            previousKeymapId = keymap.id
            // Enable animation after initial render completes
            // This ensures the first load positions keys without animation,
            // but subsequent keymap changes animate properly
            DispatchQueue.main.async {
                initialRenderComplete = true
            }
        }
    }

    /// Get target frame for a floating label based on current keymap
    /// Calculates frame directly from layout instead of using GeometryReader
    private func targetFrameFor(_ label: String, scale: CGFloat) -> CGRect {
        if let keyCode = labelToKeyCode[label],
           let key = layout.keys.first(where: { $0.keyCode == keyCode }) {
            let width = keyWidth(for: key, scale: scale)
            let height = keyHeight(for: key, scale: scale)
            let centerX = keyPositionX(for: key, scale: scale)
            let centerY = keyPositionY(for: key, scale: scale)
            return CGRect(
                x: centerX - width / 2,
                y: centerY - height / 2,
                width: width,
                height: height
            )
        }
        // Park off-screen if not in current keymap
        return CGRect(x: -100, y: -100, width: 20, height: 20)
    }

    private func keyView(key: PhysicalKey, scale: CGFloat) -> some View {
        // Use TCP KeyInput for physical key detection (no CGEvent fallback)
        // TCP KeyInput shows the physical key pressed, not the remapped output
        // Requires Kanata built from keypath-v1.10.0-base branch
        let isPressed = effectivePressedKeyCodes.contains(key.keyCode)

        if key.keyCode == 57, isPressed || holdLabels[key.keyCode] != nil {
            AppLogger.shared.debug(
                "🧪 [Overlay] keyCode=57 pressed=\(isPressed) holdLabel=\(holdLabels[key.keyCode] ?? "nil") layerLabel=\(layerKeyMap[key.keyCode]?.displayLabel ?? "nil")"
            )
        }

        // Use per-key fade amount if available, otherwise use global fade
        let hasPerKeyFade = keyFadeAmounts[key.keyCode] != nil
        let effectiveFadeAmount = keyFadeAmounts[key.keyCode] ?? fadeAmount
        let baseLabel = keymap.displayLabel(
            for: key,
            includeExtraKeys: includeKeymapPunctuation
        )

        return OverlayKeycapView(
            key: key,
            baseLabel: baseLabel,
            isPressed: isPressed,
            scale: scale,
            isDarkMode: isDarkMode,
            isCapsLockOn: isCapsLockOn,
            fadeAmount: effectiveFadeAmount,
            isReleaseFading: hasPerKeyFade,
            currentLayerName: currentLayerName,
            isLoadingLayerMap: isLoadingLayerMap,
            layerKeyInfo: layerKeyMap[key.keyCode],
            isEmphasized: emphasizedKeyCodes.contains(key.keyCode),
            holdLabel: holdLabels[key.keyCode],
            onKeyClick: onKeyClick,
            colorway: activeColorway,
            // Pass layout width for rainbow gradient calculation
            layoutTotalWidth: layout.totalWidth,
            // Hide keycap alpha labels when floating labels are rendered
            // (floating labels handle animation, keycaps just show backgrounds)
            // Disable floating labels for non-standard legend styles (dots, blank, etc.)
            useFloatingLabels: !reduceMotion && activeColorway.legendStyle == .standard,
            // Kinesis keyboards have scooped/dished home row keys
            showScoopedHomeRow: layout.id == "kinesis-360"
        )
        .frame(
            width: keyWidth(for: key, scale: scale),
            height: keyHeight(for: key, scale: scale)
        )
        .rotationEffect(.degrees(key.rotation))
        .position(
            x: keyPositionX(for: key, scale: scale),
            y: keyPositionY(for: key, scale: scale)
        )
    }

    // MARK: - Layout Calculations

    private func calculateScale(for size: CGSize) -> CGFloat {
        let widthScale = size.width / (layout.totalWidth * (keyUnitSize + keyGap))
        let heightScale = size.height / (layout.totalHeight * (keyUnitSize + keyGap))
        return min(widthScale, heightScale)
    }

    private func keyWidth(for key: PhysicalKey, scale: CGFloat) -> CGFloat {
        (key.width * keyUnitSize + (key.width - 1) * keyGap) * scale
    }

    private func keyHeight(for key: PhysicalKey, scale: CGFloat) -> CGFloat {
        (key.height * keyUnitSize + (key.height - 1) * keyGap) * scale
    }

    private func keyPositionX(for key: PhysicalKey, scale: CGFloat) -> CGFloat {
        // Use visualX which applies rotation transform for ergonomic keyboards
        let baseX = key.visualX * (keyUnitSize + keyGap) * scale
        let halfWidth = keyWidth(for: key, scale: scale) / 2
        return baseX + halfWidth + keyGap * scale
    }

    private func keyPositionY(for key: PhysicalKey, scale: CGFloat) -> CGFloat {
        // Use visualY which applies rotation transform for ergonomic keyboards
        let baseY = key.visualY * (keyUnitSize + keyGap) * scale
        let halfHeight = keyHeight(for: key, scale: scale) / 2
        return baseY + halfHeight + keyGap * scale
    }

    static func escLeftInset(
        for layout: PhysicalLayout,
        scale: CGFloat,
        keyUnitSize: CGFloat = 32,
        keyGap: CGFloat = 2
    ) -> CGFloat {
        guard let escKey = layout.keys.first(where: { $0.keyCode == 53 }) else {
            return keyGap * scale
        }

        let keyWidth = (escKey.width * keyUnitSize + (escKey.width - 1) * keyGap) * scale
        let baseX = escKey.x * (keyUnitSize + keyGap) * scale
        let halfWidth = keyWidth / 2
        let positionX = baseX + halfWidth + keyGap * scale
        let leftEdge = positionX - halfWidth
        return max(0, leftEdge)
    }

    // MARK: - Key Code to Kanata Name Mapping

    /// Maps CGEvent key codes to OsCode Display names (lowercase).
    /// These match what Kanata sends via TCP KeyInput events: OsCode.to_string().to_lowercase()
    nonisolated static func keyCodeToKanataName(_ keyCode: UInt16) -> String {
        switch keyCode {
        // Row 3: Home row (ASDF...)
        case 0: "a"
        case 1: "s"
        case 2: "d"
        case 3: "f"
        case 4: "h"
        case 5: "g"
        // Row 4: Bottom row (ZXCV...)
        case 6: "z"
        case 7: "x"
        case 8: "c"
        case 9: "v"
        case 11: "b"
        // Row 2: Top row (QWERTY...)
        case 12: "q"
        case 13: "w"
        case 14: "e"
        case 15: "r"
        case 16: "y"
        case 17: "t"
        // Row 1: Number row
        case 18: "1"
        case 19: "2"
        case 20: "3"
        case 21: "4"
        case 22: "6"
        case 23: "5"
        case 24: "equal"
        case 25: "9"
        case 26: "7"
        case 27: "minus"
        case 28: "8"
        case 29: "0"
        // More top row keys
        case 30: "rightbrace"
        case 31: "o"
        case 32: "u"
        case 33: "leftbrace"
        case 34: "i"
        case 35: "p"
        // Home row continued
        case 36: "enter"
        case 37: "l"
        case 38: "j"
        case 39: "apostrophe"
        case 40: "k"
        case 41: "semicolon"
        case 42: "backslash"
        // Bottom row continued
        case 43: "comma"
        case 44: "slash"
        case 45: "n"
        case 46: "m"
        case 47: "dot"
        // Special keys
        case 48: "tab"
        case 49: "space"
        case 50: "grave"
        case 51: "backspace"
        case 53: "esc"
        // Modifiers
        case 54: "rightmeta"
        case 55: "leftmeta"
        case 56: "leftshift"
        case 57: "capslock"
        case 58: "leftalt"
        case 59: "leftctrl"
        case 60: "rightshift"
        case 61: "rightalt"
        case 63: "fn"
        // Function keys
        case 96: "f5"
        case 97: "f6"
        case 98: "f7"
        case 99: "f3"
        case 100: "f8"
        case 101: "f9"
        case 103: "f11"
        case 109: "f10"
        case 111: "f12"
        case 118: "f4"
        case 120: "f2"
        case 122: "f1"
        // Arrow keys
        case 123: "left"
        case 124: "right"
        case 125: "down"
        case 126: "up"
        // Navigation keys
        case 115: "home"
        case 116: "pageup"
        case 117: "del"
        case 119: "end"
        case 121: "pagedown"
        case 114: "help"
        // Extended function keys
        case 64: "f17"
        case 79: "f18"
        case 80: "f19"
        case 102: "rightctrl"
        case 105: "f13"
        case 106: "f16"
        case 107: "f14"
        case 113: "f15"
        default:
            "unknown-\(keyCode)"
        }
    }
}

// MARK: - Floating Keymap Label

/// A label that floats above the keyboard and animates to its target keycap.
/// Each label has randomized spring parameters for a playful shuffling effect.
/// Renders both main symbol and shift symbol (if any) as a unit that animates together.
private struct FloatingKeymapLabel: View {
    let label: String
    let targetFrame: CGRect
    let isVisible: Bool
    let scale: CGFloat
    let colorway: GMKColorway
    var enableAnimation: Bool = false

    // Randomized animation parameters (seeded by label for consistency)
    private var springResponse: Double {
        0.3 + Double(abs(label.hashValue) % 100) / 500.0 // 0.30-0.50s
    }

    private var dampingFraction: Double {
        0.6 + Double(abs(label.hashValue >> 8) % 100) / 500.0 // 0.60-0.80
    }

    private var wobbleAngle: Double {
        Double(abs(label.hashValue >> 16) % 25) - 12.0 // -12° to +12°
    }

    /// Animation to use - nil when disabled (prevents animation on first load)
    private var positionAnimation: Animation? {
        enableAnimation ? .spring(response: springResponse, dampingFraction: dampingFraction) : nil
    }

    /// Shift symbol for this key (e.g., "1" -> "!", ";" -> ":")
    private var shiftSymbol: String? {
        LabelMetadata.forLabel(label).shiftSymbol
    }

    /// Optical adjustments for shift symbol
    private var shiftAdjustments: OpticalAdjustments {
        guard let shift = shiftSymbol else { return .default }
        return OpticalAdjustments.forLabel(shift)
    }

    /// Optical adjustments for main label
    private var mainAdjustments: OpticalAdjustments {
        OpticalAdjustments.forLabel(label)
    }

    /// Spacing between shift and main symbols
    private var dualSymbolSpacing: CGFloat {
        switch label {
        case ",", ".": -0.5 * scale // Tighter for < > symbols
        case ";", "'", "/": 0
        default: 2 * scale
        }
    }

    /// Whether to hide shift symbol at small sizes
    private var isSmallSize: Bool { scale < 0.8 }

    @State private var rotation: Angle = .zero
    @State private var scaleEffect: CGFloat = 1.0
    @State private var wasVisible: Bool = false
    @State private var previousNormalizedX: CGFloat?
    @State private var previousNormalizedY: CGFloat?

    /// Normalized position (position / scale) - stays constant during resize, changes during layout change
    private var normalizedX: CGFloat { scale > 0 ? targetFrame.midX / scale : 0 }
    private var normalizedY: CGFloat { scale > 0 ? targetFrame.midY / scale : 0 }

    /// Detect if this is a layout change (not just resize)
    private func isLayoutChange() -> Bool {
        guard let prevX = previousNormalizedX, let prevY = previousNormalizedY else {
            return false // First render
        }
        // Use small threshold to handle floating point precision
        let threshold: CGFloat = 0.1
        return abs(normalizedX - prevX) > threshold || abs(normalizedY - prevY) > threshold
    }

    var body: some View {
        labelContent
            .frame(width: targetFrame.width, height: targetFrame.height)
            .scaleEffect(scaleEffect)
            .rotationEffect(rotation)
            .opacity(isVisible ? 1.0 : 0.0)
            .position(x: targetFrame.midX, y: targetFrame.midY)
            // Only animate position during layout changes, not resize
            .animation(isLayoutChange() ? positionAnimation : nil, value: targetFrame)
            .animation(positionAnimation, value: isVisible)
            .onChange(of: targetFrame) { _, _ in
                let layoutChanged = isLayoutChange()
                // Update tracked position
                previousNormalizedX = normalizedX
                previousNormalizedY = normalizedY
                // Only wobble on layout changes, not resize
                if isVisible, enableAnimation, layoutChanged {
                    triggerWobble()
                }
            }
            .onChange(of: isVisible) { _, newVisible in
                if newVisible, !wasVisible, enableAnimation {
                    triggerWobble()
                }
                wasVisible = newVisible
            }
            .onAppear {
                previousNormalizedX = normalizedX
                previousNormalizedY = normalizedY
            }
    }

    @ViewBuilder
    private var labelContent: some View {
        if let shift = shiftSymbol {
            // Dual symbol layout: shift on top, main on bottom
            VStack(spacing: dualSymbolSpacing) {
                Text(shift)
                    .font(.system(
                        size: 9 * scale * shiftAdjustments.fontScale,
                        weight: shiftAdjustments.fontWeight ?? .light
                    ))
                    .foregroundStyle(colorway.alphaLegendColor.opacity(isSmallSize ? 0 : 0.6))

                Text(label.uppercased())
                    .font(.system(
                        size: 12 * scale * mainAdjustments.fontScale,
                        weight: mainAdjustments.fontWeight ?? .medium
                    ))
                    .offset(y: mainAdjustments.verticalOffset * scale)
                    .foregroundStyle(colorway.alphaLegendColor)
            }
        } else {
            // Single symbol (letters)
            Text(label.uppercased())
                .font(.system(size: 12 * scale, weight: .medium))
                .foregroundStyle(colorway.alphaLegendColor)
        }
    }

    private func triggerWobble() {
        rotation = .degrees(wobbleAngle)
        scaleEffect = 1.15
        withAnimation(.spring(response: springResponse, dampingFraction: dampingFraction)) {
            rotation = .zero
            scaleEffect = 1.0
        }
    }
}

// MARK: - Preview

#Preview {
    OverlayKeyboardView(
        layout: .macBookUS,
        keymap: .qwertyUS,
        includeKeymapPunctuation: false,
        pressedKeyCodes: [0, 56, 55] // a, leftshift, leftmeta
    )
    .padding()
    .frame(width: 600, height: 250)
    .background(Color(white: 0.1))
}
