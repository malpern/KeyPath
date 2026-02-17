import AppKit
import KeyPathCore
import SwiftUI

/// Window controller for the Simulator window.
@MainActor
final class SimulatorWindowController {
    static let shared = SimulatorWindowController()

    private var window: NSWindow?

    private init() {}

    func showWindow() {
        if let existingWindow = window {
            existingWindow.makeKeyAndOrderFront(nil)
            NSApp.activate(ignoringOtherApps: true)
            return
        }

        let contentView = SimulatorView()
        let hostingController = NSHostingController(rootView: contentView)

        let newWindow = NSWindow(contentViewController: hostingController)
        newWindow.title = "Simulator"
        newWindow.styleMask = [.titled, .closable, .resizable, .miniaturizable]
        newWindow.setContentSize(NSSize(width: 1000, height: 680))
        newWindow.minSize = NSSize(width: 760, height: 560)
        newWindow.center()
        newWindow.isReleasedWhenClosed = false
        newWindow.setFrameAutosaveName("SimulatorWindow")

        window = newWindow
        newWindow.makeKeyAndOrderFront(nil)
        NSApp.activate(ignoringOtherApps: true)

        AppLogger.shared.log("⌨️ [Simulator] Window opened")
    }
}
