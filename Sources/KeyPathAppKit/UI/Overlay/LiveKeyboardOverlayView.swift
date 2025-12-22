import AppKit
import SwiftUI

/// The main live keyboard overlay view.
/// Shows a borderless floating keyboard that highlights keys as they are pressed.
struct LiveKeyboardOverlayView: View {
    @ObservedObject var viewModel: KeyboardVisualizationViewModel
    @ObservedObject var uiState: LiveKeyboardOverlayUIState
    let inspectorWidth: CGFloat
    /// Callback when a key is clicked (not dragged) - for opening Mapper with preset values
    var onKeyClick: ((PhysicalKey, LayerKeyInfo?) -> Void)?
    /// Callback when the overlay close button is pressed
    var onClose: (() -> Void)?
    /// Callback when the inspector button is pressed
    var onToggleInspector: (() -> Void)?

    @Environment(\.colorScheme) private var colorScheme
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Environment(\.accessibilityReduceTransparency) private var reduceTransparency
    @AppStorage("overlayLayoutId") private var selectedLayoutId: String = "macbook-us"
    @AppStorage(KeymapPreferences.keymapIdKey) private var selectedKeymapId: String = LogicalKeymap.defaultId
    @AppStorage(KeymapPreferences.includePunctuationStoreKey) private var keymapIncludePunctuationStore: String = "{}"

    @State private var escKeyLeftInset: CGFloat = 0
    @State private var keyboardWidth: CGFloat = 0
    @State private var inspectorSection: InspectorSection = .keyboard
    /// Shared state for tracking mouse interaction with keyboard (for refined click delay)
    @StateObject private var keyboardMouseState = KeyboardMouseState()

    /// The currently selected physical keyboard layout
    private var activeLayout: PhysicalLayout {
        PhysicalLayout.find(id: selectedLayoutId) ?? .macBookUS
    }

    /// The currently selected logical keymap for labeling
    private var activeKeymap: LogicalKeymap {
        LogicalKeymap.find(id: selectedKeymapId) ?? .qwertyUS
    }

    /// Whether to apply number row + outer punctuation mappings
    private var includeKeymapPunctuation: Bool {
        KeymapPreferences.includePunctuation(
            for: selectedKeymapId,
            store: keymapIncludePunctuationStore
        )
    }

    var body: some View {
        let cornerRadius: CGFloat = 10 // Fixed corner radius for glass container
        let fadeAmount: CGFloat = viewModel.fadeAmount
        let headerHeight = OverlayLayoutMetrics.headerHeight
        let keyboardPadding = OverlayLayoutMetrics.keyboardPadding
        let keyboardTrailingPadding = OverlayLayoutMetrics.keyboardTrailingPadding
        let headerBottomSpacing = OverlayLayoutMetrics.headerBottomSpacing
        let outerHorizontalPadding = OverlayLayoutMetrics.outerHorizontalPadding
        let headerContentLeadingPadding = keyboardPadding + escKeyLeftInset
        let inspectorReveal = uiState.inspectorReveal
        let inspectorVisible = inspectorReveal > 0
        let trailingOuterPadding = inspectorVisible ? 0 : outerHorizontalPadding
        let keyboardAspectRatio = activeLayout.totalWidth / activeLayout.totalHeight
        let inspectorSeamWidth = OverlayLayoutMetrics.inspectorSeamWidth
        let inspectorChrome = uiState.isInspectorOpen ? inspectorWidth + inspectorSeamWidth : 0
        let inspectorTotalWidth = inspectorWidth + inspectorSeamWidth
        let verticalChrome = OverlayLayoutMetrics.verticalChrome
        let shouldFreezeKeyboard = uiState.isInspectorAnimating
        let fixedKeyboardWidth: CGFloat? = keyboardWidth > 0 ? keyboardWidth : nil
        let fixedKeyboardHeight: CGFloat? = fixedKeyboardWidth.map { $0 / keyboardAspectRatio }

        VStack(spacing: 0) {
            VStack(spacing: 0) {
                OverlayDragHeader(
                    isDark: isDark,
                    fadeAmount: fadeAmount,
                    height: headerHeight,
                    isInspectorOpen: uiState.isInspectorOpen,
                    leadingContentPadding: headerContentLeadingPadding,
                    reduceTransparency: reduceTransparency,
                    inspectorReveal: inspectorReveal,
                    inspectorHeaderWidth: inspectorTotalWidth,
                    onToggleInspector: { onToggleInspector?() },
                    onClose: { onClose?() }
                )
                .frame(maxWidth: .infinity)

                ZStack(alignment: .topLeading) {
                    if inspectorVisible {
                        Rectangle()
                            .fill(overlayPanelFill)
                            .frame(width: inspectorTotalWidth)
                            .frame(maxHeight: .infinity)
                            .frame(maxWidth: .infinity, alignment: .topTrailing)
                    }

                    HStack(alignment: .top, spacing: 0) {
                        // Main keyboard with directional shadow (light from above)
                        OverlayKeyboardView(
                            layout: activeLayout,
                            keymap: activeKeymap,
                            includeKeymapPunctuation: includeKeymapPunctuation,
                            pressedKeyCodes: viewModel.pressedKeyCodes,
                            isDarkMode: isDark,
                            fadeAmount: fadeAmount,
                            keyFadeAmounts: viewModel.keyFadeAmounts,
                            currentLayerName: viewModel.currentLayerName,
                            isLoadingLayerMap: viewModel.isLoadingLayerMap,
                            layerKeyMap: viewModel.layerKeyMap,
                            effectivePressedKeyCodes: viewModel.effectivePressedKeyCodes,
                            emphasizedKeyCodes: viewModel.emphasizedKeyCodes,
                            holdLabels: viewModel.holdLabels,
                            onKeyClick: onKeyClick
                        )
                        .environmentObject(viewModel)
                        .environmentObject(keyboardMouseState)
                        .onHover { hovering in
                            // Reset click state when mouse exits keyboard area
                            if !hovering {
                                keyboardMouseState.reset()
                            }
                        }
                        .frame(
                            width: fixedKeyboardWidth,
                            height: fixedKeyboardHeight,
                            alignment: .leading
                        )
                        .onPreferenceChange(EscKeyLeftInsetPreferenceKey.self) { newValue in
                            escKeyLeftInset = newValue
                        }
                        .animation(nil, value: fixedKeyboardWidth)

                        Spacer(minLength: 0)
                    }
                    .padding(.top, headerBottomSpacing)
                    .padding(.bottom, keyboardPadding)

                    if inspectorVisible {
                        OverlayInspectorPanel(
                            selectedSection: inspectorSection,
                            onSelectSection: { inspectorSection = $0 },
                            fadeAmount: fadeAmount
                        )
                        .frame(width: inspectorWidth, alignment: .leading)
                        .frame(width: inspectorTotalWidth, alignment: .leading)
                        .frame(width: inspectorTotalWidth * inspectorReveal, alignment: .leading)
                        .frame(maxHeight: .infinity, alignment: .top)
                        .clipped()
                        .frame(maxWidth: .infinity, alignment: .topTrailing)
                    }
                }
                .padding(.leading, keyboardPadding)
                .padding(.trailing, keyboardTrailingPadding)
                .background(
                    GeometryReader { proxy in
                        Color.clear
                            .preference(
                                key: OverlayAvailableWidthPreferenceKey.self,
                                value: proxy.size.width
                            )
                    }
                )
            }
        }
        .onPreferenceChange(OverlayAvailableWidthPreferenceKey.self) { newValue in
            guard newValue > 0 else { return }
            let availableKeyboardWidth = max(0, newValue - keyboardPadding - keyboardTrailingPadding - inspectorChrome)
            let canUpdateWidth = keyboardWidth == 0 || !shouldFreezeKeyboard
            let targetWidth = canUpdateWidth ? availableKeyboardWidth : keyboardWidth
            if canUpdateWidth {
                keyboardWidth = availableKeyboardWidth
            }
            guard targetWidth > 0 else { return }
            let desiredHeight = verticalChrome + (targetWidth / keyboardAspectRatio)
            if uiState.desiredContentHeight != desiredHeight {
                uiState.desiredContentHeight = desiredHeight
            }
        }
        .onChange(of: selectedLayoutId) { _, _ in
            uiState.keyboardAspectRatio = keyboardAspectRatio
            guard keyboardWidth > 0 else { return }
            let desiredHeight = verticalChrome + (keyboardWidth / keyboardAspectRatio)
            if uiState.desiredContentHeight != desiredHeight {
                uiState.desiredContentHeight = desiredHeight
            }
        }
        .onAppear {
            uiState.keyboardAspectRatio = keyboardAspectRatio
        }
        .background(
            glassBackground(cornerRadius: cornerRadius, fadeAmount: fadeAmount)
        )
        .clipShape(RoundedRectangle(cornerRadius: cornerRadius, style: .continuous))
        .environmentObject(viewModel)
        // Minimal padding for shadow (keep horizontal only)
        .padding(.leading, outerHorizontalPadding)
        .padding(.trailing, trailingOuterPadding)
        .onHover { hovering in
            if hovering { viewModel.noteInteraction() }
        }
        .background(MouseMoveMonitor { viewModel.noteInteraction() })
        .opacity(0.11 + 0.89 * (1 - viewModel.deepFadeAmount))
        // Animate deep fade smoothly; fade-in is instant
        .animation(
            reduceMotion ? nil : (viewModel.deepFadeAmount > 0 ? .easeOut(duration: 0.3) : nil),
            value: viewModel.deepFadeAmount
        )
    }
}

// MARK: - LiveKeyboardOverlayView Styling Extension

extension LiveKeyboardOverlayView {
    var isDark: Bool { colorScheme == .dark }
    var overlayPanelFill: Color {
        Color(white: isDark ? 0.11 : 0.88)
    }

    @ViewBuilder
    func glassBackground(cornerRadius: CGFloat, fadeAmount: CGFloat) -> some View {
        // Simulated "liquid glass" backdrop: adaptive material + tint + softened shadows.
        let tint = isDark
            ? Color.white.opacity(0.12 - 0.07 * fadeAmount)
            : Color.black.opacity(0.08 - 0.04 * fadeAmount)

        let contactShadow = Color.black.opacity((isDark ? 0.12 : 0.08) * (1 - fadeAmount))

        let baseShape = RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)

        if reduceTransparency {
            baseShape
                .fill(Color(white: isDark ? 0.1 : 0.92))
                .overlay(
                    baseShape.stroke(Color.white.opacity(isDark ? 0.08 : 0.25), lineWidth: 0.5)
                )
        } else {
            baseShape
                .fill(.ultraThinMaterial)
                .overlay(
                    baseShape.fill(tint)
                )
                // Fade overlay: animating material .opacity() directly causes discrete jumps,
                // so we overlay a semi-transparent wash that fades in smoothly instead
                .overlay(
                    baseShape.fill(Color(white: isDark ? 0.1 : 0.9).opacity(0.25 * fadeAmount))
                )
                // y >= radius ensures shadow only renders below (light from above)
                .shadow(color: contactShadow, radius: 4, x: 0, y: 4)
                .animation(reduceMotion ? nil : .easeOut(duration: 0.3), value: fadeAmount)
        }
    }
}

// MARK: - Overlay Drag Header + Inspector

private struct OverlayDragHeader: View {
    let isDark: Bool
    let fadeAmount: CGFloat
    let height: CGFloat
    let isInspectorOpen: Bool
    let leadingContentPadding: CGFloat
    let reduceTransparency: Bool
    let inspectorReveal: CGFloat
    let inspectorHeaderWidth: CGFloat
    let onToggleInspector: () -> Void
    let onClose: () -> Void

    @State private var isDragging = false
    @State private var initialFrame: NSRect = .zero
    @State private var initialMouseLocation: NSPoint = .zero

    var body: some View {
        let buttonSize = max(10, height * 0.9)

        ZStack {
            Rectangle()
                .fill(headerFill)
                .contentShape(Rectangle())
                .gesture(
                    DragGesture(minimumDistance: 1, coordinateSpace: .global)
                        .onChanged { _ in
                            if !isDragging {
                                if let window = findOverlayWindow() {
                                    initialFrame = window.frame
                                    initialMouseLocation = NSEvent.mouseLocation
                                }
                                isDragging = true
                            }

                            let currentMouse = NSEvent.mouseLocation
                            let deltaX = currentMouse.x - initialMouseLocation.x
                            let deltaY = currentMouse.y - initialMouseLocation.y
                            moveWindow(deltaX: deltaX, deltaY: deltaY)
                        }
                        .onEnded { _ in
                            isDragging = false
                        }
                )

            HStack(spacing: 6) {
                Button(action: onClose) {
                    Image(systemName: "xmark")
                        .font(.system(size: buttonSize * 0.45, weight: .semibold))
                        .foregroundStyle(headerIconColor)
                        .frame(width: buttonSize, height: buttonSize)
                }
                .modifier(GlassButtonStyleModifier(reduceTransparency: reduceTransparency))
                .help("Close Overlay")

                Button(action: onToggleInspector) {
                    Image(systemName: "rectangle.and.sidebar.right")
                        .font(.system(size: buttonSize * 0.45, weight: .semibold))
                        .foregroundStyle(isInspectorOpen ? Color.accentColor : headerIconColor)
                        .frame(width: buttonSize, height: buttonSize)
                }
                .modifier(GlassButtonStyleModifier(reduceTransparency: reduceTransparency))
                .help(isInspectorOpen ? "Hide Inspector" : "Show Inspector")

                Spacer()
            }
            .padding(.leading, leadingContentPadding)
            .padding(.trailing, 6)
            .frame(maxWidth: .infinity, alignment: .leading)

        }
        .frame(height: height)
    }

    private var headerTint: Color {
        headerFill
    }

    private var headerFill: Color {
        Color(white: isDark ? 0.11 : 0.88)
    }

    private var headerIconColor: Color {
        Color.white.opacity(isDark ? 0.7 : 0.6)
    }

    private func moveWindow(deltaX: CGFloat, deltaY: CGFloat) {
        guard let window = findOverlayWindow() else { return }
        var newOrigin = initialFrame.origin
        newOrigin.x += deltaX
        newOrigin.y += deltaY
        window.setFrameOrigin(newOrigin)
    }

    private func findOverlayWindow() -> NSWindow? {
        NSApplication.shared.windows.first {
            $0.styleMask.contains(.borderless) && $0.level == .floating
        }
    }
}

private struct OverlayAvailableWidthPreferenceKey: PreferenceKey {
    static let defaultValue: CGFloat = 0

    static func reduce(value: inout CGFloat, nextValue: () -> CGFloat) {
        value = nextValue()
    }
}

private struct RightRoundedRectangle: Shape {
    let radius: CGFloat

    func path(in rect: CGRect) -> Path {
        let r = min(radius, rect.width / 2, rect.height / 2)
        var path = Path()
        path.move(to: CGPoint(x: rect.minX, y: rect.minY))
        path.addLine(to: CGPoint(x: rect.maxX - r, y: rect.minY))
        path.addQuadCurve(
            to: CGPoint(x: rect.maxX, y: rect.minY + r),
            control: CGPoint(x: rect.maxX, y: rect.minY)
        )
        path.addLine(to: CGPoint(x: rect.maxX, y: rect.maxY - r))
        path.addQuadCurve(
            to: CGPoint(x: rect.maxX - r, y: rect.maxY),
            control: CGPoint(x: rect.maxX, y: rect.maxY)
        )
        path.addLine(to: CGPoint(x: rect.minX, y: rect.maxY))
        path.closeSubpath()
        return path
    }
}

struct OverlayInspectorPanel: View {
    @Environment(\.colorScheme) private var colorScheme
    let selectedSection: InspectorSection
    let onSelectSection: (InspectorSection) -> Void
    let fadeAmount: CGFloat

    var body: some View {
        VStack(spacing: 12) {
            InspectorPanelToolbar(
                isDark: isDark,
                selectedSection: selectedSection,
                onSelectSection: onSelectSection
            )
            .padding(.top, 6)

            VStack(alignment: .leading, spacing: 12) {
                Text(sectionTitle)
                    .font(.headline)
                    .foregroundStyle(.primary)

                Text(sectionSubtitle)
                    .font(.caption)
                    .foregroundStyle(.secondary)

                Button("Open Settings…") {
                    NotificationCenter.default.post(name: .openSettingsGeneral, object: nil)
                }
                .buttonStyle(.borderedProminent)
                .controlSize(.small)

                Spacer(minLength: 0)
            }
            .padding(.horizontal, 12)
            .padding(.bottom, 12)
        }
        .background(panelBackground)
        .overlay(
            RightRoundedRectangle(radius: 10)
                .stroke(Color(white: isDark ? 0.35 : 0.7), lineWidth: 1)
        )
        .clipShape(RightRoundedRectangle(radius: 10))
    }

    private var panelBackground: some View {
        let fill = Color(white: isDark ? 0.11 : 0.88)
        return RightRoundedRectangle(radius: 10).fill(fill)
    }

    private var isDark: Bool {
        colorScheme == .dark
    }

    private var sectionTitle: String {
        switch selectedSection {
        case .keyboard:
            "Keymap"
        case .layout:
            "Physical Layout"
        }
    }

    private var sectionSubtitle: String {
        switch selectedSection {
        case .keyboard:
            "Logical labels for the keys you see."
        case .layout:
            "Choose the physical keyboard shape."
        }
    }
}

private struct InspectorPanelToolbar: View {
    let isDark: Bool
    let selectedSection: InspectorSection
    let onSelectSection: (InspectorSection) -> Void
    private let buttonSize: CGFloat = 32
    @Environment(\.accessibilityReduceTransparency) private var reduceTransparency
    @State private var isHoveringKeyboard = false
    @State private var isHoveringLayout = false

    var body: some View {
        HStack(spacing: 8) {
            toolbarButton(
                systemImage: "keyboard",
                isSelected: selectedSection == .keyboard,
                isHovering: isHoveringKeyboard,
                onHover: { isHoveringKeyboard = $0 }
            ) {
                onSelectSection(.keyboard)
            }
            .accessibilityLabel("Keymap")

            toolbarButton(
                systemImage: "square.grid.3x2",
                isSelected: selectedSection == .layout,
                isHovering: isHoveringLayout,
                onHover: { isHoveringLayout = $0 }
            ) {
                onSelectSection(.layout)
            }
            .accessibilityLabel("Physical Layout")
        }
        .controlSize(.regular)
        .padding(.horizontal, 14)
        .padding(.vertical, 8)
        .modifier(
            GlassEffectModifier(
                isEnabled: !reduceTransparency,
                cornerRadius: 12,
                fallbackFill: Color(white: isDark ? 0.18 : 0.92)
            )
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
                .foregroundStyle((isSelected || isHovering) ? .primary : .secondary)
                .frame(width: buttonSize, height: buttonSize)
        }
        .modifier(GlassButtonStyleModifier(reduceTransparency: reduceTransparency))
        .onHover(perform: onHover)
    }
}

private struct GlassButtonStyleModifier: ViewModifier {
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

private struct GlassEffectModifier: ViewModifier {
    let isEnabled: Bool
    let cornerRadius: CGFloat
    let fallbackFill: Color

    func body(content: Content) -> some View {
        if isEnabled {
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

enum InspectorSection {
    case keyboard
    case layout
}

// MARK: - Preview

#Preview("Keys Pressed") {
    LiveKeyboardOverlayView(
        viewModel: {
            let vm = KeyboardVisualizationViewModel()
            vm.pressedKeyCodes = [0, 56, 55] // a, leftshift, leftmeta
            return vm
        }(),
        uiState: LiveKeyboardOverlayUIState(),
        inspectorWidth: 240
    )
    .padding(40)
    .frame(width: 700, height: 350)
    .background(Color(white: 0.3))
}

#Preview("No Keys") {
    LiveKeyboardOverlayView(
        viewModel: KeyboardVisualizationViewModel(),
        uiState: LiveKeyboardOverlayUIState(),
        inspectorWidth: 240
    )
    .padding(40)
    .frame(width: 700, height: 350)
    .background(Color(white: 0.3))
}

// MARK: - Mouse move monitor (resets idle on movement within overlay)

private struct MouseMoveMonitor: NSViewRepresentable {
    let onMove: () -> Void

    func makeNSView(context _: Context) -> TrackingView {
        TrackingView(onMove: onMove)
    }

    func updateNSView(_ nsView: TrackingView, context _: Context) {
        nsView.onMove = onMove
    }

    /// NSView subclass that fires on every mouse move within its bounds.
    @MainActor
    final class TrackingView: NSView {
        var onMove: () -> Void
        private var trackingArea: NSTrackingArea?

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
