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
                    inspectorReveal: inspectorReveal,
                    inspectorHeaderWidth: inspectorTotalWidth,
                    onToggleInspector: { onToggleInspector?() },
                    onClose: { onClose?() }
                )
                .frame(maxWidth: .infinity)
                .padding(.bottom, headerBottomSpacing)

                ZStack(alignment: .topLeading) {
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

                    if inspectorVisible {
                        OverlayInspectorPanel(
                            selectedSection: inspectorSection,
                            onSelectSection: { inspectorSection = $0 }
                        )
                        .frame(width: inspectorWidth, alignment: .leading)
                        .frame(width: inspectorTotalWidth, alignment: .leading)
                        .frame(width: inspectorTotalWidth * inspectorReveal, alignment: .leading)
                        .clipped()
                        .frame(maxWidth: .infinity, alignment: .topTrailing)
                    }
                }
                .padding(.leading, keyboardPadding)
                .padding(.trailing, keyboardTrailingPadding)
                .padding(.bottom, keyboardPadding)
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
        .environmentObject(viewModel)
        // Minimal padding for shadow (keep horizontal only)
        .padding(.horizontal, outerHorizontalPadding)
        .onHover { hovering in
            if hovering { viewModel.noteInteraction() }
        }
        .background(MouseMoveMonitor { viewModel.noteInteraction() })
        .opacity(0.11 + 0.89 * (1 - viewModel.deepFadeAmount))
        // Animate deep fade smoothly; fade-in is instant
        .animation(viewModel.deepFadeAmount > 0 ? .easeOut(duration: 0.3) : nil,
                   value: viewModel.deepFadeAmount)
    }
}

// MARK: - LiveKeyboardOverlayView Styling Extension

extension LiveKeyboardOverlayView {
    var isDark: Bool { colorScheme == .dark }

    @ViewBuilder
    func glassBackground(cornerRadius: CGFloat, fadeAmount: CGFloat) -> some View {
        // Simulated "liquid glass" backdrop: adaptive material + tint + softened shadows.
        let tint = isDark
            ? Color.white.opacity(0.12 - 0.07 * fadeAmount)
            : Color.black.opacity(0.08 - 0.04 * fadeAmount)

        let contactShadow = Color.black.opacity((isDark ? 0.12 : 0.08) * (1 - fadeAmount))

        RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
            .fill(.ultraThinMaterial)
            .overlay(
                RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
                    .fill(tint)
            )
            // Fade overlay: animating material .opacity() directly causes discrete jumps,
            // so we overlay a semi-transparent wash that fades in smoothly instead
            .overlay(
                RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
                    .fill(Color(white: isDark ? 0.1 : 0.9).opacity(0.25 * fadeAmount))
            )
            // y >= radius ensures shadow only renders below (light from above)
            .shadow(color: contactShadow, radius: 4, x: 0, y: 4)
            .animation(.easeOut(duration: 0.3), value: fadeAmount)
    }
}

// MARK: - Overlay Drag Header + Inspector

private struct OverlayDragHeader: View {
    let isDark: Bool
    let fadeAmount: CGFloat
    let height: CGFloat
    let isInspectorOpen: Bool
    let leadingContentPadding: CGFloat
    let inspectorReveal: CGFloat
    let inspectorHeaderWidth: CGFloat
    let onToggleInspector: () -> Void
    let onClose: () -> Void

    @State private var isDragging = false
    @State private var initialFrame: NSRect = .zero
    @State private var initialMouseLocation: NSPoint = .zero

    var body: some View {
        let buttonSize = max(10, height * 0.9)
        let revealWidth = inspectorHeaderWidth * inspectorReveal
        let shouldShowInspector = inspectorReveal > 0.01

        ZStack {
            Rectangle()
                .fill(.ultraThinMaterial)
                .overlay(
                    Rectangle()
                        .fill(headerTint)
                )
                .overlay(alignment: .trailing) {
                    if shouldShowInspector {
                        Rectangle()
                            .fill(inspectorTint)
                            .frame(width: revealWidth)
                    }
                }
                .overlay(
                    Rectangle()
                        .stroke(headerStroke, lineWidth: 1)
                )
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
                        .background(
                            RoundedRectangle(cornerRadius: 4)
                                .fill(headerIconBackground)
                        )
                }
                .buttonStyle(.plain)
                .help("Close Overlay")

                Button(action: onToggleInspector) {
                    Image(systemName: "rectangle.and.sidebar.right")
                        .font(.system(size: buttonSize * 0.45, weight: .semibold))
                        .foregroundStyle(isInspectorOpen ? Color.accentColor : headerIconColor)
                        .frame(width: buttonSize, height: buttonSize)
                        .background(
                            RoundedRectangle(cornerRadius: 4)
                                .fill(headerIconBackground)
                        )
                }
                .buttonStyle(.plain)
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
        let base = isDark ? 0.14 : 0.93
        let opacity = max(0.18, 0.32 - 0.18 * fadeAmount)
        return Color(white: base).opacity(opacity)
    }

    private var inspectorTint: Color {
        let base = isDark ? 0.1 : 0.97
        let opacity = max(0.22, 0.38 - 0.18 * fadeAmount)
        return Color(white: base).opacity(opacity)
    }

    private var headerStroke: Color {
        Color.white.opacity(isDark ? 0.08 : 0.2)
    }

    private var headerIconColor: Color {
        Color.white.opacity(isDark ? 0.7 : 0.6)
    }

    private var headerIconBackground: Color {
        Color.white.opacity(isDark ? 0.08 : 0.18)
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

struct OverlayInspectorPanel: View {
    @Environment(\.colorScheme) private var colorScheme
    let selectedSection: InspectorSection
    let onSelectSection: (InspectorSection) -> Void

    var body: some View {
        VStack(spacing: 12) {
            InspectorPanelToolbar(
                selectedSection: selectedSection,
                onSelectSection: onSelectSection
            )
            .padding(.top, 10)

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
            Rectangle()
                .stroke(Color(white: isDark ? 0.35 : 0.7), lineWidth: 1)
        )
    }

    private var panelBackground: some View {
        let fill = Color(white: isDark ? 0.12 : 0.88)
        return Rectangle().fill(fill)
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
    let selectedSection: InspectorSection
    let onSelectSection: (InspectorSection) -> Void
    private let buttonSize: CGFloat = 22

    var body: some View {
        HStack(spacing: 8) {
            toolbarButton(
                systemImage: "keyboard",
                isSelected: selectedSection == .keyboard
            ) {
                onSelectSection(.keyboard)
            }
            .accessibilityLabel("Keymap")

            toolbarButton(
                systemImage: "square.grid.3x2",
                isSelected: selectedSection == .layout
            ) {
                onSelectSection(.layout)
            }
            .accessibilityLabel("Physical Layout")
        }
        .controlSize(.regular)
        .padding(.horizontal, 14)
        .padding(.vertical, 6)
        .glassEffect(.regular.interactive(), in: .rect(cornerRadius: 10))
        .frame(maxWidth: .infinity, alignment: .center)
    }

    private func toolbarButton(
        systemImage: String,
        isSelected: Bool,
        action: @escaping () -> Void
    ) -> some View {
        Button(action: action) {
            Image(systemName: systemImage)
                .font(.system(size: buttonSize * 0.5, weight: .semibold))
                .foregroundStyle(isSelected ? .primary : .secondary)
                .frame(width: buttonSize, height: buttonSize)
        }
        .buttonStyle(.borderless)
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
