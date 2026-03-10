import Foundation
import KeyPathCore
import KeyPathPermissions

extension RuntimeCoordinator {
    enum RuntimeStatus: Equatable, Sendable {
        case running(pid: Int)
        case stopped
        case failed(reason: String)
        case starting
        case unknown

        var isRunning: Bool {
            if case .running = self { return true }
            return false
        }
    }

    func currentSplitRuntimeDecision() async -> KanataRuntimePathDecision {
        return await KanataRuntimePathCoordinator.evaluateCurrentPath()
    }

    func shouldUseSplitRuntimeHost() async -> Bool {
        let decision = await currentSplitRuntimeDecision()
        switch decision {
        case let .useSplitRuntime(reason):
            AppLogger.shared.info("🧪 [Service] Split runtime host selected: \(reason)")
            return true
        case let .useLegacySystemBinary(reason):
            AppLogger.shared.info("🧪 [Service] Split runtime host disabled by evaluator, using legacy path: \(reason)")
            return false
        case let .blocked(reason):
            AppLogger.shared.warn("⚠️ [Service] Split runtime host blocked, using legacy path: \(reason)")
            return false
        }
    }

    /// Starts Kanata with VirtualHID connection validation
    func startKanataWithValidation() async {
        await recoveryCoordinator.startKanataWithValidation(
            isKarabinerDaemonRunning: { await isKarabinerDaemonRunning() },
            startKanata: { await startKanata(reason: "VirtualHID validation start") },
            onError: { [weak self] error in
                self?.lastError = error
                self?.notifyStateChanged()
            }
        )
    }

    // MARK: - Service Management Helpers

    @discardableResult
    func startKanata(reason: String = "Manual start", precomputedDecision: KanataRuntimePathDecision? = nil) async -> Bool {
        AppLogger.shared.log("🚀 [Service] Starting Kanata (\(reason))")
        lastWarning = nil

        // CRITICAL: Check VHID daemon health before starting Kanata
        // If Kanata starts without a healthy VHID daemon, it will grab keyboard input
        // but have nowhere to output keystrokes, freezing the keyboard
        if await !isKarabinerDaemonRunning() {
            AppLogger.shared.error("❌ [Service] Cannot start Kanata - VirtualHID daemon is not running")
            lastError = "Cannot start: Karabiner VirtualHID daemon is not running. Please complete the setup wizard."
            notifyStateChanged()
            return false
        }

        let decision: KanataRuntimePathDecision
        if let precomputedDecision {
            decision = precomputedDecision
        } else {
            decision = await currentSplitRuntimeDecision()
        }
        switch decision {
        case .useSplitRuntime:
            break
        case let .useLegacySystemBinary(evalReason), let .blocked(evalReason):
            let message =
                "Split runtime host is enabled, but KeyPath could not start it: \(evalReason). " +
                "The legacy recovery daemon is no longer used for ordinary startup."
            AppLogger.shared.error("❌ [Service] \(message)")
            lastError = message
            notifyStateChanged()
            return false
        }

        let legacyWasRunning = await recoveryDaemonService.isRecoveryDaemonRunning()
        if legacyWasRunning {
            AppLogger.shared.log(
                "🔀 [Service] Split runtime selected while legacy recovery daemon is active - stopping legacy recovery daemon before cutover"
            )
            do {
                _ = try await recoveryDaemonService.stopIfRunning()
                await AppContextService.shared.stop()
                AppLogger.shared.log("✅ [Service] Legacy recovery daemon stopped for split-runtime cutover")
            } catch {
                let message = (error as? LocalizedError)?.errorDescription ?? error.localizedDescription
                AppLogger.shared.error(
                    "❌ [Service] Could not stop legacy recovery daemon for split-runtime cutover: \(message)"
                )
                lastError =
                    "Split runtime host is ready, but KeyPath could not stop the legacy recovery daemon for cutover: \(message)"
                notifyStateChanged()
                return false
            }
        }

        do {
            let pid = try await KanataSplitRuntimeHostService.shared.startPersistentPassthruHost(includeCapture: true)
            AppLogger.shared.log("✅ [Service] Started split-runtime host (PID \(pid))")
            await AppContextService.shared.start()
            lastError = nil
            lastWarning = nil
            notifyStateChanged()
            return true
        } catch {
            let message = (error as? LocalizedError)?.errorDescription ?? error.localizedDescription
            AppLogger.shared.error(
                "❌ [Service] Split-runtime host start failed during normal startup: \(message)"
            )
            lastError =
                "Split runtime host failed to start: \(message). Legacy fallback is reserved for recovery paths."
            notifyStateChanged()
            return false
        }
    }

    @discardableResult
    func stopKanata(reason: String = "Manual stop") async -> Bool {
        AppLogger.shared.log("🛑 [Service] Stopping Kanata (\(reason))")

        // Stop the app context service first
        await AppContextService.shared.stop()

        if KanataSplitRuntimeHostService.shared.isPersistentPassthruHostRunning {
            let pid = KanataSplitRuntimeHostService.shared.activePersistentHostPID ?? 0
            AppLogger.shared.log("🛑 [Service] Stopping split-runtime host (PID \(pid))")
            KanataSplitRuntimeHostService.shared.stopPersistentPassthruHost()
            lastError = nil
            lastWarning = nil
            notifyStateChanged()
            return true
        }

        do {
            _ = try await recoveryDaemonService.stopIfRunning()
            lastWarning = nil
            notifyStateChanged()
            return true
        } catch {
            let message = (error as? LocalizedError)?.errorDescription ?? error.localizedDescription
            AppLogger.shared.error("❌ [Service] Stop failed: \(message)")
            lastError = "Stop failed: \(message)"
            notifyStateChanged()
            return false
        }
    }

    @discardableResult
    func restartKanata(reason: String = "Manual restart") async -> Bool {
        let splitDecision = await currentSplitRuntimeDecision()
        if KanataSplitRuntimeHostService.shared.isPersistentPassthruHostRunning {
            let stopped = await stopKanata(reason: "\(reason) (stop split runtime)")
            guard stopped else { return false }
            return await startKanata(reason: "\(reason) (start split runtime)", precomputedDecision: splitDecision)
        }

        switch splitDecision {
        case .useSplitRuntime:
            if await recoveryDaemonService.isRecoveryDaemonRunning() {
                let stopped = await stopKanata(reason: "\(reason) (stop legacy recovery daemon)")
                guard stopped else { return false }
            }
            return await startKanata(reason: "\(reason) (start split runtime)", precomputedDecision: splitDecision)
        case let .useLegacySystemBinary(evalReason), let .blocked(evalReason):
            let message =
                "Split runtime host is enabled, but KeyPath could not restart it: \(evalReason). " +
                "The legacy recovery daemon is no longer used for ordinary restart."
            AppLogger.shared.error("❌ [Service] \(message)")
            lastError = message
            notifyStateChanged()
            return false
        }
    }

    func currentRuntimeStatus() async -> RuntimeStatus {
        if isStartingKanata {
            return .starting
        }

        if KanataSplitRuntimeHostService.shared.isPersistentPassthruHostRunning {
            return .running(pid: Int(KanataSplitRuntimeHostService.shared.activePersistentHostPID ?? 0))
        }

        // Secondary check: the legacy recovery daemon may still be active during
        // migration. Report it as running so callers (e.g. resetToDefaultConfig)
        // don't skip TCP reload.
        if await recoveryDaemonService.isRecoveryDaemonRunning() {
            AppLogger.shared.warn(
                "⚠️ [Service] Split runtime host is not running but legacy recovery daemon is active — half-migrated state"
            )
            return .running(pid: 0)
        }

        return .stopped
    }
    /// Check if permission issues should trigger the wizard
    func shouldShowWizardForPermissions() async -> Bool {
        let snapshot = await PermissionOracle.shared.forceRefresh()
        return snapshot.blockingIssue != nil
    }

    // MARK: - UI-Focused Lifecycle Methods (from SimpleRuntimeCoordinator)

    /// Check if this is a fresh install (no Kanata binary or config)
    func isFirstTimeInstall() -> Bool {
        installationCoordinator.isFirstTimeInstall(configPath: KeyPathConstants.Config.mainConfigPath)
    }
}
