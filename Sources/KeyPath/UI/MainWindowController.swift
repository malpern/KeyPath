import AppKit
import SwiftUI

@MainActor
final class MainWindowController: NSWindowController {
    
    init(kanataManager: KanataManager) {
        // Create SwiftUI hosting controller with full environment
        let rootView = RootView()
            .environmentObject(kanataManager)
            .environment(\.preferencesService, PreferencesService.shared)
            .environment(\.permissionSnapshotProvider, PermissionOracle.shared)
        
        let hostingController = NSHostingController(rootView: rootView)
        
        // Create window with proper styling
        let window = NSWindow(
            contentRect: NSRect(x: 0, y: 0, width: 500, height: 400),
            styleMask: [.titled, .closable, .miniaturizable, .resizable],
            backing: .buffered,
            defer: false
        )
        
        // Configure window properties
        window.title = ""
        window.center()
        // Enable glass-friendly window appearance
        window.titlebarAppearsTransparent = true
        window.titleVisibility = .hidden
        window.styleMask.insert(.fullSizeContentView)
        window.isOpaque = false
        window.backgroundColor = .clear
        window.isMovableByWindowBackground = true

        // Remove any default toolbar; rely on full-size content view and transparent titlebar
        window.toolbar = nil
        
        // State restoration and window behavior
        window.setFrameAutosaveName("MainWindow")
        window.isRestorable = true
        window.tabbingMode = .disallowed
        window.collectionBehavior = [.moveToActiveSpace]
        
        super.init(window: window)

        AppLogger.shared.log("🪟 [MainWindowController] titleVisibility=\(window.titleVisibility.rawValue) transparent=\(window.titlebarAppearsTransparent) fullSize=\(window.styleMask.contains(.fullSizeContentView)) toolbar=\(window.toolbar != nil) opaque=\(window.isOpaque) bgClear=\(window.backgroundColor == .clear)")

        // Wrap hosting view in a visual effect container so the entire window is glass-backed
        let container = GlassContainerViewController(hosting: hostingController)
        self.contentViewController = container
        
        // Configure window delegate for proper lifecycle
        window.delegate = self
        
        AppLogger.shared.log("🪟 [MainWindowController] Window controller initialized")
    }
    
    @available(*, unavailable)
    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }
    
    func show(focus: Bool = true) {
        guard let window = window else { return }
        
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
        guard let window = window else { return }
        if !window.isVisible {
            window.orderFrontRegardless()
            AppLogger.shared.log("🪟 [MainWindowController] Primed window for activation (orderFrontRegardless)")
        }
    }

    var isWindowVisible: Bool {
        guard let window = window else { return false }
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
    required init?(coder: NSCoder) { fatalError("init(coder:) has not been implemented") }

    override func loadView() {
        effectView.material = .menu
        effectView.blendingMode = .behindWindow
        effectView.state = .active
        effectView.isEmphasized = true
        effectView.translatesAutoresizingMaskIntoConstraints = false

        // Use the effect view as our main view
        self.view = effectView

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
    func windowShouldClose(_ sender: NSWindow) -> Bool {
        AppLogger.shared.log("🪟 [MainWindowController] Window should close")
        return true
    }
    
    func windowDidBecomeKey(_ notification: Notification) {
        AppLogger.shared.log("🪟 [MainWindowController] Window became key")
    }
    
    func windowDidResignKey(_ notification: Notification) {
        AppLogger.shared.log("🪟 [MainWindowController] Window resigned key")
    }
}
