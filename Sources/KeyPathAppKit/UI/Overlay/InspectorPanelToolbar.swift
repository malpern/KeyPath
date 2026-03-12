import SwiftUI

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
    @State private var isHoveringDevices = false
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
        .accessibilityIdentifier("inspector-tab-settings-gear-button")
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

            toolbarButton(
                systemImage: "cable.connector",
                isSelected: selectedSection == .devices,
                isHovering: isHoveringDevices,
                onHover: { isHoveringDevices = $0 },
                action: { onSelectSection(.devices) }
            )
            .accessibilityIdentifier("inspector-tab-devices")
            .accessibilityLabel("Devices")
            .help("Devices")
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
