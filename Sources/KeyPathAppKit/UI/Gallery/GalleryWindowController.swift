// M1 Gallery MVP — controller for the Gallery window.
// Pattern matches InputCaptureExperimentWindowController.

import AppKit
import SwiftUI

@MainActor
final class GalleryWindowController: NSObject {
    static let shared = GalleryWindowController()

    private var window: NSWindow?
    private var willCloseObserver: NSObjectProtocol?

    /// Open (or focus if already open) the Gallery window. Hides the live
    /// keyboard overlay while the Gallery is up (same pattern Settings uses
    /// via `autoHideOnceForSettings`) and restores it on close, so the
    /// overlay doesn't hover on top of the Gallery sheet.
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

        // Hide the overlay so it doesn't float on top of the Gallery window.
        // Reuses the same API Settings uses — the controller remembers
        // pre-hide visibility and restores it when we reset the guard.
        LiveKeyboardOverlayController.shared.autoHideOnceForSettings()

        // Observe this window's willClose so we can restore the overlay
        // when the user dismisses the Gallery (either clicking the ✕ or
        // Cmd+W). Scoped to this window so we don't fire on unrelated closes.
        willCloseObserver = NotificationCenter.default.addObserver(
            forName: NSWindow.willCloseNotification,
            object: newWindow,
            queue: .main
        ) { [weak self] _ in
            Task { @MainActor in
                LiveKeyboardOverlayController.shared.resetSettingsAutoHideGuard()
                self?.willCloseObserver.map(NotificationCenter.default.removeObserver)
                self?.willCloseObserver = nil
                self?.window = nil
            }
        }

        newWindow.makeKeyAndOrderFront(nil)
        self.window = newWindow
    }

    /// Close the Gallery window if it's open. Does nothing otherwise.
    /// Overlay restoration happens via the willClose observer.
    func closeWindow() {
        window?.close()
    }
}
