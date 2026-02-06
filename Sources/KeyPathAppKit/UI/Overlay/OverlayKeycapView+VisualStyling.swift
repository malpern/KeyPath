import AppKit
import KeyPathCore
import SwiftUI

// MARK: - Visual Styling (colors, shadows, glow)

extension OverlayKeycapView {
    // MARK: - Debug Logging

    func logSize(_ size: CGSize) {
        AppLogger.shared
            .log("[Keycap] role=\(key.layoutRole) label=\(key.label) keyCode=\(key.keyCode) size=\(String(format: "%.2f x %.2f", size.width, size.height)) scale=\(String(format: "%.2f", scale))")
    }

    // MARK: - Styling

    /// Interpolate between two colors based on progress (0 = from, 1 = to)
    func interpolate(from: Color, to: Color, progress: CGFloat) -> (red: Double, green: Double, blue: Double) {
        // Extract RGB components (simplified - assumes sRGB)
        let fromRGB = NSColor(from).usingColorSpace(.sRGB) ?? NSColor.black
        let toRGB = NSColor(to).usingColorSpace(.sRGB) ?? NSColor.black

        let r = Double(fromRGB.redComponent) * (1 - progress) + Double(toRGB.redComponent) * progress
        let g = Double(fromRGB.greenComponent) * (1 - progress) + Double(toRGB.greenComponent) * progress
        let b = Double(fromRGB.blueComponent) * (1 - progress) + Double(toRGB.blueComponent) * progress

        return (r, g, b)
    }

    var cornerRadius: CGFloat {
        key.layoutRole == .arrow ? 3 * scale : 4 * scale
    }

    var keyBackground: Color {
        // For per-key release fade: blend from blue to black
        if isReleaseFading, fadeAmount > 0 {
            let blue = Color.accentColor
            let targetColor = backgroundColor // Use colorway's background color
            return Color(
                red: interpolate(from: blue, to: targetColor, progress: fadeAmount).red,
                green: interpolate(from: blue, to: targetColor, progress: fadeAmount).green,
                blue: interpolate(from: blue, to: targetColor, progress: fadeAmount).blue
            )
        }
        // For global overlay fade: use opacity
        else if fadeAmount > 0 {
            return backgroundColor.opacity(1 - 0.9 * fadeAmount)
        }
        // No fade: use base color
        else {
            return backgroundColor
        }
    }

    var keyStroke: Color {
        // No borders at any time - keys rely on shadows for separation
        // (User preference: cleaner look without outlines, including during fade)
        Color.white.opacity(0)
    }

    var strokeWidth: CGFloat {
        // No border stroke width at any time
        0
    }

    var shadowColor: Color {
        Color.black.opacity(isDarkMode ? 0.5 : 0.35).opacity(1 - fadeAmount)
    }

    var shadowRadius: CGFloat {
        // Ensure minimum shadow even when pressed for grounding
        let minRadius: CGFloat = 0.3 * scale
        let normalRadius: CGFloat = 0.5 * scale
        let pressedRadius: CGFloat = 0.2 * scale
        let baseRadius = isPressed ? max(pressedRadius, minRadius) : normalRadius
        // Reduce fade impact on shadow (was 1 - fadeAmount, now only 50% reduction)
        return baseRadius * (1 - fadeAmount * 0.5)
    }

    var shadowOffset: CGFloat {
        // Match shadow radius logic for consistency
        let minOffset: CGFloat = 0.3 * scale
        let normalOffset: CGFloat = 0.5 * scale
        let pressedOffset: CGFloat = 0.2 * scale
        let baseOffset = isPressed ? max(pressedOffset, minOffset) : normalOffset
        return baseOffset * (1 - fadeAmount * 0.5)
    }

    /// Whether this key is a modifier (shift, ctrl, opt, cmd, fn, etc.)
    var isModifierKey: Bool {
        let modifierLabels = ["⇧", "⌃", "⌥", "⌘", "fn", "shift", "ctrl", "control", "opt", "option", "alt", "cmd", "command", "⇪", "caps"]
        let label = baseLabel.lowercased()
        return modifierLabels.contains { label.contains($0.lowercased()) }
            || key.width >= 1.5 // Wide keys are typically modifiers
            || key.keyCode == 63 // fn key
            || (key.keyCode >= 54 && key.keyCode <= 61) // modifier key codes
    }

    /// Whether this key should use accent colors (enter, escape, etc.)
    var isAccentKey: Bool {
        let accentLabels = ["⏎", "↵", "return", "enter", "esc", "escape", "⌫", "delete", "⇥", "tab"]
        let label = baseLabel.lowercased()
        return accentLabels.contains { label.contains($0.lowercased()) }
    }

    /// Whether this key is a numpad key (doesn't show shift symbols)
    /// Numpad keyCodes on macOS: 65 (.), 67 (*), 69 (+), 71 (clear), 75 (/),
    /// 76 (enter), 78 (-), 81 (=), 82-92 (0-9 and operators)
    var isNumpadKey: Bool {
        let numpadKeyCodes: Set<UInt16> = [
            65, 67, 69, 71, 75, 76, 78, 81, // operators and special
            82, 83, 84, 85, 86, 87, 88, 89, 91, 92 // numbers 0-9
        ]
        return numpadKeyCodes.contains(key.keyCode)
    }

    var foregroundColor: Color {
        let baseColor: Color = if isModifierKey {
            colorway.modLegendColor
        } else if isAccentKey {
            colorway.accentLegendColor
        } else {
            colorway.alphaLegendColor
        }
        return baseColor.opacity(isPressed ? 1.0 : 0.88)
    }

    var backgroundColor: Color {
        if isPressed {
            Color.accentColor
        } else if isOneShot {
            // One-shot modifier active: cyan/teal glow to indicate waiting for next key
            Color(red: 0.2, green: 0.7, blue: 0.8)
        } else if isEmphasized {
            Color.orange
        }
        // Launcher mode: blue/teal background for mapped keys
        else if isLauncherMode, hasLauncherMapping {
            Color(red: 0.15, green: 0.35, blue: 0.45)
        }
        // Launcher mode: dark gray for ALL unmapped keys including modifiers/fn (RGB 56, 56, 57 - 10% lighter)
        else if isLauncherMode {
            Color(red: 56 / 255, green: 56 / 255, blue: 57 / 255)
        }
        // Layer mode: collection-specific color for mapped keys
        else if isLayerMode, hasLayerMapping || isNavIdentityMapping {
            collectionColor(for: layerKeyInfo?.collectionId)
        }
        // Layer mode: dark gray for unmapped keys (same as launcher)
        else if isLayerMode {
            Color(red: 56 / 255, green: 56 / 255, blue: 57 / 255)
        } else if isModifierKey {
            colorway.modBaseColor
        } else if isAccentKey {
            colorway.accentBaseColor
        } else if showScoopedHomeRow, isHomeRowKey {
            // Kinesis home row keys have a different color (darker/accent shade)
            colorway.modBaseColor
        } else {
            colorway.alphaBaseColor
        }
    }

    // MARK: - Glow (dynamic based on fade)

    /// Outer glow blur radius: reduced when visible, increases when fading
    var glowOuterRadius: CGFloat {
        let base: CGFloat = 1.5 // Reduced from 3 for crisper default
        let max: CGFloat = 5.0 // Enhanced when faded
        return (base + (max - base) * fadeAmount) * scale
    }

    /// Outer glow opacity: subtle when visible, stronger when fading
    var glowOuterOpacity: CGFloat {
        let base: CGFloat = 0.15 // Reduced from 0.25 for crisper default
        let max: CGFloat = 0.4 // Enhanced when faded
        return base + (max - base) * fadeAmount
    }

    /// Inner glow blur radius: tight when visible, softer when fading
    var glowInnerRadius: CGFloat {
        let base: CGFloat = 0.5 // Reduced from 1 for crisper default
        let max: CGFloat = 2.0 // Enhanced when faded
        return (base + (max - base) * fadeAmount) * scale
    }

    /// Inner glow opacity: subtle when visible, stronger when fading
    var glowInnerOpacity: CGFloat {
        let base: CGFloat = 0.25 // Reduced from 0.4 for crisper default
        let max: CGFloat = 0.5 // Enhanced when faded
        return base + (max - base) * fadeAmount
    }
}
