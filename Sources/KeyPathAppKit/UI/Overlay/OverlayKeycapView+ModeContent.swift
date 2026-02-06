import AppKit
import KeyPathCore
import SwiftUI

// MARK: - Multi-Legend, Launcher Mode, and Layer Mode Content

extension OverlayKeycapView {
    // MARK: - Multi-Legend Content (JIS/ISO)

    /// Renders a key with multiple legends in different positions
    /// Two layout modes based on key type:
    ///
    /// **Number row (has shiftLabel)**: 3-position layout
    /// - Top-left: shifted character (e.g., "!")
    /// - Bottom-left: main character (e.g., "1")
    /// - Bottom-right: hiragana (e.g., "ぬ")
    ///
    /// **Alpha keys (no shiftLabel)**: 2-position layout
    /// - Center: LARGE main character (e.g., "Q")
    /// - Bottom-right: small hiragana (e.g., "た")
    var multiLegendContent: some View {
        GeometryReader { geometry in
            let padding: CGFloat = 3 * scale
            let subFontSize: CGFloat = 7 * scale

            // Choose layout based on whether key has shift label
            if key.shiftLabel != nil {
                // Number row style: 3-position layout
                let mainFontSize: CGFloat = 10 * scale
                let shiftFontSize: CGFloat = 8 * scale

                ZStack {
                    // Top-left: shift label (shifted character)
                    if let shiftLabel = key.shiftLabel {
                        Text(shiftLabel)
                            .font(.system(size: shiftFontSize, weight: .regular))
                            .foregroundStyle(foregroundColor.opacity(0.7))
                            .position(
                                x: padding + shiftFontSize / 2,
                                y: padding + shiftFontSize / 2
                            )
                    }

                    // Top-right: tertiary label (optional)
                    if let tertiaryLabel = key.tertiaryLabel {
                        Text(tertiaryLabel)
                            .font(.system(size: subFontSize, weight: .regular))
                            .foregroundStyle(foregroundColor.opacity(0.5))
                            .position(
                                x: geometry.size.width - padding - subFontSize / 2,
                                y: padding + subFontSize / 2
                            )
                    }

                    // Bottom-left: main label (primary character)
                    Text(key.label)
                        .font(.system(size: mainFontSize, weight: .medium))
                        .foregroundStyle(foregroundColor)
                        .position(
                            x: padding + mainFontSize / 2,
                            y: geometry.size.height - padding - mainFontSize / 2
                        )

                    // Bottom-right: sub label (hiragana/katakana)
                    if let subLabel = key.subLabel {
                        Text(subLabel)
                            .font(.system(size: subFontSize, weight: .regular))
                            .foregroundStyle(foregroundColor.opacity(0.6))
                            .position(
                                x: geometry.size.width - padding - subFontSize / 2,
                                y: geometry.size.height - padding - subFontSize / 2
                            )
                    }
                }
                .frame(width: geometry.size.width, height: geometry.size.height)
            } else {
                // Alpha key style: large centered letter + small bottom-right hiragana
                let mainFontSize: CGFloat = 14 * scale

                ZStack {
                    // Center: LARGE main character
                    Text(key.label.uppercased())
                        .font(.system(size: mainFontSize, weight: .medium))
                        .foregroundStyle(foregroundColor)
                        .frame(maxWidth: .infinity, maxHeight: .infinity)

                    // Bottom-right: small hiragana
                    if let subLabel = key.subLabel {
                        VStack {
                            Spacer()
                            HStack {
                                Spacer()
                                Text(subLabel)
                                    .font(.system(size: subFontSize, weight: .regular))
                                    .foregroundStyle(foregroundColor.opacity(0.5))
                                    .padding(.trailing, padding)
                                    .padding(.bottom, padding)
                            }
                        }
                    }
                }
                .frame(width: geometry.size.width, height: geometry.size.height)
            }
        }
    }

    // MARK: - Launcher Mode Content

    /// Label to display in launcher mode (hold label like ✦ takes priority over base label)
    /// For Caps Lock (keyCode 57), always show ✦ in launcher mode since it's the hyper activator
    var launcherKeyLabel: String {
        // Caps Lock is the hyper activator - always show ✦ in launcher mode
        if key.keyCode == 57 {
            return "✦"
        }
        return holdLabel ?? baseLabel
    }

    /// Content for launcher mode: app icon centered, key letter in top-left corner
    /// Uses animated transition values for smooth tab-switching animation
    @ViewBuilder
    var launcherModeContent: some View {
        // Subtle label transition - icons are the focus
        let labelFontSize = lerp(from: 11, to: 8, progress: launcherTransition) * scale
        let labelOpacity = lerp(from: 0.85, to: 0.55, progress: launcherTransition)
        // Label offset: subtle move to top-left (less dramatic than before)
        let labelOffsetX = lerp(from: 0, to: -10, progress: launcherTransition) * scale
        let labelOffsetY = lerp(from: 0, to: -10, progress: launcherTransition) * scale

        // Fade multiplier for keyboard dimming (icons stay visible at 30% when fully dimmed)
        let fadeFactor = 1 - fadeAmount * 0.7

        if let mapping = launcherMapping {
            // Mapped key: app icon centered, key letter fades to corner
            ZStack {
                // Centered icon (app or favicon) - THE STAR OF THE SHOW
                if iconVisible {
                    if let icon = launcherAppIcon {
                        ZStack(alignment: .bottomTrailing) {
                            Image(nsImage: icon)
                                .resizable()
                                .aspectRatio(contentMode: .fit)
                                .frame(width: 20 * scale, height: 20 * scale)
                                .clipShape(RoundedRectangle(cornerRadius: 4 * scale))

                            // Link badge for websites
                            if !mapping.target.isApp {
                                launcherLinkBadge(size: 6 * scale)
                            }
                        }
                        .scaleEffect(iconVisible ? 1.0 : 0.3)
                        .opacity((iconVisible ? 1.0 : 0) * fadeFactor)
                        .offset(x: 2 * scale)
                    } else {
                        // Fallback placeholder while icon loads
                        Image(systemName: mapping.target.isApp ? "app.fill" : "globe")
                            .font(.system(size: 14 * scale))
                            .foregroundStyle(foregroundColor.opacity(0.6))
                            .scaleEffect(iconVisible ? 1.0 : 0.3)
                            .opacity((iconVisible ? 1.0 : 0) * fadeFactor)
                            .offset(x: 2 * scale)
                    }
                }

                // Key letter - fades to corner (subtle, not distracting)
                Text(launcherKeyLabel.uppercased())
                    .font(.system(size: labelFontSize, weight: .medium, design: .rounded))
                    .foregroundStyle(Color.white.opacity(labelOpacity * fadeFactor))
                    .offset(x: labelOffsetX, y: labelOffsetY)
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
        } else {
            // Unmapped key in launcher mode: label fades back
            ZStack {
                Text(launcherKeyLabel.uppercased())
                    .font(.system(size: labelFontSize, weight: .medium, design: .rounded))
                    .foregroundStyle(Color.white.opacity(lerp(from: 0.85, to: 0.4, progress: launcherTransition) * fadeFactor))
                    .offset(x: labelOffsetX, y: labelOffsetY)
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
        }
    }

    /// Linear interpolation helper
    func lerp(from: CGFloat, to: CGFloat, progress: CGFloat) -> CGFloat {
        from + (to - from) * progress
    }

    /// Link indicator for website icons in launcher mode
    /// Simple icon with good contrast, no complex background
    func launcherLinkBadge(size: CGFloat) -> some View {
        Image(systemName: "link")
            .font(.system(size: size * 1.2, weight: .semibold))
            .foregroundStyle(.white)
            .shadow(color: .black.opacity(0.5), radius: 1, y: 0.5)
            .offset(x: size * 0.3, y: size * 0.3)
    }

    /// App icon for launcher mapping (cached in appIcon or faviconImage state)
    var launcherAppIcon: NSImage? {
        appIcon ?? faviconImage
    }

    // MARK: - Layer Mode Content (Vim/Nav)

    /// Label to display in layer mode (hold label like ✦ takes priority, then base label)
    var layerKeyLabel: String {
        // Caps Lock is the hyper activator - always show ✦ in layer mode
        if key.keyCode == 57 {
            return "✦"
        }
        return holdLabel ?? baseLabel
    }

    /// Content for layer mode: action icon/symbol centered, key letter in top-left corner
    @ViewBuilder
    var layerModeContent: some View {
        // Arrow keys don't need top-left label (would just duplicate the arrow)
        let isArrowKey = key.layoutRole == .arrow

        if isNavIdentityMapping {
            navIdentityContent
        } else if hasLayerMapping {
            // Special case: fn key should always show globe + "fn" even when mapped
            if key.label == "fn" {
                fnKeyContent
            } else {
                // For Window layer, prefer SF symbols over text labels
                let useWindowSymbol = currentLayerName.lowercased().contains("window")
                let windowSymbol = useWindowSymbol ? windowActionSymbol(from: layerKeyInfo?.displayLabel ?? "") : nil

                if let symbol = windowSymbol {
                    // Window action with SF Symbol: show symbol in center, key letter in top-left
                    ZStack(alignment: .topLeading) {
                        // Centered SF Symbol
                        Image(systemName: symbol)
                            .font(.system(size: 16 * scale, weight: .semibold))
                            .foregroundStyle(Color.white)
                            .frame(maxWidth: .infinity, maxHeight: .infinity)

                        // Key letter in top-left corner
                        if !isArrowKey {
                            Text(layerKeyLabel.uppercased())
                                .font(.system(size: 8 * scale, weight: .medium, design: .rounded))
                                .foregroundStyle(Color.white.opacity(0.7))
                                .padding(3 * scale)
                        }
                    }
                } else {
                    // Default: action in center, key letter in top-left (except arrows)
                    ZStack(alignment: .topLeading) {
                        // Centered action content
                        layerActionContent
                            .frame(maxWidth: .infinity, maxHeight: .infinity)

                        // Key letter in top-left corner (skip for arrow keys to avoid dual arrows)
                        if !isArrowKey {
                            Text(layerKeyLabel.uppercased())
                                .font(.system(size: 8 * scale, weight: .medium, design: .rounded))
                                .foregroundStyle(Color.white.opacity(0.7))
                                .padding(3 * scale)
                        }
                    }
                }
            }
        } else {
            // Unmapped key in layer mode: small label in top-left (skip for arrows and bottom row modifiers)
            if isArrowKey {
                // Arrow keys: just show centered arrow
                arrowContent
            } else if key.layoutRole == .narrowModifier {
                // Bottom row modifiers (fn, ctrl, opt, cmd): render same as base layer
                narrowModifierContent
            } else {
                // In Nav layer, convert symbols to text labels (except modifier keys)
                let displayLabel: String = {
                    if currentLayerName.lowercased() == "nav" {
                        // Keep modifier symbols (⌃, ⌥, ⌘) as-is, convert others to text
                        let modifierSymbols: Set<String> = ["⌃", "⌥", "⌘", "fn"]
                        if modifierSymbols.contains(layerKeyLabel) {
                            return layerKeyLabel
                        }
                        let physicalMetadata = LabelMetadata.forLabel(layerKeyLabel)
                        return physicalMetadata.wordLabel ?? layerKeyLabel
                    }
                    return layerKeyLabel
                }()

                // Keep letter keys uppercase, but word labels (tab, shift, etc.) lowercase
                let finalLabel = displayLabel.count > 2 ? displayLabel : displayLabel.uppercased()

                // Caps lock (hyper key) shows ✦ at bottom to avoid overlapping with indicator light
                let isCapsLock = key.keyCode == 57
                let alignment: Alignment = isCapsLock ? .bottomLeading : .topLeading

                ZStack(alignment: alignment) {
                    Text(finalLabel)
                        .font(.system(size: 8 * scale, weight: .medium, design: .rounded))
                        .foregroundStyle(Color.white.opacity(0.5))
                        .padding(3 * scale)
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: alignment)
            }
        }
    }

    /// Nav-layer identity mapping: large centered label (same visual weight as base layer)
    var navIdentityContent: some View {
        Text(baseLabel.uppercased())
            .font(.system(size: 12 * scale, weight: .medium))
            .foregroundStyle(foregroundColor)
            .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    /// The action content to display in center for layer mode (arrows, icons, etc.)
    @ViewBuilder
    var layerActionContent: some View {
        // Check for custom icon from push-msg first (highest priority)
        if let iconName = customIcon {
            // Try as SF Symbol first
            Image(systemName: iconName)
                .font(.system(size: 18 * scale, weight: .medium))
                .foregroundStyle(Color.accentColor.opacity(0.9))
        }
        // Check for app icon
        else if let icon = appIcon {
            Image(nsImage: icon)
                .resizable()
                .aspectRatio(contentMode: .fit)
                .frame(width: 18 * scale, height: 18 * scale)
                .clipShape(RoundedRectangle(cornerRadius: 4 * scale))
        }
        // Check for favicon (URL mapping)
        else if let favicon = faviconImage {
            Image(nsImage: favicon)
                .resizable()
                .aspectRatio(contentMode: .fit)
                .frame(width: 18 * scale, height: 18 * scale)
                .clipShape(RoundedRectangle(cornerRadius: 4 * scale))
        }
        // Check for system action SF Symbol
        else if let iconName = systemActionIcon {
            Image(systemName: iconName)
                .font(.system(size: 14 * scale, weight: .medium))
                .foregroundStyle(Color.white.opacity(0.9))
        }
        // Check for navigation arrows (Vim style)
        else if let info = layerKeyInfo {
            let arrowLabels: Set<String> = ["←", "→", "↑", "↓"]
            if arrowLabels.contains(info.displayLabel) {
                // Large centered arrow
                Text(info.displayLabel)
                    .font(.system(size: 16 * scale, weight: .semibold))
                    .foregroundStyle(Color.white.opacity(0.9))
            } else if !info.displayLabel.isEmpty {
                // Skip SF symbols for modifier/special keys - keep text labels
                let skipSymbolConversion = isModifierOrSpecialKey(info.displayLabel)

                // Check for action-specific SF Symbol (window management, etc.)
                // But skip if it's a modifier/special key
                if !skipSymbolConversion, let actionSymbol = sfSymbolForAction(info.displayLabel) {
                    Image(systemName: actionSymbol)
                        .font(.system(size: 14 * scale, weight: .medium))
                        .foregroundStyle(Color.white.opacity(0.9))
                        .help(info.displayLabel) // Tooltip on hover
                }
                // Check for SF symbol (media keys, system actions)
                else if !skipSymbolConversion, let sfSymbol = LabelMetadata.sfSymbol(forOutputLabel: info.displayLabel) {
                    Image(systemName: sfSymbol)
                        .font(.system(size: 14 * scale, weight: .medium))
                        .foregroundStyle(Color.white.opacity(0.9))
                        .help(info.displayLabel) // Tooltip on hover
                } else {
                    // No SF Symbol - use dynamic text with wrapping
                    dynamicTextLabel(info.displayLabel)
                        .help(info.displayLabel) // Tooltip on hover
                }
            }
        }
    }

    /// Check if a label represents a modifier or special key that should keep text labels
    /// instead of being converted to SF symbols
    func isModifierOrSpecialKey(_ label: String) -> Bool {
        let lower = label.lowercased()
        let modifierKeys: Set<String> = [
            "shift", "lshift", "rshift", "leftshift", "rightshift",
            "control", "ctrl", "lctrl", "rctrl", "leftcontrol", "rightcontrol",
            "option", "opt", "alt", "lalt", "ralt", "leftoption", "rightoption",
            "command", "cmd", "meta", "lmet", "rmet", "leftcommand", "rightcommand",
            "hyper", "meh",
            "capslock", "caps",
            "return", "enter", "ret",
            "escape", "esc",
            "tab",
            "space", "spc",
            "backspace", "bspc",
            "delete", "del",
            "fn", "function"
        ]
        return modifierKeys.contains(lower)
    }

    /// Map action descriptions to SF Symbols
    /// Returns SF Symbol name if a good match exists for the action
    func sfSymbolForAction(_ action: String) -> String? {
        let lower = action.lowercased()

        // Window management - snapping to halves
        if lower.contains("left") && lower.contains("half") {
            return "rectangle.lefthalf.filled"
        }
        if lower.contains("right") && lower.contains("half") {
            return "rectangle.righthalf.filled"
        }
        if lower.contains("top") && lower.contains("half") {
            return "rectangle.tophalf.filled"
        }
        if lower.contains("bottom") && lower.contains("half") {
            return "rectangle.bottomhalf.filled"
        }

        // Window management - corners
        if lower.contains("top") && lower.contains("left") && lower.contains("corner") {
            return "arrow.up.left"
        }
        if lower.contains("top") && lower.contains("right") && lower.contains("corner") {
            return "arrow.up.right"
        }
        if lower.contains("bottom") && lower.contains("left") && lower.contains("corner") {
            return "arrow.down.left"
        }
        if lower.contains("bottom") && lower.contains("right") && lower.contains("corner") {
            return "arrow.down.right"
        }

        // Window management - maximize/fullscreen
        if lower.contains("maximize") || lower.contains("fullscreen") || lower.contains("full screen") {
            return "arrow.up.left.and.arrow.down.right"
        }
        if lower.contains("restore") {
            return "arrow.down.right.and.arrow.up.left"
        }
        if lower.contains("center") && !lower.contains("align") {
            return "circle.grid.cross"
        }

        // Window management - display/monitor movement
        if lower.contains("next display") || lower.contains("display right") || lower.contains("move right display") {
            return "arrow.right.to.line"
        }
        if lower.contains("previous display") || lower.contains("display left") || lower.contains("move left display") {
            return "arrow.left.to.line"
        }

        // Window management - space/desktop movement
        if lower.contains("next space") || lower.contains("space right") {
            return "arrow.right.square"
        }
        if lower.contains("previous space") || lower.contains("space left") {
            return "arrow.left.square"
        }

        // Window management - thirds
        if lower.contains("left third") || lower.contains("left 1/3") {
            return "rectangle.leadinghalf.filled"
        }
        if lower.contains("center third") || lower.contains("middle third") {
            return "rectangle.center.inset.filled"
        }
        if lower.contains("right third") || lower.contains("right 1/3") {
            return "rectangle.trailinghalf.filled"
        }

        // Window management - two-thirds
        if lower.contains("left two thirds") || lower.contains("left 2/3") {
            return "rectangle.leadingthird.inset.filled"
        }
        if lower.contains("right two thirds") || lower.contains("right 2/3") {
            return "rectangle.trailingthird.inset.filled"
        }

        // Navigation - directional (when not already arrows)
        if lower == "up" || lower == "move up" {
            return "arrow.up"
        }
        if lower == "down" || lower == "move down" {
            return "arrow.down"
        }
        if lower == "left" || lower == "move left" {
            return "arrow.left"
        }
        if lower == "right" || lower == "move right" {
            return "arrow.right"
        }

        // Common text editing actions
        if lower.contains("yank") || lower.contains("copy") {
            return "doc.on.doc"
        }
        if lower.contains("paste") {
            return "doc.on.clipboard"
        }
        if lower.contains("delete") || lower.contains("remove") {
            return "trash"
        }
        if lower.contains("undo") {
            return "arrow.uturn.backward"
        }
        if lower.contains("redo") {
            return "arrow.uturn.forward"
        }
        if lower.contains("save") {
            return "square.and.arrow.down"
        }

        // Search/Find
        if lower.contains("search") || lower.contains("find") {
            return "magnifyingglass"
        }

        // No good SF Symbol match
        return nil
    }

    /// Render text label with dynamic sizing and multi-line wrapping
    func dynamicTextLabel(_ text: String) -> some View {
        GeometryReader { geometry in
            let availableWidth = geometry.size.width - 4 * scale
            let availableHeight = geometry.size.height - 4 * scale
            let preferredSize: CGFloat = 10 * scale
            let mediumSize: CGFloat = 8 * scale
            let smallSize: CGFloat = 6 * scale
            let estimatedWidth = CGFloat(text.count) * preferredSize * 0.6
            let fontSize = estimatedWidth <= availableWidth ? preferredSize : (estimatedWidth <= availableWidth * 1.5 ? mediumSize : smallSize)

            Text(text.uppercased())
                .font(.system(size: fontSize, weight: .medium))
                .foregroundStyle(Color.white.opacity(0.9))
                .lineLimit(2)
                .multilineTextAlignment(.center)
                .minimumScaleFactor(0.5)
                .frame(maxWidth: availableWidth, maxHeight: availableHeight)
                .frame(maxWidth: .infinity, maxHeight: .infinity)
        }
    }
}
