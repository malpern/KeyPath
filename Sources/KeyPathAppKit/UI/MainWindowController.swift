import AppKit
import KeyPathCore
import KeyPathDaemonLifecycle
import KeyPathPermissions
import SwiftUI

@MainActor
final class MainWindowController: NSWindowController {
    private var topLeftBeforeResize: NSPoint?

    init(viewModel: KanataViewModel) {
        // Phase 4: MVVM - Use shared ViewModel (don't create a new one!)

        // Create SwiftUI hosting controller with full environment
        let rootView = RootView()
            .environmentObject(viewModel) // Phase 4: Inject ViewModel
            .environment(\.preferencesService, PreferencesService.shared)
            .environment(\.permissionSnapshotProvider, PermissionOracle.shared)

        let hostingController = NSHostingController(rootView: rootView)

        // Create window with proper styling
        let window = NSWindow(
            contentRect: NSRect(x: 0, y: 0, width: 500, height: 400),
            styleMask: [.titled, .closable, .miniaturizable, .resizable, .fullSizeContentView],
            backing: .buffered,
            defer: false
        )

        // Configure window properties
        window.title = ""
        // Titled window with transparent titlebar & full-size content (Apple-recommended)
        window.titlebarAppearsTransparent = true
        window.titleVisibility = .hidden
        window.isOpaque = false
        window.backgroundColor = .clear
        window.isMovableByWindowBackground = true
        window.hasShadow = true

        // Transparent titlebar works without a toolbar; keep nil unless needed
        window.toolbar = nil

        // State restoration and window behavior
        window.setFrameAutosaveName("MainWindow")
        window.isRestorable = true
        window.tabbingMode = .disallowed
        window.collectionBehavior = [.moveToActiveSpace]

        // Set min/max size constraints for dynamic resizing
        window.minSize = NSSize(width: 500, height: 300)
        window.maxSize = NSSize(width: 500, height: 800)

        // Only center if no saved frame exists
        if !window.setFrameUsingName("MainWindow") {
            window.center()
        }

        super.init(window: window)

        AppLogger.shared
            .log(
                "🪟 [MainWindowController] titleVisibility=\(window.titleVisibility.rawValue) transparent=\(window.titlebarAppearsTransparent) fullSize=\(window.styleMask.contains(.fullSizeContentView)) toolbar=\(window.toolbar != nil) opaque=\(window.isOpaque) bgClear=\(window.backgroundColor == .clear)"
            )

        // Wrap hosting view in a visual effect container so the entire window is glass-backed
        let container = GlassContainerViewController(hosting: hostingController)
        contentViewController = container

        // Add titlebar accessory with KeyPath label, status, and controls
        let accessory = TitlebarHeaderAccessory(viewModel: viewModel)
        window.addTitlebarAccessoryViewController(accessory)

        // Configure window delegate for proper lifecycle
        window.delegate = self

        // Observe height changes from SwiftUI content
        NotificationCenter.default.addObserver(
            self,
            selector: #selector(handleHeightChange(_:)),
            name: .mainWindowHeightChanged,
            object: nil
        )

        AppLogger.shared.log("🪟 [MainWindowController] Window controller initialized")
    }

    deinit {
        NotificationCenter.default.removeObserver(self)
    }

    /// Handle dynamic height changes from SwiftUI content
    @objc private func handleHeightChange(_ notification: Notification) {
        guard let window,
              let height = notification.userInfo?["height"] as? CGFloat
        else { return }

        let titlebarHeight: CGFloat = 28
        let newHeight = min(height + titlebarHeight, 800) // Cap at max height

        // Skip if height hasn't meaningfully changed (avoid jitter)
        let currentHeight = window.frame.height
        guard abs(newHeight - currentHeight) > 2 else { return }

        // Anchor top-left, grow from bottom
        let currentFrame = window.frame
        let newOrigin = NSPoint(
            x: currentFrame.origin.x,
            y: currentFrame.maxY - newHeight
        )
        let newFrame = NSRect(
            origin: newOrigin,
            size: NSSize(width: currentFrame.width, height: newHeight)
        )

        // Animate the resize
        NSAnimationContext.runAnimationGroup { context in
            context.duration = 0.25
            context.timingFunction = CAMediaTimingFunction(name: .easeInEaseOut)
            window.animator().setFrame(newFrame, display: true)
        }

        AppLogger.shared.log("🪟 [MainWindowController] Dynamic height: \(currentHeight) → \(newHeight)")
    }

    @available(*, unavailable)
    required init?(coder _: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    func show(focus _: Bool = true) {
        guard let window else { return }

        // Safety: clamp window to visible screen if it's off-screen
        if NSScreen.screens.first(where: { $0.visibleFrame.intersects(window.frame) }) == nil {
            window.center()
            AppLogger.shared.log("🪟 [MainWindowController] Window was off-screen, centered")
        }

        // Handle minimized state
        if window.isMiniaturized {
            window.deminiaturize(nil)
            AppLogger.shared.log("🪟 [MainWindowController] Window deminiaturized")
        }

        // Make visible if hidden; avoid explicit app activation during early startup
        if !window.isVisible {
            window.makeKeyAndOrderFront(nil)
            AppLogger.shared.log("🪟 [MainWindowController] Window made visible")
        } else {
            window.makeKeyAndOrderFront(nil)
        }
    }

    func closeWindow() {
        window?.close()
        AppLogger.shared.log("🪟 [MainWindowController] Window closed")
    }

    /// Ensure the window is visible even if the app has not yet
    /// been made active by the system (e.g., Finder launch).
    /// This should be called once at startup; subsequent focus
    /// is handled by applicationDidBecomeActive.
    func primeForActivation() {
        guard let window else { return }
        if !window.isVisible {
            window.orderFrontRegardless()
            AppLogger.shared.log(
                "🪟 [MainWindowController] Primed window for activation (orderFrontRegardless)")
        }
    }

    var isWindowVisible: Bool {
        guard let window else { return false }
        // Stronger predicate: check if window is actually key or visible on screen
        return window.isKeyWindow || window.occlusionState.contains(.visible)
    }
}

// MARK: - Glass Container View Controller

@MainActor
final class GlassContainerViewController<Content: View>: NSViewController {
    private let hosting: NSHostingController<Content>
    private let effectView = NSVisualEffectView()

    init(hosting: NSHostingController<Content>) {
        self.hosting = hosting
        super.init(nibName: nil, bundle: nil)
    }

    @available(*, unavailable)
    required init?(coder _: NSCoder) { fatalError("init(coder:) has not been implemented") }

    override func loadView() {
        effectView.material = .hudWindow
        effectView.blendingMode = .behindWindow
        effectView.state = .active
        effectView.isEmphasized = true
        effectView.translatesAutoresizingMaskIntoConstraints = false

        // Use the effect view as our main view
        view = effectView

        // Add hosting controller's view
        addChild(hosting)
        let hosted = hosting.view
        hosted.translatesAutoresizingMaskIntoConstraints = false
        hosted.wantsLayer = true
        hosted.layer?.backgroundColor = NSColor.clear.cgColor
        hosted.layer?.isOpaque = false
        hosted.appearance = NSAppearance(named: .darkAqua)
        effectView.addSubview(hosted)

        NSLayoutConstraint.activate([
            hosted.leadingAnchor.constraint(equalTo: effectView.leadingAnchor),
            hosted.trailingAnchor.constraint(equalTo: effectView.trailingAnchor),
            hosted.topAnchor.constraint(equalTo: effectView.topAnchor),
            hosted.bottomAnchor.constraint(equalTo: effectView.bottomAnchor)
        ])
    }
}

// MARK: - NSWindowDelegate

extension MainWindowController: NSWindowDelegate {
    func windowShouldClose(_: NSWindow) -> Bool {
        AppLogger.shared.log("🪟 [MainWindowController] Window should close")
        return true
    }

    func windowDidBecomeKey(_: Notification) {
        AppLogger.shared.log("🪟 [MainWindowController] Window became key")
    }

    func windowDidResignKey(_: Notification) {
        AppLogger.shared.log("🪟 [MainWindowController] Window resigned key")
    }

    func windowWillResize(_ sender: NSWindow, to _: NSSize) -> NSSize {
        // Capture the top-left position before resize
        let frame = sender.frame
        topLeftBeforeResize = NSPoint(x: frame.minX, y: frame.maxY)
        return sender.frame.size
    }

    func windowDidResize(_ notification: Notification) {
        guard let window = notification.object as? NSWindow,
              let topLeft = topLeftBeforeResize
        else { return }

        // Restore the top-left corner position after resize
        // This makes the window shrink/grow from the bottom edge
        let newFrame = window.frame
        let newOrigin = NSPoint(
            x: topLeft.x,
            y: topLeft.y - newFrame.height
        )

        window.setFrameOrigin(newOrigin)
        topLeftBeforeResize = nil
    }
}
