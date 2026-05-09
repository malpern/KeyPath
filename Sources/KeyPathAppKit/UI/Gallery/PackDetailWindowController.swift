import AppKit
import SwiftUI

@MainActor
final class PackDetailWindowController: NSObject {
    static let shared = PackDetailWindowController()

    private var window: NSWindow?
    private var willCloseObserver: NSObjectProtocol?
    private var currentPackID: String?

    func showWindow(pack: Pack, kanataManager: KanataViewModel) {
        if let existingWindow = window, existingWindow.isVisible {
            if currentPackID == pack.id {
                existingWindow.makeKeyAndOrderFront(nil)
                return
            }
            // Different pack — replace content in the same window
            let content = PackDetailView(pack: pack)
                .environment(kanataManager)
            existingWindow.contentView = NSHostingView(rootView: content)
            existingWindow.title = pack.name
            currentPackID = pack.id
            existingWindow.makeKeyAndOrderFront(nil)
            return
        }

        let content = PackDetailView(pack: pack)
            .environment(kanataManager)

        let hosting = NSHostingView(rootView: content)

        let newWindow = NSWindow(
            contentRect: NSRect(x: 0, y: 0, width: 560, height: 640),
            styleMask: [.titled, .closable, .miniaturizable],
            backing: .buffered,
            defer: false
        )
        newWindow.title = pack.name
        newWindow.contentView = hosting
        newWindow.isReleasedWhenClosed = false
        newWindow.setFrameAutosaveName("KeyPathPackDetailWindow")
        if !newWindow.setFrameUsingName("KeyPathPackDetailWindow") {
            newWindow.center()
        }

        LiveKeyboardOverlayController.shared.autoHideOnceForSettings()

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
                self?.currentPackID = nil
            }
        }

        newWindow.makeKeyAndOrderFront(nil)
        self.window = newWindow
        self.currentPackID = pack.id
    }

    func closeWindow() {
        window?.close()
    }
}
