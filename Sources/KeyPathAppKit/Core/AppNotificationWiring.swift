import AppKit
import KeyPathCore
import KeyPathDaemonLifecycle

/// Centralizes notification observer registration that previously lived in
/// `AppDelegate.applicationDidFinishLaunching`.
///
/// All observers are registered on the `AppDelegate` or use closure-based observers
/// that capture the delegate weakly to avoid retain cycles.
@MainActor
enum AppNotificationWiring {
    /// Register all notification observers. Called once during `applicationDidFinishLaunching`.
    static func registerAll(on delegate: AppDelegate) {
        registerWizardNotifications(on: delegate)
        registerValidationNotifications()
        registerFeedbackNotifications()
        registerServiceNotifications(on: delegate)
        registerActionDispatcherCallbacks()
        registerSplitRuntimeProbeNotifications(on: delegate)
    }

    // MARK: - Wizard Notifications

    private static func registerWizardNotifications(on delegate: AppDelegate) {
        // Show the installation wizard regardless of whether the main window is visible.
        NotificationCenter.default.addObserver(
            delegate,
            selector: #selector(AppDelegate.handleShowWizardNotification(_:)),
            name: .showWizard,
            object: nil
        )

        // Unified "open wizard" action used by permission notifications.
        NotificationCenter.default.addObserver(
            delegate,
            selector: #selector(AppDelegate.handleOpenInstallationWizardNotification(_:)),
            name: .openInstallationWizard,
            object: nil
        )
    }

    // MARK: - Validation Notifications

    private static func registerValidationNotifications() {
        // Startup + post-wizard validation trigger.
        NotificationCenter.default.addObserver(
            forName: .kp_startupRevalidate, object: nil, queue: NotificationObserverManager.mainOperationQueue
        ) { _ in
            Task { @MainActor in
                await MainAppStateController.shared.performInitialValidation()
            }
        }
    }

    // MARK: - Feedback Notifications

    private static func registerFeedbackNotifications() {
        // Settings/permission flows sometimes post a "toast" message; show as a user notification.
        NotificationCenter.default.addObserver(
            forName: NSNotification.Name("ShowUserFeedback"), object: nil, queue: NotificationObserverManager.mainOperationQueue
        ) { notification in
            if let message = notification.userInfo?["message"] as? String {
                Task { @MainActor in
                    UserNotificationService.shared.notifyRecoverySucceeded(message)
                }
            }
        }

        // Reset-to-safe config action (used by notification buttons).
        NotificationCenter.default.addObserver(
            forName: .resetToSafeConfig, object: nil, queue: NotificationObserverManager.mainOperationQueue
        ) { _ in
            Task { @MainActor in
                // Access viewModel through the shared app delegate
                if let delegate = NSApp.delegate as? AppDelegate {
                    _ = await delegate.viewModel?.createDefaultUserConfigIfMissing()
                }
                await MainAppStateController.shared.revalidate()
                UserNotificationService.shared.notifyRecoverySucceeded("Configuration reset to safe defaults.")
            }
        }
    }

    // MARK: - Service Notifications

    private static func registerServiceNotifications(on delegate: AppDelegate) {
        // Retry start service (from notification buttons)
        NotificationCenter.default.addObserver(
            forName: .retryStartService, object: nil, queue: NotificationObserverManager.mainOperationQueue
        ) { [weak delegate] _ in
            Task { @MainActor in
                AppLogger.shared.log("🔄 [App] Retry start requested via notification")
                guard let manager = delegate?.kanataManager else {
                    AppLogger.shared.error("❌ [App] Retry start requested but RuntimeCoordinator unavailable")
                    return
                }
                let success = await manager.startKanata(reason: "Notification retryStartService")
                if !success {
                    AppLogger.shared.error("❌ [App] Retry start failed")
                }
            }
        }

        // Open Input Monitoring settings
        NotificationCenter.default.addObserver(
            forName: .openInputMonitoringSettings, object: nil, queue: NotificationObserverManager.mainOperationQueue
        ) { [weak delegate] _ in
            Task { @MainActor in
                delegate?.kanataManager?.openInputMonitoringSettings()
            }
        }

        // Open Accessibility settings
        NotificationCenter.default.addObserver(
            forName: .openAccessibilitySettings, object: nil, queue: NotificationObserverManager.mainOperationQueue
        ) { [weak delegate] _ in
            Task { @MainActor in
                delegate?.kanataManager?.openAccessibilitySettings()
            }
        }
    }

    // MARK: - Action Dispatcher Callbacks

    private static func registerActionDispatcherCallbacks() {
        // Wire ActionDispatcher errors to user notifications (for deep link failures)
        ActionDispatcher.shared.onError = { message in
            UserNotificationService.shared.notifyActionError(message)
        }

        // Wire layer action to update the overlay and layer indicator
        ActionDispatcher.shared.onLayerAction = { layerName in
            Task { @MainActor in
                // Update the keyboard overlay
                LiveKeyboardOverlayController.shared.updateLayerName(layerName)

                // Post notification for other listeners (e.g., RuleCollectionsManager)
                NotificationCenter.default.post(
                    name: .kanataLayerChanged,
                    object: nil,
                    userInfo: ["layerName": layerName, "source": "push"]
                )

                AppLogger.shared.log("🔄 [App] Layer action dispatched: '\(layerName)'")
            }
        }
    }

    // MARK: - Split Runtime Probe Notifications

    private static func registerSplitRuntimeProbeNotifications(on delegate: AppDelegate) {
        NotificationCenter.default.addObserver(
            forName: .exerciseCoordinatorSplitRuntimeRecovery,
            object: nil,
            queue: NotificationObserverManager.mainOperationQueue
        ) { [weak delegate] note in
            let outputPath =
                note.userInfo?["outputPath"] as? String
                    ?? "/var/tmp/keypath-runtime-coordinator-companion-recovery.txt"
            Task { @MainActor in
                guard let delegate, let manager = delegate.kanataManager else { return }
                var lines: [String] = []

                lines.append("split_runtime_mode=always_on")

                do {
                    let started = await manager.startKanata(reason: "Coordinator split runtime recovery probe")
                    lines.append("coordinator_start_success=\(started)")
                    let startedState = manager.getCurrentUIState()
                    lines.append("runtime_path_after_start=\(startedState.activeRuntimePathTitle ?? "none")")
                    lines.append("runtime_detail_after_start=\(startedState.activeRuntimePathDetail ?? "none")")

                    if let companionStatusBefore = try? await KanataOutputBridgeCompanionManager.shared.outputBridgeStatus() {
                        lines.append("companion_running_before=\(companionStatusBefore.companionRunning)")
                    } else {
                        lines.append("companion_running_before=unknown")
                    }

                    try await KanataOutputBridgeCompanionManager.shared.restartCompanion()
                    lines.append("companion_restarted=1")

                    try await Task.sleep(for: .seconds(12))

                    let finalState = manager.getCurrentUIState()
                    lines.append("runtime_path_after_recovery=\(finalState.activeRuntimePathTitle ?? "none")")
                    lines.append("runtime_detail_after_recovery=\(finalState.activeRuntimePathDetail ?? "none")")
                    lines.append("last_error=\(finalState.lastError ?? "none")")
                    lines.append("last_warning=\(finalState.lastWarning ?? "none")")
                    lines.append("split_host_running_after_recovery=\(KanataSplitRuntimeHostService.shared.isPersistentPassthruHostRunning)")
                    if let activePID = KanataSplitRuntimeHostService.shared.activePersistentHostPID {
                        lines.append("split_host_pid_after_recovery=\(activePID)")
                    }
                    if let companionStatusAfter = try? await KanataOutputBridgeCompanionManager.shared.outputBridgeStatus() {
                        lines.append("companion_running_after=\(companionStatusAfter.companionRunning)")
                    } else {
                        lines.append("companion_running_after=unknown")
                    }
                } catch {
                    lines.append("probe_error=\(error.localizedDescription.replacingOccurrences(of: "\n", with: " "))")
                }

                _ = await manager.stopKanata(reason: "Coordinator split runtime recovery probe cleanup")
                lines.append("cleanup_complete=1")

                let payload = lines.joined(separator: "\n") + "\n"
                do {
                    try payload.write(toFile: outputPath, atomically: true, encoding: .utf8)
                    AppLogger.shared.info(
                        "🧪 [AppDelegate] Coordinator split-runtime recovery probe completed output=\(outputPath)"
                    )
                } catch {
                    AppLogger.shared.error(
                        "❌ [AppDelegate] Failed to write coordinator split-runtime recovery probe output: \(error.localizedDescription)"
                    )
                }
            }
        }

        NotificationCenter.default.addObserver(
            forName: .exerciseCoordinatorSplitRuntimeRestartSoak,
            object: nil,
            queue: NotificationObserverManager.mainOperationQueue
        ) { [weak delegate] note in
            let outputPath =
                note.userInfo?["outputPath"] as? String
                    ?? "/var/tmp/keypath-runtime-coordinator-companion-restart-soak.txt"
            let durationSeconds = note.userInfo?["durationSeconds"] as? Int ?? 20
            Task { @MainActor in
                guard let delegate, let manager = delegate.kanataManager else { return }
                var lines: [String] = []

                lines.append("split_runtime_mode=always_on")
                lines.append("duration_seconds=\(durationSeconds)")

                do {
                    let started = await manager.startKanata(reason: "Coordinator split runtime restart soak probe")
                    lines.append("coordinator_start_success=\(started)")
                    let startedState = manager.getCurrentUIState()
                    lines.append("runtime_path_after_start=\(startedState.activeRuntimePathTitle ?? "none")")
                    lines.append("runtime_detail_after_start=\(startedState.activeRuntimePathDetail ?? "none")")

                    if let companionStatusBefore = try? await KanataOutputBridgeCompanionManager.shared.outputBridgeStatus() {
                        lines.append("companion_running_before=\(companionStatusBefore.companionRunning)")
                    } else {
                        lines.append("companion_running_before=unknown")
                    }

                    let preRestartDelaySeconds = max(1, durationSeconds / 2)
                    let postRestartDelaySeconds = max(1, durationSeconds - preRestartDelaySeconds)
                    try await Task.sleep(for: .seconds(preRestartDelaySeconds))

                    try await KanataOutputBridgeCompanionManager.shared.restartCompanion()
                    lines.append("companion_restarted=1")

                    try await Task.sleep(for: .seconds(postRestartDelaySeconds))

                    let finalState = manager.getCurrentUIState()
                    lines.append("runtime_path_after_soak=\(finalState.activeRuntimePathTitle ?? "none")")
                    lines.append("runtime_detail_after_soak=\(finalState.activeRuntimePathDetail ?? "none")")
                    lines.append("last_error=\(finalState.lastError ?? "none")")
                    lines.append("last_warning=\(finalState.lastWarning ?? "none")")
                    lines.append("split_host_running_after_soak=\(KanataSplitRuntimeHostService.shared.isPersistentPassthruHostRunning)")
                    if let activePID = KanataSplitRuntimeHostService.shared.activePersistentHostPID {
                        lines.append("split_host_pid_after_soak=\(activePID)")
                    }
                    if let companionStatusAfter = try? await KanataOutputBridgeCompanionManager.shared.outputBridgeStatus() {
                        lines.append("companion_running_after=\(companionStatusAfter.companionRunning)")
                    } else {
                        lines.append("companion_running_after=unknown")
                    }
                } catch {
                    lines.append("probe_error=\(error.localizedDescription.replacingOccurrences(of: "\n", with: " "))")
                }

                _ = await manager.stopKanata(reason: "Coordinator split runtime restart soak probe cleanup")
                lines.append("cleanup_complete=1")

                let payload = lines.joined(separator: "\n") + "\n"
                do {
                    try payload.write(toFile: outputPath, atomically: true, encoding: .utf8)
                    AppLogger.shared.info(
                        "🧪 [AppDelegate] Coordinator split-runtime restart soak probe completed output=\(outputPath)"
                    )
                } catch {
                    AppLogger.shared.error(
                        "❌ [AppDelegate] Failed to write coordinator split-runtime restart soak probe output: \(error.localizedDescription)"
                    )
                }
            }
        }
    }
}
