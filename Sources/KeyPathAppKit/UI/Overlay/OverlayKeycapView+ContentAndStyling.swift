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
                .animation(.easeOut(duration: 0.15), value: isPressed)
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

            // Zone subtitle overlay (e.g., ⌃ under Q for hold modifier)
            // Skip when subtitle is rendered inline as a VStack in centeredContent
            if let subtitle = zoneSubtitle, !isLayerMode, !isLauncherMode,
               !zoneSubtitleRenderedInline
            {
                VStack(spacing: 0) {
                    Spacer()
                    Text(subtitle)
                        .font(.system(size: 9 * scale, weight: .medium))
                        .foregroundStyle(Color.white.opacity(0.45))
                        .padding(.bottom, 1 * scale)
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            }

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
        .allowsHitTesting(isAutomationClickable)
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
        // - Drawer CLOSED + launcher mode: tap gestures with count disambiguation (double-click edits, single-click executes)
        // - Drawer CLOSED + base mode: only Touch ID key captures clicks, all other keys pass through for window drag
        // - Drawer OPEN: all keys capture clicks for mapping via DragGesture
        // Touch ID uses highPriorityGesture(TapGesture) so it wins over the parent keyboard's
        // highPriorityGesture(DragGesture) which would otherwise swallow tap events.
        .highPriorityGesture(
            TapGesture()
                .onEnded {
                    guard key.layoutRole == .touchId, let onKeyClick else { return }
                    onKeyClick(key, layerKeyInfo)
                },
            including: key.layoutRole == .touchId ? .all : .none
        )
        // Launcher mode (inspector closed): double-click opens edit panel, single-click executes shortcut.
        // onTapGesture(count:2) before count:1 makes SwiftUI delay the single tap to disambiguate.
        .onTapGesture(count: 2) {
            guard isLauncherMode, !isInspectorVisible, key.layoutRole != .touchId,
                  let onKeyDoubleClick else { return }
            onKeyDoubleClick(key, layerKeyInfo)
        }
        .onTapGesture {
            guard isLauncherMode, !isInspectorVisible, key.layoutRole != .touchId,
                  let onKeyClick else { return }
            onKeyClick(key, layerKeyInfo)
        }
        // Inspector open: DragGesture for key selection (coexists with keyboard drag)
        .simultaneousGesture(
            DragGesture(minimumDistance: 0)
                .onEnded { _ in
                    guard key.layoutRole != .touchId, let onKeyClick else { return }
                    onKeyClick(key, layerKeyInfo)
                },
            including: isInspectorVisible ? .all : .none
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
        .accessibilityValue(keycapAccessibilityValue)
        .accessibilityAddTraits(isAutomationClickable ? .isButton : [])
        .accessibilityAction {
            guard isAutomationClickable, let onKeyClick else { return }
            onKeyClick(key, layerKeyInfo)
        }
    }

    var isAutomationClickable: Bool {
        isInspectorVisible || isLauncherMode || key.layoutRole == .touchId
    }

    /// Accessibility identifier for this keycap
    var keycapAccessibilityId: String {
        "keycap-code-\(key.keyCode)"
    }

    /// Accessibility label describing the key and its current mapping
    var keycapAccessibilityLabel: String {
        let keyName = key.label.isEmpty ? "Key \(key.keyCode)" : key.label

        // Launcher mode: describe the app/URL this key launches
        if isLauncherMode, let mapping = launcherMapping {
            let targetType = mapping.action.isLaunchApp ? "app" : "website"
            return "\(keyName), launches \(targetType) \(mapping.action.displayName)"
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

        guard let info = layerKeyInfo else { return keyName }

        // Layer switch keys
        if info.isLayerSwitch {
            return "\(keyName), layer switch to \(info.displayLabel)"
        }

        // App launch keys (non-launcher mode)
        if let appId = info.appLaunchIdentifier {
            return "\(keyName), launches \(info.displayLabel.isEmpty ? appId : info.displayLabel)"
        }

        // System action keys
        if let actionId = info.systemActionIdentifier {
            return "\(keyName), \(info.displayLabel.isEmpty ? actionId : info.displayLabel)"
        }

        // URL keys
        if let url = info.urlIdentifier {
            return "\(keyName), opens \(info.displayLabel.isEmpty ? url : info.displayLabel)"
        }

        // Tap-hold keys: describe both actions when idle on base layer
        if let idleLabel = tapHoldIdleLabel, !isLauncherMode,
           currentLayerName.lowercased() == "base",
           !info.displayLabel.isEmpty, info.displayLabel != idleLabel
        {
            return "\(keyName), tap \(idleLabel), hold \(info.displayLabel)"
        }

        // Standard mapping
        if !info.displayLabel.isEmpty, info.displayLabel != keyName {
            return "\(keyName), mapped to \(info.displayLabel)"
        }
        return keyName
    }

    /// Accessibility value describing the key's current state
    var keycapAccessibilityValue: String {
        if isPressed, isHoldActive {
            return "held"
        } else if isPressed {
            return "pressed"
        } else if isOneShot {
            return "one-shot active"
        } else if isEmphasized {
            return "highlighted"
        } else if isSelected {
            return "selected"
        }
        return ""
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

    // MARK: - Launcher Mode Exclusions

    var preservesBaseInLauncher: Bool {
        if launcherMapping != nil { return false }
        return switch key.keyCode {
        case 36, 48, 49, 51, 53: true // Return, Tab, Space, Delete, Esc
        case 54, 55, 56, 58, 59, 60, 61, 63: true // Modifiers: Cmd, Shift, Opt, Ctrl, Fn
        case 123, 124, 125, 126: true // Arrow keys
        default: false
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
        // TouchID/Drawer key: ALWAYS show drawer icon regardless of mode
        // Only for keys with .touchId role (keyCode 0xFFFF + label "🔒"),
        // NOT all unmapped keys (layer switches like L0, T1 should show their labels)
        if key.layoutRole == .touchId {
            touchIdContent
        }
        // Launcher mode: mapped keys show icons, unmapped keys use launcher styling
        // Utility keys (tab, esc, shift, modifiers, arrows, etc.) keep base-layer rendering
        else if isLauncherMode, !preservesBaseInLauncher {
            LauncherModeKeycap(
                keyCode: key.keyCode,
                baseLabel: baseLabel,
                holdLabel: holdLabel,
                scale: scale,
                fadeAmount: fadeAmount,
                foregroundColor: foregroundColor,
                launcherMapping: launcherMapping,
                appIcon: appIcon,
                faviconImage: faviconImage,
                launcherTransition: launcherTransition,
                iconVisible: iconVisible
            )
        }
        // Layer mode (Vim/Nav): ALL keys use layer styling (action in center, label in top-left)
        else if isLayerMode {
            LayerModeKeycap(
                key: key,
                baseLabel: baseLabel,
                holdLabel: holdLabel,
                scale: scale,
                currentLayerName: currentLayerName,
                layerKeyInfo: layerKeyInfo,
                customIcon: customIcon,
                zoneSubtitle: zoneSubtitle,
                foregroundColor: foregroundColor,
                appIcon: appIcon,
                faviconImage: faviconImage,
                systemActionIcon: systemActionIcon,
                hasLayerMapping: hasLayerMapping,
                isNavIdentityMapping: isNavIdentityMapping
            )
        }
        // Base layer content (multi-legend, novelty, function, app launch, URL, system action, layout roles)
        else {
            BaseKeycap(
                key: key,
                baseLabel: baseLabel,
                scale: scale,
                foregroundColor: foregroundColor,
                colorway: colorway,
                layerKeyInfo: layerKeyInfo,
                holdLabel: holdLabel,
                tapHoldIdleLabel: tapHoldIdleLabel,
                useFloatingLabels: useFloatingLabels,
                shiftLabelOverride: shiftLabelOverride,
                isPressed: isPressed,
                currentLayerName: currentLayerName,
                isLauncherMode: isLauncherMode,
                isLayerMode: isLayerMode,
                isKeymapTransitioning: isKeymapTransitioning,
                appIcon: appIcon,
                faviconImage: faviconImage,
                systemActionIcon: systemActionIcon,
                zoneSubtitle: zoneSubtitle,
                isLoadingLayerMap: isLoadingLayerMap,
                isCapsLockOn: isCapsLockOn,
                isInlineLayer: isInlineLayer,
                hasLayerMapping: hasLayerMapping
            )
        }
    }
}
