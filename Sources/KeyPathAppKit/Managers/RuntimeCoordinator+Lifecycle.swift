import ApplicationServices
import Foundation
import IOKit.hidsystem
import KeyPathCore
import KeyPathDaemonLifecycle
import KeyPathInstallationWizard
import KeyPathPermissions
import KeyPathWizardCore
import Network

// MARK: - RuntimeCoordinator Lifecycle Extension

extension RuntimeCoordinator {
    func performInitialization() async {
        if isInitializing {
            AppLogger.shared.warn("⚠️ [Init] Already initializing - skipping duplicate initialization")
            return
        }

        isInitializing = true
        defer { isInitializing = false }

        let engine = InstallerEngine()

        let ensuredConfig = await createDefaultUserConfigIfMissing()
        if ensuredConfig {
            AppLogger.shared.log("✅ [Init] Verified user config exists at \(configPath)")
        }

        await updateStatus()
        await saveCoordinator.ensureBackupExists()

        await MainActor.run {
            startConfigFileWatching()
        }

        let context = await engine.inspectSystem()

        if context.services.kanataRunning {
            AppLogger.shared.info("✅ [Init] Kanata is already running - skipping initialization")
            return
        }

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
