import SwiftUI

// MARK: - Floating Keymap Label

/// A label that floats above the keyboard and animates to its target keycap.
/// Each label has randomized spring parameters for a playful shuffling effect.
/// Renders both main symbol and shift symbol (if any) as a unit that animates together.
struct FloatingKeymapLabel: View {
    let label: String
    let targetFrame: CGRect
    let isVisible: Bool
    let scale: CGFloat
    let colorway: GMKColorway
    var enableAnimation: Bool = false
    var animateVisibility: Bool = true // Set false for instant show/hide (e.g., launcher mode)
    var fadeAmount: CGFloat = 0 // 0 = fully visible, 1 = fully faded (for glow effect)
    var isDarkMode: Bool = false // Whether dark mode is active (enables glow effect)
    var shiftSymbolOverride: String? // Dynamic shift symbol from system keymap

    /// Randomized animation parameters (seeded by label for consistency)
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
    /// Uses system keymap override when available, falls back to static lookup.
    private var shiftSymbol: String? {
        shiftSymbolOverride ?? LabelMetadata.forLabel(label).shiftSymbol
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
    private var isSmallSize: Bool {
        scale < 0.8
    }

    @State private var rotation: Angle = .zero
    @State private var scaleEffect: CGFloat = 1.0
    @State private var wasVisible: Bool = false
    @State private var previousNormalizedX: CGFloat?
    @State private var previousNormalizedY: CGFloat?

    /// Normalized position (position / scale) - stays constant during resize, changes during layout change
    private var normalizedX: CGFloat {
        scale > 0 ? targetFrame.midX / scale : 0
    }

    private var normalizedY: CGFloat {
        scale > 0 ? targetFrame.midY / scale : 0
    }

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
        ZStack {
            // Glow layers for dark mode backlight effect (same as keycap)
            // Glow increases as keyboard fades out for ethereal effect
            if isDarkMode {
                labelContent
                    .blur(radius: glowOuterRadius)
                    .opacity(glowOuterOpacity)

                labelContent
                    .blur(radius: glowInnerRadius)
                    .opacity(glowInnerOpacity)
            }

            // Crisp content layer
            labelContent
        }
        .frame(width: targetFrame.width, height: targetFrame.height)
        .scaleEffect(scaleEffect)
        .rotationEffect(rotation)
        .opacity(isVisible ? 1.0 : 0.0)
        .position(x: targetFrame.midX, y: targetFrame.midY)
        .allowsHitTesting(false)
        // Only animate position during layout changes, not resize
        .animation(isLayoutChange() ? positionAnimation : nil, value: targetFrame)
        // Animate visibility changes unless disabled (e.g., launcher mode toggle)
        .animation(animateVisibility ? positionAnimation : nil, value: isVisible)
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
            // Only wobble if animations are enabled AND visibility should animate
            // (skip wobble for instant transitions like launcher mode toggle)
            if newVisible, !wasVisible, enableAnimation, animateVisibility {
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

    // MARK: - Glow (dynamic based on fade, same as keycap)

    /// Outer glow blur radius: reduced when visible, increases when fading
    private var glowOuterRadius: CGFloat {
        let base: CGFloat = 1.5 // Reduced from 3 for crisper default
        let max: CGFloat = 5.0 // Enhanced when faded
        return (base + (max - base) * fadeAmount) * scale
    }

    /// Outer glow opacity: subtle when visible, stronger when fading
    private var glowOuterOpacity: CGFloat {
        let base: CGFloat = 0.15 // Reduced from 0.25 for crisper default
        let max: CGFloat = 0.4 // Enhanced when faded
        return base + (max - base) * fadeAmount
    }

    /// Inner glow blur radius: tight when visible, softer when fading
    private var glowInnerRadius: CGFloat {
        let base: CGFloat = 0.5 // Reduced from 1 for crisper default
        let max: CGFloat = 2.0 // Enhanced when faded
        return (base + (max - base) * fadeAmount) * scale
    }

    /// Inner glow opacity: subtle when visible, stronger when fading
    private var glowInnerOpacity: CGFloat {
        let base: CGFloat = 0.25 // Reduced from 0.4 for crisper default
        let max: CGFloat = 0.5 // Enhanced when faded
        return base + (max - base) * fadeAmount
    }
}
