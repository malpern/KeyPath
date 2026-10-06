@testable import KeyPathAppKit
@testable import KeyPathCore
@testable import KeyPathInstallationWizard
import KeyPathPermissions
@testable import KeyPathWizardCore
@preconcurrency import XCTest

@MainActor
final class ServiceLifecycleCoordinatorTests: KeyPathTestCase {
    private var coordinator: ServiceLifecycleCoordinator!
    private var capturedErrors: [String?] = []
    private var capturedWarnings: [String?] = []
    private var stateChangeCount = 0

    override func setUp() async throws {
        try await super.setUp()
        coordinator = ServiceLifecycleCoordinator(
            kanataDaemonService: KanataDaemonService(),
            recoveryCoordinator: RecoveryCoordinator()
        )
        capturedErrors = []
        capturedWarnings = []
        stateChangeCount = 0

        coordinator.onError = { [unowned self] error in
            capturedErrors.append(error)
        }
        coordinator.onWarning = { [unowned self] warning in
            capturedWarnings.append(warning)
        }
        coordinator.onStateChanged = { [unowned self] in
            stateChangeCount += 1
        }
    }

    func testCapsSelectionRefusalPreservesConsentAndRequiresSuccessfulCleanup() async {
        var commits = 0
        var verifications = 0
        ServiceLifecycleCoordinator.testSessionStop = { false }
        defer { ServiceLifecycleCoordinator.testSessionStop = nil }
        let stopped = await coordinator.changeCapsSelection(verify: {}, commit: { commits += 1 })
        XCTAssertFalse(stopped)
        XCTAssertEqual(commits, 0)
        ServiceLifecycleCoordinator.testSessionStop = { true }
        let refused = await coordinator.changeCapsSelection(verify: { throw SessionCapsRuntimeSupport.Refusal.selection }, commit: { commits += 1 })
        XCTAssertFalse(refused)
        XCTAssertEqual(commits, 0)
        let changed = await coordinator.changeCapsSelection(verify: {}, commit: { commits += 1; verifications += 1 })
        XCTAssertTrue(changed)
        XCTAssertEqual(commits, 1)
        XCTAssertEqual(verifications, 1)
        XCTAssertFalse(coordinator.sessionWantsRunning)
        coordinator.setUpdatePreparationActive(true)
        let updating = await coordinator.changeCapsSelection(verify: {}, commit: { commits += 1 })
        XCTAssertFalse(updating)
        XCTAssertEqual(commits, 1)
    }

    func testUpdatePreparationRefusesQueuedAndNewStartsUntilReleased() async {
        coordinator.testSessionConfigurationValidation = { .valid }
        var launches = 0
        ServiceLifecycleCoordinator.testSessionStart = { _ in launches += 1; return true }
        defer { ServiceLifecycleCoordinator.testSessionStart = nil }
        let coordinator = coordinator!
        let generation = coordinator.sessionIntentGeneration
        let blocker = Task { @MainActor in
            try await coordinator.sessionOperationGate.withOperation { _ in
                let start = Task { @MainActor in await coordinator.startKanata() }
                while await coordinator.sessionIntentGeneration == generation { await Task.yield() }
                await coordinator.setUpdatePreparationActive(true)
                return start
            }
        }
        let queued = try! await blocker.value
        let queuedResult = await queued.value
        XCTAssertFalse(queuedResult)
        let started = await coordinator.startKanata()
        let restarted = await coordinator.restartKanata()
        let resumed = await coordinator.resumeSessionRuntime(expectedGeneration: coordinator.sessionIntentGeneration)
        XCTAssertFalse(started)
        XCTAssertFalse(restarted)
        XCTAssertFalse(resumed)
        XCTAssertEqual(launches, 0)
        coordinator.setUpdatePreparationActive(false)
        let retry = await coordinator.startKanata()
        XCTAssertTrue(retry)
        XCTAssertEqual(launches, 1)
    }

    func testTerminationPreparationSurvivesUpdateAbortAndRefusesQueuedStartsButAllowsStop() async throws {
        coordinator.testSessionConfigurationValidation = { .valid }
        var launches = 0, stops = 0
        ServiceLifecycleCoordinator.testSessionStart = { _ in launches += 1; return true }
        ServiceLifecycleCoordinator.testSessionStop = { stops += 1; return true }
        defer {
            ServiceLifecycleCoordinator.testSessionStart = nil
            ServiceLifecycleCoordinator.testSessionStop = nil
        }
        let coordinator = coordinator!
        let generation = coordinator.sessionIntentGeneration
        let blocker = Task { @MainActor in
            try await coordinator.sessionOperationGate.withOperation { _ in
                let start = Task { @MainActor in await coordinator.startKanata() }
                while await coordinator.sessionIntentGeneration == generation {
                    await Task.yield()
                }
                await coordinator.setTerminationPreparationActive(true)
                let heldGeneration = await coordinator.sessionIntentGeneration
                await coordinator.setTerminationPreparationActive(true)
                let repeatedGeneration = await coordinator.sessionIntentGeneration
                XCTAssertEqual(heldGeneration, repeatedGeneration)
                await coordinator.setUpdatePreparationActive(true)
                await coordinator.setUpdatePreparationActive(false)
                return start
            }
        }
        let queued = try await blocker.value
        let queuedResult = await queued.value
        XCTAssertFalse(queuedResult)
        let started = await coordinator.startKanata()
        let restarted = await coordinator.restartKanata()
        let resumed = await coordinator.resumeSessionRuntime(expectedGeneration: coordinator.sessionIntentGeneration)
        XCTAssertFalse(started)
        XCTAssertFalse(restarted)
        XCTAssertFalse(resumed)
        XCTAssertEqual(launches, 0)
        let stopped = await coordinator.stopKanata(reason: "Termination cleanup")
        XCTAssertTrue(stopped)
        XCTAssertEqual(stops, 1)
        coordinator.setTerminationPreparationActive(false)
        let retry = await coordinator.startKanata()
        XCTAssertTrue(retry)
        XCTAssertEqual(launches, 1)
    }

    func testUpdateHoldSurvivesCancelledTermination() async {
        coordinator.testSessionConfigurationValidation = { .valid }
        var launches = 0
        ServiceLifecycleCoordinator.testSessionStart = { _ in launches += 1; return true }
        defer { ServiceLifecycleCoordinator.testSessionStart = nil }
        coordinator.setUpdatePreparationActive(true)
        coordinator.setTerminationPreparationActive(true)
        coordinator.setTerminationPreparationActive(false)
        let blocked = await coordinator.startKanata()
        XCTAssertFalse(blocked)
        XCTAssertEqual(launches, 0)
        coordinator.setUpdatePreparationActive(false)
        let started = await coordinator.startKanata()
        XCTAssertTrue(started)
        XCTAssertEqual(launches, 1)
    }

    func testRecoveryRefusalSurvivesNoWorkerStartAndRestartThenClearsOnRecovery() async {
        coordinator.testSessionConfigurationValidation = { .valid }
        ServiceLifecycleCoordinator.testSessionStart = nil
        ServiceLifecycleCoordinator.testSessionStop = nil
        var recoveries = 0
        coordinator.testSessionCapsRecovery = {
            recoveries += 1
            throw SessionCapsMappingLease.Refusal.mutationUncertain
        }
        let started = await coordinator.startKanata(reason: "retained marker")
        XCTAssertFalse(started)
        let restarted = await coordinator.restartKanata(reason: "retained marker retry")
        XCTAssertFalse(restarted)
        XCTAssertEqual(recoveries, 2)
        XCTAssertNil(coordinator.currentSessionReport())
        XCTAssertFalse(coordinator.isStartingKanata)
        let grace = await coordinator.isInTransientRuntimeStartupWindow()
        XCTAssertFalse(grace)
        let status = await coordinator.currentRuntimeStatus()
        guard case let .failed(reason) = status else { return XCTFail("Recovery failure became stopped") }
        XCTAssertTrue(reason.contains("recovery record was retained"))
        XCTAssertEqual(capturedErrors.compactMap { $0 }.last, reason)
        XCTAssertGreaterThanOrEqual(stateChangeCount, 2)

        coordinator.testSessionCapsRecovery = {}
        let recovered = await coordinator.restoreSessionCaps(for: nil)
        XCTAssertTrue(recovered)
        XCTAssertNil(coordinator.recoveryRefusalForStartup)
        let cleared = await coordinator.currentRuntimeStatus()
        XCTAssertEqual(cleared, .stopped)
    }

    func testUnsupportedConfigurationRefusesBeforeLaunchAndPersistsFailure() async {
        let privileged = StubPrivilegedOperationsCoordinator()
        WizardDependencies.privilegedOperations = privileged
        var launches = 0
        coordinator.testSessionConfigurationValidation = { .invalid(reason: "Caps Lock remapping requires the advanced driver backend") }
        ServiceLifecycleCoordinator.testSessionStart = { _ in launches += 1; return true }
        let admissionResult1 = await coordinator.startKanata(reason: "unsupported config")
        XCTAssertFalse(admissionResult1)
        XCTAssertEqual(launches, 0)
        XCTAssertTrue(privileged.calls.isEmpty)
        XCTAssertFalse(coordinator.isStartingKanata)
        let admissionResult2 = await coordinator.isInTransientRuntimeStartupWindow()
        XCTAssertFalse(admissionResult2)
        guard case let .failed(reason) = await coordinator.currentRuntimeStatus() else {
            return XCTFail("The refusal must survive absence of a worker report")
        }
        XCTAssertTrue(reason.contains("Caps Lock remapping requires the advanced driver backend"))
        XCTAssertTrue(reason.contains("Edit the configuration"))
        XCTAssertTrue(reason.contains("existing rules were preserved"))
    }

    func testValidRetryClearsConfigurationRefusal() async {
        coordinator.testSessionConfigurationValidation = { .invalid(reason: "unsupported action") }
        let admissionResult3 = await coordinator.startKanata()
        XCTAssertFalse(admissionResult3)
        coordinator.testSessionConfigurationValidation = { .valid }
        var launches = 0
        ServiceLifecycleCoordinator.testSessionStart = { _ in launches += 1; return true }
        let admissionResult4 = await coordinator.startKanata(reason: "corrected config")
        XCTAssertTrue(admissionResult4)
        XCTAssertEqual(launches, 1)
        XCTAssertNil(coordinator.sessionConfigurationRefusal)
        XCTAssertEqual(coordinator.sessionConfigurationAdmission, .valid)
    }

    func testUnavailableValidationIsNotUnsupportedConfiguration() async {
        coordinator.testSessionConfigurationValidation = { .unavailable(reason: "bridge library missing") }
        var launches = 0
        ServiceLifecycleCoordinator.testSessionStart = { _ in launches += 1; return true }
        let admissionResult5 = await coordinator.startKanata()
        XCTAssertFalse(admissionResult5)
        XCTAssertEqual(launches, 0)
        XCTAssertNil(coordinator.sessionConfigurationRefusal)
        let admissionResult6 = await coordinator.isInTransientRuntimeStartupWindow()
        XCTAssertFalse(admissionResult6, "Completed validation refusal has no pending session start")
        guard case let .failed(reason) = await coordinator.currentRuntimeStatus() else {
            return XCTFail("Validation coverage failure must remain visible")
        }
        XCTAssertTrue(reason.contains("validation is unavailable"))
        XCTAssertFalse(reason.contains("cannot run"))
    }

    func testInvalidRestartPreservesOwnedRunningTapUntilExplicitStop() async {
        let report = SessionRuntimeReport(nonce: "owned", pid: 100, uid: 501, state: .running,
                                         accessibility: true, effectiveInputAccess: true, tapActive: true,
                                         tcpPort: 37001, inputCount: 1, outputCount: 1, timestamp: Date())
        coordinator.testSessionCurrentReport = { report }
        var validations = 0, stops = 0
        coordinator.testSessionConfigurationValidation = { validations += 1; return .invalid(reason: "edited config unsupported") }
        ServiceLifecycleCoordinator.testSessionStop = { stops += 1; return true }
        let admissionResult7 = await coordinator.restartKanata(reason: "invalid edit")
        XCTAssertFalse(admissionResult7)
        XCTAssertEqual(stops, 0)
        let liveStatus = await coordinator.currentRuntimeStatus()
        XCTAssertEqual(liveStatus, .running(pid: 100))
        XCTAssertNil(coordinator.configurationRefusalForStartup())
        XCTAssertEqual(validations, 1, "Readiness must use the owned live tap rather than reparsing edited input")
        let admissionResult8 = await coordinator.stopKanata(reason: "explicit stop")
        XCTAssertTrue(admissionResult8)
        XCTAssertEqual(stops, 1, "Refusal must not bypass owned stop/restore admission")
    }

    func testRejectedStartAndRestartTransferRetainedTapSupervisionToLatestIntent() async {
        let report = SessionRuntimeReport(nonce: "owned", pid: 100, uid: 501, state: .running,
                                         accessibility: true, effectiveInputAccess: true, tapActive: true,
                                         tcpPort: 37001, inputCount: 1, outputCount: 1, timestamp: Date())
        coordinator.testSessionCurrentReport = { report }
        coordinator.testSessionConfigurationValidation = { .valid }
        coordinator.testSessionRunningReadiness = { true }
        var supervised: [UInt64] = []
        coordinator.testSessionSupervisionStarted = { supervised.append($0) }
        ServiceLifecycleCoordinator.testSessionStart = nil
        let adopted = await coordinator.startKanata(reason: "adopt existing tap")
        XCTAssertTrue(adopted)
        XCTAssertEqual(supervised, [1])

        var starts = 0, stops = 0
        ServiceLifecycleCoordinator.testSessionStart = { _ in starts += 1; return true }
        ServiceLifecycleCoordinator.testSessionStop = { stops += 1; return true }
        coordinator.testSessionConfigurationValidation = { .invalid(reason: "edited config unsupported") }
        let refusedStart = await coordinator.startKanata(reason: "invalid edited start")
        let refusedRestart = await coordinator.restartKanata(reason: "invalid edited restart")
        XCTAssertFalse(refusedStart)
        XCTAssertFalse(refusedRestart)
        XCTAssertEqual(starts, 0)
        XCTAssertEqual(stops, 0)
        XCTAssertEqual(supervised, [1, 2, 3], "Each rejected intent must retain supervision of the owned tap")
        XCTAssertEqual(supervised.last, coordinator.sessionIntentGeneration)
        XCTAssertFalse(coordinator.sessionStartIsCurrent(1), "Never roll back a rejected intent")
        XCTAssertTrue(coordinator.sessionStartIsCurrent(3))

        let stopped = await coordinator.stopKanata(reason: "explicit stop supersedes refusal")
        XCTAssertTrue(stopped)
        XCTAssertEqual(stops, 1)
        XCTAssertFalse(coordinator.sessionStartIsCurrent(3))
        XCTAssertEqual(supervised, [1, 2, 3], "A stop must not rebind running supervision")
    }

    func testRejectedConfigurationRetainsSupervisionWithoutCurrentHeartbeat() async {
        // The supervisor seam observes transfer before production checks the
        // retained application/nonce. A missing report must not suppress it.
        coordinator.testSessionCurrentReport = { nil }
        coordinator.testSessionConfigurationValidation = { .valid }
        coordinator.testSessionRunningReadiness = { true }
        var supervised: [UInt64] = []
        coordinator.testSessionSupervisionStarted = { supervised.append($0) }
        ServiceLifecycleCoordinator.testSessionStart = nil
        let adopted = await coordinator.startKanata(reason: "adopt retained ownership")
        XCTAssertTrue(adopted)

        var starts = 0, stops = 0
        ServiceLifecycleCoordinator.testSessionStart = { _ in starts += 1; return true }
        ServiceLifecycleCoordinator.testSessionStop = { stops += 1; return true }
        coordinator.testSessionConfigurationValidation = { .invalid(reason: "unsupported edit") }
        let refusedStart = await coordinator.startKanata()
        let refusedRestart = await coordinator.restartKanata()
        XCTAssertFalse(refusedStart)
        XCTAssertFalse(refusedRestart)
        XCTAssertEqual(supervised, [1, 2, 3], "Stale or terminal workers still need cleanup under current intent")
        XCTAssertEqual(supervised.last, coordinator.sessionIntentGeneration)
        XCTAssertEqual(starts, 0)
        XCTAssertEqual(stops, 0)
    }

    func testOwnedRuntimeEvidenceWinsWhenCapabilityProbeFinishesLater() async {
        let deniedProbe = PermissionOracle.PermissionSet(
            accessibility: .denied, inputMonitoring: .denied,
            source: "earlier-capability-probe", confidence: .high, timestamp: Date()
        )
        for probeResult: PermissionOracle.PermissionSet? in [nil, deniedProbe] {
            var ownedReport: SessionRuntimeReport?
            var probes = 0
            coordinator.testSessionCurrentReport = { ownedReport }
            coordinator.testSessionCapabilityProbe = {
                probes += 1
                await Task.yield()
                ownedReport = SessionRuntimeReport(
                    nonce: "owned-after-probe-start", pid: 100, uid: 501, state: .running,
                    accessibility: true, effectiveInputAccess: true, tapActive: true,
                    tcpPort: 37001, inputCount: 0, outputCount: 0, timestamp: Date()
                )
                return probeResult
            }
            let permissions = await coordinator.sessionCapabilities()
            XCTAssertEqual(probes, 1)
            XCTAssertEqual(permissions?.accessibility, .granted)
            XCTAssertEqual(permissions?.inputMonitoring, .granted)
            XCTAssertNotEqual(permissions?.source, deniedProbe.source)
        }
    }

    func testMissingOwnedEvidenceDoesNotUpgradeCapabilityProbeResult() async {
        coordinator.testSessionCurrentReport = { nil }
        coordinator.testSessionCapabilityProbe = { await Task.yield(); return nil }
        let unavailable = await coordinator.sessionCapabilities()
        XCTAssertNil(unavailable)

        let deniedProbe = PermissionOracle.PermissionSet(
            accessibility: .denied, inputMonitoring: .denied,
            source: "current-capability-probe", confidence: .high, timestamp: Date()
        )
        coordinator.testSessionCapabilityProbe = { await Task.yield(); return deniedProbe }
        let denied = await coordinator.sessionCapabilities()
        XCTAssertEqual(denied?.accessibility, .denied)
        XCTAssertEqual(denied?.inputMonitoring, .denied)
        XCTAssertEqual(denied?.source, deniedProbe.source)
    }

    // MARK: - Session lifecycle routing

    func testStartUsesSessionOwnerWithoutPrivilegedFallbackOnFailure() async {
        let privileged = StubPrivilegedOperationsCoordinator()
        WizardDependencies.privilegedOperations = privileged
        var reasons: [String] = []
        ServiceLifecycleCoordinator.testSessionStart = { reason in
            reasons.append(reason)
            XCTAssertTrue(self.coordinator.isStartingKanata)
            return false
        }
        let started = await coordinator.startKanata(reason: "session failure")
        XCTAssertFalse(started)
        XCTAssertEqual(reasons, ["session failure"])
        XCTAssertTrue(privileged.calls.isEmpty)
        XCTAssertFalse(coordinator.isStartingKanata)
    }

    func testValidationUsesSessionStart() async {
        var reasons: [String] = []
        ServiceLifecycleCoordinator.testSessionStart = { reason in
            reasons.append(reason)
            return false
        }
        await coordinator.startKanataWithValidation()
        XCTAssertEqual(reasons, ["Session validation start"])
    }

    func testStopUsesOnlySessionOwner() async {
        let privileged = StubPrivilegedOperationsCoordinator()
        WizardDependencies.privilegedOperations = privileged
        ServiceLifecycleCoordinator.testSessionStop = {
            self.coordinator.onStateChanged?()
            return true
        }
        let stopped = await coordinator.stopKanata(reason: "test")
        XCTAssertTrue(stopped)
        XCTAssertTrue(privileged.calls.isEmpty)
        XCTAssertGreaterThan(stateChangeCount, 0)
    }

    // MARK: - Stop

    func testStopNotifiesStateChange() async {
        ServiceLifecycleCoordinator.testSessionStop = { self.coordinator.onStateChanged?(); return true }
        let result = await coordinator.stopKanata(reason: "test")

        XCTAssertTrue(result)
        XCTAssertGreaterThan(stateChangeCount, 0)
    }

    // MARK: - Intentional-transition gate (#625)

    func testNotInIntentionalTransitionWhenIdle() {
        // A fresh coordinator that hasn't stopped anything is not transitioning, so a
        // grab failure observed now is genuine and eligible for recovery.
        XCTAssertFalse(coordinator.isIntentionalTransitionInProgress)
    }

    func testIntentionalTransitionFlagSetDuringStop() async {
        // The flag must be closed *while the stop runs*, so a benign `active=false`
        // from the dying kanata is suppressed. We observe it from the onStateChanged
        // callback, which fires inside stopKanata before its `defer` opens the grace.
        var seenDuringStop: Bool?
        coordinator.onStateChanged = { [unowned self] in
            if seenDuringStop == nil {
                seenDuringStop = coordinator.isIntentionalTransitionInProgress
            }
        }

        ServiceLifecycleCoordinator.testSessionStop = { self.coordinator.onStateChanged?(); return true }
        _ = await coordinator.stopKanata(reason: "test")

        XCTAssertEqual(seenDuringStop, true, "Transition gate must be closed during the stop")
    }

    func testIntentionalTransitionGraceHoldsBrieflyAfterStop() async {
        // Immediately after stop returns, the short trailing grace keeps the gate closed
        // so a late last-gasp `active=false` from the just-killed kanata is still suppressed.
        _ = await coordinator.stopKanata(reason: "test")
        XCTAssertTrue(
            coordinator.isIntentionalTransitionInProgress,
            "Gate should remain closed during the post-stop grace window"
        )
    }

    func testStartClearsLingeringStopGrace() async {
        // The stop-grace exists only to swallow the OLD process's last gasp. Once a new
        // start begins (e.g. the start phase of a restart), the grace must end so a
        // genuine `active=false` from the freshly started kanata is NOT masked as benign.
        _ = await coordinator.stopKanata(reason: "stop for restart")
        XCTAssertTrue(coordinator.isIntentionalTransitionInProgress, "Grace armed after stop")

        _ = await coordinator.startKanata(reason: "restart")

        XCTAssertFalse(
            coordinator.isIntentionalTransitionInProgress,
            "Starting a new kanata must clear the stale stop-grace so post-start grab failures are caught"
        )
    }

    func testPostStartReadinessAcceptsLiveRuntimeDespiteStaleRegistrationMetadata() {
        let snapshot = ServiceHealthChecker.KanataServiceRuntimeSnapshot(
            managementState: .smappserviceActive,
            isRunning: true,
            isResponding: true,
            inputCaptureReady: true,
            inputCaptureIssue: nil,
            launchctlExitCode: 0,
            staleEnabledRegistration: true,
            recentlyRestarted: false
        )

        XCTAssertTrue(
            ServiceLifecycleCoordinator.shouldAcceptPostStartRuntime(snapshot),
            "Current process, TCP, and input-capture evidence must outrank stale registration metadata"
        )
    }

    // MARK: - Restart

    func testRestartCallsSessionStopThenStart() async {
        var operations: [String] = []
        ServiceLifecycleCoordinator.testSessionStop = { operations.append("stop"); return true }
        ServiceLifecycleCoordinator.testSessionStart = { _ in operations.append("start"); return true }
        let restarted = await coordinator.restartKanata(reason: "test restart")
        XCTAssertTrue(restarted)
        XCTAssertEqual(operations, ["stop", "start"])
    }

    func testRestartRefusesStartAfterSessionStopFailure() async {
        var startCalls = 0
        ServiceLifecycleCoordinator.testSessionStop = { false }
        ServiceLifecycleCoordinator.testSessionStart = { _ in startCalls += 1; return true }
        let restarted = await coordinator.restartKanata(reason: "test restart")
        XCTAssertFalse(restarted)
        XCTAssertEqual(startCalls, 0)
    }

    // MARK: - Runtime Status

    func testRuntimeStatusReportsStartingDuringStart() async {
        coordinator.isStartingKanata = true

        let status = await coordinator.currentRuntimeStatus()

        XCTAssertEqual(status, .starting)
    }

    func testRuntimeStatusReportsStoppedWhenDaemonNotRunning() async {
        // In test env, daemon is not running
        let status = await coordinator.currentRuntimeStatus()

        // Should be stopped or unknown (not starting, not running)
        XCTAssertFalse(status.isRunning)
        XCTAssertNotEqual(status, .starting)
    }

    // MARK: - Startup Window

    func testTransientStartupWindowDuringStart() async {
        coordinator.isStartingKanata = true

        let inWindow = await coordinator.isInTransientRuntimeStartupWindow()

        XCTAssertTrue(inWindow, "Should be in startup window while start is in progress")
    }

    func testCompletedPermissionRefusalExposesStoppedStateUntilExplicitRetry() async {
        coordinator.testSessionConfigurationValidation = { .valid }
        var permissionsGranted = false
        var starts = 0
        ServiceLifecycleCoordinator.testSessionStart = { _ in
            starts += 1
            let transient = await self.coordinator.isInTransientRuntimeStartupWindow()
            let status = await self.coordinator.currentRuntimeStatus()
            XCTAssertTrue(transient, "An admitted start is transient while its result is pending")
            XCTAssertEqual(status, .starting)
            return permissionsGranted
        }
        defer { ServiceLifecycleCoordinator.testSessionStart = nil }

        let denied = await coordinator.startKanata(reason: "Automatic start before permission grant")
        XCTAssertFalse(denied)
        permissionsGranted = true
        let status = await coordinator.currentRuntimeStatus()
        let transient = await coordinator.isInTransientRuntimeStartupWindow()
        XCTAssertEqual(status, .stopped)
        XCTAssertFalse(transient, "A completed refusal cannot hide the wizard's Start action")
        XCTAssertFalse(ServiceStatusEvaluator.shouldRetryTransientStatus(
            runtimeStatus: .stopped, isInTransientStartupWindow: transient, completedAttempts: 1
        ))
        XCTAssertFalse(ServiceStatusEvaluator.didExhaustTransientStatus(
            runtimeStatus: .stopped, isInTransientStartupWindow: transient, completedAttempts: 30
        ))
        XCTAssertEqual(starts, 1, "Permission grant alone does not request another start")

        let retried = await coordinator.startKanata(reason: "Wizard explicit Start after permission grant")
        XCTAssertTrue(retried)
        XCTAssertEqual(starts, 2)
        let afterRetry = await coordinator.isInTransientRuntimeStartupWindow()
        XCTAssertFalse(afterRetry)
    }

    func testNotInStartupWindowWhenIdle() async {
        coordinator.isStartingKanata = false

        let inWindow = await coordinator.isInTransientRuntimeStartupWindow()

        XCTAssertFalse(inWindow, "A newly created idle session has no pending start")
    }
}
