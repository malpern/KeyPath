@testable import KeyPathAppKit
@preconcurrency import XCTest

/// No NSRunningApplication, process signal, CGEvent or host launch is used here.
/// The existing DEBUG operations are inside the production admission boundary.
@MainActor
final class SessionLifecycleInterleavingTests: KeyPathTestCase {
    private var coordinator: ServiceLifecycleCoordinator!

    @MainActor
    private final class Pause {
        private var entered = false
        private var entryWaiter: CheckedContinuation<Void, Never>?
        private var releaseWaiter: CheckedContinuation<Void, Never>?

        func suspend() async {
            await withCheckedContinuation { continuation in
                releaseWaiter = continuation
                entered = true
                entryWaiter?.resume()
                entryWaiter = nil
            }
        }

        func waitUntilEntered() async {
            if entered { return }
            await withCheckedContinuation { entryWaiter = $0 }
        }

        func release() {
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
        var task: Task<Bool, Never>!
        await withCheckedContinuation { (continuation: CheckedContinuation<Void, Never>) in
            coordinator.testSessionRequestObserved = { [self] _ in
                coordinator.testSessionRequestObserved = nil
                continuation.resume()
            }
            task = Task { @MainActor in await operation() }
        }
        return task
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
        let oldResult = await old.value
        let newResult = await new.value
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
        let startResult = await start.value
        let stopResult = await stop.value
        XCTAssertFalse(startResult)
        XCTAssertTrue(stopResult)
        XCTAssertFalse(held)
        XCTAssertEqual(starts, 1)
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
        let restartResult = await restart.value
        let stopResult = await stop.value
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
        _ = await firstStop.value
        let result = await queued.value
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
        _ = await restart.value
        let stopped = await stop.value
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
        let result = await start.value
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
        _ = await blocker.value
        let resumed = await resume.value
        let stopped = await stop.value
        XCTAssertFalse(resumed)
        XCTAssertTrue(stopped)
        XCTAssertEqual(starts, 1)
        XCTAssertFalse(coordinator.sessionWantsRunning)
    }
}
