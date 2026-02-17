import AppKit
import KeyPathCore
import SwiftUI

/// A floating window that briefly shows "Overlay Hidden — press ⌥⌘K to bring it back"
/// after the user hides the overlay. Auto-dismisses after 5 seconds with fade animation.
@MainActor
final class OverlayHiddenHintWindowController {
    private var window: NSWindow?
    private var dismissTask: Task<Void, Never>?

    /// Show the hint centered on screen
    func show() {
        guard window == nil else { return }

        let hintView = OverlayHiddenHintView()
        let hostingView = NSHostingView(rootView: hintView)
        hostingView.frame = NSRect(x: 0, y: 0, width: 400, height: 50)

        let fittingSize = hostingView.fittingSize
        hostingView.frame.size = fittingSize

        let hintWindow = NSWindow(
            contentRect: NSRect(origin: .zero, size: fittingSize),
            styleMask: [.borderless],
            backing: .buffered,
            defer: false
        )
        hintWindow.isOpaque = false
        hintWindow.backgroundColor = .clear
        hintWindow.level = .floating
        hintWindow.hasShadow = true
        hintWindow.ignoresMouseEvents = true
        hintWindow.contentView = hostingView

        // Center on main screen
        if let screen = NSScreen.main {
            let screenFrame = screen.visibleFrame
            let x = screenFrame.midX - fittingSize.width / 2
            let y = screenFrame.midY - fittingSize.height / 2
            hintWindow.setFrameOrigin(NSPoint(x: x, y: y))
        }

        // Start invisible for fade-in
        hintWindow.alphaValue = 0
        hintWindow.orderFront(nil)
        window = hintWindow

        // Animate in: fade + slight scale up
        if let contentView = hintWindow.contentView {
            contentView.wantsLayer = true
            contentView.layer?.anchorPoint = CGPoint(x: 0.5, y: 0.5)
            let bounds = contentView.bounds
            contentView.layer?.position = CGPoint(x: bounds.midX, y: bounds.midY)
            contentView.layer?.transform = CATransform3DMakeScale(0.95, 0.95, 1.0)
        }

        NSAnimationContext.runAnimationGroup { context in
            context.duration = 0.2
            context.timingFunction = CAMediaTimingFunction(name: .easeOut)
            hintWindow.animator().alphaValue = 1.0
            hintWindow.contentView?.animator().layer?.transform = CATransform3DIdentity
        }

        // Auto-dismiss after 5 seconds
        dismissTask = Task { @MainActor in
            try? await Task.sleep(for: .seconds(5))
            guard !Task.isCancelled else { return }
            dismiss()
        }

        AppLogger.shared.log("💬 [OverlayHiddenHint] Showing education message")
    }

    /// Dismiss the hint with fade-out animation
    func dismiss() {
        dismissTask?.cancel()
        dismissTask = nil

        guard let window else { return }

        NSAnimationContext.runAnimationGroup { context in
            context.duration = 0.2
            context.timingFunction = CAMediaTimingFunction(name: .easeIn)
            window.animator().alphaValue = 0
            if let layer = window.contentView?.layer {
                layer.transform = CATransform3DMakeScale(0.95, 0.95, 1.0)
            }
        } completionHandler: { [weak self] in
            MainActor.assumeIsolated {
                self?.window?.orderOut(nil)
                self?.window = nil
                AppLogger.shared.log("💬 [OverlayHiddenHint] Education message dismissed")
            }
        }
    }
}
