// M1 Gallery MVP — controller for the Gallery window.
// Pattern matches InputCaptureExperimentWindowController.

import AppKit
import SwiftUI

@MainActor
final class GalleryWindowController {
    static let shared = GalleryWindowController()

    private var window: NSWindow?

    /// Open (or focus if already open) the Gallery window.
    /// - Parameter kanataManager: the env object the content view reads.
    func showWindow(kanataManager: KanataViewModel) {
        if let existingWindow = window, existingWindow.isVisible {
            existingWindow.makeKeyAndOrderFront(nil)
            return
        }

        let content = GalleryView()
            .environment(kanataManager)

        let hosting = NSHostingView(rootView: content)

        let newWindow = NSWindow(
            contentRect: NSRect(x: 0, y: 0, width: 780, height: 520),
            styleMask: [.titled, .closable, .miniaturizable, .resizable],
            backing: .buffered,
            defer: false
        )
        newWindow.title = "KeyPath Gallery"
        newWindow.contentView = hosting
        newWindow.isReleasedWhenClosed = false
        newWindow.setFrameAutosaveName("KeyPathGalleryWindow")
        if !newWindow.setFrameUsingName("KeyPathGalleryWindow") {
            newWindow.center()
        }
        newWindow.makeKeyAndOrderFront(nil)

        self.window = newWindow
    }

    /// Close the Gallery window if it's open. Does nothing otherwise.
    func closeWindow() {
        window?.close()
    }
}
