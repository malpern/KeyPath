import AppKit
import KeyPathCore
import SwiftUI

extension OverlayKeycapView {
    var keycapBody: some View {
        ZStack {
            // Key background with subtle shadow
            // Animated color transition for launcher mode (per-key timing variation)
            RoundedRectangle(cornerRadius: cornerRadius)
                .fill(keyBackground)
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                .shadow(color: shadowColor, radius: shadowRadius, y: shadowOffset)
                .overlay(
                    RoundedRectangle(cornerRadius: cornerRadius)
                        .stroke(keyStroke, lineWidth: strokeWidth)
                )
                .animation(nil, value: isLauncherMode)

            // Home row color accent for Kinesis (different keycap color)

            // Hover highlight outline (shows when drawer is open and hovering)
            if isInspectorVisible, isHovering {
                RoundedRectangle(cornerRadius: cornerRadius)
                    .stroke(Color.accentColor, lineWidth: 2 * scale)
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
            }

            // Selection highlight (shows when key is selected in mapper drawer)
            if isSelected {
                RoundedRectangle(cornerRadius: cornerRadius)
                    .stroke(Color.accentColor.opacity(0.8), lineWidth: 2.5 * scale)
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                    .shadow(color: Color.accentColor.opacity(0.4), radius: 4 * scale)
            }

            // Rule hover highlight (shows when hovering a rule in the Custom Rules or Launcher tabs)
            // Matches isSelected style for visual consistency
            if isHoveredByRule, !isSelected {
                RoundedRectangle(cornerRadius: cornerRadius)
                    .stroke(Color.accentColor.opacity(0.8), lineWidth: 2.5 * scale)
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                    .shadow(color: Color.accentColor.opacity(0.4), radius: 4 * scale)
            }

            // Glow layers for dark mode backlight effect
            // Glow increases as keyboard fades out for ethereal effect
            // Skip glow when content is Color.clear (floating labels handle glow instead)
            if isDarkMode, hasVisibleContent {
                keyContent
                    .blur(radius: glowOuterRadius)
                    .opacity(glowOuterOpacity)

                keyContent
                    .blur(radius: glowInnerRadius)
                    .opacity(glowInnerOpacity)
            }

            // Crisp content layer
            keyContent

            // Custom icon overlay (from push-msg, takes precedence over other content)
            if let iconName = customIcon {
                Image(systemName: iconName)
                    .font(.system(size: 20 * scale, weight: .semibold))
                    .foregroundStyle(Color.accentColor)
                    .shadow(color: .black.opacity(0.3), radius: 1 * scale)
            }

            // Caps lock indicator (only for caps lock key)
            if key.label == "⇪" {
                capsLockIndicator
            }
        }
        .scaleEffect(isPressed ? 0.95 : 1.0)
        .offset(y: isPressed && fadeAmount < 1 ? 0.75 * scale : 0)
        .animation(.spring(response: 0.15, dampingFraction: 0.6), value: isPressed)
        .animation(.easeOut(duration: 0.3), value: fadeAmount)
        .animation(.easeInOut(duration: 0.15), value: isHovering)
        // Choreographed transition for launcher mode (label → color → icon)
        // Near-instant transition: labels instant, icons get 50ms fade
        .onChange(of: isLauncherMode) { _, newValue in
            launcherTransition = newValue ? 1 : 0
            withAnimation(.easeOut(duration: 0.05)) {
                iconVisible = newValue
            }
        }
        // Initialize animation state on appear
        .onAppear {
            launcherTransition = isLauncherMode ? 1 : 0
            iconVisible = isLauncherMode
        }
        .animation(nil, value: currentLayerName)
        .allowsHitTesting(isInspectorVisible || key.layoutRole == .touchId)
        // Hover detection (must be before contentShape for hit testing)
        .contentShape(Rectangle())
        .onHover { hovering in
            isHovering = hovering
            // Show pointer cursor for Touch ID key when drawer is closed (indicates clickable)
            if key.layoutRole == .touchId, !isInspectorVisible {
                if hovering {
                    NSCursor.pointingHand.push()
                } else {
                    NSCursor.pop()
                }
            }
        }
        // Click behavior based on drawer state:
        // - Drawer CLOSED: only Touch ID key captures clicks (opens drawer), all other keys pass through for window drag
        // - Drawer OPEN: all keys capture clicks for mapping
        // The `including:` parameter completely disables the gesture when .none, allowing window drag to work
        .simultaneousGesture(
            DragGesture(minimumDistance: 0)
                .onEnded { _ in
                    guard let onKeyClick else { return }
                    onKeyClick(key, layerKeyInfo)
                },
            // Only capture gestures when drawer is open OR this is the Touch ID key
            including: (isInspectorVisible || key.layoutRole == .touchId) ? .all : .none
        )
        .onAppear {
            loadAppIconIfNeeded()
            loadFaviconIfNeeded()
        }
        .onChange(of: layerKeyInfo?.appLaunchIdentifier) { _, newValue in
            if newValue != nil {
                loadAppIconIfNeeded()
            } else {
                appIcon = nil
            }
        }
        .onChange(of: layerKeyInfo?.urlIdentifier) { _, newValue in
            if newValue != nil {
                loadFaviconIfNeeded()
            } else {
                faviconImage = nil
            }
        }
        .onChange(of: launcherMapping?.id) { _, newValue in
            // Reload icons when launcher mapping changes
            if newValue != nil {
                loadAppIconIfNeeded()
                loadFaviconIfNeeded()
            } else {
                appIcon = nil
                faviconImage = nil
            }
        }
        // Accessibility: Make each key discoverable and clickable by automation
        .accessibilityElement(children: .ignore)
        .accessibilityIdentifier(keycapAccessibilityId)
        .accessibilityLabel(keycapAccessibilityLabel)
    }

    /// Accessibility identifier for this keycap
    var keycapAccessibilityId: String {
        "keycap-\(key.label.lowercased().replacingOccurrences(of: " ", with: "-"))"
    }

    /// Accessibility label describing the key and its current mapping
    var keycapAccessibilityLabel: String {
        let keyName = key.label.isEmpty ? "Key \(key.keyCode)" : key.label

        // Launcher mode: describe the app/URL this key launches
        if isLauncherMode, let mapping = launcherMapping {
            let targetType = mapping.target.isApp ? "app" : "website"
            return "\(keyName), launches \(targetType) \(mapping.target.displayName)"
        }

        // For dots legend style, describe the visual representation
        if colorway.legendStyle == .dots {
            let shape = isModifierKey ? "bar" : "dot"
            let colorDescription = dotsColorAccessibilityDescription
            if let info = layerKeyInfo, !info.displayLabel.isEmpty, info.displayLabel != keyName {
                return "\(keyName), \(colorDescription) \(shape), mapped to \(info.displayLabel)"
            }
            return "\(keyName), \(colorDescription) \(shape)"
        }

        if let info = layerKeyInfo, !info.displayLabel.isEmpty, info.displayLabel != keyName {
            return "\(keyName), mapped to \(info.displayLabel)"
        }
        return keyName
    }

    /// Human-readable color description for dots legend accessibility
    private var dotsColorAccessibilityDescription: String {
        guard let config = colorway.dotsConfig else { return "colored" }

        switch config.colorMode {
        case .monochrome:
            return "monochrome"
        case .rainbow:
            // Map column position to color name
            let totalColumns = Int(layoutTotalWidth)
            guard totalColumns > 1 else { return "colored" }
            let normalized = CGFloat(key.x) / CGFloat(totalColumns - 1)
            let colorIndex = Int(normalized * CGFloat(DotsLegendConfig.rainbowPalette.count - 1))
            let clampedIndex = max(0, min(colorIndex, DotsLegendConfig.rainbowPalette.count - 1))

            let colorNames = ["red", "orange", "yellow", "green", "blue", "purple"]
            return colorNames[clampedIndex]
        }
    }

    // MARK: - Content Routing by Layout Role

    @ViewBuilder
    var keyContent: some View {
        // Check legend style first - dots overrides normal content for most keys
        switch colorway.legendStyle {
        case .dots:
            dotsLegendContent
        case .blank:
            // No legend at all
            EmptyView()
        case .iconMods:
            // Icon mods: use symbols for modifiers, standard for others
            iconModsContent
        case .standard:
            standardKeyContent
        }
    }

    /// Standard key content routing (used for .standard legend style)
    @ViewBuilder
    var standardKeyContent: some View {
        // TouchID/Power key: ALWAYS show drawer icon regardless of mode
        if key.keyCode == 0xFFFF {
            touchIdContent
        }
        // Launcher mode: ALL keys use launcher styling (icons for mapped, labels for unmapped)
        else if isLauncherMode {
            launcherModeContent
        }
        // Layer mode (Vim/Nav): ALL keys use layer styling (action in center, label in top-left)
        else if isLayerMode {
            layerModeContent
        }
        // Multi-legend keys (JIS/ISO) get special 4-position rendering
        else if key.hasMultipleLegends {
            multiLegendContent
        }
        // Check for novelty override first (ESC, Enter with special icons)
        else if hasNoveltyKey {
            noveltyKeyContent
        }
        // Function keys always show F-label + icon (even when remapped)
        else if key.layoutRole == .functionKey {
            functionKeyWithMappingContent
        }
        // URL mapping keys show favicon
        else if hasURLMapping {
            urlMappingContent
        }
        // App launch keys show app icon regardless of layout role
        else if hasAppLaunch {
            appLaunchContent
        }
        // System action keys show SF Symbol icon
        else if hasSystemAction {
            systemActionContent
        } else {
            switch key.layoutRole {
            case .centered:
                centeredContent
            case .bottomAligned:
                bottomAlignedContent
            case .narrowModifier:
                narrowModifierContent
            case .functionKey:
                functionKeyContent // Should never reach here due to check above
            case .arrow:
                arrowContent
            case .touchId:
                touchIdContent
            case .escKey:
                escKeyContent
            }
        }
    }
}
