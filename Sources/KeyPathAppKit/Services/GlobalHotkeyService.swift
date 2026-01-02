import AppKit
import KeyPathCore

/// Manages global keyboard shortcuts for KeyPath.
/// Default: Option+Command+K toggles the keyboard overlay visibility.
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
                self.toggleOverlayVisibility()
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
        toggleOverlayVisibility()
        return true
    }

    // MARK: - Visibility Toggle

    /// Toggle visibility of the keyboard overlay
    private func toggleOverlayVisibility() {
        let overlay = LiveKeyboardOverlayController.shared
        let wasVisible = overlay.isVisible
        overlay.isVisible = !wasVisible
        AppLogger.shared.log("👁️ [GlobalHotkey] Overlay toggled: \(wasVisible) → \(!wasVisible)")
    }
}
