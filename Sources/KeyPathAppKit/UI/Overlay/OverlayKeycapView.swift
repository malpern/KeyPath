import SwiftUI

/// A read-only keycap for the live overlay.
/// Styled to match MacBook keyboard aesthetics with proper typography.
struct OverlayKeycapView: View {
    let key: PhysicalKey
    let isPressed: Bool
    /// Scale factor from keyboard resize (1.0 = default size)
    let scale: CGFloat
    /// Whether dark mode is active (for backlight glow)
    var isDarkMode: Bool = false
    /// Whether caps lock is engaged (for indicator light)
    var isCapsLockOn: Bool = false

    /// Size thresholds for typography adaptation
    private var isSmallSize: Bool { scale < 0.8 }
    private var isMediumSize: Bool { scale >= 0.8 && scale < 1.5 }
    private var isLargeSize: Bool { scale >= 1.5 }

    /// SF Pro font
    private var sfPro: Font {
        .system(size: 1, weight: .regular, design: .default)
    }

    var body: some View {
        ZStack {
            // Key background with subtle shadow - explicitly fill available space
            RoundedRectangle(cornerRadius: cornerRadius)
                .fill(backgroundColor)
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                .shadow(
                    color: .black.opacity(isDarkMode ? 0.5 : 0.35),
                    radius: isPressed ? 0.2 * scale : 0.5 * scale,
                    y: isPressed ? 0.2 * scale : 0.5 * scale
                )

            // Glow layers - blurred text underneath for bloom effect
            if isDarkMode {
                // Diffuse outer glow
                keyLabel
                    .padding(.horizontal, horizontalPadding)
                    .padding(.vertical, verticalPadding)
                    .blur(radius: 3 * scale)
                    .opacity(0.25)

                // Tight inner glow
                keyLabel
                    .padding(.horizontal, horizontalPadding)
                    .padding(.vertical, verticalPadding)
                    .blur(radius: 1 * scale)
                    .opacity(0.4)
            }

            // Crisp text layer - sharp edges on top
            keyLabel
                .padding(.horizontal, horizontalPadding)
                .padding(.vertical, verticalPadding)

            // Caps lock indicator light
            if key.label == "⇪" {
                capsLockIndicator
            }
        }
        .scaleEffect(isPressed ? 0.95 : 1.0)
        .offset(y: isPressed ? 0.75 * scale : 0)
        .animation(.spring(response: 0.15, dampingFraction: 0.6), value: isPressed)
        .animation(.easeInOut(duration: 0.15), value: isLargeSize)
        .animation(.easeInOut(duration: 0.15), value: isSmallSize)
    }

    /// Caps lock indicator light (green dot in top-left when engaged)
    @ViewBuilder
    private var capsLockIndicator: some View {
        VStack {
            HStack {
                Circle()
                    .fill(isCapsLockOn ? Color.green : Color.white.opacity(0.15))
                    .frame(width: 4 * scale, height: 4 * scale)
                    // Multiple shadow layers for intense glow when on
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

    /// Backlight glow color - cool blue-white to match MacBook backlight
    private var backlightGlow: Color {
        isDarkMode ? Color(red: 0.88, green: 0.93, blue: 1.0).opacity(0.4) : .clear
    }

    /// Tight inner glow - higher opacity for sharper halo
    private var backlightGlowTight: Color {
        isDarkMode ? Color(red: 0.88, green: 0.93, blue: 1.0).opacity(0.6) : .clear
    }

    /// Diffuse outer glow - lower opacity for soft bloom
    private var backlightGlowDiffuse: Color {
        isDarkMode ? Color(red: 0.88, green: 0.93, blue: 1.0).opacity(0.2) : .clear
    }

    // MARK: - Label Routing

    @ViewBuilder
    private var keyLabel: some View {
        if isEscKey {
            escKeyView
        } else if isTouchIdKey {
            touchIdKeyView
        } else if isFunctionKey {
            functionKeyView
        } else if isArrowKey {
            arrowKeyView
        } else if isWideModifier {
            // Wide keys: tab, caps lock, shift, return, delete - left aligned text
            wideModifierView
        } else if isBottomModifier {
            // fn, control, option, command - symbol + word
            bottomModifierView
        } else if isNumberKey {
            // Number row: digit with shift symbol above
            numberKeyView
        } else if isDualSymbolKey {
            dualSymbolKeyView
        } else {
            // Letters and other keys
            letterKeyView
        }
    }

    // MARK: - ESC Key

    private var isEscKey: Bool {
        key.label == "esc"
    }

    @ViewBuilder
    private var escKeyView: some View {
        // Same style as Shift key - bottom-left aligned with padding
        VStack {
            Spacer(minLength: 0)
            HStack {
                Text("esc")
                    .font(.system(size: 7 * scale, weight: .regular))
                Spacer(minLength: 0)
            }
            .padding(.horizontal, 4 * scale)
            .padding(.bottom, 3 * scale)
        }
        .foregroundStyle(foregroundColor)
    }

    // MARK: - Touch ID Key

    private var isTouchIdKey: Bool {
        key.label == "🔒"
    }

    @ViewBuilder
    private var touchIdKeyView: some View {
        // Fingerprint icon for Touch ID
        Image(systemName: "touchid")
            .font(.system(size: 12 * scale, weight: .regular))
            .foregroundStyle(foregroundColor)
    }

    // MARK: - Function Keys (SF Symbols)

    private var isFunctionKey: Bool {
        key.label.hasPrefix("F") && key.label.count <= 3
    }

    @ViewBuilder
    private var functionKeyView: some View {
        VStack(spacing: 0) {
            if let sfSymbol = sfSymbolName {
                Image(systemName: sfSymbol)
                    .font(.system(size: 8 * scale, weight: .regular))
                    .foregroundStyle(foregroundColor)
            }
            Spacer()
            // F1-F12 label at bottom
            Text(key.label)
                .font(.system(size: 5.4 * scale, weight: .regular))  // 10% smaller
                .foregroundStyle(foregroundColor.opacity(0.6))
        }
        .padding(.top, 4 * scale)
        .padding(.bottom, 2 * scale)
    }

    private var sfSymbolName: String? {
        switch key.keyCode {
        case 122: "sun.min"
        case 120: "sun.max"
        case 99: "rectangle.3.group"
        case 118: "magnifyingglass"
        case 96: "mic"
        case 97: "moon"
        case 98: "backward"          // outline (was backward.fill)
        case 100: "playpause"        // outline (was playpause.fill)
        case 101: "forward"          // outline (was forward.fill)
        case 109: "speaker.slash"    // outline (was speaker.slash.fill)
        case 103: "speaker.wave.1"   // outline (was speaker.wave.1.fill)
        case 111: "speaker.wave.3"   // outline (was speaker.wave.3.fill)
        default: nil
        }
    }

    // MARK: - Arrow Keys

    private var isArrowKey: Bool {
        ["▲", "▼", "◀", "▶"].contains(key.label)
    }

    @ViewBuilder
    private var arrowKeyView: some View {
        Text(key.label)
            .font(.system(size: 8 * scale, weight: .regular))
            .foregroundStyle(foregroundColor)
    }

    // MARK: - Wide Modifiers (text aligned based on position, bottom of key)

    private var isWideModifier: Bool {
        ["⇧", "↩", "⌫", "⇥", "⇪"].contains(key.label)
    }

    /// Left-side keys: tab (48), caps (57), left shift (56)
    /// Right-side keys: delete (51), return (36), right shift (60)
    private var isRightSideKey: Bool {
        [51, 36, 60].contains(key.keyCode)
    }

    @ViewBuilder
    private var wideModifierView: some View {
        // Bottom-aligned, left or right based on position
        // With padding from bottom and sides to match real MacBook
        // Note: Caps lock uses reduced leading padding to align with LED indicator
        // Extra 0.4 * scale (10% of base 4) to match LED position
        let leadingPad = (key.label == "⇪") ? 0.4 * scale : 4 * scale
        let trailingPad = 4 * scale

        VStack {
            Spacer(minLength: 0)
            HStack {
                if !isRightSideKey {
                    // Left-side keys: left-aligned at bottom
                    labelContent
                    Spacer(minLength: 0)
                } else {
                    // Right-side keys: right-aligned at bottom
                    Spacer(minLength: 0)
                    labelContent
                }
            }
            .padding(.leading, leadingPad)
            .padding(.trailing, trailingPad)
            .padding(.bottom, 3 * scale)
        }
        .foregroundStyle(foregroundColor)
    }

    @ViewBuilder
    private var labelContent: some View {
        if isSmallSize {
            // Just symbol when tiny
            Text(wideModifierSymbol)
                .font(.system(size: 10 * scale, weight: .regular, design: .default))
        } else {
            // Word label (like real MacBook keyboard)
            Text(wideModifierLabel)
                .font(.system(size: 7 * scale, weight: .regular, design: .default))
        }
    }

    private var wideModifierSymbol: String {
        switch key.label {
        case "⇧": "⇧"
        case "↩": "↩"
        case "⌫": "⌫"
        case "⇥": "⇥"
        case "⇪": "⇪"
        default: key.label
        }
    }

    private var wideModifierLabel: String {
        switch key.label {
        case "⇧": "shift"
        case "↩": "return"
        case "⌫": "delete"
        case "⇥": "tab"
        case "⇪": "caps lock"
        default: key.label
        }
    }

    // MARK: - Bottom Row Modifiers (symbol top center, word bottom center)

    private var isBottomModifier: Bool {
        ["⌃", "⌥", "⌘", "fn"].contains(key.label)
    }

    @ViewBuilder
    private var bottomModifierView: some View {
        if key.label == "fn" {
            // fn key: unified layout with animated transitions
            ZStack {
                // Centered globe (shown when not large)
                Image(systemName: "globe")
                    .font(.system(size: 8.5 * scale, weight: .regular, design: .default))
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                    .opacity(isLargeSize ? 0 : 1)

                // Bottom-aligned layout with label (shown when large)
                // Uses same padding as shift keys for consistency
                VStack {
                    Spacer(minLength: 0)
                    HStack(spacing: 0) {
                        Image(systemName: "globe")
                            .font(.system(size: 8.5 * scale, weight: .regular, design: .default))
                        Spacer(minLength: 0)
                        Text("fn")
                            .font(.system(size: 7 * scale, weight: .regular, design: .default))
                            .lineLimit(1)
                    }
                    .padding(.horizontal, 4 * scale)
                    .padding(.bottom, 3 * scale)
                }
                .opacity(isLargeSize ? 1 : 0)
            }
            .foregroundStyle(foregroundColor)
        } else {
            // Control/Option/Command: unified layout with animated transitions
            let isRightModifier = [54, 61].contains(key.keyCode)
            let alignment: HorizontalAlignment = isRightModifier ? .trailing : .leading

            ZStack {
                // Centered symbol (shown when not large)
                Text(bottomModifierSymbol)
                    .font(.system(size: symbolFontSize, weight: .light, design: .default))
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                    .opacity(isLargeSize ? 0 : 1)

                // Corner-aligned symbol + label (shown when large)
                VStack(alignment: alignment, spacing: 0) {
                    Spacer().frame(minHeight: 2 * scale, maxHeight: 6 * scale)
                    Text(bottomModifierSymbol)
                        .font(.system(size: symbolFontSize, weight: .light, design: .default))
                    Spacer()
                    Text(bottomModifierLabel)
                        .font(.system(size: 7 * scale, weight: .regular, design: .default))
                    Spacer().frame(minHeight: 1 * scale, maxHeight: 3 * scale)
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .center)
                .opacity(isLargeSize ? 1 : 0)
            }
            .foregroundStyle(foregroundColor)
        }
    }

    /// Optical size adjustment - ⌃ needs to be larger to match visual weight of ⌘
    /// Sizes reduced 15% for better proportions
    private var symbolFontSize: CGFloat {
        switch key.label {
        case "⌃": 13 * scale  // Caret is thin, needs to be larger
        case "⌥": 12 * scale  // Option symbol
        case "⌘": 11 * scale  // Command symbol is visually heavy
        default: 11 * scale
        }
    }

    private var bottomModifierSymbol: String {
        switch key.label {
        case "⌃": "⌃"
        case "⌥": "⌥"
        case "⌘": "⌘"
        default: key.label
        }
    }

    private var bottomModifierLabel: String {
        switch key.label {
        case "⌃": "control"
        case "⌥": "option"
        case "⌘": "command"
        default: ""
        }
    }

    // MARK: - Number Keys (digit + shift symbol)

    private var isNumberKey: Bool {
        ["1", "2", "3", "4", "5", "6", "7", "8", "9", "0"].contains(key.label)
    }

    @ViewBuilder
    private var numberKeyView: some View {
        // Number labels match letter keys (12pt medium), symbols sized per character
        VStack(spacing: 2 * scale) {
            Text(numberShiftSymbol)
                .font(.system(size: numberShiftSymbolSize, weight: .light))
                .foregroundStyle(foregroundColor.opacity(isSmallSize ? 0 : 0.6))
            Text(key.label)
                .font(.system(size: 12 * scale, weight: .medium))  // Match letters
                .foregroundStyle(foregroundColor)
                // Offset digits up to align with neighbors (compensate for larger symbols above)
                .offset(y: numberDigitOffset)
        }
    }

    private var numberShiftSymbol: String {
        switch key.label {
        case "1": "!"
        case "2": "@"
        case "3": "#"
        case "4": "$"
        case "5": "%"
        case "6": "^"
        case "7": "&"
        case "8": "*"
        case "9": "("
        case "0": ")"
        default: ""
        }
    }

    /// Per-symbol sizing for number row shift symbols
    private var numberShiftSymbolSize: CGFloat {
        switch key.label {
        case "2": 8.55 * scale   // @ 5% smaller
        case "3": 8.55 * scale   // # 5% smaller
        case "4": 8.55 * scale   // $ 5% smaller
        case "5": 8.55 * scale   // % 5% smaller
        case "6": 10.8 * scale   // ^ 20% larger
        case "7": 8.55 * scale   // & 5% smaller
        case "8": 10.8 * scale   // * 20% larger
        case "9": 8.55 * scale   // ( 5% smaller
        case "0": 8.55 * scale   // ) 5% smaller
        default: 9 * scale       // Base size (! 1)
        }
    }

    /// Vertical offset for number digits to align with neighbors (compensate for larger symbols)
    private var numberDigitOffset: CGFloat {
        switch key.label {
        case "6": -1 * scale     // ^ is 20% larger
        case "8": -1 * scale     // * is 20% larger
        default: 0
        }
    }

    // MARK: - Dual Symbol Keys (, . / etc)

    private var isDualSymbolKey: Bool {
        [",", ".", "/", ";", "'", "[", "]", "\\", "`", "-", "="].contains(key.label)
    }

    @ViewBuilder
    private var dualSymbolKeyView: some View {
        // Matches real MacBook key proportions with optical balancing for similar character pairs
        // Compact keys (:; "' <, >. ?/) use smaller fonts + zero spacing to match letter key heights
        let compactKeys = [";", "'", ",", ".", "/"]
        let isCompact = compactKeys.contains(key.label)
        // Negative spacing for comma/period to compensate for larger < > symbols
        let spacing: CGFloat = isCompact ? compactKeySpacing : 2 * scale

        VStack(spacing: spacing) {
            Text(shiftSymbol)
                .font(.system(size: isCompact ? compactShiftSymbolSize : dualKeyShiftSymbolSize, weight: dualKeyShiftSymbolWeight))
                .foregroundStyle(foregroundColor.opacity(isSmallSize ? 0 : 0.6))
            Text(key.label)
                .font(.system(size: isCompact ? compactMainSymbolSize : dualKeyMainSymbolSize, weight: dualKeyMainSymbolWeight))
                .foregroundStyle(foregroundColor)
        }
    }

    /// Spacing for compact dual-symbol keys
    private var compactKeySpacing: CGFloat {
        switch key.label {
        case ",", ".": -0.5 * scale  // Tighter for larger < > symbols
        default: 0
        }
    }

    /// Compact symbol sizes for :; "' <, >. ?/ keys to match letter key heights
    private var compactShiftSymbolSize: CGFloat {
        switch key.label {
        case ",": 9.9 * scale  // < 10% larger
        case ".": 9.9 * scale  // > 10% larger
        default: 9 * scale
        }
    }

    private var compactMainSymbolSize: CGFloat {
        10 * scale
    }

    /// Size for shift symbols - optically balanced with main symbols
    private var dualKeyShiftSymbolSize: CGFloat {
        switch key.label {
        // Optical pairs - shift symbol sized to match main symbol visually
        case ";": 12 * scale   // : to match ;
        case "'": 12 * scale   // " to match '
        case "[": 10 * scale   // { - 15% smaller (was 12)
        case "]": 10 * scale   // } - 15% smaller (was 12)
        case "\\": 10 * scale  // | - 15% smaller (was 12)
        case ",": 11 * scale   // < +10% (was 10)
        case ".": 11 * scale   // > +10% (was 10)
        case "/": 11 * scale   // ? +10% (was 10)
        case "-": 14 * scale   // _ doubled
        case "=": 10 * scale   // + reduced 25% (was 14)
        case "`": 12.1 * scale  // ~ 10% larger than previous
        default: 7 * scale
        }
    }

    /// Weight for shift symbols - matched with main symbols for optical pairs
    private var dualKeyShiftSymbolWeight: Font.Weight {
        switch key.label {
        // Optical pairs should use same weight
        case ";", "'", "[", "]", "\\": .regular  // : " { } | match their main symbols
        case ",", ".": .regular  // < > regular weight
        case "-", "=": .light  // _ + light weight
        default: .light
        }
    }

    /// Size for main symbols - optically balanced
    private var dualKeyMainSymbolSize: CGFloat {
        switch key.label {
        case ";": 12 * scale   // ; to match :
        case "'": 12 * scale   // ' to match "
        case "[": 10 * scale   // [ - 15% smaller (was 12)
        case "]": 10 * scale   // ] - 15% smaller (was 12)
        case "\\": 10 * scale  // \ - 15% smaller (was 12)
        case ",": 12 * scale   // , to match <
        case ".": 12 * scale   // . to match >
        case "/": 9 * scale    // / -10% (was 10)
        case "-": 10 * scale   // - reduced 30% (was 14)
        case "=": 10 * scale   // = reduced 30% (was 14)
        default: 14 * scale
        }
    }

    /// Weight for main symbols - matched with shift symbols for optical pairs
    private var dualKeyMainSymbolWeight: Font.Weight {
        switch key.label {
        // Optical pairs should use same weight
        case ";", "'", "[", "]", "\\": .regular  // ; ' [ ] \ match their shift symbols
        case ",", ".": .regular
        case "-", "=": .light  // - = light weight
        default: .regular
        }
    }

    private var shiftSymbol: String {
        switch key.label {
        case ",": "<"
        case ".": ">"
        case "/": "?"
        case ";": ":"
        case "'": "\""
        case "[": "{"
        case "]": "}"
        case "\\": "|"
        case "`": "~"
        case "-": "_"
        case "=": "+"
        default: ""
        }
    }

    // MARK: - Letter Keys

    @ViewBuilder
    private var letterKeyView: some View {
        Text(key.label.uppercased())
            .font(.system(size: 12 * scale, weight: .medium))
            .foregroundStyle(foregroundColor)
    }

    // MARK: - Styling

    private var cornerRadius: CGFloat {
        // Arrow keys are smaller, need proportionally smaller radius
        isArrowKey ? 3 * scale : 4 * scale
    }

    private var horizontalPadding: CGFloat {
        // More padding on wide keys for left-aligned text
        key.width > 1.3 ? 4 * scale : 2 * scale
    }

    private var verticalPadding: CGFloat {
        // Vertical padding scales with key size
        2 * scale
    }

    /// Text color - cool blue-white to match MacBook backlight (6500-7000K)
    private var foregroundColor: Color {
        Color(red: 0.88, green: 0.93, blue: 1.0)
            .opacity(isPressed ? 1.0 : 0.88)
    }

    private var backgroundColor: Color {
        isPressed ? Color.accentColor : Color(white: 0.08)
    }
}

// MARK: - Preview

#Preview("Not Pressed") {
    OverlayKeycapView(
        key: PhysicalKey(keyCode: 0, label: "a", x: 0, y: 0),
        isPressed: false,
        scale: 1.0
    )
    .frame(width: 40, height: 40)
    .padding()
}

#Preview("Pressed - Large") {
    OverlayKeycapView(
        key: PhysicalKey(keyCode: 0, label: "a", x: 0, y: 0),
        isPressed: true,
        scale: 2.0
    )
    .frame(width: 80, height: 80)
    .padding()
}
