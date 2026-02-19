import AppKit
import SwiftUI

/// Manages a standalone window for displaying help documentation from the Help menu.
/// Uses the same MarkdownHelpSheet content but in a window rather than a sheet.
@MainActor
final class HelpWindowController {
    static let shared = HelpWindowController()

    private var window: NSWindow?

    private init() {}

    func show(resource: String, title: String) {
        // If a help window already exists, just update its content
        if let window, window.isVisible {
            window.close()
        }

        let helpView = MarkdownHelpSheet(resource: resource, title: title)
        let hostingController = NSHostingController(rootView: helpView)

        let newWindow = NSWindow(contentViewController: hostingController)
        newWindow.title = title
        newWindow.styleMask = [.titled, .closable, .resizable]
        newWindow.setContentSize(NSSize(width: 750, height: 700))
        newWindow.center()
        newWindow.makeKeyAndOrderFront(nil)
        NSApp.activate(ignoringOtherApps: true)

        window = newWindow
    }
}
