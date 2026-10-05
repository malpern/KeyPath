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
    private(set) var sessionConfigurationAdmission: KanataHostBridgeValidationResult?
    var sessionSupervisionTask: Task<Void, Never>?
    // Process ownership is serialized across suspension points, independently of
    // configuration persistence. Intent changes immediately, before admission.
    let sessionOperationGate = ConfigurationOperationGate()
    private(set) var sessionIntentGeneration: UInt64 = 0
    private(set) var sessionWantsRunning = false

    enum SessionLifecycleOperation: Sendable {
        case start(String), stop(String), restart(String)
    }

    func sessionStartIsCurrent(_ generation: UInt64) -> Bool {
        generation == sessionIntentGeneration && sessionWantsRunning && !Task.isCancelled
    }

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
        var testSessionCurrentReport: (() -> SessionRuntimeReport?)?
        var testSessionConfigurationValidation: (() -> KanataHostBridgeValidationResult)?
        var testSessionRequestObserved: ((UInt64) -> Void)?
        var testSessionRunningReadiness: (@MainActor () async -> Bool)?
        var testSessionSupervisionStarted: ((UInt64) -> Void)?
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
        await requestSessionOperation(.start(reason))
    }

    @discardableResult
    func stopKanata(reason: String = "Manual stop") async -> Bool {
        await requestSessionOperation(.stop(reason))
    }

    @discardableResult
    func restartKanata(reason: String = "Manual restart") async -> Bool {
        await requestSessionOperation(.restart(reason))
    }

    private func requestSessionOperation(_ operation: SessionLifecycleOperation) async -> Bool {
        // A request already cancelled before entry changes no intent. An accepted
        // stop must still release held outputs even if its caller later cancels.
        if case .stop = operation {} else if Task.isCancelled { return false }
        sessionIntentGeneration &+= 1
        let generation = sessionIntentGeneration
        if case .stop = operation { sessionWantsRunning = false } else { sessionWantsRunning = true }
        #if DEBUG
            testSessionRequestObserved?(generation)
        #endif
        if case .stop = operation {
            return await Task.detached { [self] in
                await admitSessionOperation(operation, generation: generation)
            }.value
        }
        let result = await admitSessionOperation(operation, generation: generation)
        if Task.isCancelled, generation == sessionIntentGeneration {
            // A cancelled queued start has already invalidated supervision of
            // the previous worker. Finish with an admitted stop, never abandon it.
            _ = await requestSessionOperation(.stop("Cancelled lifecycle request"))
            return false
        }
        return generation == sessionIntentGeneration && sessionWantsRunning && result
    }

    private func admitSessionOperation(_ operation: SessionLifecycleOperation, generation: UInt64) async -> Bool {
        do {
            return try await sessionOperationGate.withOperation { [self] _ in
                await performSessionOperation(operation, generation: generation)
            }
        } catch {
            return false
        }
    }

    /// Automatic recovery carries the old intent; it cannot replace a newer
    /// manual stop/start request while waiting for admission.
    func resumeSessionRuntime(expectedGeneration: UInt64) async -> Bool {
        guard sessionStartIsCurrent(expectedGeneration) else { return false }
        #if DEBUG
            testSessionRequestObserved?(expectedGeneration)
        #endif
        let resumed = await Task.detached { [self] in
            await admitSessionOperation(.start("Secure typing ended"), generation: expectedGeneration)
        }.value
        return sessionStartIsCurrent(expectedGeneration) && resumed
    }

    private func performSessionOperation(_ operation: SessionLifecycleOperation, generation: UInt64) async -> Bool {
        guard generation == sessionIntentGeneration else { return false }
        switch operation {
        case let .start(reason):
            return await startSessionAdmitted(reason: reason, generation: generation)
        case let .stop(reason):
            return await stopSessionAdmitted(reason: reason)
        case let .restart(reason):
            guard admitSessionConfiguration(), sessionStartIsCurrent(generation) else { return false }
            guard await stopSessionAdmitted(reason: "\(reason) (stop for restart)"),
                  sessionStartIsCurrent(generation) else { return false }
            return await startSessionAdmitted(reason: "\(reason) (restart)", generation: generation)
        }
    }

    /// Read the unchanged current file once per admission, before any owned stop
    /// or launch. Worker validation remains the final check at execution time.
    @discardableResult
    func refreshSessionConfigurationAdmission() -> KanataHostBridgeValidationResult {
        let result: KanataHostBridgeValidationResult
        #if DEBUG
            if let validate = testSessionConfigurationValidation {
                result = validate()
            } else if TestEnvironment.isTestHostProcess {
                result = .valid
            } else {
                result = readSessionConfigurationAdmission()
            }
        #else
            result = readSessionConfigurationAdmission()
        #endif
        sessionConfigurationAdmission = result
        return result
    }

    private func readSessionConfigurationAdmission() -> KanataHostBridgeValidationResult {
        let path = KeyPathConstants.Config.mainConfigPath
        guard FileManager.default.fileExists(atPath: path) else {
            return .unavailable(reason: "User configuration is not available yet")
        }
        return SessionCapsRuntimeSupport.validate(configPath: path, runtimeHost: .current()).result
    }

    var sessionConfigurationRefusal: String? {
        guard case .invalid = sessionConfigurationAdmission else { return nil }
        return sessionConfigurationAdmission.flatMap(SessionCapsRuntimeSupport.startupFailureMessage)
    }

    /// A rejected edited file does not invalidate an already owned running tap.
    /// No-start and skipped-start paths still get current admission before UI polling.
    func configurationRefusalForStartup() -> String? {
        if let report = currentSessionReport(), report.state == .running, report.tapActive { return nil }
        refreshSessionConfigurationAdmission()
        return sessionConfigurationRefusal
    }

    private func admitSessionConfiguration() -> Bool {
        let admission = refreshSessionConfigurationAdmission()
        guard case .valid = admission else {
            onError?(SessionCapsRuntimeSupport.startupFailureMessage(admission))
            onStateChanged?()
            return false
        }
        return true
    }

    private func startSessionAdmitted(reason: String, generation: UInt64) async -> Bool {
        guard sessionStartIsCurrent(generation), admitSessionConfiguration(),
              sessionStartIsCurrent(generation) else { return false }
        stopGraceUntil = nil
        lastStartAttemptAt = Date()
        isStartingKanata = true
        defer { isStartingKanata = false }
        #if DEBUG
            if let start = Self.testSessionStart {
                let result = await start(reason)
                guard sessionStartIsCurrent(generation) else {
                    // The seam represents a launch that can complete after
                    // cancellation, just like NSWorkspace. Cleanup stays admitted.
                    _ = await stopSessionAdmitted(reason: "Superseded start")
                    return false
                }
                return result
            }
        #endif
        return await startSessionRuntime(reason: reason, generation: generation)
    }

    func stopSessionAdmitted(reason: String) async -> Bool {
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

    func isInTransientRuntimeStartupWindow() async -> Bool {
        if sessionConfigurationRefusal != nil,
           currentSessionReport()?.state != .running { return false }
        return windowEvaluator.isInWindow(
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
        guard let report = currentSessionReport() else {
            if let admission = sessionConfigurationAdmission,
               let reason = SessionCapsRuntimeSupport.startupFailureMessage(admission) {
                return .failed(reason: reason)
            }
            return .stopped
        }
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
