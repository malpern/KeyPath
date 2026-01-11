import AppKit
import KeyPathCore
import SwiftUI

/// A read-only keycap for the live overlay.
/// Uses layout roles (based on physical properties) for structure,
/// and optical adjustments (based on label) for visual harmony.
struct OverlayKeycapView: View {
    let key: PhysicalKey
    let baseLabel: String
    let isPressed: Bool
    /// Scale factor from keyboard resize (1.0 = default size)
    let scale: CGFloat
    /// Whether dark mode is active (for backlight glow)
    var isDarkMode: Bool = false
    /// Whether caps lock is engaged (for indicator light)
    var isCapsLockOn: Bool = false
    /// Fade amount: 0 = fully visible, 1 = fully faded
    var fadeAmount: CGFloat = 0
    /// Whether this is a per-key release fade (vs global overlay fade)
    var isReleaseFading: Bool = false
    /// Current layer name for Touch ID key display
    var currentLayerName: String = "base"
    /// Whether layer mapping is loading (shows spinner on Touch ID key)
    var isLoadingLayerMap: Bool = false
    /// Layer-specific key info (what this key does in current layer)
    var layerKeyInfo: LayerKeyInfo?
    /// Whether this key is emphasized (highlighted with accent color for layer hints)
    var isEmphasized: Bool = false
    /// Whether this key has an active one-shot modifier (temporary highlight)
    var isOneShot: Bool = false
    /// Hold label to display when tap-hold key is in hold state
    var holdLabel: String?
    /// Idle label to display for tap-hold inputs when not pressed
    var tapHoldIdleLabel: String?
    /// Callback when key is clicked (not dragged)
    var onKeyClick: ((PhysicalKey, LayerKeyInfo?) -> Void)?
    /// GMK colorway for keycap styling
    var colorway: GMKColorway = .default
    /// Layout total width for rainbow gradient calculation (default 15 for standard keyboards)
    var layoutTotalWidth: CGFloat = 15.0
    /// Whether to hide alpha labels (used when floating labels handle animation)
    var useFloatingLabels: Bool = false
    /// Whether to show scooped/dished home row keys (Kinesis style)
    var showScoopedHomeRow: Bool = false
    /// Whether this key is selected in the mapper drawer (shows selection highlight)
    var isSelected: Bool = false
    /// Whether this key is being hovered in the rules/launcher list (shows secondary highlight)
    var isHoveredByRule: Bool = false
    /// Whether the inspector/drawer is visible (determines click vs drag behavior)
    var isInspectorVisible: Bool = false
    /// Custom icon name set via push-msg (e.g., "arrow-left", "safari")
    var customIcon: String?

    // MARK: - Launcher Mode

    /// Whether launcher mode is active (shows app icons on mapped keys)
    var isLauncherMode: Bool = false
    /// Launcher mapping for this key (nil = no mapping)
    var launcherMapping: LauncherMapping?
    /// Whether we're in a keymap transition window (bypasses remap gating for animation)
    var isKeymapTransitioning: Bool = false

    /// Whether this key has a launcher mapping
    private var hasLauncherMapping: Bool {
        launcherMapping != nil
    }

    // MARK: - Layer Mode (Vim/Nav)

    /// Whether we're in a non-base layer (e.g., nav, vim) but not launcher mode
    private var isLayerMode: Bool {
        !isLauncherMode && currentLayerName.lowercased() != "base" && currentLayerName.lowercased() != "Base"
    }

    /// Whether this key has a meaningful layer mapping (not transparent/identity)
    private var hasLayerMapping: Bool {
        guard let info = layerKeyInfo else { return false }
        // Bottom row modifier keys (fn, ctrl, opt, cmd) should never show as mapped in layer modes
        // They are fundamental modifiers that should look consistent across all layers
        if key.layoutRole == .narrowModifier {
            return false
        }
        // Has a mapping if it's not transparent and has actual content
        if info.isTransparent { return false }
        if info.isLayerSwitch { return true }
        if info.appLaunchIdentifier != nil { return true }
        if info.systemActionIdentifier != nil { return true }
        if info.urlIdentifier != nil { return true }
        // Check if output differs from input (not identity mapping)
        if let outputKey = info.outputKey {
            return outputKey.lowercased() != inputKeyName
        }
        return !info.displayLabel.isEmpty && info.displayLabel.lowercased() != inputKeyName
    }

    /// Size thresholds for typography adaptation
    private var isSmallSize: Bool { scale < 0.8 }
    private var isLargeSize: Bool { scale >= 1.5 }

    /// Home row keyCodes (A, S, D, F, J, K, L, ;)
    private static let homeRowKeyCodes: Set<UInt16> = [0, 1, 2, 3, 38, 40, 37, 41]

    /// Whether this key is a home row key
    private var isHomeRowKey: Bool {
        Self.homeRowKeyCodes.contains(key.keyCode)
    }

    /// Whether this keycap has visible content (not Color.clear)
    /// When floating labels are enabled, standard keys render Color.clear and floating labels handle the content
    private var hasVisibleContent: Bool {
        // If floating labels are disabled, always render content
        guard useFloatingLabels else { return true }

        // Special keys always render their own content
        if hasSpecialLabel { return true }

        // If there's a nav overlay symbol, render it (arrow only, letter handled by floating label)
        if navOverlaySymbol != nil { return true }

        // If key is remapped to a different output, render the label directly
        // (floating labels only exist for base layout characters like A-Z, not for mapped outputs)
        if let info = layerKeyInfo,
           !info.displayLabel.isEmpty,
           info.displayLabel.uppercased() != baseLabel.uppercased() {
            return true
        }

        // Otherwise, content is Color.clear (floating labels handle it)
        return false
    }

    /// The effective label to display (hold label > layer mapping > keymap/physical)
    private var effectiveLabel: String {
        // When key is pressed with a hold label, show the hold label
        if isPressed, let holdLabel {
            return holdLabel
        }

        if !isPressed, let tapHoldIdleLabel, shouldShowTapHoldIdleLabel {
            return tapHoldIdleLabel
        }

        guard let info = layerKeyInfo else {
            return baseLabel
        }

        // Empty displayLabel means no meaningful mapping - fall back to base label
        // Exception: if layer explicitly blocked the key, show empty
        if info.displayLabel.isEmpty {
            // Fall back to physical key label (e.g., for number keys that passthrough)
            return baseLabel.isEmpty ? key.label : baseLabel
        }

        if shouldUseBaseLabel, baseLabel != key.label {
            return baseLabel
        }

        return info.displayLabel
    }

    private var shouldShowTapHoldIdleLabel: Bool {
        guard !isLauncherMode else { return false }
        return currentLayerName.lowercased() == "base"
    }

    /// Input key name (kanata/TCP) for identity mapping checks
    private var inputKeyName: String {
        OverlayKeyboardView.keyCodeToKanataName(key.keyCode).lowercased()
    }

    /// Whether the overlay should fall back to the base label (keymap or physical)
    private var shouldUseBaseLabel: Bool {
        guard let info = layerKeyInfo else { return true }
        if info.isTransparent { return true }
        if info.isLayerSwitch { return false }
        if info.appLaunchIdentifier != nil || info.systemActionIdentifier != nil || info.urlIdentifier != nil {
            return false
        }
        // Prefer mapped labels (including modifier-only outputs like Hyper) when they differ from input.
        if !info.displayLabel.isEmpty, info.displayLabel.lowercased() != inputKeyName {
            return false
        }
        if let outputKey = info.outputKey {
            return outputKey.lowercased() == inputKeyName
        }
        return true
    }

    /// Optical adjustments for current label
    private var adjustments: OpticalAdjustments {
        OpticalAdjustments.forLabel(effectiveLabel)
    }

    /// Metadata for current label
    private var metadata: LabelMetadata {
        LabelMetadata.forLabel(effectiveLabel)
    }

    /// Whether mouse is hovering over this key
    @State private var isHovering = false

    /// Cached app icon for launch actions
    @State private var appIcon: NSImage?

    /// Cached favicon for URL actions
    @State private var faviconImage: NSImage?

    // MARK: - Tab Transition Animation State

    /// Animation progress for launcher mode transition (0 = standard, 1 = launcher)
    @State private var launcherTransition: CGFloat = 0
    /// Whether icon should be visible (delayed appearance)
    @State private var iconVisible: Bool = false

    /// Per-key animation variation (0.0 to 1.0) based on distance from home row
    /// Home row keys move first and fastest; keys further away are noticeably slower
    private var keyAnimationVariation: CGFloat {
        // Home row is at y ≈ 2 (A, S, D, F, G, H, J, K, L row)
        let homeRowY: CGFloat = 2.0
        let maxDistance: CGFloat = 3.0 // Max rows away from home row

        // Distance from home row (0 = home row, higher = further)
        let homeRowDistance = abs(key.y - homeRowY)
        let distanceFactor = min(homeRowDistance / maxDistance, 1.0)

        // Apply power curve to make the difference more dramatic
        // Home row stays near 0, but each row away jumps more significantly
        let dramaticFactor = pow(distanceFactor, 0.7)

        // Small random noise for organic feel (scaled by distance)
        let noise = sin(CGFloat(key.keyCode) * 0.7 + key.x * 0.3) * 0.08

        // Home row: ~0, row±1: ~0.4, row±2: ~0.7, far rows: ~1.0
        return min(1.0, dramaticFactor + noise * distanceFactor)
    }

    /// Per-key delay in milliseconds (home row: 0ms, far keys: up to 60ms)
    private var keyAnimationDelayMs: Int {
        Int(keyAnimationVariation * 60)
    }

    /// Per-key spring response (home row: very snappy 0.18, far keys: slow 0.5)
    private var keySpringResponse: CGFloat {
        0.18 + keyAnimationVariation * 0.32
    }

    /// Per-key spring damping (home row: bouncy 0.5, far keys: heavy 0.85)
    private var keySpringDamping: CGFloat {
        0.5 + keyAnimationVariation * 0.35
    }

    /// Whether this key has an app launch action
    private var hasAppLaunch: Bool {
        layerKeyInfo?.appLaunchIdentifier != nil
    }

    /// Whether this key has a system action
    private var hasSystemAction: Bool {
        layerKeyInfo?.systemActionIdentifier != nil
    }

    /// Whether this key has a URL mapping
    private var hasURLMapping: Bool {
        layerKeyInfo?.urlIdentifier != nil
    }

    /// SF Symbol icon for system action (resolved via IconResolverService)
    private var systemActionIcon: String? {
        guard let actionId = layerKeyInfo?.systemActionIdentifier else { return nil }
        return IconResolverService.shared.systemActionSymbol(for: actionId)
    }

    var body: some View {
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
            if isHoveredByRule, !isSelected {
                RoundedRectangle(cornerRadius: cornerRadius)
                    .stroke(Color.accentColor.opacity(0.6), lineWidth: 2 * scale)
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
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
    private var keycapAccessibilityId: String {
        "keycap-\(key.label.lowercased().replacingOccurrences(of: " ", with: "-"))"
    }

    /// Accessibility label describing the key and its current mapping
    private var keycapAccessibilityLabel: String {
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

    // MARK: - App Icon Loading

    /// Load app icon for launch action if needed (via IconResolverService)
    private func loadAppIconIfNeeded() {
        // Check layer-based app launch first
        if let appIdentifier = layerKeyInfo?.appLaunchIdentifier {
            appIcon = IconResolverService.shared.resolveAppIcon(for: appIdentifier)
            return
        }

        // Check launcher mapping for app target
        if let mapping = launcherMapping, case let .app(name, bundleId) = mapping.target {
            appIcon = AppIconResolver.icon(for: .app(name: name, bundleId: bundleId))
            return
        }

        appIcon = nil
    }

    // MARK: - Favicon Loading

    /// Load favicon for URL action if needed (via IconResolverService)
    private func loadFaviconIfNeeded() {
        // Check layer-based URL first
        if let url = layerKeyInfo?.urlIdentifier {
            Task { @MainActor in
                faviconImage = await IconResolverService.shared.resolveFavicon(for: url)
            }
            return
        }

        // Check launcher mapping for URL target
        if let mapping = launcherMapping, case let .url(urlString) = mapping.target {
            Task { @MainActor in
                faviconImage = await IconResolverService.shared.resolveFavicon(for: urlString)
            }
            return
        }

        faviconImage = nil
    }

    // MARK: - Content Routing by Layout Role

    @ViewBuilder
    private var keyContent: some View {
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
    private var standardKeyContent: some View {
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
    @ViewBuilder
    private var multiLegendContent: some View {
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
    private var launcherKeyLabel: String {
        // Caps Lock is the hyper activator - always show ✦ in launcher mode
        if key.keyCode == 57 {
            return "✦"
        }
        return holdLabel ?? baseLabel
    }

    /// Content for launcher mode: app icon centered, key letter in top-left corner
    /// Uses animated transition values for smooth tab-switching animation
    @ViewBuilder
    private var launcherModeContent: some View {
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
    private func lerp(from: CGFloat, to: CGFloat, progress: CGFloat) -> CGFloat {
        from + (to - from) * progress
    }

    /// Link indicator for website icons in launcher mode
    /// Simple icon with good contrast, no complex background
    @ViewBuilder
    private func launcherLinkBadge(size: CGFloat) -> some View {
        Image(systemName: "link")
            .font(.system(size: size * 1.2, weight: .semibold))
            .foregroundStyle(.white)
            .shadow(color: .black.opacity(0.5), radius: 1, y: 0.5)
            .offset(x: size * 0.3, y: size * 0.3)
    }

    /// App icon for launcher mapping (cached in appIcon or faviconImage state)
    private var launcherAppIcon: NSImage? {
        appIcon ?? faviconImage
    }

    // MARK: - Layer Mode Content (Vim/Nav)

    /// Label to display in layer mode (hold label like ✦ takes priority, then base label)
    private var layerKeyLabel: String {
        // Caps Lock is the hyper activator - always show ✦ in layer mode
        if key.keyCode == 57 {
            return "✦"
        }
        return holdLabel ?? baseLabel
    }

    /// Content for layer mode: action icon/symbol centered, key letter in top-left corner
    @ViewBuilder
    private var layerModeContent: some View {
        // Arrow keys don't need top-left label (would just duplicate the arrow)
        let isArrowKey = key.layoutRole == .arrow

        if hasLayerMapping {
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

    /// The action content to display in center for layer mode (arrows, icons, etc.)
    @ViewBuilder
    private var layerActionContent: some View {
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
    private func isModifierOrSpecialKey(_ label: String) -> Bool {
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
    private func sfSymbolForAction(_ action: String) -> String? {
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
    @ViewBuilder
    private func dynamicTextLabel(_ text: String) -> some View {
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

    // MARK: - Legend Style: Dots

    /// Renders a colored dot/circle instead of text legend (GMK Dots style)
    @ViewBuilder
    private var dotsLegendContent: some View {
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
    private func dotShape(config: DotsLegendConfig, isModifier _: Bool, sizeMultiplier: CGFloat) -> some View {
        let baseSize: CGFloat = 36 * scale * config.dotSize * sizeMultiplier
        let color = dotColorForCurrentKey(config: config)

        Circle()
            .fill(color)
            .frame(width: baseSize, height: baseSize)
            .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    /// Oblong/bar shape for modifier keys
    @ViewBuilder
    private func oblongShape(config: DotsLegendConfig) -> some View {
        let height: CGFloat = 4 * scale
        let width: CGFloat = height * config.oblongWidthMultiplier
        let color = dotColorForCurrentKey(config: config)

        RoundedRectangle(cornerRadius: height / 2)
            .fill(color)
            .frame(width: width, height: height)
            .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    /// Calculate dot color based on key position and config
    private func dotColorForCurrentKey(config: DotsLegendConfig) -> Color {
        let fallbackColor = isModifierKey ? colorway.modLegendColor : colorway.alphaLegendColor
        // Use key's x position for column-based rainbow gradient
        // totalColumns derived from layout's actual width
        return config.dotColor(forColumn: Int(key.x), totalColumns: Int(layoutTotalWidth), fallbackColor: fallbackColor)
    }

    // MARK: - Legend Style: Icon Mods

    /// Icon mods style: symbols for modifiers, standard content for others
    @ViewBuilder
    private var iconModsContent: some View {
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
    private var modifierSymbolOnlyContent: some View {
        let symbol = modifierSymbolForKey
        Text(symbol)
            .font(.system(size: 14 * scale, weight: .light))
            .foregroundStyle(foregroundColor)
            .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    /// Get the appropriate symbol for a modifier key
    /// Uses standard Apple/Unicode keyboard symbols for clean icon-only modifiers
    private var modifierSymbolForKey: String {
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
    private var hasNoveltyKey: Bool {
        colorway.noveltyConfig.noveltyForKey(label: key.label) != nil
    }

    /// Returns novelty content for this key
    @ViewBuilder
    private var noveltyKeyContent: some View {
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
    private var appLaunchContent: some View {
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
    private var urlMappingContent: some View {
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
    private var systemActionContent: some View {
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
    private var hasSpecialLabel: Bool {
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
    private var navigationWordLabel: String? {
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
    private var navigationSFSymbol: String? {
        // Don't use icons - prefer text labels for consistency
        nil
    }

    /// Whether this key is remapped to a different output (displayLabel != baseLabel)
    /// During keymap transitions, always returns false to allow keycaps to render Color.clear
    /// so floating labels can animate
    private var isRemappedKey: Bool {
        // During keymap transition window, bypass remap gating to allow animation
        // (keymap switches like QWERTY → Dvorak are implemented as remaps)
        if isKeymapTransitioning {
            return false
        }

        guard let info = layerKeyInfo else { return false }
        return !info.displayLabel.isEmpty && info.displayLabel.uppercased() != baseLabel.uppercased()
    }

    @ViewBuilder
    private var centeredContent: some View {
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
    private func navigationWordContent(_ label: String) -> some View {
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
    private func dualSymbolContent(main: String, shift: String) -> some View {
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

    private var navOverlaySymbol: String? {
        guard key.layoutRole == .centered, let info = layerKeyInfo else { return nil }
        let arrowLabels: Set<String> = ["←", "→", "↑", "↓"]
        if arrowLabels.contains(info.displayLabel) {
            return info.displayLabel
        }
        return nil
    }

    @ViewBuilder
    private func navOverlayContent(arrow: String, letter: String) -> some View {
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
    private func navOverlayArrowOnly(arrow: String) -> some View {
        Text(arrow)
            .font(.system(size: 14 * scale, weight: .semibold))
            .foregroundStyle(Color.white.opacity(isPressed ? 1.0 : 0.9))
            .shadow(color: Color.black.opacity(0.25), radius: 1.5 * scale, y: 1 * scale)
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
    private func labelText(_ text: String, isHoldLabel: Bool) -> some View {
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

    /// Function key with mapping support - shows icon + F-label
    /// Handles both default function key icons and remapped actions
    @ViewBuilder
    private var functionKeyWithMappingContent: some View {
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
    private var functionKeyContent: some View {
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
                   let outputSymbol = LabelMetadata.sfSymbol(forOutputLabel: info.displayLabel) {
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
    private var arrowContent: some View {
        Text(effectiveLabel)
            .font(.system(size: 8 * scale, weight: .regular))
            .foregroundStyle(foregroundColor)
            .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    // MARK: - Layout: Touch ID / Layer Indicator

    @ViewBuilder
    private var touchIdContent: some View {
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
    private var escKeyContent: some View {
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

    /// Interpolate between two colors based on progress (0 = from, 1 = to)
    private func interpolate(from: Color, to: Color, progress: CGFloat) -> (red: Double, green: Double, blue: Double) {
        // Extract RGB components (simplified - assumes sRGB)
        let fromRGB = NSColor(from).usingColorSpace(.sRGB) ?? NSColor.black
        let toRGB = NSColor(to).usingColorSpace(.sRGB) ?? NSColor.black

        let r = Double(fromRGB.redComponent) * (1 - progress) + Double(toRGB.redComponent) * progress
        let g = Double(fromRGB.greenComponent) * (1 - progress) + Double(toRGB.greenComponent) * progress
        let b = Double(fromRGB.blueComponent) * (1 - progress) + Double(toRGB.blueComponent) * progress

        return (r, g, b)
    }

    private var cornerRadius: CGFloat {
        key.layoutRole == .arrow ? 3 * scale : 4 * scale
    }

    private var keyBackground: Color {
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

    private var keyStroke: Color {
        // No borders at any time - keys rely on shadows for separation
        // (User preference: cleaner look without outlines, including during fade)
        Color.white.opacity(0)
    }

    private var strokeWidth: CGFloat {
        // No border stroke width at any time
        0
    }

    private var shadowColor: Color {
        Color.black.opacity(isDarkMode ? 0.5 : 0.35).opacity(1 - fadeAmount)
    }

    private var shadowRadius: CGFloat {
        // Ensure minimum shadow even when pressed for grounding
        let minRadius: CGFloat = 0.3 * scale
        let normalRadius: CGFloat = 0.5 * scale
        let pressedRadius: CGFloat = 0.2 * scale
        let baseRadius = isPressed ? max(pressedRadius, minRadius) : normalRadius
        // Reduce fade impact on shadow (was 1 - fadeAmount, now only 50% reduction)
        return baseRadius * (1 - fadeAmount * 0.5)
    }

    private var shadowOffset: CGFloat {
        // Match shadow radius logic for consistency
        let minOffset: CGFloat = 0.3 * scale
        let normalOffset: CGFloat = 0.5 * scale
        let pressedOffset: CGFloat = 0.2 * scale
        let baseOffset = isPressed ? max(pressedOffset, minOffset) : normalOffset
        return baseOffset * (1 - fadeAmount * 0.5)
    }

    /// Whether this key is a modifier (shift, ctrl, opt, cmd, fn, etc.)
    private var isModifierKey: Bool {
        let modifierLabels = ["⇧", "⌃", "⌥", "⌘", "fn", "shift", "ctrl", "control", "opt", "option", "alt", "cmd", "command", "⇪", "caps"]
        let label = baseLabel.lowercased()
        return modifierLabels.contains { label.contains($0.lowercased()) }
            || key.width >= 1.5 // Wide keys are typically modifiers
            || key.keyCode == 63 // fn key
            || (key.keyCode >= 54 && key.keyCode <= 61) // modifier key codes
    }

    /// Whether this key should use accent colors (enter, escape, etc.)
    private var isAccentKey: Bool {
        let accentLabels = ["⏎", "↵", "return", "enter", "esc", "escape", "⌫", "delete", "⇥", "tab"]
        let label = baseLabel.lowercased()
        return accentLabels.contains { label.contains($0.lowercased()) }
    }

    /// Whether this key is a numpad key (doesn't show shift symbols)
    /// Numpad keyCodes on macOS: 65 (.), 67 (*), 69 (+), 71 (clear), 75 (/),
    /// 76 (enter), 78 (-), 81 (=), 82-92 (0-9 and operators)
    private var isNumpadKey: Bool {
        let numpadKeyCodes: Set<UInt16> = [
            65, 67, 69, 71, 75, 76, 78, 81, // operators and special
            82, 83, 84, 85, 86, 87, 88, 89, 91, 92 // numbers 0-9
        ]
        return numpadKeyCodes.contains(key.keyCode)
    }

    private var foregroundColor: Color {
        let baseColor: Color = if isModifierKey {
            colorway.modLegendColor
        } else if isAccentKey {
            colorway.accentLegendColor
        } else {
            colorway.alphaLegendColor
        }
        return baseColor.opacity(isPressed ? 1.0 : 0.88)
    }

    private var backgroundColor: Color {
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
        else if isLayerMode, hasLayerMapping {
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

    // MARK: - Window Action Detection

    /// Detect window action type from output label for color-coding
    private func windowActionColor(from label: String) -> Color? {
        guard currentLayerName.lowercased().contains("window") else { return nil }

        let lower = label.lowercased()

        // Corners - purple
        if lower.contains("top") && lower.contains("left") { return .purple }
        if lower.contains("top") && lower.contains("right") { return .purple }
        if lower.contains("bottom") && lower.contains("left") { return .purple }
        if lower.contains("bottom") && lower.contains("right") { return .purple }

        // Halves - blue
        if lower.contains("left") && lower.contains("half") { return .blue }
        if lower.contains("right") && lower.contains("half") { return .blue }

        // Maximize/Center - green
        if lower.contains("maximize") || lower.contains("fullscreen") { return .green }
        if lower.contains("center") { return .green }

        // Displays - orange
        if lower.contains("display") || lower.contains("monitor") { return .orange }

        // Spaces - cyan
        if lower.contains("space") { return .cyan }

        // Undo - gray
        if lower.contains("undo") { return .gray }

        return nil
    }

    /// Get SF Symbol for window action
    private func windowActionSymbol(from label: String) -> String? {
        guard currentLayerName.lowercased().contains("window") else { return nil }

        let lower = label.lowercased()

        // Directional arrows for halves
        if lower.contains("left") && lower.contains("half") { return "arrow.left" }
        if lower.contains("right") && lower.contains("half") { return "arrow.right" }

        // Diagonal arrows for corners
        if lower.contains("top") && lower.contains("left") { return "arrow.up.left" }
        if lower.contains("top") && lower.contains("right") { return "arrow.up.right" }
        if lower.contains("bottom") && lower.contains("left") { return "arrow.down.left" }
        if lower.contains("bottom") && lower.contains("right") { return "arrow.down.right" }

        // Maximize/restore
        if lower.contains("maximize") || lower.contains("fullscreen") {
            return "arrow.up.left.and.arrow.down.right"
        }
        if lower.contains("center") { return "circle.grid.cross" }

        // Displays
        if lower.contains("display") || lower.contains("monitor") { return "display" }

        // Spaces
        if lower.contains("next") && lower.contains("space") { return "arrow.right.square" }
        if lower.contains("previous") && lower.contains("space") { return "arrow.left.square" }

        return nil
    }

    // MARK: - Collection Colors

    /// Determine key color based on collection ownership
    private func collectionColor(for collectionId: UUID?) -> Color {
        guard let id = collectionId else {
            // No collection info - use default layer mode orange
            return Color(red: 0.85, green: 0.45, blue: 0.15)
        }

        // Map collection UUIDs to colors
        switch id {
        case RuleCollectionIdentifier.vimNavigation:
            return Color(red: 0.85, green: 0.45, blue: 0.15)  // Orange - Vim navigation keys
        case RuleCollectionIdentifier.windowSnapping:
            return .purple  // Purple - Window snapping keys
        case RuleCollectionIdentifier.symbolLayer:
            return .blue    // Blue - Symbol layer keys (future)
        case RuleCollectionIdentifier.launcher:
            return .cyan    // Cyan - Launcher keys (future)
        default:
            // Unknown collection - default orange
            return Color(red: 0.85, green: 0.45, blue: 0.15)
        }
    }
}

// MARK: - Preview

#Preview("Keyboard Row") {
    HStack(spacing: 4) {
        // fn key
        OverlayKeycapView(
            key: PhysicalKey(keyCode: 63, label: "fn", x: 0, y: 5, width: 1.1),
            baseLabel: "fn",
            isPressed: false,
            scale: 1.5
        )
        .frame(width: 50, height: 45)

        // Control
        OverlayKeycapView(
            key: PhysicalKey(keyCode: 59, label: "⌃", x: 1.2, y: 5, width: 1.1),
            baseLabel: "⌃",
            isPressed: false,
            scale: 1.5
        )
        .frame(width: 50, height: 45)

        // Option
        OverlayKeycapView(
            key: PhysicalKey(keyCode: 58, label: "⌥", x: 2.4, y: 5, width: 1.1),
            baseLabel: "⌥",
            isPressed: false,
            scale: 1.5
        )
        .frame(width: 50, height: 45)

        // Command
        OverlayKeycapView(
            key: PhysicalKey(keyCode: 55, label: "⌘", x: 3.6, y: 5, width: 1.35),
            baseLabel: "⌘",
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
        baseLabel: "a",
        isPressed: false,
        scale: 1.5,
        isDarkMode: true
    )
    .frame(width: 50, height: 50)
    .padding()
    .background(Color.black)
}

#Preview("Layer Indicator") {
    HStack(spacing: 8) {
        // Base layer (muted)
        OverlayKeycapView(
            key: PhysicalKey(keyCode: 0xFFFF, label: "🔒", x: 14.5, y: 0, width: 1.0),
            baseLabel: "🔒",
            isPressed: false,
            scale: 1.5,
            isDarkMode: true,
            currentLayerName: "base"
        )
        .frame(width: 50, height: 50)

        // Active layer (full opacity)
        OverlayKeycapView(
            key: PhysicalKey(keyCode: 0xFFFF, label: "🔒", x: 14.5, y: 0, width: 1.0),
            baseLabel: "🔒",
            isPressed: false,
            scale: 1.5,
            isDarkMode: true,
            currentLayerName: "nav"
        )
        .frame(width: 50, height: 50)

        // Loading state
        OverlayKeycapView(
            key: PhysicalKey(keyCode: 0xFFFF, label: "🔒", x: 14.5, y: 0, width: 1.0),
            baseLabel: "🔒",
            isPressed: false,
            scale: 1.5,
            isDarkMode: true,
            isLoadingLayerMap: true
        )
        .frame(width: 50, height: 50)
    }
    .padding()
    .background(Color.black)
}

#Preview("Emphasized Keys (HJKL)") {
    HStack(spacing: 8) {
        // Normal key
        OverlayKeycapView(
            key: PhysicalKey(keyCode: 0, label: "a", x: 0, y: 0),
            baseLabel: "a",
            isPressed: false,
            scale: 1.5,
            isDarkMode: true
        )
        .frame(width: 50, height: 50)

        // Emphasized key (vim nav)
        OverlayKeycapView(
            key: PhysicalKey(keyCode: 4, label: "h", x: 0, y: 0),
            baseLabel: "h",
            isPressed: false,
            scale: 1.5,
            isDarkMode: true,
            isEmphasized: true
        )
        .frame(width: 50, height: 50)

        // Emphasized + Pressed
        OverlayKeycapView(
            key: PhysicalKey(keyCode: 38, label: "j", x: 0, y: 0),
            baseLabel: "j",
            isPressed: true,
            scale: 1.5,
            isDarkMode: true,
            isEmphasized: true
        )
        .frame(width: 50, height: 50)

        // Just pressed (not emphasized)
        OverlayKeycapView(
            key: PhysicalKey(keyCode: 40, label: "k", x: 0, y: 0),
            baseLabel: "k",
            isPressed: true,
            scale: 1.5,
            isDarkMode: true
        )
        .frame(width: 50, height: 50)
    }
    .padding()
    .background(Color.black)
}

#Preview("GMK Dots Rainbow") {
    HStack(spacing: 4) {
        // Alpha keys with rainbow dots at different column positions
        ForEach(0 ..< 10, id: \.self) { col in
            OverlayKeycapView(
                key: PhysicalKey(keyCode: UInt16(col), label: String(Character(UnicodeScalar(97 + col)!)), x: CGFloat(col), y: 1),
                baseLabel: String(Character(UnicodeScalar(97 + col)!)),
                isPressed: false,
                scale: 1.5,
                colorway: .dots,
                layoutTotalWidth: 10
            )
            .frame(width: 45, height: 45)
        }
    }
    .padding()
    .background(Color.black)
}

#Preview("GMK Dots Dark Rainbow") {
    VStack(spacing: 4) {
        // Top row with rainbow alphas
        HStack(spacing: 4) {
            ForEach(0 ..< 10, id: \.self) { col in
                OverlayKeycapView(
                    key: PhysicalKey(keyCode: UInt16(col), label: String(col), x: CGFloat(col), y: 0),
                    baseLabel: String(col),
                    isPressed: false,
                    scale: 1.2,
                    colorway: .dotsDark,
                    layoutTotalWidth: 15
                )
                .frame(width: 38, height: 38)
            }
        }
        // Bottom row with modifiers (oblongs)
        HStack(spacing: 4) {
            OverlayKeycapView(
                key: PhysicalKey(keyCode: 59, label: "⌃", x: 0, y: 3, width: 1.5),
                baseLabel: "⌃",
                isPressed: false,
                scale: 1.2,
                colorway: .dotsDark,
                layoutTotalWidth: 15
            )
            .frame(width: 55, height: 38)

            OverlayKeycapView(
                key: PhysicalKey(keyCode: 58, label: "⌥", x: 2, y: 3, width: 1.2),
                baseLabel: "⌥",
                isPressed: false,
                scale: 1.2,
                colorway: .dotsDark,
                layoutTotalWidth: 15
            )
            .frame(width: 45, height: 38)

            OverlayKeycapView(
                key: PhysicalKey(keyCode: 55, label: "⌘", x: 4, y: 3, width: 1.3),
                baseLabel: "⌘",
                isPressed: false,
                scale: 1.2,
                colorway: .dotsDark,
                layoutTotalWidth: 15
            )
            .frame(width: 50, height: 38)

            // Spacebar
            OverlayKeycapView(
                key: PhysicalKey(keyCode: 49, label: " ", x: 6, y: 3, width: 5.0),
                baseLabel: " ",
                isPressed: false,
                scale: 1.2,
                colorway: .dotsDark,
                layoutTotalWidth: 15
            )
            .frame(width: 180, height: 38)
        }
    }
    .padding()
    .background(Color.black)
}

// MARK: - Pulse Animation

/// Simple pulsing animation for loading indicator
private struct PulseAnimation: ViewModifier {
    @State private var isPulsing = false

    func body(content: Content) -> some View {
        content
            .opacity(isPulsing ? 0.3 : 1.0)
            .animation(
                Animation.easeInOut(duration: 0.8)
                    .repeatForever(autoreverses: true),
                value: isPulsing
            )
            .onAppear { isPulsing = true }
    }
}
