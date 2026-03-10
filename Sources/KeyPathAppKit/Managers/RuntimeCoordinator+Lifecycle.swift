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

    func startSplitRuntimeCompanionMonitor() {
        splitRuntimeCompanionMonitorTask?.cancel()
        splitRuntimeCompanionMonitorTask = Task { @MainActor [weak self] in
            guard let self else { return }
            while !Task.isCancelled {
                try? await Task.sleep(for: .seconds(5))
                guard !Task.isCancelled else { return }
                await self.checkSplitRuntimeCompanionHealth()
            }
        }
    }

    func checkSplitRuntimeCompanionHealth() async {
        guard KanataSplitRuntimeHostService.shared.isPersistentPassthruHostRunning else {
            return
        }

        guard !isRecoveringSplitRuntimeCompanion else {
            return
        }

        guard let status = try? await KanataOutputBridgeCompanionManager.shared.outputBridgeStatus() else {
            return
        }

        guard !status.companionRunning else {
            return
        }

        isRecoveringSplitRuntimeCompanion = true
        defer { isRecoveringSplitRuntimeCompanion = false }

        AppLogger.shared.warn(
            "⚠️ [SplitRuntime] Output bridge companion not running while split host is active; attempting recovery"
        )

        do {
            let recovery = try await KanataSplitRuntimeHostService.shared.restartCompanionAndRecoverPersistentHost()
            guard recovery.companionRunningAfterRestart, recovery.recoveredHostPID != nil else {
                throw NSError(
                    domain: "KeyPath.SplitRuntime",
                    code: 1,
                    userInfo: [NSLocalizedDescriptionKey: "Split runtime companion recovery did not restore a healthy host"]
                )
            }

            lastWarning = "Split runtime host recovered after output bridge companion interruption."
            lastError = nil
            notifyStateChanged()
            return
        } catch {
            AppLogger.shared.error(
                "❌ [SplitRuntime] Failed to recover split runtime host after output bridge companion interruption: \(error.localizedDescription)"
            )
            let failedPID = KanataSplitRuntimeHostService.shared.activePersistentHostPID ?? 0
            KanataSplitRuntimeHostService.shared.stopPersistentPassthruHost()
            await handleSplitRuntimeHostExit(
                pid: failedPID,
                exitCode: -1,
                terminationReason: "output-bridge-companion-unavailable",
                expected: false,
                stderrLogPath: nil
            )
        }
    }

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

        // Ensure SaveCoordinator has a backup of the current config for rollback safety
        await saveCoordinator.ensureBackupExists()

        // Start config file watching (must happen regardless of kanata state)
        await MainActor.run {
            startConfigFileWatching()
        }

        // Try to start Kanata automatically on launch if environment allows
        let context = await engine.inspectSystem()
        let splitRuntimeDecision = await currentSplitRuntimeDecision()
        let splitRuntimePreferred: Bool
        switch splitRuntimeDecision {
        case .useSplitRuntime:
            splitRuntimePreferred = true
        case .useLegacySystemBinary, .blocked:
            splitRuntimePreferred = false
        }

        // Check if Kanata is already running. If split runtime is the preferred healthy path but
        // the active runtime is still the legacy daemon, use normal startup to cut over instead
        // of treating the legacy path as "good enough".
        if context.services.kanataRunning {
            let activeRuntimeTitle = context.services.activeRuntimePathTitle?
                .trimmingCharacters(in: CharacterSet.whitespacesAndNewlines)
            if activeRuntimeTitle == SplitRuntimeIdentity.hostTitle {
                AppLogger.shared.info("✅ [Init] Split runtime host is already running - skipping initialization")
                return
            }

            if splitRuntimePreferred {
                AppLogger.shared.log(
                    "🔀 [Init] Kanata is already running via \(activeRuntimeTitle ?? "an unknown runtime path"); cutting over to split runtime host"
                )
                let started = await startKanata(reason: "Initialization split runtime cutover")
                if started {
                    AppLogger.shared.log("✅ [Init] Initialization cutover to split runtime host completed")
                    return
                }

                AppLogger.shared.warn(
                    "⚠️ [Init] Initialization cutover to split runtime host failed; leaving existing runtime in place"
                )
                return
            }

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

    func handleSplitRuntimeHostExit(
        pid: pid_t,
        exitCode: Int32,
        terminationReason: String,
        expected: Bool,
        stderrLogPath: String?
    ) async {
        guard pid > 0
        else {
            return
        }

        AppLogger.shared.log(
            "🧪 [SplitRuntime] Persistent host exited pid=\(pid) code=\(exitCode) reason=\(terminationReason) expected=\(expected)"
        )

        await AppContextService.shared.stop()

        if expected {
            notifyStateChanged()
            return
        }

        var message = "Split runtime host exited unexpectedly"
        if let stderrLogPath, !stderrLogPath.isEmpty {
            message += " (see \(stderrLogPath))"
        }
        message += ". KeyPath no longer auto-falls back to the legacy daemon. Toggle the service again to restart the split runtime host."

        lastError = message
        lastWarning = nil
        notifyStateChanged()
    }
}
