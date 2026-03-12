import Foundation
import KeyPathCore
import KeyPathDaemonLifecycle
import KeyPathPermissions

/// Manages the lifecycle of the Kanata runtime service (start, stop, restart, status).
///
/// Extracted from `RuntimeCoordinator+ServiceManagement.swift` to give service lifecycle
/// its own focused type. `RuntimeCoordinator` delegates all start/stop/restart calls here.
@MainActor
final class ServiceLifecycleCoordinator {
    // MARK: - Runtime Status

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

    // MARK: - Dependencies

    private let recoveryDaemonService: RecoveryDaemonService
    private let recoveryCoordinator: RecoveryCoordinator

    /// Mutable flag shared with RuntimeCoordinator to track in-progress start attempts.
    var isStartingKanata = false

    // MARK: - Callbacks (set by RuntimeCoordinator after init)

    /// Called when an error should be surfaced to the UI.
    var onError: ((String?) -> Void)?

    /// Called when a warning should be surfaced to the UI.
    var onWarning: ((String?) -> Void)?

    /// Called to notify the UI of a state change.
    var onStateChanged: (() -> Void)?

    /// Called to check whether the Karabiner daemon is running.
    var isKarabinerDaemonRunning: (() async -> Bool)?

    // MARK: - Init

    init(
        recoveryDaemonService: RecoveryDaemonService,
        recoveryCoordinator: RecoveryCoordinator
    ) {
        self.recoveryDaemonService = recoveryDaemonService
        self.recoveryCoordinator = recoveryCoordinator
    }

    // MARK: - Runtime Path Decision

    func currentSplitRuntimeDecision() async -> KanataRuntimePathDecision {
        await KanataRuntimePathCoordinator.evaluateCurrentPath()
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

    // MARK: - Start / Stop / Restart

    @discardableResult
    func startKanata(reason: String = "Manual start", precomputedDecision: KanataRuntimePathDecision? = nil) async -> Bool {
        AppLogger.shared.log("🚀 [Service] Starting Kanata (\(reason))")
        onWarning?(nil)

        // CRITICAL: Check VHID daemon health before starting Kanata
        if let checker = isKarabinerDaemonRunning, await !checker() {
            AppLogger.shared.error("❌ [Service] Cannot start Kanata - VirtualHID daemon is not running")
            onError?("Cannot start: Karabiner VirtualHID daemon is not running. Please complete the setup wizard.")
            onStateChanged?()
            return false
        }

        let decision: KanataRuntimePathDecision = if let precomputedDecision {
            precomputedDecision
        } else {
            await currentSplitRuntimeDecision()
        }
        switch decision {
        case .useSplitRuntime:
            break
        case let .useLegacySystemBinary(evalReason), let .blocked(evalReason):
            let message =
                "Split runtime host is enabled, but KeyPath could not start it: \(evalReason). " +
                "The legacy recovery daemon is no longer used for ordinary startup."
            AppLogger.shared.error("❌ [Service] \(message)")
            onError?(message)
            onStateChanged?()
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
                onError?(
                    "Split runtime host is ready, but KeyPath could not stop the legacy recovery daemon for cutover: \(message)"
                )
                onStateChanged?()
                return false
            }
        }

        do {
            let pid = try await KanataSplitRuntimeHostService.shared.startPersistentPassthruHost(includeCapture: true)
            AppLogger.shared.log("✅ [Service] Started split-runtime host (PID \(pid))")
            await AppContextService.shared.start()
            onError?(nil)
            onWarning?(nil)
            onStateChanged?()
            return true
        } catch {
            let message = (error as? LocalizedError)?.errorDescription ?? error.localizedDescription
            AppLogger.shared.error(
                "❌ [Service] Split-runtime host start failed during normal startup: \(message)"
            )
            onError?(
                "Split runtime host failed to start: \(message). Legacy fallback is reserved for recovery paths."
            )
            onStateChanged?()
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
            onError?(nil)
            onWarning?(nil)
            onStateChanged?()
            return true
        }

        do {
            _ = try await recoveryDaemonService.stopIfRunning()
            onWarning?(nil)
            onStateChanged?()
            return true
        } catch {
            let message = (error as? LocalizedError)?.errorDescription ?? error.localizedDescription
            AppLogger.shared.error("❌ [Service] Stop failed: \(message)")
            onError?("Stop failed: \(message)")
            onStateChanged?()
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
            onError?(message)
            onStateChanged?()
            return false
        }
    }

    // MARK: - Runtime Status

    func currentRuntimeStatus() async -> RuntimeStatus {
        if isStartingKanata {
            return .starting
        }

        if KanataSplitRuntimeHostService.shared.isPersistentPassthruHostRunning {
            return .running(pid: Int(KanataSplitRuntimeHostService.shared.activePersistentHostPID ?? 0))
        }

        // Secondary check: the legacy recovery daemon may still be active during
        // migration. Report it as running so callers don't skip TCP reload.
        if await recoveryDaemonService.isRecoveryDaemonRunning() {
            AppLogger.shared.warn(
                "⚠️ [Service] Split runtime host is not running but legacy recovery daemon is active — half-migrated state"
            )
            return .running(pid: 0)
        }

        return .stopped
    }

    // MARK: - Validation Start

    func startKanataWithValidation() async {
        await recoveryCoordinator.startKanataWithValidation(
            isKarabinerDaemonRunning: { [weak self] in
                guard let self, let checker = isKarabinerDaemonRunning else { return false }
                return await checker()
            },
            startKanata: { [weak self] in
                await self?.startKanata(reason: "VirtualHID validation start") ?? false
            },
            onError: { [weak self] error in
                self?.onError?(error)
                self?.onStateChanged?()
            }
        )
    }

    // MARK: - Permission Checks

    func shouldShowWizardForPermissions() async -> Bool {
        let snapshot = await PermissionOracle.shared.forceRefresh()
        return snapshot.blockingIssue != nil
    }

    func isFirstTimeInstall() -> Bool {
        InstallationCoordinator().isFirstTimeInstall(configPath: KeyPathConstants.Config.mainConfigPath)
    }
}
