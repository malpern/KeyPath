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

}
