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

    // MARK: - Feature Flag

    /// When `false`, KeyPath uses Mode A (subprocess exec via LaunchDaemon) instead of
    /// Mode B (in-process passthru host + Output Bridge). Mode B is disabled due to
    /// SIGPIPE crashes, stale socket accumulation, and unrecoverable wizard failures.
    static let useSplitRuntimeHost = false

    // MARK: - Dependencies

    private let recoveryDaemonService: RecoveryDaemonService
    private let recoveryCoordinator: RecoveryCoordinator

    /// Mutable flag shared with RuntimeCoordinator to track in-progress start attempts.
    var isStartingKanata = false
    private var lastStartAttemptAt: Date?
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
        guard Self.useSplitRuntimeHost else {
            AppLogger.shared.info("🧪 [Service] Split runtime host disabled by feature flag, using legacy daemon path")
            return false
        }
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
        isStartingKanata = true
        defer {
            isStartingKanata = false
        }

        // CRITICAL: Check VHID daemon health before starting Kanata
        if let checker = isKarabinerDaemonRunning, await !checker() {
            AppLogger.shared.error("❌ [Service] Cannot start Kanata - VirtualHID daemon is not running")
            onError?("Cannot start: Karabiner VirtualHID daemon is not running. Please complete the setup wizard.")
            onStateChanged?()
            return false
        }

        guard Self.useSplitRuntimeHost else {
            return await startKanataViaLaunchDaemon(reason: reason)
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
            lastStartAttemptAt = Date()
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

    /// Mode A startup: register the LaunchDaemon via SMAppService so the OS launches
    /// kanata-launcher, which exec's into the bundled kanata binary.
    private func startKanataViaLaunchDaemon(reason: String) async -> Bool {
        // Clean up any stale Mode B artifacts
        cleanStalePassthruArtifacts()

        // If the split runtime host is somehow still running, stop it first
        if KanataSplitRuntimeHostService.shared.isPersistentPassthruHostRunning {
            AppLogger.shared.log("🧹 [Service] Stopping leftover split-runtime host before LaunchDaemon start")
            KanataSplitRuntimeHostService.shared.stopPersistentPassthruHost()
        }

        // Kill any orphaned kanata-launcher / kanata processes that may hold the TCP port.
        // This can happen when reverting from Mode B or after a crash leaves stale processes.
        await killOrphanedKanataProcesses()

        do {
            lastStartAttemptAt = Date()
            try await KanataDaemonManager.shared.register()
            AppLogger.shared.log("✅ [Service] Kanata LaunchDaemon registered (\(reason))")
            await AppContextService.shared.start()
            onError?(nil)
            onWarning?(nil)
            onStateChanged?()
            return true
        } catch {
            let message = (error as? LocalizedError)?.errorDescription ?? error.localizedDescription
            AppLogger.shared.error("❌ [Service] LaunchDaemon registration failed: \(message)")
            onError?("Failed to start Kanata: \(message)")
            onStateChanged?()
            return false
        }
    }

    /// Kill orphaned kanata-launcher and kanata processes that aren't managed by
    /// the current LaunchDaemon, so the new daemon can bind the TCP port.
    private func killOrphanedKanataProcesses() async {
        let processNames = ["kanata-launcher", "kanata"]
        for name in processNames {
            let task = Process()
            task.executableURL = URL(fileURLWithPath: "/usr/bin/pgrep")
            task.arguments = ["-x", name]
            let pipe = Pipe()
            task.standardOutput = pipe
            task.standardError = Pipe()
            do {
                try task.run()
                task.waitUntilExit()
                guard task.terminationStatus == 0 else { continue }
                let data = pipe.fileHandleForReading.readDataToEndOfFile()
                let pids = String(data: data, encoding: .utf8)?
                    .split(separator: "\n")
                    .compactMap { Int32(String($0).trimmingCharacters(in: .whitespaces)) } ?? []
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

    /// Remove stale Mode B socket and environment files from /var/tmp.
    private func cleanStalePassthruArtifacts() {
        let fm = Foundation.FileManager.default
        let tmpDir = "/var/tmp"
        guard let contents = try? fm.contentsOfDirectory(atPath: tmpDir) else { return }
        for name in contents where name.hasPrefix("keypath-host-passthru-") {
            let path = "\(tmpDir)/\(name)"
            try? fm.removeItem(atPath: path)
            AppLogger.shared.log("🧹 [Service] Cleaned stale passthru artifact: \(path)")
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
        guard Self.useSplitRuntimeHost else {
            let stopped = await stopKanata(reason: "\(reason) (stop for restart)")
            guard stopped else { return false }
            return await startKanata(reason: "\(reason) (restart)")
        }

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

    func isInTransientRuntimeStartupWindow() async -> Bool {
        // SMAppService state is fetched lazily — it's synchronous IPC and only
        // matters once the other (cheap) signals have all said "out of window".
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
        // On cache miss, if we've ever had a value, return it stale and
        // refresh in the background so the 250ms overlay poll never blocks
        // on a potentially slow SMAppService.status IPC round-trip. Dedupe
        // concurrent refreshes via `smAppServiceRefreshTask`.
        if let cached = smAppServicePendingCache {
            scheduleSMAppServiceRefresh()
            return cached.value
        }
        // First ever call — no stale value to return. Do the IPC synchronously
        // once so the first answer is correct; subsequent calls are cached.
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

        guard Self.useSplitRuntimeHost else {
            // Mode A: check the LaunchDaemon via RecoveryDaemonService
            let daemonStatus = await recoveryDaemonService.refreshStatus()
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

        if KanataSplitRuntimeHostService.shared.isPersistentPassthruHostRunning {
            let binaryAlive = await Task.detached {
                KanataSplitRuntimeHostService.isKanataBinaryAlive()
            }.value
            if binaryAlive {
                return .running(pid: Int(KanataSplitRuntimeHostService.shared.activePersistentHostPID ?? 0))
            } else {
                AppLogger.shared.warn("⚠️ [Service] Launcher alive but kanata binary dead — reporting stopped")
                return .stopped
            }
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
