import AppKit
import KeyPathCore
import KeyPathPermissions

/// Manages global keyboard shortcuts for KeyPath.
/// Default: Option+Command+K toggles the keyboard overlay visibility.
///          Option+Command+L shows the overlay, recenters it, and restores default size.
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
            Foundation.UserDefaults.standard.object(forKey: DefaultsKey.globalHotkeyEnabled) as? Bool ?? true
        }
        set {
            Foundation.UserDefaults.standard.set(newValue, forKey: DefaultsKey.globalHotkeyEnabled)
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
    private var activationObserver: NSObjectProtocol?

    // MARK: - Initialization

    private let notificationCenter: NotificationCenter
    private let permissionsReady: () -> Bool
    private let addGlobalMonitor: (@escaping (NSEvent) -> Void) -> Any?
    private let addLocalMonitor: (@escaping (NSEvent) -> NSEvent?) -> Any?
    private let removeMonitor: (Any) -> Void

    init(
        notificationCenter: NotificationCenter = .default,
        permissionsReady: @escaping () -> Bool = {
            let permissions = SystemStateProvider.shared.currentProcessRawPermissionCapabilities()
            return permissions.accessibility.isReady && permissions.inputMonitoring.isReady
        },
        addGlobalMonitor: @escaping (@escaping (NSEvent) -> Void) -> Any? = {
            NSEvent.addGlobalMonitorForEvents(matching: .keyDown, handler: $0)
        },
        addLocalMonitor: @escaping (@escaping (NSEvent) -> NSEvent?) -> Any? = {
            NSEvent.addLocalMonitorForEvents(matching: .keyDown, handler: $0)
        },
        removeMonitor: @escaping (Any) -> Void = { NSEvent.removeMonitor($0) }
    ) {
        self.notificationCenter = notificationCenter
        self.permissionsReady = permissionsReady
        self.addGlobalMonitor = addGlobalMonitor
        self.addLocalMonitor = addLocalMonitor
        self.removeMonitor = removeMonitor
    }

    // MARK: - Public Interface

    /// Start monitoring for the global hotkey. Call this at app launch.
    func startMonitoring() {
        guard isEnabled else {
            AppLogger.shared.log("⌨️ [GlobalHotkey] Not starting - disabled by user")
            return
        }

        // Initial setup can run before consent. Recheck after returning from Settings
        // without prompting, but only while monitoring is explicitly requested.
        if activationObserver == nil {
            activationObserver = notificationCenter.addObserver(
                forName: NSApplication.didBecomeActiveNotification,
                object: nil,
                queue: .main
            ) { [weak self] _ in
                MainActor.assumeIsolated {
                    self?.startMonitoring()
                }
            }
        }
        guard permissionsReady() else { return }

        guard globalMonitor == nil || localMonitor == nil else {
            AppLogger.shared.log("⌨️ [GlobalHotkey] Already monitoring")
            return
        }

        // Global monitor for when KeyPath is not focused
        if globalMonitor == nil {
            globalMonitor = addGlobalMonitor { [weak self] event in
                Task { @MainActor in
                    self?.handleKeyEvent(event)
                }
            }
        }

        // Local monitor for when KeyPath is focused
        if localMonitor == nil {
            localMonitor = addLocalMonitor { [weak self] event in
                // Check synchronously if this is our hotkey
                guard let self, let action = action(for: event) else { return event }

                // Trigger the action on main actor
                Task { @MainActor in
                    self.perform(action)
                }

                // Consume the event
                return nil
            }
        }

        AppLogger.shared.log("⌨️ [GlobalHotkey] Started monitoring (⌥⌘K, ⌥⌘L, ⌥⌘D)")
    }

    /// Stop monitoring for the global hotkey.
    func stopMonitoring() {
        if let activationObserver {
            notificationCenter.removeObserver(activationObserver)
            self.activationObserver = nil
        }
        if let monitor = globalMonitor {
            removeMonitor(monitor)
            globalMonitor = nil
        }
        if let monitor = localMonitor {
            removeMonitor(monitor)
            localMonitor = nil
        }
        AppLogger.shared.log("⌨️ [GlobalHotkey] Stopped monitoring")
    }

    // MARK: - Event Handling

    /// Handle a key event and return true if it was the global hotkey
    @discardableResult
    private func handleKeyEvent(_ event: NSEvent) -> Bool {
        guard let action = action(for: event) else {
            return false
        }

        perform(action)
        return true
    }

    // MARK: - Visibility Toggle

    /// Toggle visibility of the keyboard overlay
    private func toggleOverlayVisibility() {
        let overlay = LiveKeyboardOverlayController.shared
        let wasVisible = overlay.isVisible
        // Use toggle with viaKeyboardShortcut: true to track learning
        overlay.toggle(viaKeyboardShortcut: true)
        AppLogger.shared.log("👁️ [GlobalHotkey] Overlay toggled: \(wasVisible) → \(!wasVisible)")
    }

    private func restoreOverlayToDefaultCentered() {
        LiveKeyboardOverlayController.shared.showResetCentered()
        AppLogger.shared.log("👁️ [GlobalHotkey] Overlay restored to default size and centered")
    }

    /// Show overlay, bring to front, and toggle the drawer
    private func toggleDrawer() {
        let overlay = LiveKeyboardOverlayController.shared

        // Make sure overlay is visible and frontmost
        if !overlay.isVisible {
            overlay.isVisible = true
        }
        overlay.bringToFront()

        // Toggle the drawer with visual button highlight
        overlay.toggleDrawerWithHighlight()

        AppLogger.shared.log("📦 [GlobalHotkey] Drawer toggled via hotkey")
    }

    private func action(for event: NSEvent) -> GlobalHotkeyAction? {
        guard let match = GlobalHotkeyMatcher.match(
            keyCode: event.keyCode,
            modifiers: event.modifierFlags
        ) else {
            return nil
        }

        AppLogger.shared.log("⌨️ [GlobalHotkey] \(match.label) triggered")
        return match.action
    }

    private func perform(_ action: GlobalHotkeyAction) {
        switch action {
        case .toggleOverlay:
            toggleOverlayVisibility()
        case .resetOverlay:
            restoreOverlayToDefaultCentered()
        case .toggleDrawer:
            toggleDrawer()
        }
    }
}

enum GlobalHotkeyAction {
    case toggleOverlay
    case resetOverlay
    case toggleDrawer
}

struct GlobalHotkeyDefinition {
    let keyCode: UInt16
    let action: GlobalHotkeyAction
    let label: String
}

enum GlobalHotkeyMatcher {
    static let requiredModifiers: NSEvent.ModifierFlags = [.option, .command]
    static let forbiddenModifiers: NSEvent.ModifierFlags = [.control, .shift]

    static let hotkeys: [GlobalHotkeyDefinition] = [
        GlobalHotkeyDefinition(keyCode: 40, action: .toggleOverlay, label: "Option+Command+K"),
        GlobalHotkeyDefinition(keyCode: 37, action: .resetOverlay, label: "Option+Command+L"),
        GlobalHotkeyDefinition(keyCode: 2, action: .toggleDrawer, label: "Option+Command+D")
    ]

    static func match(keyCode: UInt16, modifiers: NSEvent.ModifierFlags) -> GlobalHotkeyDefinition? {
        guard modifiers.isSuperset(of: requiredModifiers),
              modifiers.intersection(forbiddenModifiers).isEmpty
        else {
            return nil
        }

        return hotkeys.first(where: { $0.keyCode == keyCode })
    }
}
