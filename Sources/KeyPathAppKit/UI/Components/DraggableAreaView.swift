import AppKit
import SwiftUI

/// A transparent NSView that lets users drag the window from SwiftUI regions.
struct DraggableAreaView: NSViewRepresentable {
    func makeNSView(context _: Context) -> NSView {
        let v = NSView(frame: .zero)
        v.wantsLayer = true
        v.layer?.backgroundColor = .clear
        v.postsFrameChangedNotifications = false
        // Allow dragging the window when clicking this view
        // We rely on the native titlebar accessory for drag; this view remains transparent.
        return v
    }

    func updateNSView(_: NSView, context _: Context) {
        // No-op
    }
}
