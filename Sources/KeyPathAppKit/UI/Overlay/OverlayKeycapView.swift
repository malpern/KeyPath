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
    /// Hold label to display when tap-hold key is in hold state
    var holdLabel: String?
    /// Callback when key is clicked (not dragged)
    var onKeyClick: ((PhysicalKey, LayerKeyInfo?) -> Void)?
    /// GMK colorway for keycap styling
    var colorway: GMKColorway = .default
    /// Whether to hide alpha labels (used when floating labels handle animation)
    var useFloatingLabels: Bool = false

    /// Size thresholds for typography adaptation
    private var isSmallSize: Bool { scale < 0.8 }
    private var isLargeSize: Bool { scale >= 1.5 }

    /// The effective label to display (hold label > layer mapping > keymap/physical)
    private var effectiveLabel: String {
        // When key is pressed with a hold label, show the hold label
        if isPressed, let holdLabel {
            return holdLabel
        }

        guard let info = layerKeyInfo else {
            return baseLabel
        }

        if info.displayLabel.isEmpty {
            return ""
        }

        if shouldUseBaseLabel, baseLabel != key.label {
            return baseLabel
        }

        return info.displayLabel
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

    /// State for hover-to-click behavior
    @State private var isHovering = false
    @State private var isClickable = false // True after dwell
    @State private var hoverTask: Task<Void, Never>?
    @State private var didDragBeyondThreshold = false

    /// Cached app icon for launch actions
    @State private var appIcon: NSImage?

    /// Cached favicon for URL actions
    @State private var faviconImage: NSImage?

    /// Shared state for tracking mouse interaction with keyboard (for refined click delay)
    @EnvironmentObject private var keyboardMouseState: KeyboardMouseState

    /// Dwell time before key becomes clickable (300ms)
    private let clickableDwellTime: TimeInterval = 0.3
    /// Drag distance threshold to treat gesture as window move (not a click)
    private let dragThreshold: CGFloat = 4

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

    /// SF Symbol icon for system action
    private var systemActionIcon: String? {
        guard let actionId = layerKeyInfo?.systemActionIdentifier else { return nil }

        // Map system action IDs to SF Symbol icons (matching SystemActionInfo in MapperView)
        switch actionId.lowercased() {
        case "spotlight": return "magnifyingglass"
        case "mission-control", "missioncontrol": return "rectangle.3.group"
        case "launchpad": return "square.grid.3x3"
        case "dnd", "do-not-disturb", "donotdisturb": return "moon.fill"
        case "notification-center", "notificationcenter": return "bell.fill"
        case "dictation": return "mic.fill"
        case "siri": return "waveform.circle.fill"
        default: return nil
        }
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

            // Hover highlight outline (shows when clickable)
            if isClickable {
                RoundedRectangle(cornerRadius: cornerRadius)
                    .stroke(Color.accentColor, lineWidth: 2 * scale)
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
            }

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
        .animation(.easeInOut(duration: 0.15), value: isClickable)
        // Hover detection with dwell time (must be before contentShape for hit testing)
        .contentShape(Rectangle())
        .onHover { hovering in
            isHovering = hovering
            if hovering {
                // If user has already clicked a key, make instantly clickable
                // Otherwise, apply 300ms dwell delay
                if keyboardMouseState.hasClickedAnyKey {
                    isClickable = true
                } else {
                    // Start dwell timer for first hover
                    hoverTask = Task { @MainActor in
                        try? await Task.sleep(for: .milliseconds(Int(clickableDwellTime * 1000)))
                        if !Task.isCancelled, isHovering {
                            isClickable = true
                        }
                    }
                }
            } else {
                // Cancel timer and reset clickable state
                hoverTask?.cancel()
                hoverTask = nil
                isClickable = false
                didDragBeyondThreshold = false
            }
        }
        // Gesture that only activates when clickable, otherwise passes through
        .simultaneousGesture(
            DragGesture(minimumDistance: 0)
                .onChanged { value in
                    let distance = hypot(value.translation.width, value.translation.height)
                    if distance > dragThreshold {
                        didDragBeyondThreshold = true
                    }
                }
                .onEnded { _ in
                    guard isClickable, !didDragBeyondThreshold, let onKeyClick else {
                        didDragBeyondThreshold = false
                        return
                    }
                    // Record that a key has been clicked (subsequent clicks will be instant)
                    keyboardMouseState.recordClick()
                    onKeyClick(key, layerKeyInfo)
                    didDragBeyondThreshold = false
                },
            // When not clickable, let gestures pass through for window repositioning
            including: isClickable ? .all : .none
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
    }

    // MARK: - App Icon Loading

    /// Load app icon for launch action if needed
    private func loadAppIconIfNeeded() {
        guard let appIdentifier = layerKeyInfo?.appLaunchIdentifier else {
            appIcon = nil
            return
        }

        // Try to find app by bundle identifier or name
        if let appURL = findAppURL(for: appIdentifier) {
            let icon = NSWorkspace.shared.icon(forFile: appURL.path)
            icon.size = NSSize(width: 64, height: 64)
            appIcon = icon
        } else {
            appIcon = nil
        }
    }

    /// Find app URL by bundle identifier or name
    private func findAppURL(for identifier: String) -> URL? {
        // First try as bundle identifier
        if let url = NSWorkspace.shared.urlForApplication(withBundleIdentifier: identifier) {
            return url
        }

        // Try as app name in /Applications
        let applicationsPath = "/Applications/\(identifier).app"
        if FileManager.default.fileExists(atPath: applicationsPath) {
            return URL(fileURLWithPath: applicationsPath)
        }

        // Try with capitalized first letter
        let capitalizedPath = "/Applications/\(identifier.capitalized).app"
        if FileManager.default.fileExists(atPath: capitalizedPath) {
            return URL(fileURLWithPath: capitalizedPath)
        }

        return nil
    }

    // MARK: - Favicon Loading

    private func loadFaviconIfNeeded() {
        guard let url = layerKeyInfo?.urlIdentifier else {
            faviconImage = nil
            return
        }

        Task { @MainActor in
            let favicon = await FaviconFetcher.shared.fetchFavicon(for: url)
            faviconImage = favicon
        }
    }

    // MARK: - Content Routing by Layout Role

    @ViewBuilder
    private var keyContent: some View {
        // Function keys always show F-label + icon (even when remapped)
        if key.layoutRole == .functionKey {
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

    /// Whether this key is a simple alpha key (single letter that floating labels handle)
    private var isSimpleAlphaKey: Bool {
        let label = effectiveLabel.uppercased()
        // Single character A-Z or 0-9
        guard label.count == 1 else { return false }
        guard let char = label.first else { return false }
        return char.isLetter || char.isNumber
    }

    @ViewBuilder
    private var centeredContent: some View {
        // Hide label if floating labels are handling it (during keymap animation)
        if useFloatingLabels && isSimpleAlphaKey {
            Color.clear.frame(maxWidth: .infinity, maxHeight: .infinity)
        } else if let navSymbol = navOverlaySymbol {
            navOverlayContent(arrow: navSymbol, letter: baseLabel)
        } else if let shiftSymbol = metadata.shiftSymbol {
            // Dual content: shift symbol above, main below
            dualSymbolContent(main: effectiveLabel, shift: shiftSymbol)
        } else {
            // Single centered content
            Text(effectiveLabel.uppercased())
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
        // Layer indicator replaces Touch ID icon
        // Shows current layer name or loading indicator
        if isLoadingLayerMap {
            // Subtle pulsing dot while loading layer mapping
            Circle()
                .fill(foregroundColor.opacity(0.6))
                .frame(width: 4 * scale, height: 4 * scale)
                .modifier(PulseAnimation())
                .frame(maxWidth: .infinity, maxHeight: .infinity)
        } else {
            // Layer indicator - icon + label like function keys
            let isBase = currentLayerName.lowercased() == "base"

            if isBase {
                // Base layer: sidebar icon with "base" label underneath (like F-keys)
                VStack(spacing: 0) {
                    Image(systemName: "sidebar.right")
                        .font(.system(size: 8 * scale, weight: .regular))
                        .foregroundStyle(foregroundColor)
                    Spacer()
                    Text("base")
                        .font(.system(size: 5.4 * scale, weight: .regular))
                        .foregroundStyle(foregroundColor.opacity(0.6))
                }
                .padding(.top, 4 * scale)
                .padding(.bottom, 2 * scale)
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else {
                // Other layers: bottom-left aligned like ESC key
                VStack {
                    Spacer(minLength: 0)
                    HStack {
                        Text(currentLayerName.lowercased())
                            .font(.system(size: 7 * scale, weight: .regular))
                            .foregroundStyle(foregroundColor)
                        Spacer(minLength: 0)
                    }
                    .padding(.leading, 4 * scale)
                    .padding(.trailing, 4 * scale)
                    .padding(.bottom, 3 * scale)
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            }
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
        // Show white stroke during global overlay fade only
        if isReleaseFading {
            Color.white.opacity(0)
        } else {
            Color.white.opacity(0.35 * fadeAmount)
        }
    }

    private var strokeWidth: CGFloat {
        isReleaseFading ? 0 : fadeAmount * scale
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

    private var foregroundColor: Color {
        let baseColor: Color
        if isModifierKey {
            baseColor = colorway.modLegendColor
        } else if isAccentKey {
            baseColor = colorway.accentLegendColor
        } else {
            baseColor = colorway.alphaLegendColor
        }
        return baseColor.opacity(isPressed ? 1.0 : 0.88)
    }

    private var backgroundColor: Color {
        if isPressed {
            Color.accentColor
        } else if isEmphasized {
            Color.orange
        } else if isModifierKey {
            colorway.modBaseColor
        } else if isAccentKey {
            colorway.accentBaseColor
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
