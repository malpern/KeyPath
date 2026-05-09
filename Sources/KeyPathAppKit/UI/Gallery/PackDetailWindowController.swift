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
        let width = Self.windowWidth(for: pack)

        let newWindow = NSWindow(
            contentRect: NSRect(x: 0, y: 0, width: width, height: 640),
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

    private static func windowWidth(for pack: Pack) -> CGFloat {
        // Wide: packs with multi-column binding tables
        let widePacks: Set<String> = [
            "com.keypath.pack.vim-navigation",
            "com.keypath.pack.window-snapping",
            "com.keypath.pack.mission-control",
            "com.keypath.pack.numpad-layer",
            "com.keypath.pack.symbol-layer",
            "com.keypath.pack.fun-layer",
        ]
        if widePacks.contains(pack.id) { return 760 }

        // Medium: packs with sliders, grids, or multi-key editors
        let mediumPacks: Set<String> = [
            "com.keypath.pack.home-row-mods",
            "com.keypath.pack.auto-shift-symbols",
            "com.keypath.pack.quick-launcher",
        ]
        if mediumPacks.contains(pack.id) { return 640 }

        // Narrow: simple pickers and toggles
        return 560
    }

    func closeWindow() {
        window?.close()
    }
}
