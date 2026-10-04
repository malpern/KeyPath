import AppKit
import Foundation
import KeyPathCore
import KeyPathDaemonLifecycle
import KeyPathInstallationWizard
import KeyPathPermissions
import KeyPathWizardCore

/// Manages the lifecycle of the Kanata runtime service (start, stop, restart, status).
///
/// Owns the unprivileged session application and its readiness evidence.
@MainActor
final class ServiceLifecycleCoordinator {
    var sessionApplication: NSRunningApplication?
    var sessionReportURL: URL?
    var sessionNonce: String?
    var sessionOutputsRecovered = false
    var sessionSupervisionTask: Task<Void, Never>?

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

    let kanataDaemonService: KanataDaemonService

    #if DEBUG
        /// Lifecycle tests inject session operations without launching an application.
        nonisolated(unsafe) static var testSessionStart: (@MainActor (String) async -> Bool)?
        nonisolated(unsafe) static var testSessionStop: (@MainActor () async -> Bool)?
    #endif

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

    /// True while the runtime is deliberately moving between executable instances.
    /// Reload failures during this window are expected transport churn, not user-facing
    /// configuration failures: the old TCP server can disappear while stale-runtime
    /// recovery replaces it with the newly bundled process.
    var isRuntimeTransitionInProgress: Bool {
        isStartingKanata || isIntentionalTransitionInProgress
    }

    private let windowEvaluator = TransientStartupWindowEvaluator(
        gracePeriod: RuntimeStartupTiming.uiGracePeriod,
        createdAt: Date()
    )

    // MARK: - Callbacks (set by RuntimeCoordinator after init)

    /// Called when an error should be surfaced to the UI.
    var onError: ((String?) -> Void)?

    /// Called when a warning should be surfaced to the UI.
    var onWarning: ((String?) -> Void)?

    /// Called to notify the UI of a state change.
    var onStateChanged: (() -> Void)?

    // MARK: - Init

    init(
        kanataDaemonService: KanataDaemonService,
        recoveryCoordinator _: RecoveryCoordinator
    ) {
        self.kanataDaemonService = kanataDaemonService
        ServiceHealthChecker.shared.configureSessionReadinessProvider { [weak self] in
            guard let report = await self?.currentSessionReport() else {
                return KanataRuntimeReadiness(isRunning: false, isResponding: false, inputCaptureReady: false)
            }
            let running = report.state == .running && report.tapActive
            let responding = running ? await SystemStateProvider.shared.isTCPPortResponding(port: Int(report.tcpPort), timeoutMs: 300) : false
            return KanataRuntimeReadiness(isRunning: running, isResponding: responding, inputCaptureReady: running)
        }
        Task { [weak self] in
            await SystemStateProvider.shared.configureSessionPermissionCapabilityProvider { [weak self] in
                await self?.sessionCapabilities()
            }
        }
    }

    // MARK: - Start / Stop / Restart

    @discardableResult
    func startKanata(reason: String = "Manual start") async -> Bool {
        stopGraceUntil = nil
        lastStartAttemptAt = Date()
        isStartingKanata = true
        defer { isStartingKanata = false }
        #if DEBUG
            if let start = Self.testSessionStart { return await start(reason) }
        #endif
        return await startSessionRuntime(reason: reason)
    }

    @discardableResult
    func stopKanata(reason: String = "Manual stop") async -> Bool {
        AppLogger.shared.log("Stopping session runtime (\(reason))")
        intentionalStopDepth += 1
        defer {
            intentionalStopDepth = max(0, intentionalStopDepth - 1)
            if intentionalStopDepth == 0 {
                stopGraceUntil = Date().addingTimeInterval(intentionalStopGrace)
            }
        }
        #if DEBUG
            if let stop = Self.testSessionStop { return await stop() }
        #endif
        return await stopSessionRuntime()
    }

    @discardableResult
    func restartKanata(reason: String = "Manual restart") async -> Bool {
        let stopped = await stopKanata(reason: "\(reason) (stop for restart)")
        guard stopped else { return false }
        return await startKanata(reason: "\(reason) (restart)")
    }

    func isInTransientRuntimeStartupWindow() async -> Bool {
        windowEvaluator.isInWindow(
            now: Date(),
            isStarting: isStartingKanata,
            lastStartAttemptAt: lastStartAttemptAt,
            isSMAppServicePending: false
        )
    }

    static func shouldAcceptPostStartRuntime(
        _ snapshot: ServiceHealthChecker.KanataServiceRuntimeSnapshot
    ) -> Bool {
        snapshot.readiness.isReady
    }

    // MARK: - Runtime Status

    func currentRuntimeStatus() async -> RuntimeStatus {
        if isStartingKanata { return .starting }
        guard let report = currentSessionReport() else { return .stopped }
        return report.state == .running && report.tapActive
            ? .running(pid: Int(report.pid)) : .failed(reason: report.failure ?? report.state.rawValue)
    }

    // MARK: - Validation Start

    func startKanataWithValidation() async {
        _ = await startKanata(reason: "Session validation start")
    }

    // MARK: - Permission Checks

    func shouldShowWizardForPermissions() async -> Bool {
        let snapshot = await SystemStateProvider.shared.refreshPermissionSnapshot()
        return snapshot.blockingIssue != nil
    }

    func isFirstTimeInstall() -> Bool {
        InstallationCoordinator().isFirstTimeInstall(configPath: KeyPathConstants.Config.mainConfigPath)
    }
}
