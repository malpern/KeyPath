import AppKit
@testable import KeyPathAppKit
import KeyPathCore
import KeyPathWizardCore
@preconcurrency import XCTest

/// No NSRunningApplication, process signal, CGEvent or host launch is used here.
/// The existing DEBUG operations are inside the production admission boundary.
@MainActor
final class SessionLifecycleInterleavingTests: KeyPathTestCase {
    private var coordinator: ServiceLifecycleCoordinator!

    @MainActor
    private final class Pause {
        private let entry = XCTestExpectation(description: "Lifecycle seam entered")
        private var released = false
        private var releaseWaiter: CheckedContinuation<Void, Never>?

        func suspend() async {
            // A timed-out entry wait may release before the seam finally enters.
            guard !released else { return }
            await withCheckedContinuation { continuation in
                releaseWaiter = continuation
                entry.fulfill()
            }
        }

        func waitUntilEntered() async {
            let outcome = await XCTWaiter.fulfillment(of: [entry], timeout: 5)
            if outcome != .completed {
                release()
                XCTFail("Lifecycle seam did not enter within five seconds")
            }
        }

        func release() {
            released = true
            releaseWaiter?.resume()
            releaseWaiter = nil
        }
    }

    override func setUp() async throws {
        try await super.setUp()
        coordinator = ServiceLifecycleCoordinator(
            kanataDaemonService: KanataDaemonService(),
            recoveryCoordinator: RecoveryCoordinator()
        )
    }

    private func nextRequest(_ operation: @escaping @MainActor () async -> Bool) async -> Task<Bool, Never> {
        let observed = XCTestExpectation(description: "Lifecycle request observed")
        coordinator.testSessionRequestObserved = { [self] _ in
            coordinator.testSessionRequestObserved = nil
            observed.fulfill()
        }
        let task = Task { @MainActor in await operation() }
        let outcome = await XCTWaiter.fulfillment(of: [observed], timeout: 5)
        if outcome != .completed {
            coordinator.testSessionRequestObserved = nil
            task.cancel()
            XCTFail("Lifecycle request was not observed within five seconds")
        }
        return task
    }

    private func completion<Value: Sendable>(of task: Task<Value, Never>, fallback: Value) async -> Value {
        let completed = XCTestExpectation(description: "Lifecycle task completed")
        var result: Value?
        let observer = Task { @MainActor in
            result = await task.value
            completed.fulfill()
        }
        let outcome = await XCTWaiter.fulfillment(of: [completed], timeout: 5)
        guard outcome == .completed else {
            task.cancel()
            observer.cancel()
            XCTFail("Lifecycle task did not complete within five seconds")
            return fallback
        }
        return result ?? fallback
    }

    /// Regression (mini, 2026-10-19): with the chosen keyboard unplugged and
    /// several others connected, automatic Caps setup cannot choose, and that
    /// used to refuse the whole start. The session now starts with Caps Lock
    /// rules paused; every other rule runs.
    func testFailedCapsPreparationStillStartsTheSession() async {
        struct NoKeyboard: Error {}
        var launches: [String] = []
        ServiceLifecycleCoordinator.testSessionStart = { reason in
            launches.append(reason)
            return true
        }
        defer { ServiceLifecycleCoordinator.testSessionStart = { _ in false } }
        coordinator.testSessionCapsPreparation = { throw NoKeyboard() }
        let started = await coordinator.startKanata()
        XCTAssertTrue(started)
        XCTAssertEqual(launches.count, 1)
    }

    func testCancelledCapsPreparationDoesNotPublishRefusal() async {
        let pause = Pause()
        coordinator.testSessionCapsPreparation = {
            await pause.suspend()
            throw CancellationError()
        }
        let restart = Task { await self.coordinator.restartKanata() }
        await pause.waitUntilEntered()
        let generation = coordinator.sessionIntentGeneration
        restart.cancel()
        pause.release()
        let restarted = await completion(of: restart, fallback: true)
        XCTAssertFalse(restarted)
        XCTAssertNotEqual(coordinator.sessionIntentGeneration, generation, "The cancelled restart is retired")
        XCTAssertFalse(coordinator.sessionWantsRunning)
    }

    func testRepeatedHealthyStartTransfersSupervisionToLatestIntent() async {
        ServiceLifecycleCoordinator.testSessionStart = nil
        var adopted: [UInt64] = []
        coordinator.testSessionRunningReadiness = { true }
        coordinator.testSessionSupervisionStarted = { adopted.append($0) }
        let first = await coordinator.startKanata()
        let second = await coordinator.startKanata()
        XCTAssertTrue(first)
        XCTAssertTrue(second)
        XCTAssertEqual(adopted, [1, 2], "The real healthy-session fast path must re-adopt supervision")
        XCTAssertEqual(adopted.last, coordinator.sessionIntentGeneration)
    }

    func testHealthyWorkerPendingCleanupCannotBeAdopted() async {
        ServiceLifecycleCoordinator.testSessionStart = nil
        coordinator.testSessionRunningReadiness = { true }
        var adopted = false
        coordinator.testSessionSupervisionStarted = { _ in adopted = true }
        coordinator.sessionCleanupTask = Task {}
        defer { coordinator.sessionCleanupTask = nil }
        let started = await coordinator.startKanata()
        XCTAssertFalse(started)
        XCTAssertFalse(adopted)
    }

    func testRepeatedCapsRecoveryRefusalIsReportedOnce() async {
        var errors = 0
        coordinator.onError = { _ in errors += 1 }
        coordinator.testSessionCapsRecovery = { throw CancellationError() }
        let first = await coordinator.restoreSessionCaps(for: nil)
        let second = await coordinator.restoreSessionCaps(for: nil)
        XCTAssertFalse(first)
        XCTAssertFalse(second)
        XCTAssertEqual(errors, 1)
    }

    func testHealthyReportWithFailedTCPStopsInsteadOfAbandoningOutputs() async {
        ServiceLifecycleCoordinator.testSessionStart = nil
        var held = true
        var adoptionCount = 0
        coordinator.testSessionRunningReadiness = { false }
        coordinator.testSessionSupervisionStarted = { _ in adoptionCount += 1 }
        ServiceLifecycleCoordinator.testSessionStop = { held = false; return true }
        let result = await coordinator.startKanata()
        XCTAssertFalse(result)
        XCTAssertFalse(held)
        XCTAssertEqual(adoptionCount, 0)
    }

    func testOverlappingStartsCleanLateOldLaunchBeforeNewLaunch() async {
        let pause = Pause()
        var events: [String] = []
        var live: String?
        ServiceLifecycleCoordinator.testSessionStart = { reason in
            events.append("start:\(reason)")
            if reason == "old" { await pause.suspend() }
            XCTAssertNil(live, "A previous launch must be cleaned before a new one")
            live = reason
            return true
        }
        ServiceLifecycleCoordinator.testSessionStop = { events.append("cleanup:\(live ?? "none")"); live = nil; return true }
        let old = Task { await coordinator.startKanata(reason: "old") }
        await pause.waitUntilEntered()
        let new = await nextRequest { await self.coordinator.startKanata(reason: "new") }
        XCTAssertEqual(events, ["start:old"])
        XCTAssertTrue(coordinator.isStartingKanata)
        pause.release()
        let oldResult = await completion(of: old, fallback: false)
        let newResult = await completion(of: new, fallback: false)
        XCTAssertFalse(oldResult, "Superseded startup cannot report success")
        XCTAssertTrue(newResult)
        XCTAssertEqual(events, ["start:old", "cleanup:old", "start:new"])
        XCTAssertEqual(live, "new")
        XCTAssertFalse(coordinator.isStartingKanata)
        _ = await coordinator.stopKanata()
    }

    func testStopDuringLateStartCleansBeforeReturningAndPreventsSuccess() async {
        let pause = Pause()
        var held = false
        var starts = 0
        ServiceLifecycleCoordinator.testSessionStart = { _ in starts += 1; await pause.suspend(); held = true; return true }
        ServiceLifecycleCoordinator.testSessionStop = { held = false; return true }
        let start = Task { await coordinator.startKanata() }
        await pause.waitUntilEntered()
        let stop = await nextRequest { await self.coordinator.stopKanata() }
        XCTAssertFalse(coordinator.sessionWantsRunning)
        pause.release()
        let startResult = await completion(of: start, fallback: false)
        let stopResult = await completion(of: stop, fallback: false)
        XCTAssertFalse(startResult)
        XCTAssertTrue(stopResult)
        XCTAssertFalse(held)
        XCTAssertEqual(starts, 1)
    }

    /// A keyboard that cannot be chosen automatically no longer vetoes the
    /// restart (which used to leave a just-saved profile unapplied): the
    /// session restarts with Caps Lock rules paused, and nothing is an error.
    func testCapsSelectionRefusalRestartsWithCapsPaused() async {
        var starts = 0
        var stops = 0
        var errors: [String] = []
        ServiceLifecycleCoordinator.testSessionStart = { _ in
            starts += 1
            return true
        }
        ServiceLifecycleCoordinator.testSessionStop = { stops += 1; return true }
        let started = await coordinator.startKanata()
        XCTAssertTrue(started)
        coordinator.onError = { if let error = $0 { errors.append(error) } }
        coordinator.testSessionCapsPreparation = {
            throw NSError(domain: "CapsSelectionTest", code: 1)
        }

        let restarted = await coordinator.restartKanata(reason: "Caps mode changed")

        XCTAssertTrue(restarted)
        XCTAssertEqual(starts, 2)
        XCTAssertEqual(stops, 1)
        XCTAssertEqual(errors, [])
    }

    func testCapsPreparationRunsOnceBeforeRestartStopAndLaunch() async {
        var events: [String] = []
        coordinator.testSessionCapsPreparation = { events.append("prepare") }
        ServiceLifecycleCoordinator.testSessionStop = { events.append("stop"); return true }
        ServiceLifecycleCoordinator.testSessionStart = { _ in events.append("start"); return true }

        let restarted = await coordinator.restartKanata()

        XCTAssertTrue(restarted)
        XCTAssertEqual(events, ["prepare", "stop", "start"],
                       "A restart must not repeat selection persistence after stopping")
    }

    func testStopSupersedesSuspendedCapsPreparationWithoutRestartLaunch() async {
        let pause = Pause()
        var events: [String] = []
        coordinator.testSessionCapsPreparation = {
            events.append("prepare")
            await pause.suspend()
        }
        ServiceLifecycleCoordinator.testSessionStop = { events.append("stop"); return true }
        ServiceLifecycleCoordinator.testSessionStart = { _ in events.append("start"); return true }
        let restart = Task { await coordinator.restartKanata() }
        await pause.waitUntilEntered()
        let stop = await nextRequest { await self.coordinator.stopKanata() }
        XCTAssertEqual(events, ["prepare"], "Preflight must precede destructive restart work")
        pause.release()

        let restarted = await completion(of: restart, fallback: false)
        let stopped = await completion(of: stop, fallback: false)

        XCTAssertFalse(restarted)
        XCTAssertTrue(stopped)
        XCTAssertEqual(events, ["prepare", "stop"], "Only the newer explicit stop may stop the runtime")
    }

    func testRestartHoldsAdmissionAcrossStopAndSkipsStartAfterNewStop() async {
        let pause = Pause()
        var events: [String] = []
        ServiceLifecycleCoordinator.testSessionStop = {
            events.append("stop")
            if events.count == 1 { await pause.suspend() }
            return true
        }
        ServiceLifecycleCoordinator.testSessionStart = { _ in events.append("start"); return true }
        let restart = Task { await coordinator.restartKanata() }
        await pause.waitUntilEntered()
        let stop = await nextRequest { await self.coordinator.stopKanata() }
        XCTAssertEqual(events, ["stop"], "New stop cannot enter the active restart")
        pause.release()
        let restartResult = await completion(of: restart, fallback: false)
        let stopResult = await completion(of: stop, fallback: false)
        XCTAssertFalse(restartResult)
        XCTAssertTrue(stopResult)
        XCTAssertEqual(events, ["stop", "stop"])
    }

    func testCancelledQueuedStartNeverLaunchesAndDoesNotStrandPriorOutputs() async {
        let pause = Pause()
        var held = true
        var starts = 0
        ServiceLifecycleCoordinator.testSessionStop = {
            if held { await pause.suspend() }
            held = false
            return true
        }
        ServiceLifecycleCoordinator.testSessionStart = { _ in starts += 1; return true }
        let firstStop = Task { await coordinator.stopKanata() }
        await pause.waitUntilEntered()
        let queued = await nextRequest { await self.coordinator.startKanata() }
        queued.cancel()
        pause.release()
        _ = await completion(of: firstStop, fallback: false)
        let result = await completion(of: queued, fallback: false)
        XCTAssertFalse(result)
        XCTAssertEqual(starts, 0)
        XCTAssertFalse(held)
        XCTAssertFalse(coordinator.sessionWantsRunning)
    }

    func testCancelledAcceptedStopStillReleasesPriorHeldOutputs() async {
        let pause = Pause()
        var held = true
        var stopCalls = 0
        ServiceLifecycleCoordinator.testSessionStop = {
            stopCalls += 1
            if stopCalls == 1 { await pause.suspend() }
            held = false
            return true
        }
        ServiceLifecycleCoordinator.testSessionStart = { _ in XCTFail("Restart superseded by stop must not launch"); return false }
        let restart = Task { await coordinator.restartKanata() }
        await pause.waitUntilEntered()
        let stop = await nextRequest { await self.coordinator.stopKanata() }
        stop.cancel()
        pause.release()
        _ = await completion(of: restart, fallback: false)
        let stopped = await completion(of: stop, fallback: false)
        XCTAssertTrue(stopped, "Accepted stop cleanup survives caller cancellation")
        XCTAssertFalse(held)
        XCTAssertEqual(stopCalls, 2)
        XCTAssertFalse(coordinator.sessionWantsRunning)
    }

    func testCancellationAfterLaunchCompletionCleansOwnedOutput() async {
        let pause = Pause()
        var held = false
        ServiceLifecycleCoordinator.testSessionStart = { _ in await pause.suspend(); held = true; return true }
        ServiceLifecycleCoordinator.testSessionStop = { held = false; return true }
        let start = Task { await coordinator.startKanata() }
        await pause.waitUntilEntered()
        start.cancel()
        pause.release()
        let result = await completion(of: start, fallback: false)
        XCTAssertFalse(result)
        XCTAssertFalse(held)
        XCTAssertFalse(coordinator.sessionWantsRunning)
    }

    func testSecureResumeQueuedBeforeManualStopCannotRecreateWorker() async {
        let pause = Pause()
        var starts = 0
        ServiceLifecycleCoordinator.testSessionStart = { _ in starts += 1; return true }
        let initiallyStarted = await coordinator.startKanata()
        XCTAssertTrue(initiallyStarted)
        let oldGeneration = coordinator.sessionIntentGeneration
        // Hold the real gate, without inheriting its TaskLocal ownership in the
        // independent recovery task. Secure recovery uses the same boundary.
        let blocker = Task {
            try? await coordinator.sessionOperationGate.withOperation { _ in
                await pause.suspend()
            }
        }
        await pause.waitUntilEntered()
        let resume = await nextRequest { await self.coordinator.resumeSessionRuntime(expectedGeneration: oldGeneration) }
        let stop = await nextRequest { await self.coordinator.stopKanata() }
        pause.release()
        _ = await completion(of: blocker, fallback: ())
        let resumed = await completion(of: resume, fallback: false)
        let stopped = await completion(of: stop, fallback: false)
        XCTAssertFalse(resumed)
        XCTAssertTrue(stopped)
        XCTAssertEqual(starts, 1)
        XCTAssertFalse(coordinator.sessionWantsRunning)
    }

    func testWakeBeforeTerminalReportResumesFreshAdmission() async {
        var reasons: [String] = []
        ServiceLifecycleCoordinator.testSessionStart = { reasons.append($0); return true }
        _ = await coordinator.startKanata()
        coordinator.testSessionWakeReady = { true }
        coordinator.sessionWakeEpoch = 1
        let resumed = await coordinator.resumeAfterSystemWake(
            expectedGeneration: coordinator.sessionIntentGeneration, launchWakeEpoch: 0, wakeAlreadyObserved: false
        )
        XCTAssertTrue(resumed)
        XCTAssertEqual(reasons, ["Manual start", "System wake"])
    }

    func testSleepWaitsForWakeAndReadySession() async {
        var starts = 0
        ServiceLifecycleCoordinator.testSessionStart = { _ in starts += 1; return true }
        _ = await coordinator.startKanata()
        var ready = false
        var waits = 0
        coordinator.testSessionWakeReady = { ready }
        coordinator.testSessionWakeWait = { [self] in
            XCTAssertEqual(starts, 1)
            XCTAssertTrue(coordinator.isRecoveringFromSystemWake)
            let transient = await coordinator.isInTransientRuntimeStartupWindow()
            XCTAssertTrue(transient)
            waits += 1
            if waits == 1 { coordinator.sessionWakeEpoch += 1 }
            else { ready = true }
        }
        let resumed = await coordinator.resumeAfterSystemWake(
            expectedGeneration: coordinator.sessionIntentGeneration, launchWakeEpoch: 0, wakeAlreadyObserved: false
        )
        XCTAssertTrue(resumed)
        XCTAssertEqual(waits, 2)
        XCTAssertEqual(starts, 2)
        XCTAssertFalse(coordinator.isRecoveringFromSystemWake)
        XCTAssertNil(coordinator.sessionWakeRecovery)
    }

    func testWakeRecoveryPublishesCheckingWithoutPermissionOrHealthPolling() async {
        _ = await coordinator.startKanata()
        let controller = MainAppStateController()
        controller.configure(serviceLifecycle: coordinator, onSystemHealthy: {})
        controller.setValidator(StubSystemValidator(context: SystemContextBuilder(componentsInstalled: true).build()))
        controller.configureStartupGateTestingState(permissionsOverride: {
            XCTFail("Normal wake recovery must not probe locked-session permissions")
            return SystemContextBuilder().build().permissions
        }, healthOverride: {
            XCTFail("Normal wake recovery must not validate a retired worker")
            return .init(isRunning: false, isResponding: false, inputCaptureReady: false)
        })
        defer { controller.resetStartupGateTestingState() }
        coordinator.testSessionWakeReady = { false }
        coordinator.testSessionWakeWait = { [self] in
            await controller.revalidate()
            XCTAssertEqual(controller.validationState, .checking)
            XCTAssertTrue(controller.issues.isEmpty)
            XCTAssertEqual(controller.lastAdaptedState, .initializing)
            coordinator.setTerminationPreparationActive(true)
            XCTAssertFalse(coordinator.isRecoveringFromSystemWake)
        }
        _ = await coordinator.resumeAfterSystemWake(expectedGeneration: coordinator.sessionIntentGeneration,
                                                    launchWakeEpoch: 0, wakeAlreadyObserved: true)
        XCTAssertNil(coordinator.sessionWakeRecovery)
    }

    func testManualStopWhileSleepingPreventsWakeRestart() async {
        var starts = 0
        ServiceLifecycleCoordinator.testSessionStart = { _ in starts += 1; return true }
        ServiceLifecycleCoordinator.testSessionStop = { true }
        _ = await coordinator.startKanata()
        coordinator.testSessionWakeReady = { true }
        coordinator.testSessionWakeWait = { [self] in
            _ = await coordinator.stopKanata()
            coordinator.sessionWakeEpoch += 1
        }
        let resumed = await coordinator.resumeAfterSystemWake(
            expectedGeneration: coordinator.sessionIntentGeneration, launchWakeEpoch: 0, wakeAlreadyObserved: false
        )
        XCTAssertFalse(resumed)
        XCTAssertEqual(starts, 1)
    }

    func testWorkerObservedWakeDoesNotRequireSecondNotification() async {
        var starts = 0
        ServiceLifecycleCoordinator.testSessionStart = { _ in starts += 1; return true }
        _ = await coordinator.startKanata()
        coordinator.testSessionWakeReady = { true }
        let resumed = await coordinator.resumeAfterSystemWake(
            expectedGeneration: coordinator.sessionIntentGeneration, launchWakeEpoch: 0, wakeAlreadyObserved: true
        )
        XCTAssertTrue(resumed)
        XCTAssertEqual(starts, 2)
    }

    func testQuitWhileWaitingForWakePreventsRestart() async {
        ServiceLifecycleCoordinator.testSessionStart = { _ in true }
        _ = await coordinator.startKanata()
        coordinator.testSessionWakeReady = { true }
        coordinator.testSessionWakeWait = { [self] in coordinator.setTerminationPreparationActive(true) }
        let resumed = await coordinator.resumeAfterSystemWake(
            expectedGeneration: coordinator.sessionIntentGeneration, launchWakeEpoch: 0, wakeAlreadyObserved: false
        )
        XCTAssertFalse(resumed)
    }

    func testWakeRetriesHeldKeyRaceWithoutCancellingRecoveryTask() async {
        var starts = 0
        ServiceLifecycleCoordinator.testSessionStart = { [self] _ in
            starts += 1
            if starts == 2 {
                // Production cleanup cancels the worker supervisor. It must no
                // longer own the task that is waiting to retry wake recovery.
                XCTAssertNil(coordinator.sessionSupervisionTask)
                coordinator.sessionSupervisionTask?.cancel()
                coordinator.sessionWakeRetryGeneration = coordinator.sessionIntentGeneration
                return false
            }
            return true
        }
        _ = await coordinator.startKanata()
        coordinator.testSessionWakeReady = { true }
        var waits = 0
        coordinator.testSessionWakeWait = { waits += 1 }
        var resumed = false
        let recovery = Task { @MainActor [self] in
            resumed = await coordinator.resumeAfterSystemWake(expectedGeneration: coordinator.sessionIntentGeneration,
                                                              launchWakeEpoch: 0, wakeAlreadyObserved: true)
        }
        // The current supervisor calls recovery on its own task in production.
        coordinator.sessionSupervisionTask = recovery
        _ = await completion(of: recovery, fallback: ())
        XCTAssertTrue(resumed)
        XCTAssertEqual(starts, 3)
        XCTAssertEqual(waits, 1)
        XCTAssertNil(coordinator.sessionWakeRetryGeneration)
    }

    func testStopAndQuitDuringHeldKeyRetryPreventAnotherLaunch() async {
        for quit in [false, true] {
            coordinator.setTerminationPreparationActive(false)
            var starts = 0
            ServiceLifecycleCoordinator.testSessionStart = { [self] _ in
                starts += 1
                if starts == 1 { return true }
                coordinator.sessionWakeRetryGeneration = coordinator.sessionIntentGeneration
                return false
            }
            ServiceLifecycleCoordinator.testSessionStop = { true }
            _ = await coordinator.startKanata()
            coordinator.testSessionWakeReady = { true }
            coordinator.testSessionWakeWait = { [self] in
                if quit { coordinator.setTerminationPreparationActive(true) }
                else { _ = await coordinator.stopKanata() }
            }
            let resumed = await coordinator.resumeAfterSystemWake(
                expectedGeneration: coordinator.sessionIntentGeneration, launchWakeEpoch: 0, wakeAlreadyObserved: true
            )
            XCTAssertFalse(resumed)
            XCTAssertEqual(starts, 2)
        }
    }

    func testWakeDoesNotRetryUnrelatedFailureOrStaleRetryEvidence() async {
        var starts = 0
        ServiceLifecycleCoordinator.testSessionStart = { _ in starts += 1; return starts == 1 }
        _ = await coordinator.startKanata()
        coordinator.sessionWakeRetryGeneration = coordinator.sessionIntentGeneration
        coordinator.testSessionWakeReady = { true }
        let resumed = await coordinator.resumeAfterSystemWake(
            expectedGeneration: coordinator.sessionIntentGeneration, launchWakeEpoch: 0, wakeAlreadyObserved: true
        )
        XCTAssertFalse(resumed)
        XCTAssertEqual(starts, 2)
    }

    func testWakeRetryRequiresOwnedHeldKeyFailureAndCompletedCleanup() {
        func report(_ failure: String) -> SessionRuntimeReport {
            SessionRuntimeReport(nonce: "owned", pid: 123, uid: 502, state: .failed,
                                 accessibility: true, effectiveInputAccess: true, tapActive: false,
                                 tcpPort: 37001, inputCount: 0, outputCount: 0, failure: failure)
        }
        let held = report("managed-caps-activation-refused: physicalKeysHeld")
        XCTAssertTrue(ServiceLifecycleCoordinator.canRetryWakeStartup(held, nonce: "owned", pid: 123, uid: 502, cleanedUp: true))
        XCTAssertFalse(ServiceLifecycleCoordinator.canRetryWakeStartup(held, nonce: "owned", pid: 123, uid: 502, cleanedUp: false))
        XCTAssertFalse(ServiceLifecycleCoordinator.canRetryWakeStartup(held, nonce: "other", pid: 123, uid: 502, cleanedUp: true))
        XCTAssertFalse(ServiceLifecycleCoordinator.canRetryWakeStartup(held, nonce: "owned", pid: 456, uid: 502, cleanedUp: true))
        XCTAssertFalse(ServiceLifecycleCoordinator.canRetryWakeStartup(held, nonce: "owned", pid: 123, uid: 501, cleanedUp: true))
        XCTAssertFalse(ServiceLifecycleCoordinator.canRetryWakeStartup(report("managed-caps-restoration-pending"), nonce: "owned", pid: 123, uid: 502, cleanedUp: true))
        XCTAssertFalse(ServiceLifecycleCoordinator.canRetryWakeStartup(nil, nonce: "owned", pid: 123, uid: 502, cleanedUp: true))
    }

    func testWakeStartupRetriesLateWakeOnlyAfterOwnedCleanup() {
        func report(_ state: SessionRuntimeReport.State, reason: String) -> SessionRuntimeReport {
            SessionRuntimeReport(nonce: "owned", pid: 123, uid: 502, state: state,
                                 accessibility: true, effectiveInputAccess: true, tapActive: false,
                                 tcpPort: 37001, inputCount: 0, outputCount: 0,
                                 failure: state == .failed ? "managed-caps-restoration-pending" : reason,
                                 retirementReason: reason)
        }
        for state in [SessionRuntimeReport.State.stopped, .failed] {
            let wake = report(state, reason: "system-wake-observed")
            XCTAssertTrue(ServiceLifecycleCoordinator.canRetryWakeStartup(wake, nonce: "owned", pid: 123, uid: 502, cleanedUp: true))
            XCTAssertFalse(ServiceLifecycleCoordinator.canRetryWakeStartup(wake, nonce: "owned", pid: 123, uid: 502, cleanedUp: false))
            XCTAssertFalse(ServiceLifecycleCoordinator.canRetryWakeStartup(wake, nonce: "other", pid: 123, uid: 502, cleanedUp: true))
            XCTAssertFalse(ServiceLifecycleCoordinator.canRetryWakeStartup(report(state, reason: "system-will-sleep"), nonce: "owned", pid: 123, uid: 502, cleanedUp: true))
        }
        XCTAssertFalse(ServiceLifecycleCoordinator.canRetryWakeStartup(report(.running, reason: "system-wake-observed"), nonce: "owned", pid: 123, uid: 502, cleanedUp: true))
    }

    func testScreenWakeResumesWithoutWaitingForSystemWake() async {
        var starts = 0
        ServiceLifecycleCoordinator.testSessionStart = { _ in starts += 1; return true }
        _ = await coordinator.startKanata()
        let retired = Date()
        coordinator.observeSessionWake(NSWorkspace.screensDidWakeNotification, at: retired.addingTimeInterval(1))
        coordinator.testSessionWakeReady = { true }
        let resumed = await coordinator.resumeAfterSystemWake(
            expectedGeneration: coordinator.sessionIntentGeneration, launchWakeEpoch: 0,
            wakeAlreadyObserved: false, retiredAt: retired
        )
        XCTAssertTrue(resumed)
        XCTAssertEqual(starts, 2)
    }

    func testEarlierScreenWakeCannotResumeLaterSleepAndStillWaitsForReadiness() async {
        var starts = 0
        ServiceLifecycleCoordinator.testSessionStart = { _ in starts += 1; return true }
        _ = await coordinator.startKanata()
        let retired = Date()
        coordinator.observeSessionWake(NSWorkspace.screensDidWakeNotification, at: retired.addingTimeInterval(-1))
        var ready = false
        var waits = 0
        coordinator.testSessionWakeReady = { ready }
        coordinator.testSessionWakeWait = { [self] in
            waits += 1
            XCTAssertEqual(starts, 1)
            if waits == 1 {
                coordinator.observeSessionWake(NSWorkspace.sessionDidBecomeActiveNotification, at: retired.addingTimeInterval(1))
            } else { ready = true }
        }
        let resumed = await coordinator.resumeAfterSystemWake(
            expectedGeneration: coordinator.sessionIntentGeneration, launchWakeEpoch: 0,
            wakeAlreadyObserved: false, retiredAt: retired
        )
        XCTAssertTrue(resumed)
        XCTAssertEqual(waits, 2)
        XCTAssertEqual(starts, 2)
    }

    func testStartupSleepArmsRecoveryAndWaitsForFreshWake() async {
        var starts = 0
        ServiceLifecycleCoordinator.testSessionStart = { _ in starts += 1; return true }
        _ = await coordinator.startKanata()
        let retired = Date()
        let report = SessionRuntimeReport(nonce: "owned", pid: 123, uid: getuid(), state: .failed,
                                          accessibility: true, effectiveInputAccess: true, tapActive: false,
                                          tcpPort: 37001, inputCount: 0, outputCount: 0,
                                          failure: "system-will-sleep")
        coordinator.testSessionWakeReady = { true }
        coordinator.testSessionWakeWait = { [self] in
            XCTAssertEqual(starts, 1)
            coordinator.observeSessionWake(NSWorkspace.didWakeNotification, at: retired.addingTimeInterval(1))
        }
        XCTAssertTrue(coordinator.scheduleInterruptedStartupRecovery(report, nonce: "owned", pid: 123,
                                                                     generation: coordinator.sessionIntentGeneration, cleanedUp: true))
        guard let recovery = coordinator.sessionSupervisionTask else { return XCTFail("Recovery was not armed") }
        _ = await completion(of: recovery, fallback: ())
        XCTAssertEqual(starts, 2)
    }

    func testStartupSessionChangeRecoversOnlyAfterConsoleReadiness() async {
        for reason in ["session-resigned-active", "console-session-change-observed", "console-session-inactive"] {
            var starts = 0
            ServiceLifecycleCoordinator.testSessionStart = { _ in starts += 1; return true }
            _ = await coordinator.startKanata()
            let report = SessionRuntimeReport(nonce: "owned", pid: 123, uid: getuid(), state: .failed,
                                              accessibility: true, effectiveInputAccess: true, tapActive: false,
                                              tcpPort: 37001, inputCount: 0, outputCount: 0, failure: reason)
            var ready = false
            coordinator.testSessionWakeReady = { ready }
            coordinator.testSessionWakeWait = { XCTAssertEqual(starts, 1); ready = true }
            XCTAssertTrue(coordinator.scheduleInterruptedStartupRecovery(report, nonce: "owned", pid: 123,
                                                                         generation: coordinator.sessionIntentGeneration, cleanedUp: true))
            guard let recovery = coordinator.sessionSupervisionTask else { return XCTFail("Recovery was not armed") }
            _ = await completion(of: recovery, fallback: ())
            XCTAssertEqual(starts, 2)
        }
    }

    func testHeldKeyStartupWaitsForReleaseThenResumesAutomatically() async {
        var starts = 0
        var errors: [String] = []
        ServiceLifecycleCoordinator.testSessionStart = { _ in starts += 1; return true }
        coordinator.onError = { if let error = $0 { errors.append(error) } }
        _ = await coordinator.startKanata()
        let report = SessionRuntimeReport(nonce: "owned", pid: 123, uid: getuid(), state: .failed,
                                          accessibility: true, effectiveInputAccess: true, tapActive: false,
                                          tcpPort: 37001, inputCount: 0, outputCount: 0,
                                          failure: "managed-caps-activation-refused: physicalKeysHeld")
        var ready = false
        coordinator.testSessionWakeReady = { ready }
        coordinator.testSessionWakeWait = { [self] in
            XCTAssertEqual(starts, 1)
            XCTAssertTrue(coordinator.isRecoveringFromSystemWake)
            XCTAssertTrue(errors.isEmpty)
            ready = true
        }
        XCTAssertTrue(coordinator.scheduleInterruptedStartupRecovery(report, nonce: "owned", pid: 123,
                                                                     generation: coordinator.sessionIntentGeneration, cleanedUp: true))
        guard let recovery = coordinator.sessionSupervisionTask else { return XCTFail("Recovery was not armed") }
        _ = await completion(of: recovery, fallback: ())
        XCTAssertEqual(starts, 2)
        XCTAssertTrue(errors.isEmpty)
        XCTAssertNil(coordinator.sessionWakeRecovery)
    }

    /// Air, 2026-10-18 12:01: KeyPath launched while the screen was locked
    /// (loginwindow held Secure Input). Startup was refused as terminal and the
    /// setup wizard opened instead of resuming after unlock.
    func testSecureInputStartupWaitsForUnlockThenResumesAutomatically() async {
        var starts = 0
        var errors: [String] = []
        ServiceLifecycleCoordinator.testSessionStart = { _ in starts += 1; return true }
        coordinator.onError = { if let error = $0 { errors.append(error) } }
        _ = await coordinator.startKanata()
        let report = SessionRuntimeReport(nonce: "owned", pid: 123, uid: getuid(), state: .secureInput,
                                          accessibility: true, effectiveInputAccess: true, tapActive: false,
                                          tcpPort: 37001, inputCount: 0, outputCount: 0)
        var ready = false
        coordinator.testSessionWakeReady = { ready }
        coordinator.testSessionWakeWait = { [self] in
            XCTAssertEqual(starts, 1)
            XCTAssertTrue(coordinator.isRecoveringFromSystemWake)
            XCTAssertTrue(errors.isEmpty)
            ready = true
        }
        XCTAssertTrue(coordinator.scheduleInterruptedStartupRecovery(report, nonce: "owned", pid: 123,
                                                                     generation: coordinator.sessionIntentGeneration, cleanedUp: true))
        guard let recovery = coordinator.sessionSupervisionTask else { return XCTFail("Recovery was not armed") }
        _ = await completion(of: recovery, fallback: ())
        XCTAssertEqual(starts, 2)
        XCTAssertTrue(errors.isEmpty)
        XCTAssertNil(coordinator.sessionWakeRecovery)
    }

    func testSecureInputStartupRejectsUnownedEvidenceAndIncompleteCleanup() async {
        ServiceLifecycleCoordinator.testSessionStart = { _ in true }
        _ = await coordinator.startKanata()
        let report = SessionRuntimeReport(nonce: "owned", pid: 123, uid: getuid(), state: .secureInput,
                                          accessibility: true, effectiveInputAccess: true, tapActive: false,
                                          tcpPort: 37001, inputCount: 0, outputCount: 0)
        let generation = coordinator.sessionIntentGeneration
        XCTAssertFalse(coordinator.scheduleInterruptedStartupRecovery(report, nonce: "owned", pid: 123,
                                                                      generation: generation, cleanedUp: false))
        XCTAssertFalse(coordinator.scheduleInterruptedStartupRecovery(report, nonce: "other", pid: 123,
                                                                      generation: generation, cleanedUp: true))
        XCTAssertFalse(coordinator.scheduleInterruptedStartupRecovery(report, nonce: "owned", pid: 456,
                                                                      generation: generation, cleanedUp: true))
        XCTAssertFalse(coordinator.scheduleInterruptedStartupRecovery(report, nonce: "owned", pid: 123,
                                                                      generation: generation &+ 1, cleanedUp: true))
    }

    func testHeldKeyStartupCannotRestartAfterQuit() async {
        var starts = 0
        ServiceLifecycleCoordinator.testSessionStart = { _ in starts += 1; return true }
        _ = await coordinator.startKanata()
        let report = SessionRuntimeReport(nonce: "owned", pid: 123, uid: getuid(), state: .failed,
                                          accessibility: true, effectiveInputAccess: true, tapActive: false,
                                          tcpPort: 37001, inputCount: 0, outputCount: 0,
                                          failure: "managed-caps-activation-refused: physicalKeysHeld")
        coordinator.testSessionWakeReady = { false }
        coordinator.testSessionWakeWait = { [self] in coordinator.setTerminationPreparationActive(true) }
        XCTAssertTrue(coordinator.scheduleInterruptedStartupRecovery(report, nonce: "owned", pid: 123,
                                                                     generation: coordinator.sessionIntentGeneration, cleanedUp: true))
        guard let recovery = coordinator.sessionSupervisionTask else { return XCTFail("Recovery was not armed") }
        _ = await completion(of: recovery, fallback: ())
        XCTAssertEqual(starts, 1)
        XCTAssertNil(coordinator.sessionWakeRecovery)
    }

    func testInterruptedStartupRejectsUnownedEvidenceAndIncompleteCleanup() async {
        ServiceLifecycleCoordinator.testSessionStart = { _ in true }
        _ = await coordinator.startKanata()
        let report = SessionRuntimeReport(nonce: "owned", pid: 123, uid: getuid(), state: .failed,
                                          accessibility: true, effectiveInputAccess: true, tapActive: false,
                                          tcpPort: 37001, inputCount: 0, outputCount: 0, failure: "system-will-sleep")
        XCTAssertFalse(coordinator.scheduleInterruptedStartupRecovery(report, nonce: "owned", pid: 123,
                                                                      generation: coordinator.sessionIntentGeneration, cleanedUp: false))
        XCTAssertFalse(coordinator.scheduleInterruptedStartupRecovery(report, nonce: "other", pid: 123,
                                                                      generation: coordinator.sessionIntentGeneration, cleanedUp: true))
        XCTAssertFalse(coordinator.scheduleInterruptedStartupRecovery(report, nonce: "owned", pid: 123,
                                                                      generation: coordinator.sessionIntentGeneration &+ 1, cleanedUp: true))
        XCTAssertFalse(ServiceLifecycleCoordinator.isRecoverableSessionBoundary("console-observation-unavailable"))
        XCTAssertFalse(ServiceLifecycleCoordinator.isRecoverableSessionBoundary("managed-caps-ownership-lost"))
    }

    func testShutdownDoesNotEscalateWhileMutationIsStillJoining() async {
        var signals = 0
        var waits = 0
        let exited = await ServiceLifecycleCoordinator.awaitGracefulSessionExit(
            isTerminated: { false }, sendTermination: { signals += 1 }, wait: { waits += 1 }
        )
        XCTAssertFalse(exited)
        XCTAssertEqual(signals, 1)
        XCTAssertEqual(waits, 600)
    }

    func testShutdownCompletesAfterMutationJoinsWithoutAnotherSignal() async {
        var signals = 0
        var waits = 0
        let exited = await ServiceLifecycleCoordinator.awaitGracefulSessionExit(
            isTerminated: { waits == 3 }, sendTermination: { signals += 1 }, wait: { waits += 1 }
        )
        XCTAssertTrue(exited)
        XCTAssertEqual(signals, 1)
        XCTAssertEqual(waits, 3)
    }
}
