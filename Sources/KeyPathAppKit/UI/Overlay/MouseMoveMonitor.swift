import AppKit
import SwiftUI

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
