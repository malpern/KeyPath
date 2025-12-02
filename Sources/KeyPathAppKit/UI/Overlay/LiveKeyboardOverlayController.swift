import AppKit
import SwiftUI

/// Controls the floating live keyboard overlay window.
/// Creates an always-on-top borderless window that shows the live keyboard state.
/// Uses CGEvent tap for reliable key detection (same as "See Keymap" feature).
@MainActor
final class LiveKeyboardOverlayController: NSObject, NSWindowDelegate {
    private var window: NSWindow?
    private let viewModel = KeyboardVisualizationViewModel()
    private var hasAutoHiddenForCurrentSettingsSession = false

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

    override private init() {
        super.init()
        setupLayerChangeObserver()
    }

    // MARK: - Layer State

    /// Update the current layer name displayed on the overlay
    func updateLayerName(_ layerName: String) {
        viewModel.updateLayer(layerName)
    }

    /// Set loading state for layer mapping
    func setLoadingLayerMap(_ isLoading: Bool) {
        viewModel.isLoadingLayerMap = isLoading
    }

    private func setupLayerChangeObserver() {
        NotificationCenter.default.addObserver(
            forName: .kanataLayerChanged,
            object: nil,
            queue: .main
        ) { [weak self] notification in
            if let layerName = notification.userInfo?["layerName"] as? String {
                Task { @MainActor in
                    self?.updateLayerName(layerName)
                }
            }
        }

        // Listen for config changes to rebuild layer mapping
        NotificationCenter.default.addObserver(
            forName: .kanataConfigChanged,
            object: nil,
            queue: .main
        ) { [weak self] _ in
            Task { @MainActor in
                self?.viewModel.invalidateLayerMappings()
            }
        }
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

    /// Automatically hide the overlay once when Settings opens.
    /// If the user later shows it manually, we won't hide it again until Settings closes.
    func autoHideOnceForSettings() {
        guard !hasAutoHiddenForCurrentSettingsSession else { return }
        hasAutoHiddenForCurrentSettingsSession = true
        if isVisible {
            isVisible = false
        }
    }

    /// Reset the one-shot auto-hide guard when Settings closes.
    func resetSettingsAutoHideGuard() {
        hasAutoHiddenForCurrentSettingsSession = false
    }

    // MARK: - Window Management

    private func showWindow() {
        if window == nil {
            createWindow()
        }
        viewModel.startCapturing()
        viewModel.noteInteraction() // Reset fade state when showing
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

    nonisolated func windowDidMove(_: Notification) {
        Task { @MainActor in
            saveWindowFrame()
        }
    }

    nonisolated func windowDidResize(_: Notification) {
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
        let window = OverlayWindow(
            contentRect: NSRect(origin: .zero, size: initialSize),
            styleMask: [.borderless, .resizable],
            backing: .buffered,
            defer: false
        )

        window.contentView = hostingView
        window.isMovableByWindowBackground = false // Disabled - using custom resize/move handling
        window.backgroundColor = .clear
        window.isOpaque = false
        window.hasShadow = false
        window.delegate = self

        // Always on top but not activating
        window.level = .floating
        window.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary]
        window.isReleasedWhenClosed = false

        // Allow resize
        window.minSize = NSSize(width: 400, height: 150)
        window.maxSize = NSSize(width: 1200, height: 500)

        // Restore saved position or default to bottom-right corner
        if let savedFrame {
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

// MARK: - Overlay Window (allows partial off-screen positioning)

private final class OverlayWindow: NSWindow {
    /// Keep at least this many points visible inside the screen's visibleFrame so the window is recoverable.
    private let minVisible: CGFloat = 30

    override func constrainFrameRect(_ frameRect: NSRect, to screen: NSScreen?) -> NSRect {
        guard let screen else { return frameRect }

        let visible = screen.visibleFrame
        var rect = frameRect

        // Horizontal: ensure at least `minVisible` points remain on-screen
        if rect.maxX < visible.minX + minVisible {
            rect.origin.x = visible.minX + minVisible - rect.width
        } else if rect.minX > visible.maxX - minVisible {
            rect.origin.x = visible.maxX - minVisible
        }

        // Vertical: ensure at least `minVisible` points remain on-screen
        if rect.maxY < visible.minY + minVisible {
            rect.origin.y = visible.minY + minVisible - rect.height
        } else if rect.minY > visible.maxY - minVisible {
            rect.origin.y = visible.maxY - minVisible
        }

        return rect
    }
}

// MARK: - Notification Integration

extension Notification.Name {
    /// Posted when the live keyboard overlay should be toggled
    static let toggleLiveKeyboardOverlay = Notification.Name("KeyPath.ToggleLiveKeyboardOverlay")
    /// Posted when the Kanata layer changes (userInfo["layerName"] = String)
    static let kanataLayerChanged = Notification.Name("KeyPath.KanataLayerChanged")
    /// Posted when the Kanata config changes (rules saved, etc.)
    static let kanataConfigChanged = Notification.Name("KeyPath.KanataConfigChanged")
}
