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
        let fittingSize = hosting.fittingSize
        let width = max(560, min(fittingSize.width, 900))
        let height = max(500, min(fittingSize.height, 800))

        let newWindow = NSWindow(
            contentRect: NSRect(x: 0, y: 0, width: width, height: height),
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

        // Don't manage overlay visibility — the Settings container handles that.
        // Pack Detail is opened from the Rules tab (inside Settings), so the
        // overlay is already hidden and should stay hidden until Settings closes.

        willCloseObserver = NotificationCenter.default.addObserver(
            forName: NSWindow.willCloseNotification,
            object: newWindow,
            queue: .main
        ) { [weak self] _ in
            Task { @MainActor in
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
