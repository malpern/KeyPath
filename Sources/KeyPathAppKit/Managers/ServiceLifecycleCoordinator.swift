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
    /// The managed-Caps intermediate the current session was launched with.
    var sessionCapsIntermediate: UInt32?
    /// Why the current session runs with Caps Lock rules paused, worded for
    /// the user; nil when Caps is managed, not needed, or turned off.
    var sessionCapsPaused: String?
    /// One-time notice for the session start that follows (shown as a warning).
    var sessionCapsNotice: String?
    /// The chosen Caps keyboard disconnected while its session ran. Cleared
    /// once Caps runs on a keyboard again or the user changes the setup.
    var sessionCapsDisconnectedName: String?
    /// Watches for that keyboard to come back at the same port.
    var sessionCapsReconnectTask: Task<Void, Never>?
    var sessionOutputsRecovered = false
    private(set) var sessionConfigurationAdmission: KanataHostBridgeValidationResult?
    var sessionSupervisionTask: Task<Void, Never>?
    var sessionCleanupTask: Task<Void, Never>?
    var sessionTerminationGuard: SessionCapsMappingLease.TerminationGuard?
    var sessionWakeRecoveryRevision: UInt64 = 0
    var sessionWakeRecovery: (generation: UInt64, id: UUID)?
    var isRecoveringFromSystemWake: Bool {
        guard let recovery = sessionWakeRecovery else { return false }
        return recovery.generation == sessionIntentGeneration && sessionWantsRunning
            && recoveryRefusalForStartup == nil && sessionConfigurationRefusal == nil
    }

    var sessionWakeEpoch: UInt64 = 0
    var sessionLaunchWakeEpoch: UInt64 = 0
    /// Set only after an owned held-key startup refusal has been fully cleaned up.
    var sessionWakeRetryGeneration: UInt64?
    var sessionLastWakeSignalAt: Date?
    private var sessionWakeObservationTasks: [Task<Void, Never>] = []
    // Process ownership is serialized across suspension points, independently of
    // configuration persistence. Intent changes immediately, before admission.
    let sessionOperationGate = ConfigurationOperationGate()
    private(set) var sessionIntentGeneration: UInt64 = 0
    private(set) var sessionWantsRunning = false
    private var updatePreparationActive = false
    private var terminationPreparationActive = false
    var startsSuppressed: Bool {
        updatePreparationActive || terminationPreparationActive
    }

    /// Updates hold the runtime stopped until installation ends or is aborted.
    /// Invalidate requests already waiting for lifecycle admission as well.
    func setUpdatePreparationActive(_ active: Bool) {
        guard updatePreparationActive != active else { return }
        updatePreparationActive = active
        if active {
            sessionIntentGeneration &+= 1
            sessionWantsRunning = false
        }
    }

    /// Termination and update holds are independent: an updater abort must not
    /// release starts while graceful Quit is still waiting for its cleanup.
    func setTerminationPreparationActive(_ active: Bool) {
        guard terminationPreparationActive != active else { return }
        terminationPreparationActive = active
        if active {
            sessionIntentGeneration &+= 1
            sessionWantsRunning = false
        }
    }

    enum SessionLifecycleOperation: Sendable {
        case start(String), stop(String), restart(String)
    }

    func sessionStartIsCurrent(_ generation: UInt64) -> Bool {
        !startsSuppressed && generation == sessionIntentGeneration && sessionWantsRunning && !Task.isCancelled
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
        var testSessionCapabilityProbe: (() async -> PermissionOracle.PermissionSet?)?
        var testSessionConfigurationValidation: (() -> KanataHostBridgeValidationResult)?
        var testSessionRequestObserved: ((UInt64) -> Void)?
        var testSessionRunningReadiness: (@MainActor () async -> Bool)?
        var testSessionSupervisionStarted: ((UInt64) -> Void)?
        var testSessionCapsRecovery: (() async throws -> Void)?
        var testSessionCapsPreparation: (() async throws -> Void)?
        var testSessionWakeReady: (() -> Bool)?
        var testSessionWakeWait: (() async -> Void)?
    #endif

    /// Mutable flag shared with RuntimeCoordinator to track in-progress start attempts.
    var isStartingKanata = false
    /// A completed recovery refusal survives absence of a worker report.
    var sessionRecoveryRefusal: String?

    var recoveryRefusalForStartup: String? {
        if let report = currentSessionReport(), report.state == .running, report.tapActive { return nil }
        return sessionRecoveryRefusal
    }

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

    // MARK: - Callbacks (set by RuntimeCoordinator after init)

    /// Called when an error should be surfaced to the UI.
    var onError: ((String?) -> Void)?

    /// Called when a warning should be surfaced to the UI.
    var onWarning: ((String?) -> Void)?

    /// Called to notify the UI of a state change.
    var onStateChanged: (() -> Void)?

    /// Called at each session start with what admission learned about Caps
    /// Lock (phase 4d); `RuntimeCoordinator` hands it to the rules manager.
    var onAdmissionEnvironment: ((AdmissionEngine.Environment) -> Void)?

    // MARK: - Init

    init(
        kanataDaemonService: KanataDaemonService,
        recoveryCoordinator _: RecoveryCoordinator
    ) {
        self.kanataDaemonService = kanataDaemonService
        for name in [NSWorkspace.didWakeNotification, NSWorkspace.screensDidWakeNotification,
                     NSWorkspace.sessionDidBecomeActiveNotification]
        {
            let notifications = NSWorkspace.shared.notificationCenter.notifications(named: name)
            sessionWakeObservationTasks.append(Task { [weak self] in
                for await _ in notifications {
                    guard !Task.isCancelled else { return }
                    self?.observeSessionWake(name)
                }
            })
        }
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

    func observeSessionWake(_ name: Notification.Name, at date: Date = Date()) {
        guard [NSWorkspace.didWakeNotification, NSWorkspace.screensDidWakeNotification,
               NSWorkspace.sessionDidBecomeActiveNotification].contains(name) else { return }
        sessionWakeEpoch &+= 1
        sessionLastWakeSignalAt = date
        AppLogger.shared.info("[SessionRuntime] Recovery wake signal: \(name.rawValue)")
    }

    deinit {
        sessionWakeObservationTasks.forEach { $0.cancel() }
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

    /// A preference change cannot race an owned Caps lease or a queued launch.
    /// Restore first, then verify the proposed selection, then commit consent.
    func changeCapsSelection(verify: @escaping @Sendable () async throws -> Void,
                             commit: @escaping @MainActor @Sendable () throws -> Void) async -> Bool
    {
        guard !startsSuppressed, !Task.isCancelled else { return false }
        sessionIntentGeneration &+= 1
        let generation = sessionIntentGeneration
        sessionWantsRunning = false
        do {
            return try await sessionOperationGate.withOperation { [self] _ in
                guard await generation == sessionIntentGeneration else { return false }
                guard await stopSessionAdmitted(reason: "Caps Lock setup changed") else { return false }
                try await verify()
                return try await commitCapsSelection(generation: generation, commit: commit)
            }
        } catch {
            onError?("Caps Lock setup could not be changed safely. Existing selection and recovery records were preserved.")
            return false
        }
    }

    /// `changeCapsSelection` stops the runtime to release the Caps lease. Start it
    /// again if it was running before, whether the change committed or was refused,
    /// so remapping is never left off by a settings change.
    func resumeAfterCapsSelectionChange(wasRunning: Bool) async {
        guard wasRunning, !sessionWantsRunning else { return }
        await startKanata(reason: "Caps Lock setup changed")
    }

    private func commitCapsSelection(generation: UInt64, commit: @MainActor () throws -> Void) throws -> Bool {
        guard generation == sessionIntentGeneration, !startsSuppressed, !Task.isCancelled else { return false }
        try commit()
        sessionCapsDisconnectedName = nil
        // An explicit choice replaces any claim of a disconnected keyboard.
        SessionCapsSelectionStore.setDisplaced(nil, name: nil)
        refreshSessionConfigurationAdmission()
        onStateChanged?()
        return true
    }

    private func requestSessionOperation(_ operation: SessionLifecycleOperation) async -> Bool {
        if case .stop = operation {} else if startsSuppressed { return false }
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
    func resumeSessionRuntime(expectedGeneration: UInt64, reason: String = "Secure typing ended") async -> Bool {
        guard sessionStartIsCurrent(expectedGeneration) else { return false }
        #if DEBUG
            testSessionRequestObserved?(expectedGeneration)
        #endif
        let resumed = await Task.detached { [self] in
            await admitSessionOperation(.start(reason), generation: expectedGeneration)
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
            guard await prepareSessionStart(generation: generation) else { return false }
            guard await stopSessionAdmitted(reason: "\(reason) (stop for restart)"),
                  sessionStartIsCurrent(generation) else { return false }
            return await launchPreparedSession(reason: "\(reason) (restart)", generation: generation)
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
        return SessionCapsRuntimeSupport.validate(configPath: path, runtimeHost: .current(), requireSelection: false).result
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

    private func admitSessionConfiguration(generation: UInt64) -> Bool {
        let admission = refreshSessionConfigurationAdmission()
        guard case .valid = admission else {
            retainOwnedSessionSupervision(generation: generation)
            onError?(SessionCapsRuntimeSupport.startupFailureMessage(admission))
            onStateChanged?()
            return false
        }
        return true
    }

    /// Complete keyboard selection and parsed admission while the existing worker
    /// is still owned. A rejected setup must not interrupt its working mapping.
    private func prepareSessionStart(generation: UInt64) async -> Bool {
        guard sessionStartIsCurrent(generation) else { return false }
        do {
            try await prepareAutomaticCapsSelection(generation: generation)
        } catch {
            guard sessionStartIsCurrent(generation) else { return false }
            // No keyboard could be chosen for Caps Lock. The session still
            // starts: Caps Lock passes through and every other rule runs. The
            // launch words the pause for the user.
            AppLogger.shared.info("[Session] Caps keyboard not chosen automatically (\(error)); starting with Caps Lock rules paused")
        }
        guard sessionStartIsCurrent(generation), admitSessionConfiguration(generation: generation),
              sessionStartIsCurrent(generation) else { return false }
        return true
    }

    private func prepareAutomaticCapsSelection(generation: UInt64) async throws {
        #if DEBUG
            if let prepare = testSessionCapsPreparation {
                try await prepare()
                return
            }
        #endif
        guard !TestEnvironment.isTestHostProcess,
              SessionCapsRuntimeSupport.validate(configPath: KeyPathConstants.Config.mainConfigPath,
                                                 runtimeHost: .current(), requireSelection: false).managedCaps,
              !UserDefaults.standard.bool(forKey: SessionCapsRuntimeSupport.automaticSetupDisabledKey) else { return }
        let displaced = SessionCapsSelectionStore.displaced?.data
        let hasCurrent = (try? SessionCapsRuntimeSupport.selectedDevice()) != nil
        // A current choice stands unless a disconnected one may come back.
        guard !hasCurrent || displaced != nil else { return }
        let stored = UserDefaults.standard.data(forKey: SessionCapsRuntimeSupport.selectionKey)
        let found = try await Task.detached { () -> (choice: (SessionCapsSelection, String?, Bool)?, displacedStale: Bool) in
            let list = try SessionCapsHIDUtilTransport.keyboards()
            let boot = try SessionCapsRuntimeSupport.bootSessionUUID()
            let devices = list.keyboards.map(\.device)
            let stale = displaced.map { (try? SessionCapsSelection.decode($0, currentBoot: boot)) == nil } ?? false
            func named(_ selection: SessionCapsSelection) -> String? {
                list.keyboards.first { $0.device == selection.device }?.name
            }
            // The chosen keyboard back at the same port gets its choice back,
            // ahead of whatever automatic setup picked while it was away.
            if let rebound = SessionCapsRuntimeSupport.reboundSelection(selectionData: displaced, devices: devices, boot: boot)
                ?? SessionCapsRuntimeSupport.reboundSelection(selectionData: stored, devices: devices, boot: boot)
            {
                return ((rebound, named(rebound), true), stale)
            }
            if hasCurrent { return (nil, stale) }
            let selection = try SessionCapsRuntimeSupport.automaticSelection(devices: devices, withheld: list.withheld, boot: boot)
            return ((selection, named(selection), false), stale)
        }.value
        guard sessionStartIsCurrent(generation) else { throw CancellationError() }
        // A new boot ends any claim: a restart always asks again.
        if found.displacedStale { SessionCapsSelectionStore.setDisplaced(nil, name: nil) }
        guard let (selection, name, rebound) = found.choice else { return }
        try SessionCapsSelectionStore.save(selection)
        SessionCapsSelectionStore.saveName(name)
        if rebound {
            AppLogger.shared.info("[Session] Caps keyboard reconnected at the same port; keeping its choice")
            if sessionCapsDisconnectedName != nil || displaced != nil {
                sessionCapsNotice = "\(name ?? "Your keyboard") was reconnected. Caps Lock rules are back on."
            }
            sessionCapsDisconnectedName = nil
            SessionCapsSelectionStore.setDisplaced(nil, name: nil)
        }
    }

    private func startSessionAdmitted(reason: String, generation: UInt64) async -> Bool {
        guard await prepareSessionStart(generation: generation) else { return false }
        return await launchPreparedSession(reason: reason, generation: generation)
    }

    private func launchPreparedSession(reason: String, generation: UInt64) async -> Bool {
        guard sessionStartIsCurrent(generation) else { return false }
        stopGraceUntil = nil
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
                if result { await invalidatePermissionsForNewSessionRuntime() }
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
        if recoveryRefusalForStartup != nil { return false }
        if sessionConfigurationRefusal != nil,
           currentSessionReport()?.state != .running { return false }
        // Session starts are owned and awaited here. Once the attempt returns,
        // no service is starting in the background. A creation/attempt-age grace
        // would hide Start after a completed permission refusal.
        return isStartingKanata || isRecoveringFromSystemWake
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
            if let refusal = sessionRecoveryRefusal { return .failed(reason: refusal) }
            if let admission = sessionConfigurationAdmission,
               let reason = SessionCapsRuntimeSupport.startupFailureMessage(admission)
            {
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
