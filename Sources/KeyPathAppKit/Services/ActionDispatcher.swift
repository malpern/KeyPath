import AppKit
import Foundation
import KeyPathCore
import KeyPathDaemonLifecycle
import KeyPathPluginKit

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
/// - `keypath://window/{action}` - Window management (left, right, maximize, center, top-left, top-right, bottom-left, bottom-right, next-display, previous-display, undo)
/// - `keypath://folder/{path}` - Open a folder in Finder
/// - `keypath://script/{path}` - Execute a script (requires security approval)
@MainActor
public final class ActionDispatcher {
    private static let hostPassthruDiagnosticOutputPath = "/var/tmp/keypath-host-passthru-diagnostic.txt"
    private static let hostPassthruLiveOutputPath = "/var/tmp/keypath-host-passthru-live.txt"
    private static let hostPassthruCycleOutputPath = "/var/tmp/keypath-host-passthru-cycle.txt"
    private static let hostPassthruCompanionRestartOutputPath = "/var/tmp/keypath-host-passthru-companion-restart.txt"
    private static let hostPassthruSoakOutputPath = "/var/tmp/keypath-host-passthru-soak.txt"
    private static let hostPassthruCompanionRestartSoakOutputPath = "/var/tmp/keypath-host-passthru-companion-restart-soak.txt"
    private static let coordinatorSplitRuntimeRecoveryOutputPath = "/var/tmp/keypath-runtime-coordinator-companion-recovery.txt"
    private static let coordinatorSplitRuntimeRestartSoakOutputPath = "/var/tmp/keypath-runtime-coordinator-companion-restart-soak.txt"
    private static let helperRepairOutputPath = "/var/tmp/keypath-helper-repair.txt"

    // MARK: - Singleton

    public static let shared = ActionDispatcher()

    // MARK: - Callbacks

    /// Called when an action fails or is unknown (for UI feedback)
    public var onError: ((String) -> Void)?

    /// Called when a layer-related action is received
    public var onLayerAction: ((String) -> Void)?

    /// Called when a rule-related action is received
    public var onRuleAction: ((String, [String]) -> Void)?

    /// Called when script execution needs user confirmation
    /// Parameters: script path, confirm callback, cancel callback
    public var onScriptConfirmationNeeded: ((String, @escaping () -> Void, @escaping () -> Void) -> Void)?

    /// Called when script execution is disabled and user tries to run a script
    /// Parameter: callback to open settings
    public var onScriptExecutionDisabled: ((@escaping () -> Void) -> Void)?

    // MARK: - Initialization

    private init() {}

    // MARK: - Dispatch

    /// Dispatch a KeyPath action URI
    @discardableResult
    public func dispatch(_ uri: KeyPathActionURI) -> ActionDispatchResult {
        AppLogger.shared.log("🎬 [ActionDispatcher] Dispatching: \(uri.url.absoluteString)")

        // Forward to loaded plugins for analytics/side effects
        PluginManager.shared.broadcastActionEvent(
            action: uri.action,
            target: uri.target,
            uri: uri.url.absoluteString
        )

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
        case "window":
            return handleWindow(uri)
        case "folder":
            return handleFolder(uri)
        case "script":
            return handleScript(uri)
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
            if Foundation.FileManager().fileExists(atPath: path), !urlsToTry.contains(url) {
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
            LiveKeyboardOverlayController.shared.noteLauncherActionDispatched()
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
        if !TestEnvironment.isRunningTests {
            NSWorkspace.shared.open(url)
            LiveKeyboardOverlayController.shared.noteLauncherActionDispatched()
        }
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
    /// Actions: mission-control, spotlight, dictation, dnd, launchpad, notification-center, siri, prepare-host-passthru-bridge, run-host-passthru-diagnostic, start-host-passthru, stop-host-passthru, exercise-host-passthru-cycle, exercise-output-bridge-companion-restart, exercise-coordinator-split-runtime-recovery, exercise-coordinator-split-runtime-restart-soak, repair-helper
    private func handleSystem(_ uri: KeyPathActionURI) -> ActionDispatchResult {
        guard let action = uri.target else {
            let message = "system action requires action name: keypath://system/{action}"
            AppLogger.shared.log("⚠️ [ActionDispatcher] \(message)")
            onError?(message)
            return .missingTarget("system")
        }

        AppLogger.shared.log("⚙️ [ActionDispatcher] System action: \(action)")

        switch action.lowercased() {
        case "prepare-host-passthru-bridge", "prepare-host-bridge", "prep-host-passthru-bridge":
            Task { @MainActor in
                do {
                    let session = try await KanataOutputBridgeCompanionManager.shared
                        .prepareEnvironmentAndPersist(
                            hostPID: getpid(),
                            outputPath: KanataOutputBridgeCompanionManager.bridgeEnvironmentOutputPath
                        )
                    AppLogger.shared.info(
                        "🧪 [ActionDispatcher] Prepared host passthru bridge session=\(session.sessionID) socket=\(session.socketPath) output=\(KanataOutputBridgeCompanionManager.bridgeEnvironmentOutputPath)"
                    )
                } catch {
                    AppLogger.shared.error(
                        "❌ [ActionDispatcher] Failed to prepare host passthru bridge: \(error.localizedDescription)"
                    )
                    self.onError?("Failed to prepare host passthru bridge: \(error.localizedDescription)")
                }
            }
            return .success

        case "run-host-passthru-diagnostic", "run-host-diagnostic", "host-passthru-diagnostic":
            let captureRaw = uri.queryItems["capture"]?
                .trimmingCharacters(in: .whitespacesAndNewlines)
                .lowercased()
            let includeCapture = captureRaw == "1" || captureRaw == "true" || captureRaw == "yes"
            Task { @MainActor in
                let diagnosticsService = DiagnosticsService(
                    processLifecycleManager: ProcessLifecycleManager()
                )
                let diagnostic = await diagnosticsService.runHostPassthruDiagnostic(includeCapture: includeCapture)
                let payload = """
                title=\(diagnostic.title)
                severity=\(diagnostic.severity.rawValue)
                details=\(diagnostic.technicalDetails)
                """
                do {
                    try payload.write(
                        toFile: Self.hostPassthruDiagnosticOutputPath,
                        atomically: true,
                        encoding: .utf8
                    )
                    AppLogger.shared.info(
                        "🧪 [ActionDispatcher] Host passthru diagnostic completed capture=\(includeCapture) output=\(Self.hostPassthruDiagnosticOutputPath)"
                    )
                } catch {
                    AppLogger.shared.error(
                        "❌ [ActionDispatcher] Failed to write host passthru diagnostic output: \(error.localizedDescription)"
                    )
                    self.onError?("Failed to write host passthru diagnostic output: \(error.localizedDescription)")
                }
            }
            return .success

        case "start-host-passthru", "start-host-runtime":
            let captureRaw = uri.queryItems["capture"]?
                .trimmingCharacters(in: .whitespacesAndNewlines)
                .lowercased()
            let includeCapture = captureRaw == nil || captureRaw == "1" || captureRaw == "true" || captureRaw == "yes"
            Task { @MainActor in
                do {
                    let pid = try await KanataSplitRuntimeHostService.shared.startPersistentPassthruHost(
                        includeCapture: includeCapture
                    )
                    let payload = """
                    pid=\(pid)
                    capture=\(includeCapture)
                    """
                    try payload.write(
                        toFile: Self.hostPassthruLiveOutputPath,
                        atomically: true,
                        encoding: .utf8
                    )
                    AppLogger.shared.info(
                        "🧪 [ActionDispatcher] Started persistent host passthru pid=\(pid) capture=\(includeCapture) output=\(Self.hostPassthruLiveOutputPath)"
                    )
                } catch {
                    AppLogger.shared.error(
                        "❌ [ActionDispatcher] Failed to start persistent host passthru: \(error.localizedDescription)"
                    )
                    self.onError?("Failed to start persistent host passthru: \(error.localizedDescription)")
                }
            }
            return .success

        case "stop-host-passthru", "stop-host-runtime":
            Task { @MainActor in
                KanataSplitRuntimeHostService.shared.stopPersistentPassthruHost()
                let payload = "stopped=1\n"
                try? payload.write(
                    toFile: Self.hostPassthruLiveOutputPath,
                    atomically: true,
                    encoding: .utf8
                )
                AppLogger.shared.info("🧪 [ActionDispatcher] Stopped persistent host passthru")
            }
            return .success

        case "exercise-host-passthru-cycle", "exercise-host-runtime-cycle":
            let captureRaw = uri.queryItems["capture"]?
                .trimmingCharacters(in: .whitespacesAndNewlines)
                .lowercased()
            let includeCapture = captureRaw == nil || captureRaw == "1" || captureRaw == "true" || captureRaw == "yes"
            Task { @MainActor in
                do {
                    var lines: [String] = []
                    let firstPID = try await KanataSplitRuntimeHostService.shared.startPersistentPassthruHost(
                        includeCapture: includeCapture
                    )
                    lines.append("first_pid=\(firstPID)")
                    lines.append("capture=\(includeCapture)")
                    try await Task.sleep(for: .milliseconds(250))

                    KanataSplitRuntimeHostService.shared.stopPersistentPassthruHost()
                    lines.append("stopped_first=1")
                    try await Task.sleep(for: .milliseconds(250))

                    let secondPID = try await KanataSplitRuntimeHostService.shared.startPersistentPassthruHost(
                        includeCapture: includeCapture
                    )
                    lines.append("second_pid=\(secondPID)")
                    try await Task.sleep(for: .milliseconds(250))

                    KanataSplitRuntimeHostService.shared.stopPersistentPassthruHost()
                    lines.append("stopped_second=1")

                    let payload = lines.joined(separator: "\n") + "\n"
                    try payload.write(
                        toFile: Self.hostPassthruCycleOutputPath,
                        atomically: true,
                        encoding: .utf8
                    )
                    AppLogger.shared.info(
                        "🧪 [ActionDispatcher] Exercised persistent host passthru cycle capture=\(includeCapture) output=\(Self.hostPassthruCycleOutputPath)"
                    )
                } catch {
                    AppLogger.shared.error(
                        "❌ [ActionDispatcher] Failed to exercise persistent host passthru cycle: \(error.localizedDescription)"
                    )
                    self.onError?("Failed to exercise persistent host passthru cycle: \(error.localizedDescription)")
                }
            }
            return .success

        case "exercise-host-passthru-soak", "exercise-host-runtime-soak":
            let captureRaw = uri.queryItems["capture"]?
                .trimmingCharacters(in: .whitespacesAndNewlines)
                .lowercased()
            let includeCapture = captureRaw == nil || captureRaw == "1" || captureRaw == "true" || captureRaw == "yes"
            let durationSeconds = max(1, Int(uri.queryItems["seconds"] ?? "") ?? 30)
            Task { @MainActor in
                do {
                    var lines: [String] = []
                    let pid = try await KanataSplitRuntimeHostService.shared.startPersistentPassthruHost(
                        includeCapture: includeCapture
                    )
                    lines.append("host_pid=\(pid)")
                    lines.append("capture=\(includeCapture)")
                    lines.append("duration_seconds=\(durationSeconds)")

                    if let statusBefore = try? await KanataOutputBridgeCompanionManager.shared.outputBridgeStatus() {
                        lines.append("companion_running_before=\(statusBefore.companionRunning)")
                    } else {
                        lines.append("companion_running_before=unknown")
                    }

                    try await Task.sleep(for: .seconds(durationSeconds))

                    let hostAliveAtEnd = KanataSplitRuntimeHostService.shared.isPersistentPassthruHostRunning
                    lines.append("host_alive_at_end=\(hostAliveAtEnd)")
                    if let activePID = KanataSplitRuntimeHostService.shared.activePersistentHostPID {
                        lines.append("host_pid_at_end=\(activePID)")
                    }

                    if let statusAfter = try? await KanataOutputBridgeCompanionManager.shared.outputBridgeStatus() {
                        lines.append("companion_running_after=\(statusAfter.companionRunning)")
                    } else {
                        lines.append("companion_running_after=unknown")
                    }

                    KanataSplitRuntimeHostService.shared.stopPersistentPassthruHost()
                    lines.append("host_stopped=1")

                    let payload = lines.joined(separator: "\n") + "\n"
                    try payload.write(
                        toFile: Self.hostPassthruSoakOutputPath,
                        atomically: true,
                        encoding: .utf8
                    )
                    AppLogger.shared.info(
                        "🧪 [ActionDispatcher] Exercised persistent host passthru soak capture=\(includeCapture) seconds=\(durationSeconds) output=\(Self.hostPassthruSoakOutputPath)"
                    )
                } catch {
                    AppLogger.shared.error(
                        "❌ [ActionDispatcher] Failed to exercise persistent host passthru soak: \(error.localizedDescription)"
                    )
                    self.onError?("Failed to exercise persistent host passthru soak: \(error.localizedDescription)")
                }
            }
            return .success

        case "exercise-output-bridge-companion-restart", "exercise-host-passthru-companion-restart":
            let captureRaw = uri.queryItems["capture"]?
                .trimmingCharacters(in: .whitespacesAndNewlines)
                .lowercased()
            let includeCapture = captureRaw == nil || captureRaw == "1" || captureRaw == "true" || captureRaw == "yes"
            Task { @MainActor in
                do {
                    var lines: [String] = []
                    if let statusBefore = try? await KanataOutputBridgeCompanionManager.shared.outputBridgeStatus() {
                        lines.append("companion_running_before=\(statusBefore.companionRunning)")
                    } else {
                        lines.append("companion_running_before=unknown")
                    }
                    lines.append("capture=\(includeCapture)")

                    let pid = try await KanataSplitRuntimeHostService.shared.startPersistentPassthruHost(
                        includeCapture: includeCapture
                    )
                    lines.append("host_pid=\(pid)")
                    try await Task.sleep(for: .milliseconds(300))

                    do {
                        let recovery = try await KanataSplitRuntimeHostService.shared
                            .restartCompanionAndRecoverPersistentHost()
                        lines.append("companion_restarted=1")
                        lines.append("companion_running_after=\(recovery.companionRunningAfterRestart)")
                        if let recoveredHostPID = recovery.recoveredHostPID {
                            lines.append("host_recovered=1")
                            lines.append("host_pid_after_recovery=\(recoveredHostPID)")
                        } else {
                            lines.append("host_recovered=0")
                            lines.append("host_recovery_reason=no-active-host")
                        }
                    } catch {
                        lines.append("companion_restarted=0")
                        lines.append(
                            "companion_restart_error=\(error.localizedDescription.replacingOccurrences(of: "\n", with: " "))"
                        )
                        lines.append("host_recovered=0")
                        lines.append(
                            "host_recovery_error=\(error.localizedDescription.replacingOccurrences(of: "\n", with: " "))"
                        )
                    }
                    try await Task.sleep(for: .milliseconds(300))

                    KanataSplitRuntimeHostService.shared.stopPersistentPassthruHost()
                    lines.append("host_stopped=1")

                    let payload = lines.joined(separator: "\n") + "\n"
                    try payload.write(
                        toFile: Self.hostPassthruCompanionRestartOutputPath,
                        atomically: true,
                        encoding: .utf8
                    )
                    AppLogger.shared.info(
                        "🧪 [ActionDispatcher] Exercised output bridge companion restart capture=\(includeCapture) output=\(Self.hostPassthruCompanionRestartOutputPath)"
                    )
                } catch {
                    AppLogger.shared.error(
                        "❌ [ActionDispatcher] Failed to exercise output bridge companion restart: \(error.localizedDescription)"
                    )
                    self.onError?("Failed to exercise output bridge companion restart: \(error.localizedDescription)")
                }
            }
            return .success

        case "exercise-output-bridge-companion-restart-soak", "exercise-host-passthru-companion-restart-soak":
            let captureRaw = uri.queryItems["capture"]?
                .trimmingCharacters(in: .whitespacesAndNewlines)
                .lowercased()
            let includeCapture = captureRaw == nil || captureRaw == "1" || captureRaw == "true" || captureRaw == "yes"
            let durationSeconds = max(2, Int(uri.queryItems["seconds"] ?? "") ?? 30)
            Task { @MainActor in
                do {
                    var lines: [String] = []
                    if let statusBefore = try? await KanataOutputBridgeCompanionManager.shared.outputBridgeStatus() {
                        lines.append("companion_running_before=\(statusBefore.companionRunning)")
                    } else {
                        lines.append("companion_running_before=unknown")
                    }
                    lines.append("capture=\(includeCapture)")
                    lines.append("duration_seconds=\(durationSeconds)")

                    let pid = try await KanataSplitRuntimeHostService.shared.startPersistentPassthruHost(
                        includeCapture: includeCapture
                    )
                    lines.append("host_pid=\(pid)")

                    let preRestartDelayMilliseconds = max(250, (durationSeconds * 1000) / 2)
                    let postRestartDelayMilliseconds = max(250, durationSeconds * 1000 - preRestartDelayMilliseconds)

                    try await Task.sleep(for: .milliseconds(preRestartDelayMilliseconds))

                    do {
                        let recovery = try await KanataSplitRuntimeHostService.shared
                            .restartCompanionAndRecoverPersistentHost()
                        lines.append("companion_restarted=1")
                        lines.append("companion_running_after_restart=\(recovery.companionRunningAfterRestart)")
                        if let recoveredHostPID = recovery.recoveredHostPID {
                            lines.append("host_recovered=1")
                            lines.append("host_pid_after_recovery=\(recoveredHostPID)")
                        } else {
                            lines.append("host_recovered=0")
                            lines.append("host_recovery_reason=no-active-host")
                        }
                    } catch {
                        lines.append("companion_restarted=0")
                        lines.append(
                            "companion_restart_error=\(error.localizedDescription.replacingOccurrences(of: "\n", with: " "))"
                        )
                        lines.append("host_recovered=0")
                        lines.append(
                            "host_recovery_error=\(error.localizedDescription.replacingOccurrences(of: "\n", with: " "))"
                        )
                    }

                    try await Task.sleep(for: .milliseconds(postRestartDelayMilliseconds))

                    let hostAliveAtEnd = KanataSplitRuntimeHostService.shared.isPersistentPassthruHostRunning
                    lines.append("host_alive_at_end=\(hostAliveAtEnd)")
                    if let activePID = KanataSplitRuntimeHostService.shared.activePersistentHostPID {
                        lines.append("host_pid_at_end=\(activePID)")
                    }

                    if let statusAfter = try? await KanataOutputBridgeCompanionManager.shared.outputBridgeStatus() {
                        lines.append("companion_running_after=\(statusAfter.companionRunning)")
                    } else {
                        lines.append("companion_running_after=unknown")
                    }

                    KanataSplitRuntimeHostService.shared.stopPersistentPassthruHost()
                    lines.append("host_stopped=1")

                    let payload = lines.joined(separator: "\n") + "\n"
                    try payload.write(
                        toFile: Self.hostPassthruCompanionRestartSoakOutputPath,
                        atomically: true,
                        encoding: .utf8
                    )
                    AppLogger.shared.info(
                        "🧪 [ActionDispatcher] Exercised output bridge companion restart soak capture=\(includeCapture) seconds=\(durationSeconds) output=\(Self.hostPassthruCompanionRestartSoakOutputPath)"
                    )
                } catch {
                    AppLogger.shared.error(
                        "❌ [ActionDispatcher] Failed to exercise output bridge companion restart soak: \(error.localizedDescription)"
                    )
                    self.onError?("Failed to exercise output bridge companion restart soak: \(error.localizedDescription)")
                }
            }
            return .success

        case "exercise-coordinator-split-runtime-recovery", "exercise-runtime-coordinator-companion-recovery":
            NotificationCenter.default.post(
                name: .exerciseCoordinatorSplitRuntimeRecovery,
                object: nil,
                userInfo: ["outputPath": Self.coordinatorSplitRuntimeRecoveryOutputPath]
            )
            return .success

        case "exercise-coordinator-split-runtime-restart-soak", "exercise-runtime-coordinator-companion-restart-soak":
            let durationSeconds = max(2, Int(uri.queryItems["seconds"] ?? "") ?? 20)
            NotificationCenter.default.post(
                name: .exerciseCoordinatorSplitRuntimeRestartSoak,
                object: nil,
                userInfo: [
                    "outputPath": Self.coordinatorSplitRuntimeRestartSoakOutputPath,
                    "durationSeconds": durationSeconds
                ]
            )
            return .success

        case "repair-helper":
            if TestEnvironment.isRunningTests {
                return .success
            }

            let useAppleScriptFallbackRaw = uri.queryItems["applescript"]?
                .trimmingCharacters(in: .whitespacesAndNewlines)
                .lowercased()
            let useAppleScriptFallback = useAppleScriptFallbackRaw == nil
                || useAppleScriptFallbackRaw == "1"
                || useAppleScriptFallbackRaw == "true"
                || useAppleScriptFallbackRaw == "yes"

            Task { @MainActor in
                let repaired = await HelperMaintenance.shared.runCleanupAndRepair(
                    useAppleScriptFallback: useAppleScriptFallback
                )
                let details = HelperMaintenance.shared.logLines.joined(separator: " | ")
                let payload = """
                success=\(repaired)
                use_apple_script_fallback=\(useAppleScriptFallback)
                details=\(details)
                """
                do {
                    try payload.write(
                        toFile: Self.helperRepairOutputPath,
                        atomically: true,
                        encoding: .utf8
                    )
                    AppLogger.shared.info(
                        "🧪 [ActionDispatcher] Helper repair completed success=\(repaired) output=\(Self.helperRepairOutputPath)"
                    )
                } catch {
                    AppLogger.shared.error(
                        "❌ [ActionDispatcher] Failed to write helper repair output: \(error.localizedDescription)"
                    )
                    self.onError?("Failed to write helper repair output: \(error.localizedDescription)")
                }
            }
            return .success

        case "mission-control", "missioncontrol", "expose":
            // Mission Control - open the expose launcher app
            let workspace = NSWorkspace.shared
            if let appURL = workspace.urlForApplication(withBundleIdentifier: "com.apple.exposelauncher") {
                AppLogger.shared.log("🚀 [ActionDispatcher] Launching Mission Control via exposelauncher")
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
                if Foundation.FileManager().fileExists(atPath: path) {
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
            // Notification Center - click the date/time area in menu bar (rightmost)
            // Save mouse position, reveal menu bar if hidden, click, restore position
            if let mainScreen = NSScreen.main {
                let screenFrame = mainScreen.frame
                let clickX = screenFrame.maxX - 50 // 50px from right edge

                // Save original mouse position
                let originalPosition = NSEvent.mouseLocation
                // Convert from bottom-left origin (AppKit) to top-left origin (CGEvent)
                let originalCGPoint = CGPoint(x: originalPosition.x, y: screenFrame.height - originalPosition.y)

                // First, move mouse to top of screen to reveal hidden menu bar
                let topPoint = CGPoint(x: clickX, y: 0)
                if let moveEvent = CGEvent(mouseEventSource: nil, mouseType: .mouseMoved, mouseCursorPosition: topPoint, mouseButton: .left) {
                    moveEvent.post(tap: .cghidEventTap)
                }

                // Wait briefly for menu bar to appear, click, then restore position
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.15) {
                    let clickPoint = CGPoint(x: clickX, y: 12) // Menu bar height
                    if let mouseDown = CGEvent(mouseEventSource: nil, mouseType: .leftMouseDown, mouseCursorPosition: clickPoint, mouseButton: .left),
                       let mouseUp = CGEvent(mouseEventSource: nil, mouseType: .leftMouseUp, mouseCursorPosition: clickPoint, mouseButton: .left)
                    {
                        mouseDown.post(tap: .cghidEventTap)
                        mouseUp.post(tap: .cghidEventTap)

                        // Restore original mouse position after click registers
                        DispatchQueue.main.asyncAfter(deadline: .now() + 0.3) {
                            if let restoreEvent = CGEvent(mouseEventSource: nil, mouseType: .mouseMoved, mouseCursorPosition: originalCGPoint, mouseButton: .left) {
                                restoreEvent.post(tap: .cghidEventTap)
                            }
                        }
                        AppLogger.shared.log("🔔 [ActionDispatcher] Notification Center triggered, mouse restored")
                    }
                }
                return .success
            }
            onError?("Could not click Notification Center")
            return .failed("system", NSError(domain: "ActionDispatcher", code: 3))

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
            let message = "Unknown system action: \(action). Supported: mission-control, spotlight, dictation, dnd, launchpad, notification-center, siri, prepare-host-passthru-bridge, run-host-passthru-diagnostic, start-host-passthru, stop-host-passthru, exercise-host-passthru-cycle, exercise-output-bridge-companion-restart, exercise-coordinator-split-runtime-recovery, exercise-coordinator-split-runtime-restart-soak, repair-helper"
            AppLogger.shared.log("⚠️ [ActionDispatcher] \(message)")
            onError?(message)
            return .unknownAction(action)
        }
    }

    /// Handle window management actions
    /// Format: keypath://window/{action}
    /// Actions: left, right, maximize, center, top-left, top-right, bottom-left, bottom-right, next-display, previous-display, undo
    private func handleWindow(_ uri: KeyPathActionURI) -> ActionDispatchResult {
        guard let action = uri.target else {
            let message = "window action requires action name: keypath://window/{action}"
            AppLogger.shared.log("⚠️ [ActionDispatcher] \(message)")
            onError?(message)
            return .missingTarget("window")
        }

        AppLogger.shared.log("🪟 [ActionDispatcher] Window action: \(action)")

        guard let position = WindowPosition(rawValue: action.lowercased()) else {
            let message = "Unknown window action: \(action). Supported: \(WindowPosition.allValues)"
            AppLogger.shared.log("⚠️ [ActionDispatcher] \(message)")
            onError?(message)
            return .unknownAction(action)
        }

        // Check permission first for better error message
        guard WindowManager.shared.hasAccessibilityPermission else {
            let message = "Window Management requires Accessibility permission. Enable in System Settings > Privacy & Security > Accessibility."
            AppLogger.shared.log("⚠️ [ActionDispatcher] \(message)")
            onError?(message)
            return .failed("window", NSError(domain: "ActionDispatcher", code: 5, userInfo: [
                NSLocalizedDescriptionKey: message
            ]))
        }

        let success = WindowManager.shared.moveWindow(to: position)

        if success {
            return .success
        } else {
            let message = "Window action '\(action)' failed. The window may not support resizing or moving."
            onError?(message)
            return .failed("window", NSError(domain: "ActionDispatcher", code: 5, userInfo: [
                NSLocalizedDescriptionKey: message
            ]))
        }
    }

    /// Open a folder in Finder
    /// Format: keypath://folder/{path}
    private func handleFolder(_ uri: KeyPathActionURI) -> ActionDispatchResult {
        // Reconstruct path from path components (handles paths with slashes)
        let pathString = uri.pathComponents.joined(separator: "/")

        guard !pathString.isEmpty else {
            let message = "folder action requires path: keypath://folder/{path}"
            AppLogger.shared.log("⚠️ [ActionDispatcher] \(message)")
            onError?(message)
            return .missingTarget("folder")
        }

        // Expand tilde and decode URL encoding
        let decodedPath = pathString.removingPercentEncoding ?? pathString
        let expandedPath = (decodedPath as NSString).expandingTildeInPath

        AppLogger.shared.log("📁 [ActionDispatcher] Opening folder: \(expandedPath)")

        // Check if path exists
        var isDirectory: ObjCBool = false
        guard Foundation.FileManager().fileExists(atPath: expandedPath, isDirectory: &isDirectory) else {
            let message = "Folder not found: \(expandedPath)"
            AppLogger.shared.log("❌ [ActionDispatcher] \(message)")
            onError?(message)
            return .failed("folder", NSError(domain: "ActionDispatcher", code: 6, userInfo: [
                NSLocalizedDescriptionKey: message
            ]))
        }

        // Verify it's a directory
        guard isDirectory.boolValue else {
            let message = "Path is not a folder: \(expandedPath)"
            AppLogger.shared.log("❌ [ActionDispatcher] \(message)")
            onError?(message)
            return .failed("folder", NSError(domain: "ActionDispatcher", code: 7, userInfo: [
                NSLocalizedDescriptionKey: message
            ]))
        }

        // Open in Finder
        let url = URL(fileURLWithPath: expandedPath)
        if !TestEnvironment.isRunningTests {
            NSWorkspace.shared.selectFile(nil, inFileViewerRootedAtPath: expandedPath)
            LiveKeyboardOverlayController.shared.noteLauncherActionDispatched()
        }
        AppLogger.shared.log("✅ [ActionDispatcher] Opened folder: \(url.path)")

        return .success
    }

    /// Execute a script file
    /// Format: keypath://script/{path}
    private func handleScript(_ uri: KeyPathActionURI) -> ActionDispatchResult {
        // Reconstruct path from path components
        let pathString = uri.pathComponents.joined(separator: "/")

        guard !pathString.isEmpty else {
            let message = "script action requires path: keypath://script/{path}"
            AppLogger.shared.log("⚠️ [ActionDispatcher] \(message)")
            onError?(message)
            return .missingTarget("script")
        }

        // Expand tilde and decode URL encoding
        let decodedPath = pathString.removingPercentEncoding ?? pathString
        let expandedPath = (decodedPath as NSString).expandingTildeInPath

        AppLogger.shared.log("📜 [ActionDispatcher] Script execution requested: \(expandedPath)")

        // Check security
        let securityService = ScriptSecurityService.shared
        let checkResult = securityService.checkExecution(at: expandedPath)

        switch checkResult {
        case .disabled:
            AppLogger.shared.log("🔐 [ActionDispatcher] Script execution is disabled")
            if let handler = onScriptExecutionDisabled {
                handler {
                    // Callback to open settings - the UI will handle this
                    AppLogger.shared.log("🔐 [ActionDispatcher] User requested to open settings")
                }
            } else {
                onError?("Script execution is disabled. Enable it in Settings to run scripts.")
            }
            return .failed("script", NSError(domain: "ActionDispatcher", code: 8, userInfo: [
                NSLocalizedDescriptionKey: "Script execution is disabled"
            ]))

        case let .fileNotFound(path):
            let message = "Script not found: \(path)"
            AppLogger.shared.log("❌ [ActionDispatcher] \(message)")
            onError?(message)
            return .failed("script", NSError(domain: "ActionDispatcher", code: 9, userInfo: [
                NSLocalizedDescriptionKey: message
            ]))

        case let .notExecutable(path):
            let message = "Script is not executable: \(path)"
            AppLogger.shared.log("❌ [ActionDispatcher] \(message)")
            onError?(message)
            return .failed("script", NSError(domain: "ActionDispatcher", code: 10, userInfo: [
                NSLocalizedDescriptionKey: message
            ]))

        case let .needsConfirmation(path):
            AppLogger.shared.log("🔐 [ActionDispatcher] Script needs user confirmation")
            if let handler = onScriptConfirmationNeeded {
                handler(path, { [weak self] in
                    LiveKeyboardOverlayController.shared.noteLauncherActionDispatched()
                    // User confirmed - execute the script
                    self?.executeScript(at: path)
                }, {
                    // User cancelled
                    AppLogger.shared.log("🔐 [ActionDispatcher] User cancelled script execution")
                })
            } else {
                // No UI handler registered, cannot show dialog
                onError?("Script execution requires confirmation but no UI is available")
            }
            return .success // Return success as we're showing the dialog

        case .allowed:
            // Execute directly
            LiveKeyboardOverlayController.shared.noteLauncherActionDispatched()
            executeScript(at: expandedPath)
            return .success
        }
    }

    /// Execute a script at the given path
    private func executeScript(at path: String) {
        let securityService = ScriptSecurityService.shared
        // Check script type on main actor before entering task
        let isAppleScriptFile = securityService.isAppleScript(path)
        let isInterpretedScript = securityService.isInterpretedScript(path)

        Task { [weak self] in
            do {
                if isAppleScriptFile {
                    // Execute AppleScript
                    try await self?.executeAppleScript(at: path)
                } else if isInterpretedScript {
                    // Execute interpreted script (Python, Ruby, Perl, Lua)
                    try await self?.executeInterpretedScript(at: path)
                } else {
                    // Execute shell script or executable
                    try await self?.executeShellScript(at: path)
                }

                securityService.logExecution(path: path, success: true, error: nil)
                AppLogger.shared.log("✅ [ActionDispatcher] Script executed successfully: \(path)")
            } catch {
                securityService.logExecution(path: path, success: false, error: error.localizedDescription)
                AppLogger.shared.log("❌ [ActionDispatcher] Script failed: \(path) - \(error)")
                self?.onError?("Script execution failed: \(error.localizedDescription)")
            }
        }
    }

    /// Execute an AppleScript file
    private func executeAppleScript(at path: String) async throws {
        let url = URL(fileURLWithPath: path)

        // Try compiled script first (.scpt)
        if path.hasSuffix(".scpt") {
            var errorInfo: NSDictionary?
            if let script = NSAppleScript(contentsOf: url, error: &errorInfo) {
                var executeError: NSDictionary?
                script.executeAndReturnError(&executeError)
                if let error = executeError {
                    throw NSError(domain: "AppleScript", code: 1, userInfo: [
                        NSLocalizedDescriptionKey: error["NSAppleScriptErrorMessage"] as? String ?? "AppleScript execution failed"
                    ])
                }
                return
            }
            if let error = errorInfo {
                throw NSError(domain: "AppleScript", code: 2, userInfo: [
                    NSLocalizedDescriptionKey: error["NSAppleScriptErrorMessage"] as? String ?? "Failed to load AppleScript"
                ])
            }
        }

        // Text-based AppleScript (.applescript)
        let scriptSource = try String(contentsOfFile: path, encoding: .utf8)
        var errorInfo: NSDictionary?
        if let script = NSAppleScript(source: scriptSource) {
            script.executeAndReturnError(&errorInfo)
            if let error = errorInfo {
                throw NSError(domain: "AppleScript", code: 3, userInfo: [
                    NSLocalizedDescriptionKey: error["NSAppleScriptErrorMessage"] as? String ?? "AppleScript execution failed"
                ])
            }
        } else {
            throw NSError(domain: "AppleScript", code: 4, userInfo: [
                NSLocalizedDescriptionKey: "Failed to create AppleScript from source"
            ])
        }
    }

    /// Execute a shell script or executable
    private func executeShellScript(at path: String) async throws {
        let process = Process()

        // Determine how to run based on extension
        let ext = URL(fileURLWithPath: path).pathExtension.lowercased()

        switch ext {
        case "sh", "bash":
            process.executableURL = URL(fileURLWithPath: "/bin/bash")
            process.arguments = [path]
        case "zsh":
            process.executableURL = URL(fileURLWithPath: "/bin/zsh")
            process.arguments = [path]
        default:
            // Try to execute directly (must be executable)
            process.executableURL = URL(fileURLWithPath: path)
        }

        let outputPipe = Pipe()
        let errorPipe = Pipe()
        process.standardOutput = outputPipe
        process.standardError = errorPipe

        try process.run()
        process.waitUntilExit()

        if process.terminationStatus != 0 {
            let errorData = errorPipe.fileHandleForReading.readDataToEndOfFile()
            let errorString = String(data: errorData, encoding: .utf8) ?? "Unknown error"
            throw NSError(domain: "ShellScript", code: Int(process.terminationStatus), userInfo: [
                NSLocalizedDescriptionKey: "Script exited with code \(process.terminationStatus): \(errorString)"
            ])
        }
    }

    /// Execute an interpreted script (Python, Ruby, Perl, Lua)
    private func executeInterpretedScript(at path: String) async throws {
        let process = Process()
        let ext = URL(fileURLWithPath: path).pathExtension.lowercased()

        // Determine interpreter based on extension
        switch ext {
        case "py":
            // Try python3 first, fall back to python
            if Foundation.FileManager().fileExists(atPath: "/usr/bin/python3") {
                process.executableURL = URL(fileURLWithPath: "/usr/bin/python3")
            } else if Foundation.FileManager().fileExists(atPath: "/usr/local/bin/python3") {
                process.executableURL = URL(fileURLWithPath: "/usr/local/bin/python3")
            } else {
                process.executableURL = URL(fileURLWithPath: "/usr/bin/python")
            }
            process.arguments = [path]

        case "rb":
            process.executableURL = URL(fileURLWithPath: "/usr/bin/ruby")
            process.arguments = [path]

        case "pl":
            process.executableURL = URL(fileURLWithPath: "/usr/bin/perl")
            process.arguments = [path]

        case "lua":
            // Lua is typically installed via Homebrew
            if Foundation.FileManager().fileExists(atPath: "/usr/local/bin/lua") {
                process.executableURL = URL(fileURLWithPath: "/usr/local/bin/lua")
            } else if Foundation.FileManager().fileExists(atPath: "/opt/homebrew/bin/lua") {
                process.executableURL = URL(fileURLWithPath: "/opt/homebrew/bin/lua")
            } else {
                throw NSError(domain: "InterpretedScript", code: 1, userInfo: [
                    NSLocalizedDescriptionKey: "Lua interpreter not found"
                ])
            }
            process.arguments = [path]

        default:
            assertionFailure("executeInterpretedScript called with unexpected extension: .\(ext)")
            throw NSError(domain: "InterpretedScript", code: 2, userInfo: [
                NSLocalizedDescriptionKey: "Unknown script type: .\(ext)"
            ])
        }

        let outputPipe = Pipe()
        let errorPipe = Pipe()
        process.standardOutput = outputPipe
        process.standardError = errorPipe

        try process.run()
        process.waitUntilExit()

        if process.terminationStatus != 0 {
            let errorData = errorPipe.fileHandleForReading.readDataToEndOfFile()
            let errorString = String(data: errorData, encoding: .utf8) ?? "Unknown error"
            throw NSError(domain: "InterpretedScript", code: Int(process.terminationStatus), userInfo: [
                NSLocalizedDescriptionKey: "Script exited with code \(process.terminationStatus): \(errorString)"
            ])
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
