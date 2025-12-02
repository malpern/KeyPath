import AppKit
import SwiftUI

/// Keyboard view for the live overlay.
/// Renders a full keyboard layout with keys highlighting based on key codes.
struct OverlayKeyboardView: View {
    let layout: PhysicalLayout
    let pressedKeyCodes: Set<UInt16>
    var isDarkMode: Bool = false
    var fadeAmount: CGFloat = 0 // 0 = fully visible, 1 = fully faded
    var currentLayerName: String = "base"
    var isLoadingLayerMap: Bool = false
    /// Key mapping for current layer: keyCode -> LayerKeyInfo
    var layerKeyMap: [UInt16: LayerKeyInfo] = [:]
    /// Effective pressed key codes (includes remapped outputs for dual highlighting)
    var effectivePressedKeyCodes: Set<UInt16> = []

    /// Track caps lock state from system
    @State private var isCapsLockOn: Bool = NSEvent.modifierFlags.contains(.capsLock)

    /// Size of a standard 1u key in points
    private let keyUnitSize: CGFloat = 32
    /// Gap between keys
    private let keyGap: CGFloat = 2

    var body: some View {
        GeometryReader { geometry in
            let scale = calculateScale(for: geometry.size)

            ZStack(alignment: .topLeading) {
                ForEach(layout.keys) { key in
                    // Use effectivePressedKeyCodes for dual highlighting
                    // This includes both physical pressed keys AND their remapped outputs
                    let isPressed = effectivePressedKeyCodes.contains(key.keyCode)
                        || pressedKeyCodes.contains(key.keyCode)

                    OverlayKeycapView(
                        key: key,
                        isPressed: isPressed,
                        scale: scale,
                        isDarkMode: isDarkMode,
                        isCapsLockOn: isCapsLockOn,
                        fadeAmount: fadeAmount,
                        currentLayerName: currentLayerName,
                        isLoadingLayerMap: isLoadingLayerMap,
                        layerKeyInfo: layerKeyMap[key.keyCode]
                    )
                    .frame(
                        width: keyWidth(for: key, scale: scale),
                        height: keyHeight(for: key, scale: scale)
                    )
                    .position(
                        x: keyPositionX(for: key, scale: scale),
                        y: keyPositionY(for: key, scale: scale)
                    )
                }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
        }
        .aspectRatio(layout.totalWidth / layout.totalHeight, contentMode: .fit)
        .onChange(of: pressedKeyCodes) { _, _ in
            // Update caps lock state when any key changes (captures toggle)
            isCapsLockOn = NSEvent.modifierFlags.contains(.capsLock)
        }
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
        let baseX = key.x * (keyUnitSize + keyGap) * scale
        let halfWidth = keyWidth(for: key, scale: scale) / 2
        return baseX + halfWidth + keyGap * scale
    }

    private func keyPositionY(for key: PhysicalKey, scale: CGFloat) -> CGFloat {
        let baseY = key.y * (keyUnitSize + keyGap) * scale
        let halfHeight = keyHeight(for: key, scale: scale) / 2
        return baseY + halfHeight + keyGap * scale
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
        default:
            "unknown-\(keyCode)"
        }
    }
}

// MARK: - Preview

#Preview {
    OverlayKeyboardView(
        layout: .macBookUS,
        pressedKeyCodes: [0, 56, 55] // a, leftshift, leftmeta
    )
    .padding()
    .frame(width: 600, height: 250)
    .background(Color(white: 0.1))
}
