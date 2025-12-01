import AppKit
import SwiftUI

/// Controls the floating live keyboard overlay window.
/// Creates an always-on-top borderless window that shows the live keyboard state.
/// Uses CGEvent tap for reliable key detection (same as "See Keymap" feature).
@MainActor
final class LiveKeyboardOverlayController: NSObject, NSWindowDelegate {
    private var window: NSWindow?
    private let viewModel = KeyboardVisualizationViewModel()

    // MARK: - UserDefaults Keys
    private enum DefaultsKey {
        static let isVisible = "LiveKeyboardOverlay.isVisible"
        static let windowX = "LiveKeyboardOverlay.windowX"
        static let windowY = "LiveKeyboardOverlay.windowY"
        static let windowWidth = "LiveKeyboardOverlay.windowWidth"
        static let windowHeight = "LiveKeyboardOverlay.windowHeight"
    }

    /// Shared instance for app-wide access
    static let shared = LiveKeyboardOverlayController()

    private override init() {
        super.init()
    }

    /// Restore overlay state from previous session
    func restoreState() {
        let defaults = UserDefaults.standard
        if defaults.bool(forKey: DefaultsKey.isVisible) {
            isVisible = true
        }
    }

    /// Show or hide the overlay window
    var isVisible: Bool {
        get { window?.isVisible ?? false }
        set {
            if newValue {
                showWindow()
            } else {
                hideWindow()
            }
            UserDefaults.standard.set(newValue, forKey: DefaultsKey.isVisible)
        }
    }

    /// Toggle overlay visibility
    func toggle() {
        isVisible = !isVisible
    }

    // MARK: - Window Management

    private func showWindow() {
        if window == nil {
            createWindow()
        }
        viewModel.startCapturing()
        window?.orderFront(nil)
    }

    private func hideWindow() {
        viewModel.stopCapturing()
        window?.orderOut(nil)
    }

    private func saveWindowFrame() {
        guard let frame = window?.frame else { return }
        let defaults = UserDefaults.standard
        defaults.set(frame.origin.x, forKey: DefaultsKey.windowX)
        defaults.set(frame.origin.y, forKey: DefaultsKey.windowY)
        defaults.set(frame.size.width, forKey: DefaultsKey.windowWidth)
        defaults.set(frame.size.height, forKey: DefaultsKey.windowHeight)
    }

    private func restoreWindowFrame() -> NSRect? {
        let defaults = UserDefaults.standard
        // Check if we have saved values (width > 0 means we've saved before)
        let width = defaults.double(forKey: DefaultsKey.windowWidth)
        guard width > 0 else { return nil }

        let x = defaults.double(forKey: DefaultsKey.windowX)
        let y = defaults.double(forKey: DefaultsKey.windowY)
        let height = defaults.double(forKey: DefaultsKey.windowHeight)
        return NSRect(x: x, y: y, width: width, height: height)
    }

    // MARK: - NSWindowDelegate

    nonisolated func windowDidMove(_ notification: Notification) {
        Task { @MainActor in
            saveWindowFrame()
        }
    }

    nonisolated func windowDidResize(_ notification: Notification) {
        Task { @MainActor in
            saveWindowFrame()
        }
    }

    private func createWindow() {
        // Restore saved frame or use defaults
        let savedFrame = restoreWindowFrame()
        let initialSize = savedFrame?.size ?? NSSize(width: 580, height: 220)

        let contentView = LiveKeyboardOverlayView(viewModel: viewModel)

        let hostingView = NSHostingView(rootView: contentView)
        hostingView.setFrameSize(initialSize)

        // Borderless, resizable window
        let window = NSWindow(
            contentRect: NSRect(origin: .zero, size: initialSize),
            styleMask: [.borderless, .resizable],
            backing: .buffered,
            defer: false
        )

        window.contentView = hostingView
        window.isMovableByWindowBackground = true
        window.backgroundColor = .clear
        window.isOpaque = false
        window.hasShadow = true
        window.delegate = self

        // Always on top but not activating
        window.level = .floating
        window.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary]
        window.isReleasedWhenClosed = false

        // Allow resize
        window.minSize = NSSize(width: 400, height: 150)
        window.maxSize = NSSize(width: 1200, height: 500)

        // Restore saved position or default to bottom-right corner
        if let savedFrame = savedFrame {
            window.setFrameOrigin(savedFrame.origin)
        } else if let screen = NSScreen.main {
            let screenFrame = screen.visibleFrame
            let windowFrame = window.frame
            let x = screenFrame.maxX - windowFrame.width - 20
            let y = screenFrame.minY + 20
            window.setFrameOrigin(NSPoint(x: x, y: y))
        }

        self.window = window
    }
}

// MARK: - Notification Integration

extension Notification.Name {
    /// Posted when the live keyboard overlay should be toggled
    static let toggleLiveKeyboardOverlay = Notification.Name("KeyPath.ToggleLiveKeyboardOverlay")
}
