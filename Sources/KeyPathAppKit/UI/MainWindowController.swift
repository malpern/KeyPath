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

        // Add a native titlebar accessory for drag + instrumentation (small build stamp)
        let accessory = TitlebarHeaderAccessory()
        window.addTitlebarAccessoryViewController(accessory)

        // Configure window delegate for proper lifecycle
        window.delegate = self

        AppLogger.shared.log("🪟 [MainWindowController] Window controller initialized")

        NotificationCenter.default.addObserver(
            self,
            selector: #selector(handlePreferredHeightNotification(_:)),
            name: .mainWindowHeightChanged,
            object: nil
        )
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

    @objc private func handlePreferredHeightNotification(_ notification: Notification) {
        guard let window,
              let height = notification.userInfo?["height"] as? CGFloat
        else { return }

        let clampedHeight = max(window.minSize.height, min(height, window.maxSize.height == 0 ? height : window.maxSize.height))
        let currentHeight = window.frame.height
        guard abs(currentHeight - clampedHeight) > 4 else { return }

        let topLeft = NSPoint(x: window.frame.minX, y: window.frame.maxY)
        var newFrame = window.frame
        newFrame.size.height = clampedHeight
        newFrame.origin.y = topLeft.y - clampedHeight

        window.setFrame(newFrame, display: true, animate: true)
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
        effectView.material = .menu
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
        hosted.appearance = NSAppearance(named: .aqua)
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
