@testable import KeyPathAppKit
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
}
