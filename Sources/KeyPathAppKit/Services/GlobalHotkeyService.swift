import AppKit
import KeyPathCore

/// Manages global keyboard shortcuts for KeyPath.
/// Default: Option+Command+K shows/hides KeyPath and all its windows.
@MainActor
final class GlobalHotkeyService {
    static let shared = GlobalHotkeyService()

    // MARK: - UserDefaults Keys

    private enum DefaultsKey {
        static let globalHotkeyEnabled = "KeyPath.GlobalHotkey.Enabled"
    }

    // MARK: - State

    /// Whether the global hotkey is enabled (user preference)
    var isEnabled: Bool {
        get {
            UserDefaults.standard.object(forKey: DefaultsKey.globalHotkeyEnabled) as? Bool ?? true
        }
        set {
            UserDefaults.standard.set(newValue, forKey: DefaultsKey.globalHotkeyEnabled)
            if newValue {
                startMonitoring()
            } else {
                stopMonitoring()
            }
            AppLogger.shared.log("⌨️ [GlobalHotkey] Enabled: \(newValue)")
        }
    }

    /// Whether KeyPath windows are currently hidden by the hotkey
    private var isHiddenByHotkey = false

    /// Whether the overlay was visible before hiding (to restore on show)
    private var overlayWasVisibleBeforeHide = false

    /// Global event monitor handle
    private var globalMonitor: Any?

    /// Local event monitor handle (for when KeyPath is focused)
    private var localMonitor: Any?

    // MARK: - Initialization

    private init() {}

    // MARK: - Public Interface

    /// Start monitoring for the global hotkey. Call this at app launch.
    func startMonitoring() {
        guard isEnabled else {
            AppLogger.shared.log("⌨️ [GlobalHotkey] Not starting - disabled by user")
            return
        }

        guard globalMonitor == nil else {
            AppLogger.shared.log("⌨️ [GlobalHotkey] Already monitoring")
            return
        }

        // Global monitor for when KeyPath is not focused
        globalMonitor = NSEvent.addGlobalMonitorForEvents(matching: .keyDown) { [weak self] event in
            Task { @MainActor in
                self?.handleKeyEvent(event)
            }
        }

        // Local monitor for when KeyPath is focused
        localMonitor = NSEvent.addLocalMonitorForEvents(matching: .keyDown) { [weak self] event in
            // Check synchronously if this is our hotkey
            guard let self else { return event }

            // Check for Option+Command+K
            // keyCode 40 = 'k'
            guard event.keyCode == 40,
                  event.modifierFlags.contains(.option),
                  event.modifierFlags.contains(.command),
                  !event.modifierFlags.contains(.control),
                  !event.modifierFlags.contains(.shift)
            else {
                return event
            }

            // Trigger the toggle on main actor
            Task { @MainActor in
                self.toggleKeyPathVisibility()
            }

            // Consume the event
            return nil
        }

        AppLogger.shared.log("⌨️ [GlobalHotkey] Started monitoring (Option+Command+K)")
    }

    /// Stop monitoring for the global hotkey.
    func stopMonitoring() {
        if let monitor = globalMonitor {
            NSEvent.removeMonitor(monitor)
            globalMonitor = nil
        }
        if let monitor = localMonitor {
            NSEvent.removeMonitor(monitor)
            localMonitor = nil
        }
        AppLogger.shared.log("⌨️ [GlobalHotkey] Stopped monitoring")
    }

    // MARK: - Event Handling

    /// Handle a key event and return true if it was the global hotkey
    @discardableResult
    private func handleKeyEvent(_ event: NSEvent) -> Bool {
        // Check for Option+Command+K
        // keyCode 40 = 'k'
        guard event.keyCode == 40,
              event.modifierFlags.contains(.option),
              event.modifierFlags.contains(.command),
              !event.modifierFlags.contains(.control),
              !event.modifierFlags.contains(.shift)
        else {
            return false
        }

        AppLogger.shared.log("⌨️ [GlobalHotkey] Option+Command+K triggered")
        toggleKeyPathVisibility()
        return true
    }

    // MARK: - Visibility Toggle

    /// Toggle visibility of all KeyPath windows
    private func toggleKeyPathVisibility() {
        if isHiddenByHotkey || NSApp.isHidden {
            showKeyPath()
        } else {
            hideKeyPath()
        }
    }

    /// Hide KeyPath and all its windows
    private func hideKeyPath() {
        AppLogger.shared.log("👁️ [GlobalHotkey] Hiding KeyPath")
        isHiddenByHotkey = true

        // Remember overlay visibility BEFORE hiding
        overlayWasVisibleBeforeHide = LiveKeyboardOverlayController.shared.isVisible

        // Hide the overlay without updating its saved state
        if overlayWasVisibleBeforeHide {
            LiveKeyboardOverlayController.shared.isVisible = false
        }

        // Hide the app (this hides all windows)
        NSApp.hide(nil)

        AppLogger.shared.log("👁️ [GlobalHotkey] Hidden (overlay was: \(overlayWasVisibleBeforeHide))")
    }

    /// Show KeyPath and restore windows
    private func showKeyPath() {
        AppLogger.shared.log("👁️ [GlobalHotkey] Showing KeyPath (overlay was: \(overlayWasVisibleBeforeHide))")
        isHiddenByHotkey = false

        // Unhide the app
        NSApp.unhide(nil)
        NSApp.activate(ignoringOtherApps: true)

        // Show the main window
        if let mainWindow = NSApp.windows.first(where: { $0.title == "KeyPath" || $0.identifier?.rawValue == "main" }) {
            mainWindow.makeKeyAndOrderFront(nil)
        }

        // Restore the overlay if it was visible before we hid
        if overlayWasVisibleBeforeHide {
            LiveKeyboardOverlayController.shared.isVisible = true
            // Center the overlay in the bottom half of the screen
            centerOverlayInBottomHalf()
        }
    }

    /// Center the keyboard overlay in the bottom half of the screen
    private func centerOverlayInBottomHalf() {
        guard LiveKeyboardOverlayController.shared.isVisible else { return }

        // Access the overlay window through reflection or a method we'll add
        // For now, we'll use the public interface
        Task { @MainActor in
            // Give the window time to appear
            try? await Task.sleep(nanoseconds: 50_000_000) // 50ms

            guard let screen = NSScreen.main else { return }
            let screenFrame = screen.visibleFrame

            // Get overlay window - it's a floating window with specific title
            guard let overlayWindow = NSApp.windows.first(where: {
                $0.title == "KeyPath Keyboard Overlay" ||
                    $0.accessibilityIdentifier() == "keypath-keyboard-overlay-window"
            }) else {
                AppLogger.shared.log("⚠️ [GlobalHotkey] Could not find overlay window to center")
                return
            }

            let windowSize = overlayWindow.frame.size

            // Calculate center position for bottom half of screen
            // Bottom half: from screenFrame.minY to screenFrame.midY
            let bottomHalfHeight = screenFrame.height / 2
            let bottomHalfMidY = screenFrame.minY + (bottomHalfHeight / 2)

            // Center horizontally
            let centerX = screenFrame.midX - (windowSize.width / 2)

            // Center vertically in bottom half, but keep some padding from bottom
            let centerY = bottomHalfMidY - (windowSize.height / 2)
            let minY = screenFrame.minY + 20 // Minimum 20pt from bottom
            let finalY = max(centerY, minY)

            let newOrigin = NSPoint(x: centerX, y: finalY)
            overlayWindow.setFrameOrigin(newOrigin)

            AppLogger.shared.log("📐 [GlobalHotkey] Centered overlay at (\(Int(newOrigin.x)), \(Int(newOrigin.y)))")
        }
    }
}
