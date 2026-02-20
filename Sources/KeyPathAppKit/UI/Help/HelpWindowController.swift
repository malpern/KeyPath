import AppKit
import SwiftUI

/// Manages a standalone window for displaying help documentation from the Help menu.
@MainActor
final class HelpWindowController: NSObject, NSWindowDelegate {
    static let shared = HelpWindowController()

    private var window: NSWindow?
    private var overlayWasVisible = false
    private var keepingOverlayVisible = false

    override private init() {}

    /// Opens the help browser with a navigable sidebar of all topics.
    func showBrowser() {
        showBrowser(selecting: nil)
    }

    /// Opens the help browser with a specific topic pre-selected.
    /// - Parameters:
    ///   - topic: Optional topic to pre-select.
    ///   - keepOverlayVisible: When `true`, the overlay stays visible and the help window
    ///     is positioned on the left side of the screen so both are usable simultaneously.
    func showBrowser(selecting topic: HelpTopic?, keepOverlayVisible: Bool = false) {
        if let window, window.isVisible {
            window.makeKeyAndOrderFront(nil)
            NSApp.activate(ignoringOtherApps: true)
            return
        }

        keepingOverlayVisible = keepOverlayVisible

        if !keepOverlayVisible {
            // Hide the overlay while help is open (restore on close)
            let overlay = LiveKeyboardOverlayController.shared
            overlayWasVisible = overlay.isVisible
            if overlayWasVisible {
                overlay.isVisible = false
            }
        }

        let browserView = HelpBrowserView(initialTopic: topic)
        let hostingController = NSHostingController(rootView: browserView)

        let newWindow = NSWindow(contentViewController: hostingController)
        newWindow.title = "KeyPath Help"
        newWindow.styleMask = [.titled, .closable, .resizable, .miniaturizable]
        newWindow.setContentSize(NSSize(width: 850, height: 650))
        newWindow.delegate = self

        if keepOverlayVisible, let screen = NSScreen.main {
            // Position on left side of screen so overlay (centered-bottom) stays visible
            let screenFrame = screen.visibleFrame
            let windowSize = newWindow.frame.size
            let x = screenFrame.minX + 40
            let y = screenFrame.midY - windowSize.height / 2
            newWindow.setFrameOrigin(NSPoint(x: x, y: y))
        } else {
            newWindow.center()
        }

        newWindow.makeKeyAndOrderFront(nil)
        NSApp.activate(ignoringOtherApps: true)

        window = newWindow
    }

    /// Opens a single help topic in the browser (backwards-compatible deep link).
    func show(resource: String, title _: String) {
        let topic = HelpTopic.topic(forResource: resource)
        showBrowser(selecting: topic)
    }

    // MARK: - NSWindowDelegate

    nonisolated func windowWillClose(_: Notification) {
        MainActor.assumeIsolated {
            if !keepingOverlayVisible, overlayWasVisible {
                LiveKeyboardOverlayController.shared.isVisible = true
            }
            overlayWasVisible = false
            keepingOverlayVisible = false
        }
    }
}
