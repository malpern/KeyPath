import Foundation
import KeyPathCore
import KeyPathDaemonLifecycle
import KeyPathInstallationWizard
import KeyPathPermissions

/// Manages the lifecycle of the Kanata runtime service (start, stop, restart, status).
///
/// Uses Mode A: kanata-launcher registers as a LaunchDaemon via SMAppService,
/// then exec's into the bundled kanata binary. Single root process.
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

    private let kanataDaemonService: KanataDaemonService
    private let recoveryCoordinator: RecoveryCoordinator

    /// Mutable flag shared with RuntimeCoordinator to track in-progress start attempts.
    var isStartingKanata = false
    private var lastStartAttemptAt: Date?

    /// Intentional-transition gate (#625). While we are deliberately stopping kanata,
    /// the dying process may emit one last `InputGrab active=false` on its still-open
    /// socket — that is benign and must NOT trigger auto-recovery. Depth-counted so an
    /// overlapping stop composes correctly; a short trailing grace swallows the late
    /// last-gasp event after the stop call returns.
    ///
    /// Deliberately scoped to the STOP phase only, and the trailing grace is cleared at
    /// the top of `startKanata`: the start phase of a restart stays un-gated so a genuine
    /// post-start grab failure (the #625 race) from the freshly started kanata is still
    /// caught and recovered, rather than masked as a benign transition.
    private var intentionalStopDepth = 0
    private var stopGraceUntil: Date?
    private let intentionalStopGrace: TimeInterval = 2.0

    /// True while an intentional kanata stop is in progress (or within the short grace
    /// window after one). Read by RuntimeCoordinator before acting on a grab failure.
    var isIntentionalTransitionInProgress: Bool {
        if intentionalStopDepth > 0 { return true }
        if let until = stopGraceUntil, Date() < until { return true }
        return false
    }

    private let windowEvaluator = TransientStartupWindowEvaluator(
        gracePeriod: RuntimeStartupTiming.uiGracePeriod,
        createdAt: Date()
    )

    /// Short-lived cache of the SMAppService "pending" check so the 250ms
    /// overlay polling loop doesn't hammer SMAppService.status (synchronous
    /// IPC, can block 10-30s under concurrent load — see CLAUDE.md).
    private var smAppServicePendingCache: (value: Bool, timestamp: Date)?
    private static let smAppServicePendingCacheTTL: TimeInterval = 5.0
    /// In-flight SMAppService refresh, kept so back-to-back cache misses
    /// don't fan out into parallel IPC calls.
    private var smAppServiceRefreshTask: Task<Bool, Never>?

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
        kanataDaemonService: KanataDaemonService,
        recoveryCoordinator: RecoveryCoordinator
    ) {
        self.kanataDaemonService = kanataDaemonService
        self.recoveryCoordinator = recoveryCoordinator
    }

    // MARK: - Start / Stop / Restart

    @discardableResult
    func startKanata(reason: String = "Manual start") async -> Bool {
        AppLogger.shared.log("🚀 [Service] Starting Kanata (\(reason))")
        // End any lingering post-stop grace (#625): we are deliberately starting a new
        // kanata now, so its authoritative grab status is exactly what we want to act
        // on. Without this, the 2s grace armed by the preceding stop in a restart would
        // suppress a genuine `InputGrab active=false` from the freshly started daemon —
        // the very degraded state this feature recovers from. The grace only needs to
        // cover the OLD process's last gasp, which is already past once a start begins.
        stopGraceUntil = nil
        onWarning?(nil)
        isStartingKanata = true
        defer {
            isStartingKanata = false
        }

        if let checker = isKarabinerDaemonRunning, await !checker() {
            AppLogger.shared.error("❌ [Service] Cannot start Kanata - VirtualHID daemon is not running")
            onError?("Cannot start: Karabiner VirtualHID daemon is not running. Please complete the setup wizard.")
            onStateChanged?()
            return false
        }

        // Second safety layer: verify VirtualHID daemon via ServiceHealthChecker
        // (the callback above relies on the caller wiring it; this is a direct check)
        let vhidHealthy = await ServiceHealthChecker.shared.isServiceHealthy(
            serviceID: ServiceHealthChecker.vhidDaemonServiceID
        )
        if !VHIDSafetyCheck.canStartKanata(vhidDaemonHealthy: vhidHealthy) {
            AppLogger.shared.error("❌ [Service] Cannot start kanata — VirtualHID daemon not healthy (ServiceHealthChecker)")
            onError?("Cannot start: VirtualHID daemon health check failed. Please reinstall drivers.")
            onStateChanged?()
            return false
        }

        await killOrphanedKanataProcesses()

        do {
            lastStartAttemptAt = Date()
            try await KanataDaemonManager.shared.register()
            AppLogger.shared.log("✅ [Service] Kanata LaunchDaemon registered (\(reason))")

            // If the daemon registered but isn't running (e.g., it exited cleanly
            // after max retries), kickstart it to force a restart.
            try? await Task.sleep(for: .milliseconds(500))
            if !(await kanataDaemonService.isDaemonRunning()) {
                AppLogger.shared.log("🔄 [Service] Daemon registered but not running — kickstarting")
                _ = try? await SubprocessRunner.shared.launchctl("kickstart", ["system/com.keypath.kanata"])
            }

            await AppContextService.shared.start()
            onError?(nil)
            onWarning?(nil)
            onStateChanged?()
            DistributedNotificationBridge.postServiceState("running")
            return true
        } catch {
            let message = (error as? LocalizedError)?.errorDescription ?? error.localizedDescription
            AppLogger.shared.error("❌ [Service] LaunchDaemon registration failed: \(message)")
            onError?("Failed to start Kanata: \(message)")
            onStateChanged?()
            return false
        }
    }

    @discardableResult
    func stopKanata(reason: String = "Manual stop") async -> Bool {
        AppLogger.shared.log("🛑 [Service] Stopping Kanata (\(reason))")
        // Mark this as an intentional transition so a benign `InputGrab active=false`
        // emitted by the dying kanata doesn't trip auto-recovery (#625).
        intentionalStopDepth += 1
        defer {
            intentionalStopDepth = max(0, intentionalStopDepth - 1)
            if intentionalStopDepth == 0 {
                stopGraceUntil = Date().addingTimeInterval(intentionalStopGrace)
            }
        }
        await AppContextService.shared.stop()

        do {
            _ = try await kanataDaemonService.stopIfRunning()
            onWarning?(nil)
            onStateChanged?()
            DistributedNotificationBridge.postServiceState("stopped")
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
        let stopped = await stopKanata(reason: "\(reason) (stop for restart)")
        guard stopped else { return false }
        return await startKanata(reason: "\(reason) (restart)")
    }

    func isInTransientRuntimeStartupWindow() async -> Bool {
        if windowEvaluator.isInWindow(
            now: Date(),
            isStarting: isStartingKanata,
            lastStartAttemptAt: lastStartAttemptAt,
            isSMAppServicePending: false
        ) {
            return true
        }
        return await isSMAppServicePendingCached()
    }

    private func isSMAppServicePendingCached() async -> Bool {
        let now = Date()
        if let cached = smAppServicePendingCache,
           now.timeIntervalSince(cached.timestamp) < Self.smAppServicePendingCacheTTL
        {
            return cached.value
        }
        if let cached = smAppServicePendingCache {
            scheduleSMAppServiceRefresh()
            return cached.value
        }
        return await performSMAppServiceRefresh()
    }

    private func scheduleSMAppServiceRefresh() {
        if smAppServiceRefreshTask != nil { return }
        smAppServiceRefreshTask = Task { [weak self] in
            guard let self else { return false }
            let value = await self.performSMAppServiceRefresh()
            self.smAppServiceRefreshTask = nil
            return value
        }
    }

    private func performSMAppServiceRefresh() async -> Bool {
        let managementState = await KanataDaemonManager.shared.refreshManagementStateInternal()
        let isPending = managementState == .smappservicePending
        smAppServicePendingCache = (isPending, Date())
        return isPending
    }

    // MARK: - Runtime Status

    func currentRuntimeStatus() async -> RuntimeStatus {
        if isStartingKanata {
            return .starting
        }

        let daemonStatus = await kanataDaemonService.refreshStatus()
        switch daemonStatus {
        case let .running(pid):
            return .running(pid: pid)
        case .stopped:
            return .stopped
        case let .failed(reason):
            return .failed(reason: reason)
        case .unknown:
            return .unknown
        }
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

    // MARK: - Private

    /// Kill orphaned kanata-launcher and kanata processes that aren't managed by
    /// the current LaunchDaemon, so the new daemon can bind the TCP port.
    private func killOrphanedKanataProcesses() async {
        let processNames = ["kanata-launcher", "kanata"]
        for name in processNames {
            do {
                let pids = await SubprocessRunner.shared.pgrep(name)
                for pid in pids {
                    AppLogger.shared.log("🧹 [Service] Killing orphaned \(name) (PID \(pid)) before LaunchDaemon start")
                    kill(pid, SIGTERM)
                }
                if !pids.isEmpty {
                    try? await Task.sleep(for: .milliseconds(500))
                    for pid in pids where kill(pid, 0) == 0 {
                        kill(pid, SIGKILL)
                    }
                }
            } catch {
                // pgrep not finding matches is fine
            }
        }
    }
}
