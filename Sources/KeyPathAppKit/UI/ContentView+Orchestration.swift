import AppKit
import KeyPathCore
import KeyPathPermissions
import KeyPathWizardCore
import SwiftUI

// MARK: - Startup, Recovery, Emergency, Service Diagnostics

extension ContentView {
    func handleKanataServiceIssueChange(_ issues: [WizardIssue]) {
        let serviceIssue = issues.first { issue in
            if case .component(.kanataService) = issue.identifier {
                return true
            }
            return false
        }
        let hasServiceIssue = serviceIssue != nil

        if !hasServiceIssue {
            if let state = stateController.validationState, state != .checking {
                hasSeenHealthyKanataService = true
            }
        }

        if hasServiceIssue, !lastKanataServiceIssuePresent, hasSeenHealthyKanataService {
            let reason = serviceIssue?.description ?? "Service stopped unexpectedly"
            logKanataServiceStopSnapshot(reason: reason)
            showingKanataServiceStoppedAlert = true
        }

        lastKanataServiceIssuePresent = hasServiceIssue
    }

    func logKanataServiceStopSnapshot(reason: String) {
        Task {
            let uiData = await fetchKanataServiceSnapshotUIData()
            let managementState = await KanataDaemonManager.shared.refreshManagementState()
            let smStatus = KanataDaemonManager.shared.getStatus()
            let serviceStatus = await InstallerEngine().getServiceStatus()
            let pids = await SubprocessRunner.shared.pgrep("kanata.*--cfg")
            let pidSummary = pids.isEmpty ? "none" : pids.map(String.init).joined(separator: ",")

            AppLogger.shared.log("📌 [ServiceStoppedSnapshot] Reason: \(reason)")
            AppLogger.shared.log("📌 [ServiceStoppedSnapshot] ServiceState: \(uiData.serviceState.description)")
            AppLogger.shared.log(
                "📌 [ServiceStoppedSnapshot] Management: \(managementState.description), SMAppService: \(smStatus)"
            )
            AppLogger.shared.log(
                "📌 [ServiceStoppedSnapshot] LaunchDaemons: loaded=\(serviceStatus.kanataServiceLoaded), healthy=\(serviceStatus.kanataServiceHealthy)"
            )
            AppLogger.shared.log("📌 [ServiceStoppedSnapshot] pgrep: \(pidSummary)")
            AppLogger.shared.log(
                "📌 [ServiceStoppedSnapshot] lastExitCode=\(uiData.exitCode) lastError=\(uiData.lastError)"
            )
            AppLogger.shared.log("📌 [ServiceStoppedSnapshot] configPath=\(uiData.configPath)")
            AppLogger.shared.log(
                "📌 [ServiceStoppedSnapshot] logs: \(NSHomeDirectory())/Library/Logs/KeyPath/keypath-debug.log | \(KeyPathConstants.Logs.kanataStderr) | \(KeyPathConstants.Logs.kanataStdout)"
            )
        }
    }

    @MainActor
    func fetchKanataServiceSnapshotUIData() async -> (
        serviceState: KanataService.ServiceState,
        exitCode: String,
        lastError: String,
        configPath: String
    ) {
        let serviceState = await kanataManager.currentServiceState()
        let exitCode = kanataManager.lastProcessExitCode.map(String.init) ?? "nil"
        let lastError = kanataManager.lastError ?? "none"
        return (
            serviceState: serviceState,
            exitCode: exitCode,
            lastError: lastError,
            configPath: kanataManager.configPath
        )
    }

    func startEmergencyMonitoringIfPossible() {
        // Phase 2: JIT permission gate for emergency monitoring (AX)
        if FeatureFlags.useJustInTimePermissionRequests {
            Task { @MainActor in
                await PermissionGate.shared.checkAndRequestPermissions(
                    for: .emergencyStop,
                    onGranted: {
                        await startEmergencyMonitoringInternal()
                    },
                    onDenied: {
                        // No-op; user can try again later
                    }
                )
            }
            return
        }
        Task { @MainActor in
            await startEmergencyMonitoringInternal()
        }
    }

    @MainActor
    func startEmergencyMonitoringInternal() async {
        if keyboardCapture == nil {
            keyboardCapture = KeyboardCapture()
            AppLogger.shared.log("🎹 [ContentView] KeyboardCapture initialized for emergency monitoring")
        }

        guard let capture = keyboardCapture else { return }

        capture.startEmergencyMonitoring { Task { @MainActor in
            let stopped = await kanataManager.stopKanata(reason: "Emergency stop hotkey")
            if stopped {
                AppLogger.shared.log("🛑 [EmergencyStop] Kanata service stopped via façade")
            } else {
                AppLogger.shared.warn("⚠️ [EmergencyStop] Failed to stop Kanata service via façade")
            }
            kanataManager.emergencyStopActivated = true
            showStatusMessage(message: "🚨 Emergency stop activated - Kanata stopped")
            UserNotificationService.shared.notifyLaunchFailure(
                .serviceFailure("Emergency stop activated")
            )
            showingEmergencyAlert = true
        } }
    }

    // MARK: - Startup Observers

    func setupStartupObservers() {
        guard !startupObserversInstalled else { return }
        startupObserversInstalled = true

        NotificationCenter.default.addObserver(forName: .kp_startupWarm, object: nil, queue: .main) {
            _ in
            AppLogger.shared.log("🚦 [Startup] Warm phase")
            // Lightweight warm-ups (noop for now)
        }

        NotificationCenter.default.addObserver(
            forName: .kp_startupAutoLaunch, object: nil, queue: .main
        ) { _ in
            AppLogger.shared.log("🚦 [Startup] AutoLaunch phase")
            Task { @MainActor in
                // Respect permission-grant return to avoid resetting wizard state
                let result = PermissionGrantCoordinator.shared.checkForPendingPermissionGrant()
                if !result.shouldRestart {
                    AppLogger.shared.log("🚀 [ContentView] Starting auto-launch sequence (coordinated)")
                    let success = await kanataManager.startKanata(reason: "Auto-launch phase")
                    if success {
                        AppLogger.shared.log("✅ [ContentView] Auto-launch sequence completed")
                    } else {
                        AppLogger.shared.error("❌ [ContentView] Auto-launch failed via KanataService")
                    }
                    await kanataManager.updateStatus()
                }
            }
        }

        NotificationCenter.default.addObserver(
            forName: .kp_startupEmergencyMonitor, object: nil, queue: .main
        ) { _ in
            AppLogger.shared.log("🚦 [Startup] Emergency monitor phase")
            // Emergency monitoring setup is now handled elsewhere
        }

        // 🎯 Phase 3: Single notification handler for validation (startup + wizard close)
        NotificationCenter.default.addObserver(
            forName: .kp_startupRevalidate, object: nil, queue: .main
        ) { [stateController] _ in
            AppLogger.shared.log("🎯 [Phase 3] Validation requested via notification")
            Task { @MainActor in
                // Use performInitialValidation - handles both first run (waits for service) and subsequent runs
                await stateController.performInitialValidation()
            }
        }

        // Revalidate when wizard closes (system state may have changed)
        NotificationCenter.default.addObserver(forName: .wizardClosed, object: nil, queue: .main) {
            [stateController] _ in
            AppLogger.shared.log("🔄 [ContentView] Wizard closed notification - triggering revalidation")
            Task { @MainActor in
                await stateController.revalidate()
            }
        }
    }

    // Status monitoring functions removed - now handled centrally by SimpleRuntimeCoordinator

    /// Check if we're returning from granting permissions using the unified coordinator
    /// Returns true if we detected a pending permission grant restart, false otherwise
    @discardableResult
    func checkForPendingPermissionGrant() -> Bool {
        let result = PermissionGrantCoordinator.shared.checkForPendingPermissionGrant()

        if result.shouldRestart, let permissionType = result.permissionType {
            AppLogger.shared.log(
                "🔧 [ContentView] Detected return from \(permissionType.displayName) permission granting"
            )

            // Perform the permission restart using the coordinator
            PermissionGrantCoordinator.shared.performPermissionRestart(
                for: permissionType,
                kanataManager: kanataManager.underlyingManager // Phase 4: Business logic needs underlying manager
            ) { _ in
                // Show wizard after service restart completes to display results
                Task { @MainActor in
                    try? await Task.sleep(for: .seconds(1))
                    // Reopen wizard to the appropriate permission page
                    PermissionGrantCoordinator.shared.reopenWizard(for: permissionType)
                }
            }

            return true // We detected and are handling the permission grant restart
        }

        return false // No pending permission grant restart
    }

    /// Set up notification handlers for recovery actions
    func setupRecoveryActionHandlers() {
        guard !recoveryHandlersInstalled else { return }
        recoveryHandlersInstalled = true

        // Handle opening installation wizard
        NotificationCenter.default.addObserver(
            forName: .openInstallationWizard, object: nil, queue: .main
        ) { _ in
            Task { @MainActor in showingInstallationWizard = true }
        }

        // Handle resetting to safe config
        NotificationCenter.default.addObserver(forName: .resetToSafeConfig, object: nil, queue: .main) {
            _ in
            Task { @MainActor in
                _ = await kanataManager.createDefaultUserConfigIfMissing()
                await stateController.revalidate()
                showStatusMessage(message: "✅ Configuration reset to safe defaults")
            }
        }

        // Handle user feedback from PermissionGrantCoordinator
        NotificationCenter.default.addObserver(
            forName: NSNotification.Name("ShowUserFeedback"), object: nil, queue: .main
        ) { notification in
            if let message = notification.userInfo?["message"] as? String {
                Task { @MainActor in showStatusMessage(message: message) }
            }
        }
    }

    /// Attempt to repair the config using AI
    func attemptAIConfigRepair() {
        isAttemptingAIRepair = true
        aiRepairError = nil
        aiRepairBackupPath = nil

        Task {
            do {
                // 1. Create backup FIRST - abort if this fails
                let backupPath = try await kanataManager.underlyingManager.configurationService.backupConfigBeforeAIRepair()
                await MainActor.run {
                    aiRepairBackupPath = backupPath
                }
                AppLogger.shared.log("✅ [ContentView] Backup created at: \(backupPath)")

                // 2. Get current broken config
                let brokenConfig = try await kanataManager.underlyingManager.configurationService.readCurrentConfig()

                // 3. Attempt AI repair
                let repairedConfig = try await kanataManager.underlyingManager.attemptAIRepair(
                    config: brokenConfig,
                    errors: validationFailureErrors
                )

                // 4. Validate the repaired config before applying
                let validation = await kanataManager.underlyingManager.configurationService.validateConfiguration(repairedConfig)

                if validation.isValid {
                    // 5. Save and reload
                    try await kanataManager.underlyingManager.configurationService.saveRepairedConfig(repairedConfig)

                    // 6. Restart service to apply
                    _ = await kanataManager.restartKanata(reason: "AI config repair")

                    // 7. Success! Close dialog and show toast
                    await MainActor.run {
                        showingValidationFailureModal = false
                        isAttemptingAIRepair = false
                        showStatusMessage(message: "✅ Config repaired! Backup: \(backupPath)")
                    }
                } else {
                    // Repair didn't fully fix it - update errors and continue
                    await MainActor.run {
                        validationFailureErrors = validation.errors
                        aiRepairError = "AI repair improved the config but \(validation.errors.count) error(s) remain"
                        isAttemptingAIRepair = false
                    }
                }
            } catch {
                await MainActor.run {
                    aiRepairError = error.localizedDescription
                    isAttemptingAIRepair = false
                }
            }
        }
    }
}
