import AppKit
import SwiftUI

/// Manages a standalone window for displaying help documentation from the Help menu.
@MainActor
final class HelpWindowController {
    static let shared = HelpWindowController()

    private var window: NSWindow?

    private init() {}

    /// Opens the help browser with a navigable sidebar of all topics.
    func showBrowser() {
        showBrowser(selecting: nil)
    }

    /// Opens the help browser with a specific topic pre-selected.
    func showBrowser(selecting topic: HelpTopic?) {
        if let window, window.isVisible {
            window.makeKeyAndOrderFront(nil)
            NSApp.activate(ignoringOtherApps: true)
            return
        }

        let browserView = HelpBrowserView(initialTopic: topic)
        let hostingController = NSHostingController(rootView: browserView)

        let newWindow = NSWindow(contentViewController: hostingController)
        newWindow.title = "KeyPath Help"
        newWindow.styleMask = [.titled, .closable, .resizable, .miniaturizable]
        newWindow.setContentSize(NSSize(width: 850, height: 650))
        newWindow.center()
        newWindow.makeKeyAndOrderFront(nil)
        NSApp.activate(ignoringOtherApps: true)

        window = newWindow
    }

    /// Opens a single help topic in the browser (backwards-compatible deep link).
    func show(resource: String, title _: String) {
        let topic = HelpTopic.topic(forResource: resource)
        showBrowser(selecting: topic)
    }
}
