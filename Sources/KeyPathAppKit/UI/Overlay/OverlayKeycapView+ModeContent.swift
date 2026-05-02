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
        // Check for navigation arrows (Vim style) — keep arrows for hjkl
        else if let info = layerKeyInfo {
            let arrowLabels: Set<String> = ["←", "→", "↑", "↓"]
            if arrowLabels.contains(info.displayLabel) {
                // Large centered arrow
                Text(info.displayLabel)
                    .font(.system(size: 16 * scale, weight: .semibold))
                    .foregroundStyle(Color.white.opacity(0.9))
            }
            // Vim label takes priority over Mac shortcut display
            else if let vimLabel = info.vimLabel, !vimLabel.isEmpty {
                dynamicTextLabel(vimLabel)
                    .help(info.displayLabel)
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

}
