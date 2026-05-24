import AppKit
import KeyPathCore
import SwiftUI

@MainActor
final class PackDetailWindowController: NSObject {
    static let shared = PackDetailWindowController()

    private var window: NSWindow?
    private var willCloseObserver: NSObjectProtocol?
    private(set) var currentPackID: String?
    private(set) var openedFromOverlay = false

    func showWindow(pack: Pack, kanataManager: KanataViewModel, fromOverlay: Bool = false) {
        if let existingWindow = window, existingWindow.isVisible {
            if currentPackID == pack.id {
                existingWindow.makeKeyAndOrderFront(nil)
                return
            }
            // Different pack — replace content in the same window
            self.openedFromOverlay = fromOverlay
            let content = PackDetailView(pack: pack, showBackToRules: fromOverlay)
                .environment(kanataManager)
            existingWindow.contentView = NSHostingView(rootView: content)
            existingWindow.title = pack.name
            currentPackID = pack.id
            existingWindow.makeKeyAndOrderFront(nil)
            return
        }

        let content = PackDetailView(pack: pack, showBackToRules: fromOverlay)
            .environment(kanataManager)

        let hosting = NSHostingView(rootView: content)
        let width = pack.preferredDetailWidth

        let newWindow = NSWindow(
            contentRect: NSRect(x: 0, y: 0, width: width, height: 640),
            styleMask: [.titled, .closable, .miniaturizable, .fullSizeContentView],
            backing: .buffered,
            defer: false
        )
        newWindow.title = pack.name
        newWindow.titlebarAppearsTransparent = true
        newWindow.titleVisibility = .hidden
        newWindow.contentView = hosting
        newWindow.isReleasedWhenClosed = false
        newWindow.setFrameAutosaveName("KeyPathPackDetailWindow")
        if !newWindow.setFrameUsingName("KeyPathPackDetailWindow") {
            newWindow.center()
        }

        // Don't manage overlay visibility — the Settings container handles that.
        // Pack Detail is opened from the Rules tab (inside Settings), so the
        // overlay is already hidden and should stay hidden until Settings closes.

        self.openedFromOverlay = fromOverlay

        willCloseObserver = NotificationCenter.default.addObserver(
            forName: NSWindow.willCloseNotification,
            object: newWindow,
            queue: .main
        ) { [weak self] _ in
            Task { @MainActor in
                if self?.openedFromOverlay == true {
                    LiveKeyboardOverlayController.shared.resetSettingsAutoHideGuard()
                }
                self?.openedFromOverlay = false
                self?.willCloseObserver.map(NotificationCenter.default.removeObserver)
                self?.willCloseObserver = nil
                self?.window = nil
                self?.currentPackID = nil
            }
        }

        if fromOverlay {
            LiveKeyboardOverlayController.shared.autoHideOnceForSettings()
        }

        newWindow.makeKeyAndOrderFront(nil)
        self.window = newWindow
        self.currentPackID = pack.id
    }

    var hasWindow: Bool { window != nil }

    func closeWindow() {
        let wasFromOverlay = openedFromOverlay
        window?.close()
        if wasFromOverlay {
            NSApp.sendAction(Selector(("showSettingsWindow:")), to: nil, from: nil)
        }
    }
}
