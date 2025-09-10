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
        window.title = "KeyPath"
        window.center()
        window.isOpaque = true
        window.backgroundColor = NSColor.windowBackgroundColor
        
        // State restoration and window behavior
        window.setFrameAutosaveName("MainWindow")
        window.isRestorable = true
        window.tabbingMode = .disallowed
        window.collectionBehavior = [.moveToActiveSpace]
        
        super.init(window: window)
        
        // Set hosting controller as content view controller
        self.contentViewController = hostingController
        
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
        
        // Make visible if hidden
        if !window.isVisible {
            window.makeKeyAndOrderFront(nil)
            AppLogger.shared.log("🪟 [MainWindowController] Window made visible")
        }
        
        // Activate app if focus requested
        if focus {
            NSApp.activate(ignoringOtherApps: true)
            AppLogger.shared.log("🪟 [MainWindowController] App activated with focus")
        }
    }
    
    func closeWindow() {
        window?.close()
        AppLogger.shared.log("🪟 [MainWindowController] Window closed")
    }
    
    var isWindowVisible: Bool {
        guard let window = window else { return false }
        // Stronger predicate: check if window is actually key or visible on screen
        return window.isKeyWindow || window.occlusionState.contains(.visible)
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