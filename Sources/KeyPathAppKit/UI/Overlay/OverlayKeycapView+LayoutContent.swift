import AppKit
import KeyPathCore
import SwiftUI

// MARK: - Layout-Specific Content Rendering

extension OverlayKeycapView {
    // MARK: - Legend Style: Dots

    /// Renders a colored dot/circle instead of text legend (GMK Dots style)
    @ViewBuilder
    var dotsLegendContent: some View {
        let config = colorway.dotsConfig ?? .default

        // Special keys keep their standard content
        if key.layoutRole == .functionKey {
            functionKeyWithMappingContent
        } else if key.layoutRole == .touchId {
            touchIdContent
        } else if key.layoutRole == .arrow {
            // Arrows show small dots
            dotShape(config: config, isModifier: false, sizeMultiplier: 0.7)
        } else if isModifierKey || key.layoutRole == .bottomAligned || key.layoutRole == .narrowModifier {
            // Modifiers get oblongs (horizontal bars)
            oblongShape(config: config)
        } else if key.layoutRole == .escKey {
            // ESC gets a small dot
            dotShape(config: config, isModifier: false, sizeMultiplier: 0.8)
        } else {
            // Alpha keys get circles
            dotShape(config: config, isModifier: false, sizeMultiplier: 1.0)
        }
    }

    /// Circular dot for alpha keys
    @ViewBuilder
    func dotShape(config: DotsLegendConfig, isModifier _: Bool, sizeMultiplier: CGFloat) -> some View {
        let baseSize: CGFloat = 36 * scale * config.dotSize * sizeMultiplier
        let color = dotColorForCurrentKey(config: config)

        Circle()
            .fill(color)
            .frame(width: baseSize, height: baseSize)
            .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    /// Oblong/bar shape for modifier keys
    @ViewBuilder
    func oblongShape(config: DotsLegendConfig) -> some View {
        let height: CGFloat = 4 * scale
        let width: CGFloat = height * config.oblongWidthMultiplier
        let color = dotColorForCurrentKey(config: config)

        RoundedRectangle(cornerRadius: height / 2)
            .fill(color)
            .frame(width: width, height: height)
            .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    /// Calculate dot color based on key position and config
    func dotColorForCurrentKey(config: DotsLegendConfig) -> Color {
        let fallbackColor = isModifierKey ? colorway.modLegendColor : colorway.alphaLegendColor
        // Use key's x position for column-based rainbow gradient
        // totalColumns derived from layout's actual width
        return config.dotColor(forColumn: Int(key.x), totalColumns: Int(layoutTotalWidth), fallbackColor: fallbackColor)
    }

    // MARK: - Legend Style: Icon Mods

    /// Icon mods style: symbols for modifiers, standard content for others
    @ViewBuilder
    var iconModsContent: some View {
        // Modifiers use symbols only (no text labels)
        if key.layoutRole == .bottomAligned || key.layoutRole == .narrowModifier {
            modifierSymbolOnlyContent
        } else {
            // Non-modifiers use standard content
            standardKeyContent
        }
    }

    /// Modifier with symbol only (no text) for icon mods style
    @ViewBuilder
    var modifierSymbolOnlyContent: some View {
        let symbol = modifierSymbolForKey
        Text(symbol)
            .font(.system(size: 14 * scale, weight: .light))
            .foregroundStyle(foregroundColor)
            .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    /// Get the appropriate symbol for a modifier key
    /// Uses standard Apple/Unicode keyboard symbols for clean icon-only modifiers
    var modifierSymbolForKey: String {
        let label = key.label.lowercased()
        switch label {
        // Modifier keys
        case "⇧", "shift", "lshift", "rshift": return "⇧"
        case "⌃", "ctrl", "control", "lctrl", "rctrl": return "⌃"
        case "⌥", "opt", "option", "alt", "lalt", "ralt": return "⌥"
        case "⌘", "cmd", "command", "lcmd", "rcmd", "meta", "lmeta", "rmeta": return "⌘"
        case "fn", "function": return "🌐"
        case "⇪", "caps", "capslock", "caps lock": return "⇪"
        // Action keys
        case "⌫", "delete", "backspace", "bksp", "bspc": return "⌫"
        case "⌦", "del", "forward delete", "fwd del": return "⌦"
        case "⏎", "↵", "↩", "return", "enter", "ret", "ent": return "↩"
        case "⇥", "tab": return "⇥"
        case "⎋", "esc", "escape": return "⎋"
        case "␣", " ", "space", "spc": return "␣"
        // Navigation keys
        case "home": return "↖"
        case "end": return "↘"
        case "pageup", "pgup", "page up": return "⇞"
        case "pagedown", "pgdn", "page down", "page dn": return "⇟"
        // Arrow keys (filled style for icon mods)
        case "◀", "←", "left": return "◀"
        case "▶", "→", "right": return "▶"
        case "▲", "↑", "up": return "▲"
        case "▼", "↓", "down": return "▼"
        // Media/Function symbols
        case "🔇", "mute": return "🔇"
        case "🔉", "voldown", "vol-": return "🔉"
        case "🔊", "volup", "vol+": return "🔊"
        case "🔅", "bridn", "bri-": return "🔅"
        case "🔆", "briup", "bri+": return "🔆"
        default: return key.label
        }
    }

    // MARK: - Layout: Novelty Keys

    /// Whether this key has a novelty override
    var hasNoveltyKey: Bool {
        colorway.noveltyConfig.noveltyForKey(label: key.label) != nil
    }

    /// Returns novelty content for this key
    @ViewBuilder
    var noveltyKeyContent: some View {
        if let noveltyChar = colorway.noveltyConfig.noveltyForKey(label: key.label) {
            let noveltyColor = colorway.noveltyConfig.useAccentColor
                ? colorway.accentLegendColor
                : foregroundColor
            Text(noveltyChar)
                .font(.system(size: 16 * scale, weight: .medium))
                .foregroundStyle(noveltyColor)
                .frame(maxWidth: .infinity, maxHeight: .infinity)
        }
    }

    // MARK: - Layout: App Launch (shows app icon)

    @ViewBuilder
    var appLaunchContent: some View {
        if let icon = appIcon {
            Image(nsImage: icon)
                .resizable()
                .aspectRatio(contentMode: .fit)
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                .padding(4 * scale)
        } else {
            // Fallback while loading or if icon not found
            Image(systemName: "app.fill")
                .font(.system(size: 14 * scale, weight: .light))
                .foregroundStyle(foregroundColor.opacity(0.6))
                .frame(maxWidth: .infinity, maxHeight: .infinity)
        }
    }

    // MARK: - Layout: URL Mapping (shows favicon)

    @ViewBuilder
    var urlMappingContent: some View {
        if let favicon = faviconImage {
            Image(nsImage: favicon)
                .resizable()
                .aspectRatio(contentMode: .fit)
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                .padding(4 * scale)
        } else {
            // Fallback while loading or if favicon not found
            Image(systemName: "globe")
                .font(.system(size: 14 * scale, weight: .light))
                .foregroundStyle(foregroundColor.opacity(0.6))
                .frame(maxWidth: .infinity, maxHeight: .infinity)
        }
    }

    // MARK: - Layout: System Action (shows SF Symbol icon)

    @ViewBuilder
    var systemActionContent: some View {
        if let iconName = systemActionIcon {
            Image(systemName: iconName)
                .font(.system(size: 10 * scale, weight: .medium))
                .foregroundStyle(foregroundColor)
                .frame(maxWidth: .infinity, maxHeight: .infinity)
        } else {
            // Fallback to text if icon not found
            Text(effectiveLabel)
                .font(.system(size: 14 * scale, weight: .medium))
                .foregroundStyle(foregroundColor)
                .frame(maxWidth: .infinity, maxHeight: .infinity)
        }
    }

    // MARK: - Layout: Centered (letters, symbols, spacebar)

    /// Whether this key has a special label that should always be rendered in the keycap
    /// (not handled by floating labels). Includes navigation keys, system keys, number row, etc.
    ///
    /// IMPORTANT: Checks both `key.label` (physical key) and `baseLabel` (keymap label) to handle
    /// cases where the keymap changes the label (e.g., QWERTZ maps "/" key to "-").
    /// During layout transitions, we prioritize stability by checking physical key first,
    /// but also check keymap label to ensure special keys render correctly.
    var hasSpecialLabel: Bool {
        let specialLabels: Set<String> = [
            "Home", "End", "PgUp", "PgDn", "Del", "␣", "Lyr", "Fn", "Mod", "✦", "◆",
            "↩", "⌫", "⇥", "⇪", "esc", "⎋",
            // Arrow symbols (both solid and outline variants)
            "◀", "▶", "▲", "▼", "←", "→", "↑", "↓",
            // Number row (not in standard keymaps, render directly)
            "`", "1", "2", "3", "4", "5", "6", "7", "8", "9", "0", "-", "=",
            // Function row extras (Print Screen, Scroll Lock, Pause)
            "prt", "scr", "pse",
            // Navigation cluster keys (both cases for matching)
            "ins", "del", "home", "end", "pgup", "pgdn",
            "INS", "DEL", "HOME", "END", "PGUP", "PGDN",
            // Numpad keys (not in standard keymaps)
            "clr", "CLR", "/", "*", "+", ".",
            // JIS-specific keys (not in standard keymaps)
            "¥", "英数", "かな", "_", "^", ":", "@", "fn", "Fn",
            // Menu/Application key
            "☰", "▤",
            // Numpad enter
            "⏎", "⌅",
            // Modifier keys (text labels for split/ergonomic keyboards)
            "Shift", "shift", "⇧",
            "Control", "control", "Ctrl", "ctrl", "⌃",
            "Option", "option", "Alt", "alt", "⌥",
            "Command", "command", "Cmd", "cmd", "⌘",
            // Layer keys (common in split keyboards like Corne)
            "Lower", "lower", "Lwr", "lwr",
            "Raise", "raise", "Rse", "rse",
            "Adjust", "adjust", "Adj", "adj"
        ]
        // Check physical key label first (stable during transitions)
        // Also check keymap label to handle cases where keymap changes the label
        // (e.g., QWERTZ maps "/" key to "-", and "-" is special)
        if specialLabels.contains(key.label) || specialLabels.contains(baseLabel) {
            return true
        }

        // Also treat mapped output labels (e.g., Hyper/Meh) as special so they render in keycaps
        return specialLabels.contains(effectiveLabel)
    }

    /// Word labels for navigation/system keys (like ESC style)
    var navigationWordLabel: String? {
        switch key.label.lowercased() {
        // Navigation cluster
        case "home": "home"
        case "end": "end"
        case "pgup": "pg up"
        case "pgdn": "pg dn"
        case "ins": "insert"
        case "del": "del"
        // Function row extras
        case "prt": "print screen"
        case "scr": "scroll"
        case "pse": "pause"
        // Numpad
        case "clr": "clear"
        // Menu/Application key (hamburger icon)
        case "☰": "menu"
        case "▤": "menu"
        // Other special keys
        case "lyr": "layer"
        case "fn": "fn" // Function key for split keyboards
        case "mod": "mod"
        case "␣": "space"
        case "⌫": "delete"
        case "↩": "return"
        case "⏎": "enter"
        case "⌅": "enter"
        // Modifier keys (text labels for split/ergonomic keyboards)
        case "shift", "⇧": "shift"
        case "control", "ctrl", "⌃": "ctrl"
        case "option", "alt", "⌥": "opt"
        case "command", "cmd", "⌘": "cmd"
        // Layer keys (common in split keyboards like Corne)
        case "lower", "lwr": "lower"
        case "raise", "rse": "raise"
        case "adjust", "adj": "adjust"
        default: nil
        }
    }

    /// SF Symbol for special keys (some use icons instead of text)
    var navigationSFSymbol: String? {
        // Don't use icons - prefer text labels for consistency
        nil
    }

    /// Whether this key is remapped to a different output (displayLabel != baseLabel)
    /// During keymap transitions, always returns false to allow keycaps to render Color.clear
    /// so floating labels can animate
    var isRemappedKey: Bool {
        // During keymap transition window, bypass remap gating to allow animation
        // (keymap switches like QWERTY → Dvorak are implemented as remaps)
        if isKeymapTransitioning {
            return false
        }

        guard let info = layerKeyInfo else { return false }
        return !info.displayLabel.isEmpty && info.displayLabel.uppercased() != baseLabel.uppercased()
    }

    @ViewBuilder
    var centeredContent: some View {
        // When floating labels are enabled, they handle standard alpha/numeric content
        // (letters, numbers, punctuation with shift symbols).
        // Special keys (Home, PgUp, Del, Space, etc.) always render their own labels.
        // EXCEPTION: Remapped keys must render their mapped label directly (no floating label exists for mapped output)
        if useFloatingLabels, !hasSpecialLabel, !isRemappedKey {
            if let navSymbol = navOverlaySymbol {
                // Layer mapping shows arrow - display arrow only, floating label shows base letter
                navOverlayArrowOnly(arrow: navSymbol)
            } else {
                // Standard key - floating labels handle everything
                // Use Color.clear to ensure no content renders during layout transitions
                // This prevents race conditions where both floating labels and keycap content
                // might be visible simultaneously during keymap changes
                Color.clear.frame(maxWidth: .infinity, maxHeight: .infinity)
            }
        } else {
            // Special key rendering - use key.label for physical key identity
            // Only render here when floating labels are disabled OR this is a special key
            if let sfSymbol = navigationSFSymbol {
                // SF Symbol icon (Delete)
                Image(systemName: sfSymbol)
                    .font(.system(size: 10 * scale, weight: .regular))
                    .foregroundStyle(foregroundColor)
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else if let wordLabel = navigationWordLabel {
                // Small word label like ESC (bottom-left aligned)
                navigationWordContent(wordLabel)
            } else if key.label == "Fn" {
                // Fn key uses globe icon like MacBook
                fnKeyContent
            } else if let navSymbol = navOverlaySymbol {
                // Vim nav overlay
                navOverlayContent(arrow: navSymbol, letter: baseLabel)
            } else if let shiftSymbol = metadata.shiftSymbol, !isNumpadKey {
                // Dual symbol content (skip for numpad keys - they don't have shift symbols)
                // Note: This path is only reached when useFloatingLabels is false OR hasSpecialLabel is true
                // When useFloatingLabels is true, floating labels handle dual symbols
                dualSymbolContent(main: effectiveLabel, shift: shiftSymbol)
            } else if let sfSymbol = LabelMetadata.sfSymbol(forOutputLabel: effectiveLabel) {
                // Media key / system action mapped to this key - show SF Symbol
                Image(systemName: sfSymbol)
                    .font(.system(size: 14 * scale, weight: .medium))
                    .foregroundStyle(foregroundColor)
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else {
                // For special keys, prefer key.label if effectiveLabel is empty
                // Numpad keys just show their number/symbol centered
                let displayText = effectiveLabel.isEmpty ? key.label : effectiveLabel
                Text(isNumpadKey ? displayText : displayText.uppercased())
                    .font(.system(size: isNumpadKey ? 14 * scale : 12 * scale, weight: .medium))
                    .foregroundStyle(foregroundColor)
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
            }
        }
    }

    /// Navigation word label content (small bottom-left aligned like ESC)
    @ViewBuilder
    func navigationWordContent(_ label: String) -> some View {
        VStack {
            Spacer(minLength: 0)
            HStack {
                // Special case: "print screen" displays on two lines
                if label.lowercased() == "print screen" {
                    VStack(alignment: .leading, spacing: 0) {
                        Text("print")
                            .font(.system(size: 7 * scale, weight: .regular))
                            .foregroundStyle(foregroundColor)
                        Text("screen")
                            .font(.system(size: 7 * scale, weight: .regular))
                            .foregroundStyle(foregroundColor)
                    }
                } else {
                    Text(label)
                        .font(.system(size: 7 * scale, weight: .regular))
                        .foregroundStyle(foregroundColor)
                }
                Spacer(minLength: 0)
            }
            .padding(.leading, 4 * scale)
            .padding(.trailing, 4 * scale)
            .padding(.bottom, 3 * scale)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    @ViewBuilder
    func dualSymbolContent(main: String, shift: String) -> some View {
        let shiftAdj = OpticalAdjustments.forLabel(shift)
        let mainAdj = OpticalAdjustments.forLabel(main)

        VStack(spacing: dualSymbolSpacing(for: main)) {
            Text(shift)
                .font(.system(
                    size: 8.5 * scale * shiftAdj.fontScale, // Reduced from 9 for better hierarchy
                    weight: .light // Force light weight for subtle shift symbol
                ))
                .foregroundStyle(foregroundColor.opacity(isSmallSize ? 0 : 0.65)) // Increased from 0.6 for visibility

            Text(main)
                .font(.system(
                    size: 12.5 * scale * mainAdj.fontScale, // Increased from 12 for better prominence
                    weight: mainAdj.fontWeight ?? .medium
                ))
                .offset(y: mainAdj.verticalOffset * scale)
                .foregroundStyle(foregroundColor) // Full opacity for main symbol
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    // MARK: - Vim Nav Overlay (arrow + letter)

    var navOverlaySymbol: String? {
        guard key.layoutRole == .centered, let info = layerKeyInfo else { return nil }
        let arrowLabels: Set<String> = ["←", "→", "↑", "↓"]
        if arrowLabels.contains(info.displayLabel) {
            return info.displayLabel
        }
        return nil
    }

    @ViewBuilder
    func navOverlayContent(arrow: String, letter: String) -> some View {
        VStack(spacing: 6 * scale) {
            Text(arrow)
                .font(.system(size: 12 * scale, weight: .semibold))
                .foregroundStyle(Color.white.opacity(isPressed ? 1.0 : 0.9))
                .shadow(color: Color.black.opacity(0.25), radius: 1.5 * scale, y: 1 * scale)
            Text(letter.uppercased())
                .font(.system(size: 9.5 * scale, weight: .medium))
                .foregroundStyle(Color.white.opacity(isPressed ? 0.8 : 0.65))
        }
        .padding(.top, 4 * scale)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    /// Arrow-only version for when floating labels handle the base letter
    @ViewBuilder
    func navOverlayArrowOnly(arrow: String) -> some View {
        Text(arrow)
            .font(.system(size: 14 * scale, weight: .semibold))
            .foregroundStyle(Color.white.opacity(isPressed ? 1.0 : 0.9))
            .shadow(color: Color.black.opacity(0.25), radius: 1.5 * scale, y: 1 * scale)
            .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    func dualSymbolSpacing(for label: String) -> CGFloat {
        switch label {
        case ",", ".": -0.5 * scale // Tighter for < > symbols
        case ";", "'", "/": 0
        default: 2 * scale
        }
    }

    // MARK: - Layout: Bottom Aligned (wide modifiers)

    @ViewBuilder
    var bottomAlignedContent: some View {
        // For wide modifier keys, prefer text labels over symbols
        // If a hold label is active (e.g., tap-hold -> Hyper), show it verbatim.
        // Otherwise use the word-label for the effective label, then fall back to the physical key word-label.
        let physicalMetadata = LabelMetadata.forLabel(key.label)
        let wordLabel: String = {
            if let holdLabel {
                return holdLabel
            }
            // In Nav layer, always use text labels (not symbols) for unmapped keys
            if currentLayerName.lowercased() == "nav" {
                return physicalMetadata.wordLabel ?? key.label
            }
            return metadata.wordLabel ?? physicalMetadata.wordLabel ?? key.label
        }()
        let isRight = key.isRightSideKey
        let isHold = holdLabel != nil

        VStack {
            Spacer(minLength: 0)
            HStack {
                if !isRight {
                    labelText(wordLabel, isHoldLabel: isHold)
                    Spacer(minLength: 0)
                } else {
                    Spacer(minLength: 0)
                    labelText(wordLabel, isHoldLabel: isHold)
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
    func labelText(_ text: String, isHoldLabel: Bool) -> some View {
        // For hold labels (e.g., Hyper ✦) use a larger weighty glyph to make it stand out.
        if isHoldLabel {
            Text(text)
                .font(.system(size: 12 * scale, weight: .semibold))
        } else if isSmallSize {
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
    var narrowModifierContent: some View {
        if key.label == "fn" {
            fnKeyContent
        } else {
            modifierSymbolContent
        }
    }

    @ViewBuilder
    var fnKeyContent: some View {
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
    var modifierSymbolContent: some View {
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

    /// Function key with mapping support - shows icon + F-label
    /// Handles both default function key icons and remapped actions
    @ViewBuilder
    var functionKeyWithMappingContent: some View {
        // Determine which icon to show:
        // 1. System action icon (if mapped to system action like Spotlight)
        // 2. Default function key icon (brightness, volume, etc.)
        let iconName: String? = if hasSystemAction, let sysIcon = systemActionIcon {
            sysIcon
        } else {
            LabelMetadata.sfSymbol(forKeyCode: key.keyCode)
        }

        VStack(spacing: 0) {
            if let icon = iconName {
                Image(systemName: icon)
                    .font(.system(size: 8 * scale, weight: .regular))
                    .foregroundStyle(foregroundColor)
            }
            Spacer()
            // Always show F-key label (F1, F2, etc.)
            Text(key.label)
                .font(.system(size: 5.4 * scale, weight: .regular))
                .foregroundStyle(foregroundColor.opacity(0.6))
        }
        .padding(.top, 4 * scale)
        .padding(.bottom, 2 * scale)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    /// Original function key content (kept for compatibility)
    @ViewBuilder
    var functionKeyContent: some View {
        // Check if this function key is remapped to a non-system key (regular letter/number)
        // If so, show the remapped key in centered layout instead of function key layout
        let remappedLabel = layerKeyInfo?.displayLabel
        let sfSymbolResult = remappedLabel.flatMap { LabelMetadata.sfSymbol(forOutputLabel: $0) }
        let hasSystemRemapping = sfSymbolResult != nil
        let isRemappedToRegularKey = remappedLabel != nil && !hasSystemRemapping && remappedLabel != key.label

        if isRemappedToRegularKey {
            // Show remapped key in centered style (e.g., F8 -> Q shows just "Q")
            Text(remappedLabel!.uppercased())
                .font(.system(size: 10 * scale, weight: .medium))
                .foregroundStyle(foregroundColor)
                .frame(maxWidth: .infinity, maxHeight: .infinity)
        } else {
            // Standard function key layout: SF symbol on top, F-key label below
            let sfSymbol: String? = {
                if let info = layerKeyInfo,
                   let outputSymbol = LabelMetadata.sfSymbol(forOutputLabel: info.displayLabel)
                {
                    return outputSymbol
                }
                // Fall back to physical key code
                return LabelMetadata.sfSymbol(forKeyCode: key.keyCode)
            }()

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
    }

    // MARK: - Layout: Arrow

    @ViewBuilder
    var arrowContent: some View {
        Text(effectiveLabel)
            .font(.system(size: 8 * scale, weight: .regular))
            .foregroundStyle(foregroundColor)
            .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    // MARK: - Layout: Touch ID / Layer Indicator

    @ViewBuilder
    var touchIdContent: some View {
        // Simple centered icon for inspector panel toggle
        if isLoadingLayerMap {
            // Subtle pulsing dot while loading layer mapping
            Circle()
                .fill(foregroundColor.opacity(0.6))
                .frame(width: 4 * scale, height: 4 * scale)
                .modifier(PulseAnimation())
                .frame(maxWidth: .infinity, maxHeight: .infinity)
        } else {
            // Always show drawer icon (sidebar.right opens the inspector drawer)
            Image(systemName: "sidebar.right")
                .font(.system(size: 12 * scale, weight: .regular))
                .foregroundStyle(foregroundColor)
                .frame(maxWidth: .infinity, maxHeight: .infinity)
        }
    }

    // MARK: - Layout: ESC Key

    @ViewBuilder
    var escKeyContent: some View {
        // Match caps lock style: bottom-left aligned using labelText()
        VStack {
            Spacer(minLength: 0)
            HStack {
                labelText("esc", isHoldLabel: false)
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
    var capsLockIndicator: some View {
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
}
