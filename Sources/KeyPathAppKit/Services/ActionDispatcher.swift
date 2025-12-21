import AppKit
import Foundation
import KeyPathCore

// MARK: - Action Dispatch Result

/// Result of dispatching a KeyPath action
public enum ActionDispatchResult: Sendable {
    case success
    case unknownAction(String)
    case missingTarget(String)
    case failed(String, Error)
}

// MARK: - ActionDispatcher

/// Dispatches `keypath://` action URIs to their handlers.
///
/// Supported actions:
/// - `keypath://launch/{app}` - Launch application by name or bundle ID
/// - `keypath://layer/{name}` - Layer change feedback (logging for now)
/// - `keypath://rule/{id}/fired` - Rule fired feedback
/// - `keypath://notify?title=X&body=Y` - Show user notification
/// - `keypath://open/{url}` - Open URL in default browser
/// - `keypath://fakekey/{name}/{action}` - Trigger Kanata virtual key (tap/press/release/toggle)
/// - `keypath://system/{action}` - Trigger macOS system actions (mission-control, spotlight, dictation, dnd, launchpad, siri)
@MainActor
public final class ActionDispatcher {
    // MARK: - Singleton

    public static let shared = ActionDispatcher()

    // MARK: - Callbacks

    /// Called when an action fails or is unknown (for UI feedback)
    public var onError: ((String) -> Void)?

    /// Called when a layer-related action is received
    public var onLayerAction: ((String) -> Void)?

    /// Called when a rule-related action is received
    public var onRuleAction: ((String, [String]) -> Void)?

    // MARK: - Initialization

    private init() {}

    // MARK: - Dispatch

    /// Dispatch a KeyPath action URI
    @discardableResult
    public func dispatch(_ uri: KeyPathActionURI) -> ActionDispatchResult {
        AppLogger.shared.log("🎬 [ActionDispatcher] Dispatching: \(uri.url.absoluteString)")

        switch uri.action {
        case "launch":
            return handleLaunch(uri)
        case "layer":
            return handleLayer(uri)
        case "rule":
            return handleRule(uri)
        case "notify":
            return handleNotify(uri)
        case "open":
            return handleOpen(uri)
        case "fakekey", "vkey":
            return handleFakeKey(uri)
        case "system":
            return handleSystem(uri)
        default:
            let message = "Unknown action type: \(uri.action)"
            AppLogger.shared.log("⚠️ [ActionDispatcher] \(message)")
            onError?(message)
            return .unknownAction(uri.action)
        }
    }

    /// Dispatch a raw message string (attempts to parse as URI first)
    @discardableResult
    public func dispatch(message: String) -> ActionDispatchResult {
        if let uri = KeyPathActionURI(string: message) {
            return dispatch(uri)
        } else {
            let errorMessage = "Invalid keypath:// URI: \(message)"
            AppLogger.shared.log("⚠️ [ActionDispatcher] \(errorMessage)")
            onError?(errorMessage)
            return .unknownAction(message)
        }
    }

    // MARK: - Action Handlers

    /// Launch an application by name or bundle ID
    /// Format: keypath://launch/{app-name-or-bundle-id}
    private func handleLaunch(_ uri: KeyPathActionURI) -> ActionDispatchResult {
        guard let appIdentifier = uri.target else {
            let message = "launch action requires app name: keypath://launch/{app}"
            AppLogger.shared.log("⚠️ [ActionDispatcher] \(message)")
            onError?(message)
            return .missingTarget("launch")
        }

        AppLogger.shared.log("🚀 [ActionDispatcher] Launching app: \(appIdentifier)")

        let workspace = NSWorkspace.shared
        let appName = appIdentifier.hasSuffix(".app") ? appIdentifier : "\(appIdentifier).app"

        // Build list of URLs to try
        var urlsToTry: [URL] = []

        // Try as bundle identifier first
        if let appURL = workspace.urlForApplication(withBundleIdentifier: appIdentifier) {
            urlsToTry.append(appURL)
        }

        // Try common paths
        let commonPaths = [
            "/Applications/\(appName)",
            "/System/Applications/\(appName)",
            "\(NSHomeDirectory())/Applications/\(appName)"
        ]

        for path in commonPaths {
            let url = URL(fileURLWithPath: path)
            if FileManager.default.fileExists(atPath: path), !urlsToTry.contains(url) {
                urlsToTry.append(url)
            }
        }

        // Try each URL (fire-and-forget since openApplication is async)
        for appURL in urlsToTry {
            let config = NSWorkspace.OpenConfiguration()
            let capturedAppIdentifier = appIdentifier
            let capturedPath = appURL.path
            workspace.openApplication(at: appURL, configuration: config) { [weak self] app, error in
                Task { @MainActor in
                    if let error {
                        AppLogger.shared.log("⚠️ [ActionDispatcher] Failed to launch from \(capturedPath): \(error)")
                        self?.onError?("Failed to launch \(capturedAppIdentifier): \(error.localizedDescription)")
                    } else if app != nil {
                        AppLogger.shared.log("✅ [ActionDispatcher] Launched \(capturedAppIdentifier) from \(capturedPath)")
                    }
                }
            }
            // Return success optimistically - the app will launch async
            // First URL in list is most likely to succeed (bundle ID match)
            return .success
        }

        let message = "Could not find application: \(appIdentifier)"
        AppLogger.shared.log("❌ [ActionDispatcher] \(message)")
        onError?(message)
        return .failed("launch", NSError(domain: "ActionDispatcher", code: 1, userInfo: [
            NSLocalizedDescriptionKey: message
        ]))
    }

    /// Handle layer-related actions
    /// Format: keypath://layer/{layer-name}[/activate|/deactivate]
    private func handleLayer(_ uri: KeyPathActionURI) -> ActionDispatchResult {
        guard let layerName = uri.target else {
            let message = "layer action requires layer name: keypath://layer/{name}"
            AppLogger.shared.log("⚠️ [ActionDispatcher] \(message)")
            onError?(message)
            return .missingTarget("layer")
        }

        let subAction = uri.pathComponents.count > 1 ? uri.pathComponents[1] : "activated"
        AppLogger.shared.log("🔄 [ActionDispatcher] Layer \(layerName) \(subAction)")

        onLayerAction?(layerName)
        return .success
    }

    /// Handle rule-related actions
    /// Format: keypath://rule/{rule-id}[/fired|/enabled|/disabled]
    private func handleRule(_ uri: KeyPathActionURI) -> ActionDispatchResult {
        guard let ruleId = uri.target else {
            let message = "rule action requires rule ID: keypath://rule/{id}"
            AppLogger.shared.log("⚠️ [ActionDispatcher] \(message)")
            onError?(message)
            return .missingTarget("rule")
        }

        let additionalPath = Array(uri.pathComponents.dropFirst())
        AppLogger.shared.log("📋 [ActionDispatcher] Rule \(ruleId) path: \(additionalPath)")

        onRuleAction?(ruleId, additionalPath)
        return .success
    }

    /// Show a notification
    /// Format: keypath://notify?title=X&body=Y&sound=Z
    private func handleNotify(_ uri: KeyPathActionURI) -> ActionDispatchResult {
        let title = uri.queryItems["title"] ?? "KeyPath"
        let body = uri.queryItems["body"] ?? ""
        let sound = uri.queryItems["sound"]

        AppLogger.shared.log("🔔 [ActionDispatcher] Notify: \(title) - \(body)")

        // Use UserNotificationService if available, otherwise just log
        Task {
            await showNotification(title: title, body: body, sound: sound)
        }

        return .success
    }

    /// Open a URL in the default browser
    /// Format: keypath://open/{encoded-url}
    private func handleOpen(_ uri: KeyPathActionURI) -> ActionDispatchResult {
        // Reconstruct URL from path components
        let urlString = uri.pathComponents.joined(separator: "/")

        guard !urlString.isEmpty else {
            let message = "open action requires URL: keypath://open/{url}"
            AppLogger.shared.log("⚠️ [ActionDispatcher] \(message)")
            onError?(message)
            return .missingTarget("open")
        }

        // Handle URL-encoded strings and add https:// if missing scheme
        var finalURLString = urlString.removingPercentEncoding ?? urlString
        if !finalURLString.contains("://") {
            finalURLString = "https://\(finalURLString)"
        }

        guard let url = URL(string: finalURLString) else {
            let message = "Invalid URL: \(finalURLString)"
            AppLogger.shared.log("⚠️ [ActionDispatcher] \(message)")
            onError?(message)
            return .failed("open", NSError(domain: "ActionDispatcher", code: 2, userInfo: [
                NSLocalizedDescriptionKey: message
            ]))
        }

        AppLogger.shared.log("🌐 [ActionDispatcher] Opening URL: \(url)")
        NSWorkspace.shared.open(url)
        return .success
    }

    /// Trigger a Kanata virtual/fake key action
    /// Format: keypath://fakekey/{key-name}[/{action}]
    /// Actions: tap (default), press, release, toggle
    private func handleFakeKey(_ uri: KeyPathActionURI) -> ActionDispatchResult {
        guard FeatureFlags.simulatorAndVirtualKeysEnabled else {
            let message = "Virtual keys are disabled by feature flag."
            AppLogger.shared.log("⚠️ [ActionDispatcher] \(message)")
            onError?(message)
            return .failed("fakekey", NSError(domain: "ActionDispatcher", code: 4, userInfo: [
                NSLocalizedDescriptionKey: message
            ]))
        }
        guard let keyName = uri.target else {
            let message = "fakekey action requires key name: keypath://fakekey/{name}[/tap|press|release|toggle]"
            AppLogger.shared.log("⚠️ [ActionDispatcher] \(message)")
            onError?(message)
            return .missingTarget("fakekey")
        }

        // Parse action from path (default to tap)
        let actionString = uri.pathComponents.count > 1 ? uri.pathComponents[1].lowercased() : "tap"
        let action: KanataTCPClient.FakeKeyAction
        switch actionString {
        case "press":
            action = .press
        case "release":
            action = .release
        case "toggle":
            action = .toggle
        case "tap":
            action = .tap
        default:
            // Invalid action, default to tap with warning
            AppLogger.shared.log("⚠️ [ActionDispatcher] Unknown fakekey action '\(actionString)', defaulting to tap")
            action = .tap
        }

        AppLogger.shared.log("🎹 [ActionDispatcher] FakeKey: \(keyName) action=\(action.rawValue)")

        // Get TCP port from preferences
        let port = PreferencesService.shared.tcpServerPort

        // Fire-and-forget the TCP command (create client on-demand like other services)
        Task {
            let client = KanataTCPClient(port: port, timeout: 3.0)

            // Quick check if server is reachable
            let serverUp = await client.checkServerStatus()
            guard serverUp else {
                await MainActor.run {
                    let message = "Cannot trigger '\(keyName)': Kanata service is not running. Start KeyPath to enable virtual keys."
                    AppLogger.shared.log("❌ [ActionDispatcher] \(message)")
                    self.onError?(message)
                }
                await client.cancelInflightAndCloseConnection()
                return
            }

            let result = await client.actOnFakeKey(name: keyName, action: action)
            await client.cancelInflightAndCloseConnection()

            await MainActor.run {
                switch result {
                case .success:
                    AppLogger.shared.log("✅ [ActionDispatcher] FakeKey \(keyName) \(action.rawValue) succeeded")
                case let .error(error):
                    // Improve error message for common cases
                    let userMessage = if error.lowercased().contains("not found") || error.lowercased().contains("unknown") {
                        "Virtual key '\(keyName)' not found in config. Check spelling or add it to defvirtualkeys."
                    } else {
                        "FakeKey '\(keyName)' failed: \(error)"
                    }
                    AppLogger.shared.log("❌ [ActionDispatcher] \(userMessage)")
                    self.onError?(userMessage)
                case let .networkError(error):
                    let userMessage = "Network error triggering '\(keyName)': \(error). Is Kanata running?"
                    AppLogger.shared.log("❌ [ActionDispatcher] \(userMessage)")
                    self.onError?(userMessage)
                }
            }
        }

        return .success
    }

    /// Trigger a macOS system action
    /// Format: keypath://system/{action}
    /// Actions: mission-control, spotlight, dictation, dnd, launchpad, notification-center, siri
    private func handleSystem(_ uri: KeyPathActionURI) -> ActionDispatchResult {
        guard let action = uri.target else {
            let message = "system action requires action name: keypath://system/{action}"
            AppLogger.shared.log("⚠️ [ActionDispatcher] \(message)")
            onError?(message)
            return .missingTarget("system")
        }

        AppLogger.shared.log("⚙️ [ActionDispatcher] System action: \(action)")

        switch action.lowercased() {
        case "mission-control", "missioncontrol", "expose":
            // Mission Control - open the app
            let workspace = NSWorkspace.shared
            if let appURL = workspace.urlForApplication(withBundleIdentifier: "com.apple.exposelauncher") {
                workspace.openApplication(at: appURL, configuration: NSWorkspace.OpenConfiguration()) { _, error in
                    if let error {
                        AppLogger.shared.log("⚠️ [ActionDispatcher] Mission Control failed: \(error)")
                    }
                }
                return .success
            }
            // Fallback: try opening Mission Control.app
            let missionControlPaths = [
                "/System/Applications/Mission Control.app",
                "/Applications/Mission Control.app"
            ]
            for path in missionControlPaths {
                if FileManager.default.fileExists(atPath: path) {
                    workspace.openApplication(at: URL(fileURLWithPath: path), configuration: NSWorkspace.OpenConfiguration()) { _, _ in }
                    return .success
                }
            }
            onError?("Could not launch Mission Control")
            return .failed("system", NSError(domain: "ActionDispatcher", code: 3))

        case "spotlight":
            // Spotlight - simulate Cmd+Space
            simulateKeyboardShortcut(keyCode: 49, modifiers: .maskCommand) // Space = 49
            return .success

        case "dictation":
            // Dictation - simulate pressing Fn key twice (or use accessibility)
            // This is tricky - dictation trigger varies by macOS settings
            // Try opening the Dictation preference pane or simulate double-Fn
            simulateKeyboardShortcut(keyCode: 63, modifiers: []) // Fn key
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.1) {
                self.simulateKeyboardShortcut(keyCode: 63, modifiers: [])
            }
            return .success

        case "dnd", "do-not-disturb", "donotdisturb", "focus":
            // Do Not Disturb / Focus - use Shortcuts or Control Center
            // On macOS 12+, can use Shortcuts app
            let script = """
            tell application "System Events"
                tell process "Control Center"
                    click menu bar item "Focus" of menu bar 1
                end tell
            end tell
            """
            runAppleScript(script)
            return .success

        case "launchpad":
            // Launchpad - open the app
            let workspace = NSWorkspace.shared
            if let appURL = workspace.urlForApplication(withBundleIdentifier: "com.apple.launchpad.launcher") {
                workspace.openApplication(at: appURL, configuration: NSWorkspace.OpenConfiguration()) { _, _ in }
                return .success
            }
            onError?("Could not launch Launchpad")
            return .failed("system", NSError(domain: "ActionDispatcher", code: 3))

        case "notification-center", "notificationcenter", "notifications":
            // Notification Center - click the clock/date in menu bar
            let script = """
            tell application "System Events"
                tell process "Control Center"
                    click menu bar item "Clock" of menu bar 1
                end tell
            end tell
            """
            runAppleScript(script)
            return .success

        case "siri":
            // Siri - use the Siri app or hold Option+Space
            let workspace = NSWorkspace.shared
            if let appURL = workspace.urlForApplication(withBundleIdentifier: "com.apple.siri.launcher") {
                workspace.openApplication(at: appURL, configuration: NSWorkspace.OpenConfiguration()) { _, _ in }
                return .success
            }
            // Fallback: simulate Hold Cmd+Space (or just launch Siri)
            simulateKeyboardShortcut(keyCode: 49, modifiers: [.maskCommand, .maskAlternate])
            return .success

        default:
            let message = "Unknown system action: \(action). Supported: mission-control, spotlight, dictation, dnd, launchpad, notification-center, siri"
            AppLogger.shared.log("⚠️ [ActionDispatcher] \(message)")
            onError?(message)
            return .unknownAction(action)
        }
    }

    /// Simulate a keyboard shortcut using CGEvent
    private func simulateKeyboardShortcut(keyCode: CGKeyCode, modifiers: CGEventFlags) {
        guard let source = CGEventSource(stateID: .hidSystemState) else { return }

        // Key down
        if let keyDown = CGEvent(keyboardEventSource: source, virtualKey: keyCode, keyDown: true) {
            keyDown.flags = modifiers
            keyDown.post(tap: .cghidEventTap)
        }

        // Key up
        if let keyUp = CGEvent(keyboardEventSource: source, virtualKey: keyCode, keyDown: false) {
            keyUp.flags = modifiers
            keyUp.post(tap: .cghidEventTap)
        }
    }

    /// Run an AppleScript
    private func runAppleScript(_ script: String) {
        Task.detached {
            var error: NSDictionary?
            if let scriptObject = NSAppleScript(source: script) {
                scriptObject.executeAndReturnError(&error)
                if let error {
                    await MainActor.run {
                        AppLogger.shared.log("⚠️ [ActionDispatcher] AppleScript error: \(error)")
                    }
                }
            }
        }
    }

    // MARK: - Notification Helper

    private func showNotification(title: String, body: String, sound: String?) async {
        // For now, just use NSUserNotificationCenter or log
        // In production, this would integrate with UserNotificationService
        AppLogger.shared.log("🔔 [ActionDispatcher] Notification: \(title) - \(body)")

        // Play sound if specified
        if let soundName = sound {
            if let nsSound = NSSound(named: NSSound.Name(soundName)) {
                nsSound.play()
            }
        }
    }
}
