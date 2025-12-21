import AppKit
import SwiftUI

/// The main live keyboard overlay view.
/// Shows a borderless floating keyboard that highlights keys as they are pressed.
struct LiveKeyboardOverlayView: View {
    @ObservedObject var viewModel: KeyboardVisualizationViewModel
    @ObservedObject var uiState: LiveKeyboardOverlayUIState
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
        let headerHeight: CGFloat = 15
        let keyboardPadding: CGFloat = 6
        let headerBottomSpacing: CGFloat = 4
        let headerContentLeadingPadding = keyboardPadding + escKeyLeftInset

        VStack(spacing: 0) {
            VStack(spacing: 0) {
                OverlayDragHeader(
                    isDark: isDark,
                    fadeAmount: fadeAmount,
                    height: headerHeight,
                    isInspectorOpen: uiState.isInspectorOpen,
                    leadingContentPadding: headerContentLeadingPadding,
                    onToggleInspector: { onToggleInspector?() },
                    onClose: { onClose?() }
                )
                .frame(maxWidth: .infinity)
                .padding(.bottom, headerBottomSpacing)

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
                .padding(.horizontal, keyboardPadding)
                .padding(.bottom, keyboardPadding)
                .onPreferenceChange(EscKeyLeftInsetPreferenceKey.self) { newValue in
                    escKeyLeftInset = newValue
                }
            }
        }
        .background(
            glassBackground(cornerRadius: cornerRadius, fadeAmount: fadeAmount)
        )
        // Resize/move handles on the keyboard background (not shadow area)
        .windowResizeHandles()
        .environmentObject(viewModel)
        // Minimal padding for shadow (just enough for bottom shadow)
        .padding(.bottom, 20)
        .padding(.horizontal, 4)
        .padding(.top, 4)
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

        BottomRoundedRectangle(radius: cornerRadius)
            .fill(.ultraThinMaterial)
            .overlay(
                BottomRoundedRectangle(radius: cornerRadius)
                    .fill(tint)
            )
            // Fade overlay: animating material .opacity() directly causes discrete jumps,
            // so we overlay a semi-transparent wash that fades in smoothly instead
            .overlay(
                BottomRoundedRectangle(radius: cornerRadius)
                    .fill(Color(white: isDark ? 0.1 : 0.9).opacity(0.25 * fadeAmount))
            )
            // y >= radius ensures shadow only renders below (light from above)
            .shadow(color: contactShadow, radius: 4, x: 0, y: 4)
            .animation(.easeOut(duration: 0.3), value: fadeAmount)
    }
}

private struct BottomRoundedRectangle: Shape {
    let radius: CGFloat

    func path(in rect: CGRect) -> Path {
        let r = min(radius, rect.width / 2, rect.height / 2)
        var path = Path()
        path.move(to: CGPoint(x: rect.minX, y: rect.minY))
        path.addLine(to: CGPoint(x: rect.maxX, y: rect.minY))
        path.addLine(to: CGPoint(x: rect.maxX, y: rect.maxY - r))
        path.addQuadCurve(
            to: CGPoint(x: rect.maxX - r, y: rect.maxY),
            control: CGPoint(x: rect.maxX, y: rect.maxY)
        )
        path.addLine(to: CGPoint(x: rect.minX + r, y: rect.maxY))
        path.addQuadCurve(
            to: CGPoint(x: rect.minX, y: rect.maxY - r),
            control: CGPoint(x: rect.minX, y: rect.maxY)
        )
        path.addLine(to: CGPoint(x: rect.minX, y: rect.minY))
        path.closeSubpath()
        return path
    }
}

// MARK: - Overlay Drag Header + Inspector

private struct OverlayDragHeader: View {
    let isDark: Bool
    let fadeAmount: CGFloat
    let height: CGFloat
    let isInspectorOpen: Bool
    let leadingContentPadding: CGFloat
    let onToggleInspector: () -> Void
    let onClose: () -> Void

    var body: some View {
        let buttonSize = max(10, height * 0.9)

        ZStack {
            Rectangle()
                .fill(headerFill)
                .overlay(
                    Rectangle()
                        .stroke(headerStroke, lineWidth: 1)
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
        }
        .frame(height: height)
    }

    private var headerFill: Color {
        let base = isDark ? 0.14 : 0.92
        let opacity = max(0.12, 0.3 - 0.15 * fadeAmount)
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
}

struct OverlayInspectorPanel: View {
    @Environment(\.colorScheme) private var colorScheme

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Overlay")
                .font(.headline)
                .foregroundStyle(.primary)

            Text("Quick access to overlay settings.")
                .font(.caption)
                .foregroundStyle(.secondary)

            Button("Open Settings…") {
                NotificationCenter.default.post(name: .openSettingsGeneral, object: nil)
            }
            .buttonStyle(.borderedProminent)
            .controlSize(.small)

            Spacer(minLength: 0)
        }
        .padding(12)
        .frame(maxHeight: .infinity, alignment: .top)
        .background(panelBackground)
        .overlay(
            RoundedRectangle(cornerRadius: 8)
                .stroke(Color.white.opacity(isDark ? 0.08 : 0.15), lineWidth: 1)
        )
        .clipShape(RoundedRectangle(cornerRadius: 8))
    }

    private var panelBackground: some View {
        RoundedRectangle(cornerRadius: 8)
            .fill(.ultraThinMaterial)
            .overlay(
                RoundedRectangle(cornerRadius: 8)
                    .fill(Color(white: isDark ? 0.08 : 0.95).opacity(0.45))
            )
    }

    private var isDark: Bool {
        colorScheme == .dark
    }
}

// MARK: - Preview

#Preview("Keys Pressed") {
    LiveKeyboardOverlayView(
        viewModel: {
            let vm = KeyboardVisualizationViewModel()
            vm.pressedKeyCodes = [0, 56, 55] // a, leftshift, leftmeta
            return vm
        }(),
        uiState: LiveKeyboardOverlayUIState()
    )
    .padding(40)
    .frame(width: 700, height: 350)
    .background(Color(white: 0.3))
}

#Preview("No Keys") {
    LiveKeyboardOverlayView(
        viewModel: KeyboardVisualizationViewModel(),
        uiState: LiveKeyboardOverlayUIState()
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
