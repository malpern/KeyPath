import Foundation
import KeyPathCore
import KeyPathDaemonLifecycle
import KeyPathInstallationWizard
import KeyPathPermissions
import KeyPathWizardCore

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

    // MARK: - Wait-for-exit test seams (#625 part-1)

    // Test seams for the deterministic wait-for-exit routine. Without these, the
    // polling loops would spawn real `pgrep` (which deadlocks under parallel test
    // runs — see CLAUDE.md), probe a real TCP port, and sleep real time. Tests
    // inject deterministic closures; production always uses the real subprocess /
    // syscall / TCP probe. DEBUG-only and nil in production.
    #if DEBUG
        /// Replaces `SubprocessRunner.shared.pgrep`. Returns matching PIDs for a name.
        nonisolated(unsafe) static var testPgrepProvider: ((String) -> [pid_t])?
        /// Replaces `kill(pid, 0)`. Returns `true` when the process is still alive.
        nonisolated(unsafe) static var testLivenessProbe: ((pid_t) -> Bool)?
        /// Replaces `kill(pid, signal)` for SIGTERM/SIGKILL so tests with synthetic PIDs
        /// never signal a real, unrelated process on the machine.
        nonisolated(unsafe) static var testSignal: ((pid_t, Int32) -> Void)?
        /// Replaces `TCPProbe.probe`. Returns `true` when something is listening.
        nonisolated(unsafe) static var testTCPProbe: ((Int, Int) -> Bool)?
        /// Replaces `Task.sleep` in the polling loops so tests never wait real time.
        nonisolated(unsafe) static var testSleep: ((Duration) async -> Void)?
        /// Replaces the running-kanata identity check so tests can simulate stale binaries.
        nonisolated(unsafe) static var testRunningKanataIdentityProvider: (() async -> RunningKanataIdentity)?
    #endif

    /// Timing for the stop→start wait-for-exit (#625 part-1). Bounds are expressed in
    /// milliseconds so poll counts derive trivially and stay deterministic when the
    /// sleep seam is a no-op (a wall-clock deadline would never advance under that seam).
    enum WaitForExitTiming {
        static let pollIntervalMs = 100
        static let processExitGraceMs = 2000 // SIGTERM → SIGKILL window
        static let portReleaseTimeoutMs = 2000 // after processes confirmed dead
        static let postKillConfirmMs = 500 // brief confirm-gone poll after SIGKILL
        static let tcpProbeTimeoutMs = 150

        static var pollInterval: Duration {
            .milliseconds(pollIntervalMs)
        }

        static func pollCount(forMs ms: Int) -> Int {
            max(1, ms / pollIntervalMs)
        }
    }

    enum RuntimeReadinessTiming {
        static let pollIntervalMs = 250
        static let timeoutMs = 5000
        static let tcpProbeTimeoutMs = 300

        static var pollInterval: Duration {
            .milliseconds(pollIntervalMs)
        }

        static var pollCount: Int {
            max(1, timeoutMs / pollIntervalMs)
        }
    }

    private enum RuntimeReadinessVerification {
        case ready
        case pendingApproval(String)
        case failed(String)
    }

    struct RunningKanataIdentity: Equatable {
        let pid: pid_t
        let executablePath: String
        let startedAt: Date?

        func matchesBundledKanata(_ bundledPath: String) -> Bool {
            let samePath = Self.canonicalPath(executablePath) == Self.canonicalPath(bundledPath)
            guard samePath else { return false }

            guard
                let startedAt,
                let bundledModifiedAt = Self.fileModificationDate(at: bundledPath)
            else {
                return true
            }

            // `ps -o lstart` reports whole seconds, while file modification dates
            // include subsecond precision. Allow one second of slack so a freshly
            // restarted same-path process does not look stale because of truncation.
            return startedAt.addingTimeInterval(1) >= bundledModifiedAt
        }

        private static func canonicalPath(_ path: String) -> String {
            URL(fileURLWithPath: path).standardizedFileURL.path
        }

        private static func fileModificationDate(at path: String) -> Date? {
            (try? FileManager.default.attributesOfItem(atPath: path)[.modificationDate]) as? Date
        }
    }

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
            AppLogger.shared.errorUnlessQuietTest("❌ [Service] Cannot start Kanata - VirtualHID daemon is not running")
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
            AppLogger.shared.errorUnlessQuietTest(
                "❌ [Service] Cannot start kanata — VirtualHID daemon not healthy (ServiceHealthChecker)"
            )
            onError?("Cannot start: VirtualHID daemon health check failed. Please reinstall drivers.")
            onStateChanged?()
            return false
        }

        await waitForKanataExitBeforeStart()
        let mismatchedRuntimeRecovered = await recoverIfRunningKanataDoesNotMatchBundledBinary(reason: reason)

        do {
            lastStartAttemptAt = Date()
            try await KanataDaemonManager.shared.register()
            AppLogger.shared.log("✅ [Service] Kanata LaunchDaemon registered (\(reason))")

            // If the daemon registered but isn't running (e.g., it exited cleanly
            // after max retries), kickstart it to force a restart.
            try? await Task.sleep(for: .milliseconds(500))
            let daemonRunning = await kanataDaemonService.isDaemonRunning()
            if mismatchedRuntimeRecovered || !daemonRunning {
                AppLogger.shared.log("🔄 [Service] Daemon registered but not running — kickstarting")
                _ = try? await SubprocessRunner.shared.launchctl("kickstart", ["system/com.keypath.kanata"])
            }

            switch await verifyRuntimeReadinessAfterStart(reason: reason) {
            case .ready:
                break
            case let .pendingApproval(message):
                AppLogger.shared.warn("⚠️ [Service] \(message)")
                onError?(nil)
                onWarning?(message)
                onStateChanged?()
                DistributedNotificationBridge.postServiceState("pending-approval")
                return true
            case let .failed(message):
                AppLogger.shared.error("❌ [Service] \(message)")
                onError?(message)
                onStateChanged?()
                return false
            }

            await AppContextService.shared.start()
            onError?(nil)
            onWarning?(nil)
            onStateChanged?()
            DistributedNotificationBridge.postServiceState("running")
            return true
        } catch {
            let message = (error as? LocalizedError)?.errorDescription ?? error.localizedDescription
            AppLogger.shared.errorUnlessQuietTest("❌ [Service] LaunchDaemon registration failed: \(message)")
            onError?("Failed to start Kanata: \(message)")
            onStateChanged?()
            return false
        }
    }

    @discardableResult
    private func recoverIfRunningKanataDoesNotMatchBundledBinary(reason: String) async -> Bool {
        guard let runningIdentity = await detectRunningKanataIdentity() else {
            AppLogger.shared.debug("🔍 [Service] Running Kanata identity unavailable before start (\(reason))")
            return false
        }

        let bundledPath = WizardSystemPaths.bundledKanataPath
        guard !runningIdentity.matchesBundledKanata(bundledPath) else {
            AppLogger.shared.debug(
                "✅ [Service] Running Kanata binary matches bundled binary: pid=\(runningIdentity.pid), path=\(runningIdentity.executablePath)"
            )
            return false
        }

        AppLogger.shared.warnUnlessQuietTest(
            "⚠️ [Service] Running Kanata binary does not match bundled binary; " +
                "forcing privileged runtime recovery. running(pid=\(runningIdentity.pid), " +
                "path=\(runningIdentity.executablePath)) bundled=\(bundledPath)"
        )

        let report = await InstallerEngine()
            .runSingleAction(.terminateConflictingProcesses, using: PrivilegeBroker())
        if !report.success {
            AppLogger.shared.warn(
                "⚠️ [Service] Privileged stale Kanata termination failed: \(report.failureReason ?? "unknown error")"
            )
            return false
        }

        ServiceHealthChecker.shared.invalidateHealthCache()
        AppLogger.shared.log("✅ [Service] Stale Kanata runtime terminated before start (\(reason))")
        return true
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
            let value = await performSMAppServiceRefresh()
            smAppServiceRefreshTask = nil
            return value
        }
    }

    private func performSMAppServiceRefresh() async -> Bool {
        let managementState = await KanataDaemonManager.shared.refreshManagementStateInternal()
        let isPending = managementState == .smappservicePending
        smAppServicePendingCache = (isPending, Date())
        return isPending
    }

    private func verifyRuntimeReadinessAfterStart(reason: String) async -> RuntimeReadinessVerification {
        var lastSummary = "no runtime snapshot collected"

        for attempt in 0 ..< RuntimeReadinessTiming.pollCount {
            let managementState = await KanataDaemonManager.shared.refreshManagementStateInternal()
            if managementState == .smappservicePending {
                return .pendingApproval("Kanata is registered but pending approval in System Settings → Login Items.")
            }

            let staleRegistration = managementState == .smappserviceActive
                ? await KanataDaemonManager.shared.isRegisteredButNotLoaded()
                : false
            let snapshot = await ServiceHealthChecker.shared.checkKanataServiceRuntimeSnapshot(
                managementState: WizardServiceManagementState(managementState),
                staleEnabledRegistration: staleRegistration,
                tcpPort: PreferencesService.shared.tcpServerPort,
                timeoutMs: RuntimeReadinessTiming.tcpProbeTimeoutMs
            )
            let decision = ServiceHealthChecker.decideKanataHealth(for: snapshot)
            lastSummary =
                "state=\(managementState.description), running=\(snapshot.isRunning), tcp=\(snapshot.isResponding), inputCapture=\(snapshot.inputCaptureReady), decision=\(decision)"

            if snapshot.isRunning, snapshot.isResponding, snapshot.inputCaptureReady, !snapshot.staleEnabledRegistration {
                AppLogger.shared.log("✅ [Service] Runtime readiness verified after start (\(reason)): \(lastSummary)")
                return .ready
            }

            if attempt < RuntimeReadinessTiming.pollCount - 1 {
                await sleepForReadinessPoll()
            }
        }

        return .failed("Kanata start did not reach runtime readiness after \(RuntimeReadinessTiming.timeoutMs)ms (\(lastSummary))")
    }

    private func sleepForReadinessPoll() async {
        #if DEBUG
            if let testSleep = Self.testSleep {
                await testSleep(RuntimeReadinessTiming.pollInterval)
                return
            }
        #endif
        try? await Task.sleep(for: RuntimeReadinessTiming.pollInterval)
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

    /// Terminate any orphaned `kanata-launcher` / `kanata` processes and wait until
    /// they are fully gone AND the TCP port is released, BEFORE the new LaunchDaemon
    /// registers (#625 part-1 — "wait-for-exit before start").
    ///
    /// The old kanata holds the exclusive keyboard grab and TCP port until it actually
    /// exits, and `SMAppService.unregister()` returns before the OS finishes tearing the
    /// process down. Registering a new kanata while the old one lingers is the stop→start
    /// race that produces the silent "degraded" state (process up, but never grabbed the
    /// keyboard). Waiting here makes the transition deterministic.
    ///
    /// Bounded: on timeout we log a warning and proceed anyway rather than failing the
    /// start — leaving the user with no remapping would be worse, and the #625 grab
    /// auto-recovery is the backstop for any residual degraded case.
    ///
    /// `internal` (not `private`) so tests can drive it directly: `startKanata`'s VHID
    /// gates short-circuit in the test environment, so the seam-injected polling logic
    /// is exercised by calling this method rather than through `startKanata`.
    func waitForKanataExitBeforeStart() async {
        let processNames = ["kanata-launcher", "kanata"]
        var killedAny = false

        for name in processNames {
            let pids = await pgrepMatches(name)
            guard !pids.isEmpty else { continue }
            killedAny = true

            for pid in pids {
                AppLogger.shared.log("🧹 [Service] Terminating orphaned \(name) (PID \(pid)) before LaunchDaemon start")
                sendSignal(pid, SIGTERM)
            }

            // Poll until the processes exit; escalate to SIGKILL past the grace window.
            let survivors = await waitForProcessesGone(pids, withinMs: WaitForExitTiming.processExitGraceMs)
            for pid in survivors {
                AppLogger.shared.warnUnlessQuietTest("⚠️ [Service] \(name) (PID \(pid)) did not exit within grace — SIGKILL")
                sendSignal(pid, SIGKILL)
            }
            if !survivors.isEmpty {
                let stillAlive = await waitForProcessesGone(survivors, withinMs: WaitForExitTiming.postKillConfirmMs)
                if !stillAlive.isEmpty {
                    AppLogger.shared.warnUnlessQuietTest(
                        "⚠️ [Service] \(name) PIDs \(stillAlive) still alive after SIGKILL — proceeding anyway"
                    )
                }
            }
        }

        // Only wait on the TCP port if we actually killed something. A clean machine has
        // nothing of ours holding the port, so the common first-start path adds no latency.
        guard killedAny else { return }
        if await waitForPortReleased() {
            AppLogger.shared.log("✅ [Service] wait-for-exit complete — port released, proceeding with start")
        }
        // The timeout path already warned inside waitForPortReleased; no ✅ there so a
        // `grep "✅"` of the log can't be fooled into thinking a stuck port was clean.
    }

    /// Poll the given PIDs until none are alive or the budget elapses.
    /// - Returns: PIDs still alive when the budget is exhausted (empty on success).
    private func waitForProcessesGone(_ pids: [pid_t], withinMs budgetMs: Int) async -> [pid_t] {
        var remaining = pids
        let maxPolls = WaitForExitTiming.pollCount(forMs: budgetMs)
        for poll in 0 ..< maxPolls {
            remaining = remaining.filter { isProcessAlive($0) }
            if remaining.isEmpty { return [] }
            // Skip the sleep after the final poll so the budget stays ~budgetMs, not
            // budgetMs + one extra interval.
            if poll < maxPolls - 1 { await waitSleep(WaitForExitTiming.pollInterval) }
        }
        return remaining
    }

    /// Poll the kanata TCP port until nothing is listening (the old process released it)
    /// or the budget elapses.
    /// - Returns: `true` if the port was confirmed free, `false` on timeout (caller
    ///   proceeds anyway; a warning is logged here).
    private func waitForPortReleased() async -> Bool {
        let port = PreferencesService.shared.tcpServerPort
        let maxPolls = WaitForExitTiming.pollCount(forMs: WaitForExitTiming.portReleaseTimeoutMs)
        for poll in 0 ..< maxPolls {
            let listening = await probePort(port, timeoutMs: WaitForExitTiming.tcpProbeTimeoutMs)
            if !listening { return true }
            if poll < maxPolls - 1 { await waitSleep(WaitForExitTiming.pollInterval) }
        }
        AppLogger.shared.warnUnlessQuietTest(
            "⚠️ [Service] TCP port \(port) still in use after wait-for-exit — proceeding anyway (grab auto-recovery is the backstop)"
        )
        return false
    }

    // MARK: - Wait-for-exit primitives (test-seam aware)

    private func pgrepMatches(_ name: String) async -> [pid_t] {
        #if DEBUG
            if let provider = Self.testPgrepProvider { return provider(name) }
        #endif
        // Never spawn a real `pgrep` under tests: it can deadlock under parallel runs
        // (see CLAUDE.md) and would let synthetic PIDs reach a real `kill`. Tests that
        // need orphan PIDs inject `testPgrepProvider`; everything else gets a clean slate.
        if TestEnvironment.isRunningTests { return [] }
        return await SubprocessRunner.shared.pgrep(name)
    }

    private func detectRunningKanataIdentity() async -> RunningKanataIdentity? {
        #if DEBUG
            if let provider = Self.testRunningKanataIdentityProvider {
                return await provider()
            }
        #endif

        if TestEnvironment.isRunningTests { return nil }

        let pids = await pgrepMatches("kanata.*--cfg")
        for pid in pids {
            if let path = executablePath(for: pid) {
                return await RunningKanataIdentity(
                    pid: pid,
                    executablePath: path,
                    startedAt: processStartDate(for: pid)
                )
            }
        }
        return nil
    }

    private func processStartDate(for pid: pid_t) async -> Date? {
        do {
            let result = try await SubprocessRunner.shared.run(
                "/bin/ps",
                args: ["-p", "\(pid)", "-o", "lstart="],
                timeout: 2
            )
            guard result.exitCode == 0 else { return nil }
            let raw = result.stdout.trimmingCharacters(in: .whitespacesAndNewlines)
            return Self.parseProcessStartDate(raw)
        } catch {
            return nil
        }
    }

    private static func parseProcessStartDate(_ raw: String) -> Date? {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.dateFormat = "EEE MMM d HH:mm:ss yyyy"
        formatter.isLenient = true
        return formatter.date(from: raw)
    }

    private nonisolated func executablePath(for pid: pid_t) -> String? {
        let procPIDPathInfoMaxSize = 4096
        var buffer = [CChar](repeating: 0, count: procPIDPathInfoMaxSize)
        let length = proc_pidpath(pid, &buffer, UInt32(buffer.count))
        guard length > 0 else { return nil }
        let bytes = buffer
            .prefix(Int(length))
            .prefix { $0 != 0 }
            .map { UInt8(bitPattern: $0) }
        return String(bytes: bytes, encoding: .utf8)
    }

    private nonisolated func isProcessAlive(_ pid: pid_t) -> Bool {
        #if DEBUG
            if let probe = Self.testLivenessProbe { return probe(pid) }
        #endif
        return SystemStateProvider.isProcessAlive(pid: pid)
    }

    private nonisolated func sendSignal(_ pid: pid_t, _ signal: Int32) {
        #if DEBUG
            if let send = Self.testSignal {
                send(pid, signal)
                return
            }
        #endif
        kill(pid, signal)
    }

    private func probePort(_ port: Int, timeoutMs: Int) async -> Bool {
        #if DEBUG
            if let probe = Self.testTCPProbe { return probe(port, timeoutMs) }
        #endif
        return await Task.detached(priority: .utility) {
            TCPProbe.probe(port: port, timeoutMs: timeoutMs)
        }.value
    }

    private func waitSleep(_ duration: Duration) async {
        #if DEBUG
            if let sleep = Self.testSleep {
                await sleep(duration)
                return
            }
        #endif
        try? await Task.sleep(for: duration)
    }
}
