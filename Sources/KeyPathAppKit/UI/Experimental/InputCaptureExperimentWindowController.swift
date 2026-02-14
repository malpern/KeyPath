import AppKit
import SwiftUI

// MARK: - Window Controller

@MainActor
class InputCaptureExperimentWindowController {
    private var window: NSWindow?

    static let shared = InputCaptureExperimentWindowController()

    func showWindow() {
        if let existingWindow = window, existingWindow.isVisible {
            existingWindow.makeKeyAndOrderFront(nil)
            return
        }

        let contentView = InputCaptureExperimentView()

        let window = NSWindow(
            contentRect: NSRect(x: 0, y: 0, width: 480, height: 400),
            styleMask: [.titled, .closable, .miniaturizable],
            backing: .buffered,
            defer: false
        )
        window.title = "Input Capture Experiment"
        window.contentView = NSHostingView(rootView: contentView)
        window.isReleasedWhenClosed = false

        // Persistent window position
        window.setFrameAutosaveName("InputCaptureWindow")
        if !window.setFrameUsingName("InputCaptureWindow") {
            window.center()
        }

        window.makeKeyAndOrderFront(nil)

        self.window = window
    }
}
