import AppKit
import SwiftUI

/// The main live keyboard overlay view.
/// Shows a borderless floating keyboard that highlights keys as they are pressed.
struct LiveKeyboardOverlayView: View {
    @ObservedObject var viewModel: KeyboardVisualizationViewModel
    /// Callback when a key is clicked (not dragged) - for opening Mapper with preset values
    var onKeyClick: ((PhysicalKey, LayerKeyInfo?) -> Void)?

    @Environment(\.colorScheme) private var colorScheme
    @AppStorage("overlayLayoutId") private var selectedLayoutId: String = "macbook-us"
    @AppStorage(KeymapPreferences.keymapIdKey) private var selectedKeymapId: String = LogicalKeymap.defaultId
    @AppStorage(KeymapPreferences.includePunctuationStoreKey) private var keymapIncludePunctuationStore: String = "{}"

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

        VStack(spacing: 0) {
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
            .padding(10)
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

        let ambientShadow = Color.black.opacity((isDark ? 0.20 : 0.12) * (1 - fadeAmount))
        let contactShadow = Color.black.opacity((isDark ? 0.12 : 0.08) * (1 - fadeAmount))

        RoundedRectangle(cornerRadius: cornerRadius)
            .fill(.ultraThinMaterial)
            .overlay(
                RoundedRectangle(cornerRadius: cornerRadius)
                    .fill(tint)
            )
            // Fade overlay: animating material .opacity() directly causes discrete jumps,
            // so we overlay a semi-transparent wash that fades in smoothly instead
            .overlay(
                RoundedRectangle(cornerRadius: cornerRadius)
                    .fill(Color(white: isDark ? 0.1 : 0.9).opacity(0.25 * fadeAmount))
            )
            // y >= radius ensures shadow only renders below (light from above)
            .shadow(color: ambientShadow, radius: 14, x: 0, y: 14)
            .shadow(color: contactShadow, radius: 4, x: 0, y: 4)
            .animation(.easeOut(duration: 0.3), value: fadeAmount)
    }
}

// MARK: - Preview

#Preview("Keys Pressed") {
    LiveKeyboardOverlayView(
        viewModel: {
            let vm = KeyboardVisualizationViewModel()
            vm.pressedKeyCodes = [0, 56, 55] // a, leftshift, leftmeta
            return vm
        }()
    )
    .padding(40)
    .frame(width: 700, height: 350)
    .background(Color(white: 0.3))
}

#Preview("No Keys") {
    LiveKeyboardOverlayView(
        viewModel: KeyboardVisualizationViewModel()
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
