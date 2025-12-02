import KeyPathCore
import SwiftUI

/// A read-only keycap for the live overlay.
/// Uses layout roles (based on physical properties) for structure,
/// and optical adjustments (based on label) for visual harmony.
struct OverlayKeycapView: View {
    let key: PhysicalKey
    let isPressed: Bool
    /// Scale factor from keyboard resize (1.0 = default size)
    let scale: CGFloat
    /// Whether dark mode is active (for backlight glow)
    var isDarkMode: Bool = false
    /// Whether caps lock is engaged (for indicator light)
    var isCapsLockOn: Bool = false
    /// Fade amount: 0 = fully visible, 1 = fully faded
    var fadeAmount: CGFloat = 0

    /// Size thresholds for typography adaptation
    private var isSmallSize: Bool { scale < 0.8 }
    private var isLargeSize: Bool { scale >= 1.5 }

    /// Optical adjustments for current label
    private var adjustments: OpticalAdjustments {
        OpticalAdjustments.forLabel(key.label)
    }

    /// Metadata for current label
    private var metadata: LabelMetadata {
        LabelMetadata.forLabel(key.label)
    }

    var body: some View {
        ZStack {
            // Key background with subtle shadow
            RoundedRectangle(cornerRadius: cornerRadius)
                .fill(keyBackground)
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                .shadow(color: shadowColor, radius: shadowRadius, y: shadowOffset)
                .overlay(
                    RoundedRectangle(cornerRadius: cornerRadius)
                        .stroke(keyStroke, lineWidth: strokeWidth)
                )

            // Glow layers for dark mode backlight effect
            // Glow increases as keyboard fades out for ethereal effect
            if isDarkMode {
                keyContent
                    .blur(radius: glowOuterRadius)
                    .opacity(glowOuterOpacity)

                keyContent
                    .blur(radius: glowInnerRadius)
                    .opacity(glowInnerOpacity)
            }

            // Crisp content layer
            keyContent

            // Caps lock indicator (only for caps lock key)
            if key.label == "⇪" {
                capsLockIndicator
            }
        }
        .scaleEffect(isPressed ? 0.95 : 1.0)
        .offset(y: isPressed && fadeAmount < 1 ? 0.75 * scale : 0)
        .animation(.spring(response: 0.15, dampingFraction: 0.6), value: isPressed)
        .animation(.easeOut(duration: 0.3), value: fadeAmount)
        // Debug: uncomment to log key sizes
        // .background(GeometryReader { proxy in
        //     Color.clear
        //         .onAppear { logSize(proxy.size) }
        //         .onChange(of: proxy.size) { _, newSize in logSize(newSize) }
        // })
    }

    // MARK: - Content Routing by Layout Role

    @ViewBuilder
    private var keyContent: some View {
        switch key.layoutRole {
        case .centered:
            centeredContent
        case .bottomAligned:
            bottomAlignedContent
        case .narrowModifier:
            narrowModifierContent
        case .functionKey:
            functionKeyContent
        case .arrow:
            arrowContent
        case .touchId:
            touchIdContent
        case .escKey:
            escKeyContent
        }
    }

    // MARK: - Layout: Centered (letters, symbols, spacebar)

    @ViewBuilder
    private var centeredContent: some View {
        // Check if this is a number key or dual-symbol key
        if let shiftSymbol = metadata.shiftSymbol {
            // Dual content: shift symbol above, main below
            dualSymbolContent(main: key.label, shift: shiftSymbol)
        } else {
            // Single centered content
            Text(key.label.uppercased())
                .font(.system(size: 12 * scale, weight: .medium))
                .foregroundStyle(foregroundColor)
                .frame(maxWidth: .infinity, maxHeight: .infinity)
        }
    }

    @ViewBuilder
    private func dualSymbolContent(main: String, shift: String) -> some View {
        let shiftAdj = OpticalAdjustments.forLabel(shift)
        let mainAdj = OpticalAdjustments.forLabel(main)

        VStack(spacing: dualSymbolSpacing(for: main)) {
            Text(shift)
                .font(.system(
                    size: 9 * scale * shiftAdj.fontScale,
                    weight: shiftAdj.fontWeight ?? .light
                ))
                .foregroundStyle(foregroundColor.opacity(isSmallSize ? 0 : 0.6))

            Text(main)
                .font(.system(
                    size: 12 * scale * mainAdj.fontScale,
                    weight: mainAdj.fontWeight ?? .medium
                ))
                .offset(y: mainAdj.verticalOffset * scale)
                .foregroundStyle(foregroundColor)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    private func dualSymbolSpacing(for label: String) -> CGFloat {
        switch label {
        case ",", ".": -0.5 * scale // Tighter for < > symbols
        case ";", "'", "/": 0
        default: 2 * scale
        }
    }

    // MARK: - Layout: Bottom Aligned (wide modifiers)

    @ViewBuilder
    private var bottomAlignedContent: some View {
        let wordLabel = metadata.wordLabel ?? key.label
        let isRight = key.isRightSideKey

        VStack {
            Spacer(minLength: 0)
            HStack {
                if !isRight {
                    labelText(wordLabel)
                    Spacer(minLength: 0)
                } else {
                    Spacer(minLength: 0)
                    labelText(wordLabel)
                }
            }
            .padding(.leading, 4 * scale)
            .padding(.trailing, 4 * scale)
            .padding(.bottom, 3 * scale)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .foregroundStyle(foregroundColor)
    }

    @ViewBuilder
    private func labelText(_ text: String) -> some View {
        if isSmallSize {
            // Symbol only when tiny
            Text(key.label)
                .font(.system(size: 10 * scale, weight: .regular))
        } else {
            Text(text)
                .font(.system(size: 7 * scale, weight: .regular))
        }
    }

    // MARK: - Layout: Narrow Modifier (fn, ctrl, opt, cmd)

    @ViewBuilder
    private var narrowModifierContent: some View {
        if key.label == "fn" {
            fnKeyContent
        } else {
            modifierSymbolContent
        }
    }

    @ViewBuilder
    private var fnKeyContent: some View {
        let canInline = scale >= 1.0

        Group {
            if canInline {
                HStack(spacing: 4 * scale) {
                    Image(systemName: "globe")
                        .font(.system(size: 8.5 * scale, weight: .regular))
                    Text("fn")
                        .font(.system(size: 7 * scale, weight: .regular))
                }
            } else {
                Image(systemName: "globe")
                    .font(.system(size: 8.5 * scale, weight: .regular))
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .foregroundStyle(foregroundColor)
    }

    @ViewBuilder
    private var modifierSymbolContent: some View {
        let baseFontSize: CGFloat = 11 * scale
        let fontSize = baseFontSize * adjustments.fontScale
        let offset = adjustments.verticalOffset * scale

        // Single centered symbol - always respects frame bounds
        Text(key.label)
            .font(.system(size: fontSize, weight: .light))
            .offset(y: offset)
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .foregroundStyle(foregroundColor)
    }

    // MARK: - Layout: Function Key

    @ViewBuilder
    private var functionKeyContent: some View {
        let sfSymbol = LabelMetadata.sfSymbol(forKeyCode: key.keyCode)

        VStack(spacing: 0) {
            if let symbol = sfSymbol {
                Image(systemName: symbol)
                    .font(.system(size: 8 * scale, weight: .regular))
                    .foregroundStyle(foregroundColor)
            }
            Spacer()
            Text(key.label)
                .font(.system(size: 5.4 * scale, weight: .regular))
                .foregroundStyle(foregroundColor.opacity(0.6))
        }
        .padding(.top, 4 * scale)
        .padding(.bottom, 2 * scale)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    // MARK: - Layout: Arrow

    @ViewBuilder
    private var arrowContent: some View {
        Text(key.label)
            .font(.system(size: 8 * scale, weight: .regular))
            .foregroundStyle(foregroundColor)
            .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    // MARK: - Layout: Touch ID

    @ViewBuilder
    private var touchIdContent: some View {
        Image(systemName: "touchid")
            .font(.system(size: 12 * scale, weight: .regular))
            .foregroundStyle(foregroundColor)
            .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    // MARK: - Layout: ESC Key

    @ViewBuilder
    private var escKeyContent: some View {
        // Match caps lock style: bottom-left aligned using labelText()
        VStack {
            Spacer(minLength: 0)
            HStack {
                labelText("esc")
                Spacer(minLength: 0)
            }
            .padding(.leading, 4 * scale)
            .padding(.trailing, 4 * scale)
            .padding(.bottom, 3 * scale)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .foregroundStyle(foregroundColor)
    }

    // MARK: - Caps Lock Indicator

    @ViewBuilder
    private var capsLockIndicator: some View {
        VStack {
            HStack {
                Circle()
                    .fill(isCapsLockOn ? Color.green : Color.white.opacity(0.15))
                    .frame(width: 4 * scale, height: 4 * scale)
                    .shadow(color: isCapsLockOn ? Color.green.opacity(1.0) : .clear, radius: 2 * scale)
                    .shadow(color: isCapsLockOn ? Color.green.opacity(0.8) : .clear, radius: 4 * scale)
                    .shadow(color: isCapsLockOn ? Color.green.opacity(0.5) : .clear, radius: 8 * scale)
                    .animation(.easeInOut(duration: 0.2), value: isCapsLockOn)
                Spacer()
            }
            .padding(.leading, 4.4 * scale)
            .padding(.top, 3 * scale)
            Spacer()
        }
    }

    // MARK: - Debug Logging

    private func logSize(_ size: CGSize) {
        AppLogger.shared
            .log("[Keycap] role=\(key.layoutRole) label=\(key.label) keyCode=\(key.keyCode) size=\(String(format: "%.2f x %.2f", size.width, size.height)) scale=\(String(format: "%.2f", scale))")
    }

    // MARK: - Styling

    private var cornerRadius: CGFloat {
        key.layoutRole == .arrow ? 3 * scale : 4 * scale
    }

    private var keyBackground: Color {
        backgroundColor.opacity(1 - 0.9 * fadeAmount)
    }

    private var keyStroke: Color {
        Color.white.opacity(0.35 * fadeAmount)
    }

    private var strokeWidth: CGFloat {
        fadeAmount * scale
    }

    private var shadowColor: Color {
        Color.black.opacity(isDarkMode ? 0.5 : 0.35).opacity(1 - fadeAmount)
    }

    private var shadowRadius: CGFloat {
        (isPressed ? 0.2 * scale : 0.5 * scale) * (1 - fadeAmount)
    }

    private var shadowOffset: CGFloat {
        (isPressed ? 0.2 * scale : 0.5 * scale) * (1 - fadeAmount)
    }

    private var foregroundColor: Color {
        Color(red: 0.88, green: 0.93, blue: 1.0)
            .opacity(isPressed ? 1.0 : 0.88)
    }

    private var backgroundColor: Color {
        isPressed ? Color.accentColor : Color(white: 0.08)
    }

    // MARK: - Glow (dynamic based on fade)

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

// MARK: - Preview

#Preview("Keyboard Row") {
    HStack(spacing: 4) {
        // fn key
        OverlayKeycapView(
            key: PhysicalKey(keyCode: 63, label: "fn", x: 0, y: 5, width: 1.1),
            isPressed: false,
            scale: 1.5
        )
        .frame(width: 50, height: 45)

        // Control
        OverlayKeycapView(
            key: PhysicalKey(keyCode: 59, label: "⌃", x: 1.2, y: 5, width: 1.1),
            isPressed: false,
            scale: 1.5
        )
        .frame(width: 50, height: 45)

        // Option
        OverlayKeycapView(
            key: PhysicalKey(keyCode: 58, label: "⌥", x: 2.4, y: 5, width: 1.1),
            isPressed: false,
            scale: 1.5
        )
        .frame(width: 50, height: 45)

        // Command
        OverlayKeycapView(
            key: PhysicalKey(keyCode: 55, label: "⌘", x: 3.6, y: 5, width: 1.35),
            isPressed: false,
            scale: 1.5
        )
        .frame(width: 60, height: 45)
    }
    .padding()
    .background(Color.black)
}

#Preview("Letter Key") {
    OverlayKeycapView(
        key: PhysicalKey(keyCode: 0, label: "a", x: 0, y: 0),
        isPressed: false,
        scale: 1.5,
        isDarkMode: true
    )
    .frame(width: 50, height: 50)
    .padding()
    .background(Color.black)
}
