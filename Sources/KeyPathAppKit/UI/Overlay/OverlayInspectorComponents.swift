import AppKit
import KeyPathCore
import SwiftUI

/// Card view for a single keymap option with SVG image and info button
struct KeymapCard: View {
    let keymap: LogicalKeymap
    let isSelected: Bool
    let isDark: Bool
    let fadeAmount: CGFloat
    let onSelect: () -> Void

    @State private var isHovering = false
    @State private var svgImage: NSImage?

    var body: some View {
        Button(action: onSelect) {
            VStack(spacing: 4) {
                // SVG Image - becomes monochromatic when fading
                if let image = svgImage {
                    Image(nsImage: image)
                        .resizable()
                        .aspectRatio(contentMode: .fit)
                        .frame(height: 45)
                        .saturation(Double(1 - fadeAmount)) // Monochromatic when faded
                } else {
                    keymapPlaceholder
                        .frame(height: 45)
                }

                // Label with info button
                HStack(spacing: 4) {
                    Text(keymap.name)
                        .font(.system(size: 10, weight: .bold))
                        .foregroundStyle(isSelected ? .primary : .secondary)
                        .lineLimit(1)

                    Button {
                        NSWorkspace.shared.open(keymap.learnMoreURL)
                    } label: {
                        Image(systemName: "info.circle")
                            .font(.system(size: 10))
                            .foregroundStyle(.secondary)
                    }
                    .buttonStyle(.plain)
                }
            }
            .padding(6)
            .frame(maxWidth: .infinity)
            .background(cardBackground)
            .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
            .overlay(
                RoundedRectangle(cornerRadius: 8, style: .continuous)
                    .stroke(isSelected ? Color.accentColor : Color.clear, lineWidth: 2)
            )
        }
        .buttonStyle(.plain)
        .accessibilityIdentifier("overlay-keymap-button-\(keymap.id)")
        .accessibilityLabel("Select keymap \(keymap.name)")
        .onHover { isHovering = $0 }
        .onAppear { loadSVG() }
    }

    private func loadSVG() {
        // SVGs are at bundle root (not in subdirectory) due to .process() flattening
        guard let svgURL = Bundle.module.url(
            forResource: keymap.iconFilename,
            withExtension: "svg"
        ) else { return }

        svgImage = NSImage(contentsOf: svgURL)
    }

    private var cardBackground: some View {
        RoundedRectangle(cornerRadius: 8, style: .continuous)
            .fill(isSelected
                ? Color.accentColor.opacity(0.15)
                : (isHovering ? Color.white.opacity(0.08) : Color.white.opacity(0.04)))
    }

    private var keymapPlaceholder: some View {
        RoundedRectangle(cornerRadius: 6)
            .fill(Color.gray.opacity(0.2))
            .overlay(
                Image(systemName: "keyboard")
                    .font(.system(size: 16))
                    .foregroundStyle(.secondary)
            )
    }
}

/// Card view for a GMK colorway option with color swatch preview
struct ColorwayCard: View {
    let colorway: GMKColorway
    let isSelected: Bool
    let isDark: Bool
    let onSelect: () -> Void

    @State private var isHovering = false

    var body: some View {
        Button(action: onSelect) {
            VStack(spacing: 4) {
                // Color swatch preview (horizontal bars)
                colorSwatchPreview
                    .frame(height: 36)
                    .clipShape(RoundedRectangle(cornerRadius: 4, style: .continuous))

                // Name and designer
                VStack(spacing: 1) {
                    Text(colorway.name)
                        .font(.system(size: 10, weight: .bold))
                        .foregroundStyle(isSelected ? .primary : .secondary)
                        .lineLimit(1)

                    Text(colorway.designer)
                        .font(.system(size: 8))
                        .foregroundStyle(.tertiary)
                        .lineLimit(1)
                }
            }
            .padding(6)
            .frame(maxWidth: .infinity)
            .background(cardBackground)
            .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
            .overlay(
                RoundedRectangle(cornerRadius: 8, style: .continuous)
                    .stroke(isSelected ? Color.accentColor : Color.clear, lineWidth: 2)
            )
        }
        .buttonStyle(.plain)
        .accessibilityIdentifier("overlay-colorway-button-\(colorway.id)")
        .accessibilityLabel("Select colorway \(colorway.name)")
        .onHover { isHovering = $0 }
        .help("\(colorway.name) by \(colorway.designer) (\(colorway.year))")
    }

    /// Horizontal color bars showing the colorway
    private var colorSwatchPreview: some View {
        GeometryReader { geo in
            HStack(spacing: 1) {
                // Alpha base (largest - main key color)
                colorway.alphaBaseColor
                    .frame(width: geo.size.width * 0.35)

                // Mod base
                colorway.modBaseColor
                    .frame(width: geo.size.width * 0.25)

                // Accent base
                colorway.accentBaseColor
                    .frame(width: geo.size.width * 0.2)

                // Legend color (shows as small bar)
                colorway.alphaLegendColor
                    .frame(width: geo.size.width * 0.2)
            }
        }
    }

    private var cardBackground: some View {
        RoundedRectangle(cornerRadius: 8, style: .continuous)
            .fill(isSelected
                ? Color.accentColor.opacity(0.15)
                : (isHovering ? Color.white.opacity(0.08) : Color.white.opacity(0.04)))
    }
}

/// Row view for a physical layout option
struct PhysicalLayoutRow: View {
    let layout: PhysicalLayout
    let isSelected: Bool
    let isDark: Bool
    let onSelect: () -> Void

    @State private var isHovering = false

    var body: some View {
        Button(action: onSelect) {
            HStack {
                Image(systemName: layoutIcon)
                    .font(.system(size: 16))
                    .foregroundStyle(isSelected ? .primary : .secondary)
                    .frame(width: 24)

                Text(layout.name)
                    .font(.system(size: 12, weight: .semibold))
                    .foregroundStyle(isSelected ? .primary : .secondary)

                Spacer()

                if isSelected {
                    Image(systemName: "checkmark")
                        .font(.system(size: 12, weight: .semibold))
                        .foregroundStyle(Color.accentColor)
                }
            }
            .padding(.horizontal, 10)
            .padding(.vertical, 8)
            .background(rowBackground)
            .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
            .accessibilityIdentifier("overlay-layout-button-\(layout.id)")
            .accessibilityLabel("Select layout \(layout.name)")
        }
        .buttonStyle(.plain)
        .onHover { isHovering = $0 }
    }

    private var layoutIcon: String {
        switch layout.id {
        case "macbook-us": "laptopcomputer"
        case "kinesis-360": "keyboard"
        default: "keyboard"
        }
    }

    private var rowBackground: some View {
        RoundedRectangle(cornerRadius: 8, style: .continuous)
            .fill(isSelected
                ? Color.accentColor.opacity(0.15)
                : (isHovering ? Color.white.opacity(0.08) : Color.white.opacity(0.04)))
    }
}

private enum GearAnchorLocation: Hashable {
    case main
    case settings
}

private struct GearAnchorPreferenceKey: PreferenceKey {
    static let defaultValue: [GearAnchorLocation: Anchor<CGRect>] = [:]

    static func reduce(
        value: inout [GearAnchorLocation: Anchor<CGRect>],
        nextValue: () -> [GearAnchorLocation: Anchor<CGRect>]
    ) {
        value.merge(nextValue(), uniquingKeysWith: { $1 })
    }
}

struct InspectorPanelToolbar: View {
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    let isDark: Bool
    let selectedSection: InspectorSection
    let onSelectSection: (InspectorSection) -> Void
    let isMapperAvailable: Bool
    let healthIndicatorState: HealthIndicatorState
    let hasCustomRules: Bool
    let isSettingsShelfActive: Bool
    let onToggleSettingsShelf: () -> Void
    private let buttonSize: CGFloat = 32
    @State private var isHoveringMapper = false
    @State private var isHoveringCustomRules = false
    @State private var isHoveringKeyboard = false
    @State private var isHoveringLayout = false
    @State private var isHoveringKeycaps = false
    @State private var isHoveringSounds = false
    @State private var isHoveringLaunchers = false
    @State private var isHoveringSettings = false
    @State private var showMainTabs = true
    @State private var showSettingsTabs = false
    @State private var animationToken = 0
    @State private var gearSpinDegrees: Double = 0
    @State private var gearTravelDistance: CGFloat = 0
    @State private var gearPositionX: CGFloat = 0
    @State private var gearPositionY: CGFloat = 0

    var body: some View {
        ZStack(alignment: .leading) {
            mainTabsRow
            settingsTabsRow
        }
        .overlayPreferenceValue(GearAnchorPreferenceKey.self) { anchors in
            GeometryReader { proxy in
                let mainFrame = anchors[.main].map { proxy[$0] }
                let settingsFrame = anchors[.settings].map { proxy[$0] }
                if let mainFrame, let settingsFrame {
                    gearButton(isSelected: showSettingsTabs, rotationDegrees: gearRotationDegrees)
                        .accessibilityIdentifier("inspector-tab-settings")
                        .position(x: gearPositionX, y: gearPositionY)
                        .zIndex(1)
                        .onAppear {
                            // Set initial position without animation
                            let initialFrame = isSettingsShelfActive ? settingsFrame : mainFrame
                            gearPositionX = initialFrame.midX
                            gearPositionY = initialFrame.midY
                            updateGearTravelDistance(mainFrame: mainFrame, settingsFrame: settingsFrame)
                        }
                        .onChange(of: mainFrame) { _, newValue in
                            updateGearTravelDistance(mainFrame: newValue, settingsFrame: settingsFrame)
                            if !isSettingsShelfActive {
                                updateGearPosition(to: newValue)
                            }
                        }
                        .onChange(of: settingsFrame) { _, newValue in
                            updateGearTravelDistance(mainFrame: mainFrame, settingsFrame: newValue)
                            if isSettingsShelfActive {
                                updateGearPosition(to: newValue)
                            }
                        }
                        .onChange(of: isSettingsShelfActive) { _, isActive in
                            let targetFrame = isActive ? settingsFrame : mainFrame
                            updateGearPosition(to: targetFrame)
                        }
                }
            }
        }
        .controlSize(.regular)
        .padding(.horizontal, 14)
        .padding(.vertical, 8)
        // No background - transparent toolbar
        .onAppear {
            syncShelfVisibility()
        }
        .onChange(of: isSettingsShelfActive) { _, newValue in
            animateShelfTransition(isActive: newValue)
        }
    }

    private var mainTabsRow: some View {
        HStack(spacing: 8) {
            mainTabsContent
                .opacity(showMainTabs ? 1 : 0)
                .allowsHitTesting(showMainTabs)
                .accessibilityHidden(!showMainTabs)
            gearAnchor(.main)
        }
        .frame(maxWidth: .infinity, alignment: .center)
    }

    private var settingsTabsRow: some View {
        HStack(spacing: 8) {
            gearAnchor(.settings)
            settingsTabsContent
                .opacity(showSettingsTabs ? 1 : 0)
                .allowsHitTesting(showSettingsTabs)
                .accessibilityHidden(!showSettingsTabs)
        }
        .frame(maxWidth: .infinity, alignment: .center)
    }

    private var gearSlideDuration: Double {
        reduceMotion ? 0 : 0.7 // 4x faster than previous (2.8 / 4)
    }

    private var gearSpinDuration: Double {
        reduceMotion ? 0 : 0.6 // 60% reduction from original (1.5 * 0.4)
    }

    private var tabFadeAnimation: Animation? {
        reduceMotion ? nil : .easeInOut(duration: 0.16)
    }

    private var gearRotationDegrees: Double {
        reduceMotion ? 0 : gearSpinDegrees
    }

    private func gearButton(isSelected: Bool, rotationDegrees: Double) -> some View {
        Button(action: onToggleSettingsShelf) {
            Image(systemName: "gearshape.fill")
                .font(.system(size: buttonSize * 0.5, weight: .semibold))
                .foregroundStyle(isSelected ? Color.accentColor : (isHoveringSettings ? .primary : .secondary))
                .rotationEffect(.degrees(rotationDegrees))
                .frame(width: buttonSize, height: buttonSize)
                .background(gearBackground(isSelected: isSelected))
                .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
        }
        .buttonStyle(.plain)
        .accessibilityIdentifier("inspector-tab-settings")
        .accessibilityLabel(isSelected ? "Close settings shelf" : "Open settings shelf")
        .help("Settings")
        .onHover { isHoveringSettings = $0 }
    }

    private func gearBackground(isSelected: Bool) -> some View {
        let selectedFill = Color.accentColor.opacity(isDark ? 0.38 : 0.26)
        let hoverFill = (isDark ? Color.white : Color.black).opacity(isDark ? 0.08 : 0.08)
        return RoundedRectangle(cornerRadius: 8, style: .continuous)
            .fill(isSelected ? selectedFill : (isHoveringSettings ? hoverFill : Color.clear))
            .overlay(
                RoundedRectangle(cornerRadius: 8, style: .continuous)
                    .stroke(isSelected ? Color.accentColor.opacity(isDark ? 0.9 : 0.7) : Color.clear, lineWidth: 1.5)
            )
    }

    private func toolbarButton(
        systemImage: String,
        isSelected: Bool,
        isHovering: Bool,
        onHover: @escaping (Bool) -> Void,
        action: @escaping () -> Void
    ) -> some View {
        Button(action: action) {
            Image(systemName: systemImage)
                .font(.system(size: buttonSize * 0.5, weight: .semibold))
                .foregroundStyle(isSelected ? Color.accentColor : (isHovering ? .primary : .secondary))
                .frame(width: buttonSize, height: buttonSize)
        }
        .buttonStyle(PlainButtonStyle())
        .onHover(perform: onHover)
    }

    private var isMapperTabEnabled: Bool {
        if healthIndicatorState == .checking { return true }
        if case .unhealthy = healthIndicatorState { return true }
        return isMapperAvailable
    }

    private var mainTabsContent: some View {
        Group {
            // Custom Rules first (leftmost) - only shown when custom rules exist
            if hasCustomRules {
                toolbarButton(
                    systemImage: "list.bullet.rectangle",
                    isSelected: selectedSection == .customRules,
                    isHovering: isHoveringCustomRules,
                    onHover: { isHoveringCustomRules = $0 },
                    action: { onSelectSection(.customRules) }
                )
                .accessibilityIdentifier("inspector-tab-custom-rules")
                .accessibilityLabel("Custom Rules")
                .help("Custom Rules")
            }

            // Mapper
            toolbarButton(
                systemImage: "arrow.right.arrow.left",
                isSelected: selectedSection == .mapper,
                isHovering: isHoveringMapper,
                onHover: { isHoveringMapper = $0 },
                action: { onSelectSection(.mapper) }
            )
            .disabled(!isMapperTabEnabled)
            .opacity(isMapperTabEnabled ? 1 : 0.45)
            .accessibilityIdentifier("inspector-tab-mapper")
            .accessibilityLabel("Key Mapper")
            .help("Key Mapper")

            // Launchers
            toolbarButton(
                systemImage: "bolt.fill",
                isSelected: selectedSection == .launchers,
                isHovering: isHoveringLaunchers,
                onHover: { isHoveringLaunchers = $0 },
                action: { onSelectSection(.launchers) }
            )
            .accessibilityIdentifier("inspector-tab-launchers")
            .accessibilityLabel("Quick Launcher")
            .help("Quick Launcher")
        }
    }

    private var settingsTabsContent: some View {
        Group {
            // Keymap (Logical Layout) first
            toolbarButton(
                systemImage: "keyboard",
                isSelected: selectedSection == .keyboard,
                isHovering: isHoveringKeyboard,
                onHover: { isHoveringKeyboard = $0 },
                action: { onSelectSection(.keyboard) }
            )
            .accessibilityIdentifier("inspector-tab-keymap")
            .accessibilityLabel("Keymap")
            .help("Keymap")

            toolbarButton(
                systemImage: "square.grid.3x2",
                isSelected: selectedSection == .layout,
                isHovering: isHoveringLayout,
                onHover: { isHoveringLayout = $0 },
                action: { onSelectSection(.layout) }
            )
            .accessibilityIdentifier("inspector-tab-layout")
            .accessibilityLabel("Physical Layout")
            .help("Physical Layout")

            toolbarButton(
                systemImage: "swatchpalette.fill",
                isSelected: selectedSection == .keycaps,
                isHovering: isHoveringKeycaps,
                onHover: { isHoveringKeycaps = $0 },
                action: { onSelectSection(.keycaps) }
            )
            .accessibilityIdentifier("inspector-tab-keycaps")
            .accessibilityLabel("Keycap Style")
            .help("Keycap Style")

            toolbarButton(
                systemImage: "speaker.wave.2.fill",
                isSelected: selectedSection == .sounds,
                isHovering: isHoveringSounds,
                onHover: { isHoveringSounds = $0 },
                action: { onSelectSection(.sounds) }
            )
            .accessibilityIdentifier("inspector-tab-sounds")
            .accessibilityLabel("Typing Sounds")
            .help("Typing Sounds")
        }
    }

    private func gearAnchor(_ location: GearAnchorLocation) -> some View {
        Color.clear
            .frame(width: buttonSize, height: buttonSize)
            .anchorPreference(key: GearAnchorPreferenceKey.self, value: .bounds) { [location: $0] }
            .allowsHitTesting(false)
            .accessibilityHidden(true)
    }

    private func syncShelfVisibility() {
        showMainTabs = !isSettingsShelfActive
        showSettingsTabs = isSettingsShelfActive
    }

    private func animateShelfTransition(isActive: Bool) {
        animationToken += 1
        let currentToken = animationToken
        if reduceMotion {
            showMainTabs = !isActive
            showSettingsTabs = isActive
            return
        }

        let spinAmount = Double(gearTravelDistance) * gearRotationPerPoint
        let fadeAnimation = tabFadeAnimation

        if isActive {
            withAnimation(fadeAnimation) {
                showMainTabs = false
            }
            withAnimation(.easeInOut(duration: gearSpinDuration)) {
                gearSpinDegrees -= spinAmount
            }
            DispatchQueue.main.asyncAfter(deadline: .now() + gearSlideDuration) {
                guard animationToken == currentToken else { return }
                withAnimation(fadeAnimation) {
                    showSettingsTabs = true
                }
            }
        } else {
            withAnimation(fadeAnimation) {
                showSettingsTabs = false
            }
            withAnimation(.easeInOut(duration: gearSpinDuration)) {
                gearSpinDegrees += spinAmount
            }
            DispatchQueue.main.asyncAfter(deadline: .now() + gearSlideDuration) {
                guard animationToken == currentToken else { return }
                withAnimation(fadeAnimation) {
                    showMainTabs = true
                }
            }
        }
    }

    private var gearRotationPerPoint: Double {
        let circumference = Double.pi * Double(buttonSize)
        guard circumference > 0 else { return 0 }
        return 360.0 / circumference
    }

    private func updateGearTravelDistance(mainFrame: CGRect, settingsFrame: CGRect) {
        let distance = abs(settingsFrame.midX - mainFrame.midX)
        if abs(distance - gearTravelDistance) > 0.5 {
            gearTravelDistance = distance
        }
    }

    private func updateGearPosition(to frame: CGRect) {
        if reduceMotion {
            gearPositionX = frame.midX
            gearPositionY = frame.midY
        } else {
            withAnimation(.spring(response: gearSlideDuration, dampingFraction: 0.85)) {
                gearPositionX = frame.midX
                gearPositionY = frame.midY
            }
        }
    }
}

struct OverlayGlassButtonStyleModifier: ViewModifier {
    let reduceTransparency: Bool

    func body(content: Content) -> some View {
        if reduceTransparency {
            content.buttonStyle(PlainButtonStyle())
        } else if #available(macOS 26.0, *) {
            content.buttonStyle(GlassButtonStyle())
        } else {
            content.buttonStyle(PlainButtonStyle())
        }
    }
}

struct OverlayGlassEffectModifier: ViewModifier {
    let isEnabled: Bool
    let cornerRadius: CGFloat
    let fallbackFill: Color

    func body(content: Content) -> some View {
        if isEnabled, #available(macOS 26.0, *) {
            content.glassEffect(.regular.interactive(), in: .rect(cornerRadius: cornerRadius))
        } else {
            content
                .background(
                    RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
                        .fill(fallbackFill)
                )
        }
    }
}

/// Slide-over panels that can appear in the drawer
enum DrawerPanel {
    case launcherSettings // Launcher activation mode & history suggestions

    var title: String {
        switch self {
        case .launcherSettings: "Launcher Settings"
        }
    }
}

enum InspectorSection: String {
    case mapper
    case customRules // Only shown when custom rules exist
    case keyboard
    case layout
    case keycaps
    case sounds
    case launchers
}

extension InspectorSection {
    var isSettingsShelf: Bool {
        switch self {
        case .keycaps, .sounds, .keyboard, .layout:
            true
        case .mapper, .customRules, .launchers:
            false
        }
    }
}

// MARK: - Mouse move monitor (resets idle on movement/scroll within overlay)

struct MouseMoveMonitor: NSViewRepresentable {
    let onMove: () -> Void

    func makeNSView(context _: Context) -> TrackingView {
        TrackingView(onMove: onMove)
    }

    func updateNSView(_ nsView: TrackingView, context _: Context) {
        nsView.onMove = onMove
    }

    /// NSView subclass that fires on every mouse move or scroll within its bounds.
    @MainActor
    final class TrackingView: NSView {
        var onMove: () -> Void
        private var trackingArea: NSTrackingArea?
        private var scrollMonitor: Any?

        init(onMove: @escaping () -> Void) {
            self.onMove = onMove
            super.init(frame: .zero)
        }

        @MainActor required init?(coder: NSCoder) {
            onMove = {}
            super.init(coder: coder)
        }

        override func updateTrackingAreas() {
            super.updateTrackingAreas()
            if let trackingArea {
                removeTrackingArea(trackingArea)
            }
            let options: NSTrackingArea.Options = [.mouseMoved, .activeAlways, .inVisibleRect, .enabledDuringMouseDrag, .mouseEnteredAndExited]
            let area = NSTrackingArea(rect: bounds, options: options, owner: self, userInfo: nil)
            addTrackingArea(area)
            trackingArea = area
        }

        override func viewDidMoveToWindow() {
            super.viewDidMoveToWindow()
            window?.acceptsMouseMovedEvents = true

            // Set up local event monitor for scroll wheel events
            // This catches scroll events anywhere in the window (including the drawer)
            if scrollMonitor == nil {
                scrollMonitor = NSEvent.addLocalMonitorForEvents(matching: .scrollWheel) { [weak self] event in
                    // Check if the scroll event is within our window
                    if event.window == self?.window {
                        self?.onMove()
                    }
                    return event
                }
            }
        }

        override func removeFromSuperview() {
            // Clean up scroll monitor when view is removed
            if let monitor = scrollMonitor {
                NSEvent.removeMonitor(monitor)
                scrollMonitor = nil
            }
            super.removeFromSuperview()
        }

        override func mouseMoved(with _: NSEvent) {
            onMove()
        }

        override func mouseEntered(with _: NSEvent) {
            onMove()
        }

        override func mouseExited(with _: NSEvent) {
            onMove()
        }

        override func hitTest(_: NSPoint) -> NSView? {
            // Let events pass through to the SwiftUI content while still receiving mouseMoved.
            nil
        }
    }
}

// MARK: - Tap-Hold Mini Keycap

/// Small keycap for tap-hold configuration in the customize panel
struct TapHoldMiniKeycap: View {
    let label: String
    let isRecording: Bool
    let onTap: () -> Void

    @State private var isHovered = false
    @State private var isPressed = false

    private let size: CGFloat = 48
    private let cornerRadius: CGFloat = 8
    private let fontSize: CGFloat = 16

    var body: some View {
        ZStack {
            RoundedRectangle(cornerRadius: cornerRadius)
                .fill(backgroundColor)
                .shadow(color: shadowColor, radius: shadowRadius, y: shadowOffset)
                .overlay(
                    RoundedRectangle(cornerRadius: cornerRadius)
                        .stroke(borderColor, lineWidth: isRecording ? 2 : 1)
                )

            if isRecording {
                Text("...")
                    .font(.system(size: fontSize, weight: .medium))
                    .foregroundStyle(foregroundColor)
            } else if label.isEmpty {
                Image(systemName: "plus")
                    .font(.system(size: fontSize * 0.7, weight: .light))
                    .foregroundStyle(foregroundColor.opacity(0.4))
            } else {
                Text(label)
                    .font(.system(size: fontSize, weight: .medium))
                    .foregroundStyle(foregroundColor)
                    .minimumScaleFactor(0.5)
                    .lineLimit(1)
                    .padding(.horizontal, 4)
            }
        }
        .frame(width: size, height: size)
        .scaleEffect(isPressed ? 0.95 : 1.0)
        .animation(.spring(response: 0.15, dampingFraction: 0.6), value: isPressed)
        .onHover { hovering in
            withAnimation(.easeInOut(duration: 0.15)) {
                isHovered = hovering
            }
        }
        .onTapGesture {
            withAnimation(.spring(response: 0.1, dampingFraction: 0.8)) {
                isPressed = true
            }
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.1) {
                withAnimation(.spring(response: 0.1, dampingFraction: 0.8)) {
                    isPressed = false
                }
            }
            onTap()
        }
    }

    @Environment(\.colorScheme) private var colorScheme

    private var isDark: Bool {
        colorScheme == .dark
    }

    private var foregroundColor: Color {
        isDark
            ? Color(red: 0.88, green: 0.93, blue: 1.0).opacity(isPressed ? 1.0 : 0.88)
            : Color.primary.opacity(isPressed ? 1.0 : 0.88)
    }

    private var backgroundColor: Color {
        if isRecording {
            Color.accentColor
        } else if isHovered {
            isDark ? Color(white: 0.18) : Color(white: 0.92)
        } else {
            isDark ? Color(white: 0.12) : Color(white: 0.96)
        }
    }

    private var borderColor: Color {
        if isRecording {
            Color.accentColor.opacity(0.8)
        } else if isHovered {
            isDark ? Color.white.opacity(0.3) : Color.black.opacity(0.15)
        } else {
            isDark ? Color.white.opacity(0.15) : Color.black.opacity(0.1)
        }
    }

    private var shadowColor: Color {
        isDark ? Color.black.opacity(0.5) : Color.black.opacity(0.15)
    }

    private var shadowRadius: CGFloat {
        isPressed ? 1 : 2
    }

    private var shadowOffset: CGFloat {
        isPressed ? 1 : 2
    }
}
