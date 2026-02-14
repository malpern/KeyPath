import ApplicationServices
import Foundation
import IOKit.hidsystem
import KeyPathCore
import KeyPathDaemonLifecycle
import KeyPathPermissions
import KeyPathWizardCore
import Network

// MARK: - RuntimeCoordinator Lifecycle Extension

extension RuntimeCoordinator {
    // MARK: - Process Synchronization and Initialization

    func performInitialization() async {
        // Prevent concurrent initialization
        if isInitializing {
            AppLogger.shared.warn("⚠️ [Init] Already initializing - skipping duplicate initialization")
            return
        }

        isInitializing = true
        defer { isInitializing = false }

        // Use InstallerEngine to orchestrate initialization
        let engine = InstallerEngine()

        // Create default config if missing
        let ensuredConfig = await createDefaultUserConfigIfMissing()
        if ensuredConfig {
            AppLogger.shared.log("✅ [Init] Verified user config exists at \(configPath)")
        }

        // Initial status check
        await updateStatus()

        // Start config file watching (must happen regardless of kanata state)
        await MainActor.run {
            startConfigFileWatching()
        }

        // Try to start Kanata automatically on launch if environment allows
        let context = await engine.inspectSystem()

        // Check if Kanata is already running
        if context.services.kanataRunning {
            AppLogger.shared.info("✅ [Init] Kanata is already running - skipping initialization")
            return
        }

        // In headless/production mode, we might want to auto-repair/start
        // For now, we'll just log the state and let the UI drive the installation flow
        // unless we are in a state where we *expect* it to be running.

        AppLogger.shared.log(
            "🔍 [Init] System Context: installed=\(context.components.kanataBinaryInstalled), permissions=\(context.permissions.isSystemReady)"
        )
    }

    // MARK: - Recovery Operations (delegates to RecoveryCoordinator)

    func attemptKeyboardRecovery() async {
        await recoveryCoordinator.attemptKeyboardRecovery()
    }

    func killAllKanataProcesses() async {
        let report = await installerEngine
            .runSingleAction(.terminateConflictingProcesses, using: privilegeBroker)
        if report.success {
            AppLogger.shared.log("🔧 [Recovery] Killed Kanata processes")
        } else {
            let failureReason = report.failureReason ?? "Unknown error"
            AppLogger.shared.warn("⚠️ [Recovery] Failed to kill Kanata processes: \(failureReason)")
        }
    }
}
