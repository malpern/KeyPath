import AppKit
import SwiftUI

/// The main live keyboard overlay view.
/// Shows a borderless floating keyboard that highlights keys as they are pressed.
struct LiveKeyboardOverlayView: View {
    @ObservedObject var viewModel: KeyboardVisualizationViewModel

    @Environment(\.colorScheme) private var colorScheme

    /// Constants matching OverlayKeyboardView for scale calculation
    private let keyUnitSize: CGFloat = 32
    private let keyGap: CGFloat = 2
    private let layout = PhysicalLayout.macBookUS

    var body: some View {
        GeometryReader { geometry in
            let scale = calculateScale(for: geometry.size)
            let cornerRadius = 10 * scale // Larger than keys for harmonious container feel
            let fadeAmount: CGFloat = viewModel.fadeAmount

            // Main keyboard with directional shadow (light from above)
            OverlayKeyboardView(
                layout: .macBookUS,
                pressedKeyCodes: viewModel.pressedKeyCodes,
                isDarkMode: isDark,
                fadeAmount: fadeAmount,
                currentLayerName: viewModel.currentLayerName,
                isLoadingLayerMap: viewModel.isLoadingLayerMap,
                layerKeyMap: viewModel.layerKeyMap,
                effectivePressedKeyCodes: viewModel.effectivePressedKeyCodes,
                emphasizedKeyCodes: viewModel.emphasizedKeyCodes,
                holdLabels: viewModel.holdLabels
            )
            .environmentObject(viewModel)
            .padding(10)
            .background(
                glassBackground(cornerRadius: cornerRadius, fadeAmount: fadeAmount)
            )
            // Resize/move handles on the keyboard background (not shadow area)
            .windowResizeHandles()
            .environmentObject(viewModel)
            // Padding for shadow to fade naturally (asymmetric - more below)
            .padding(.bottom, 25)
            .padding(.horizontal, 15)
            .padding(.top, 8)
            .frame(maxWidth: .infinity, maxHeight: .infinity)
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

    // MARK: - Styling

    private var isDark: Bool { colorScheme == .dark }

    @ViewBuilder
    private func glassBackground(cornerRadius: CGFloat, fadeAmount: CGFloat) -> some View {
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

    /// Calculate scale to match OverlayKeyboardView's scale calculation
    private func calculateScale(for size: CGSize) -> CGFloat {
        // Account for padding (10pt on each side)
        let contentSize = CGSize(width: size.width - 20, height: size.height - 20)
        let widthScale = contentSize.width / (layout.totalWidth * (keyUnitSize + keyGap))
        let heightScale = contentSize.height / (layout.totalHeight * (keyUnitSize + keyGap))
        return min(widthScale, heightScale)
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
