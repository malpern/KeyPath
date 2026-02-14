@testable import KeyPathAppKit
import XCTest

final class EngineReloadSingleFlightTests: XCTestCase {
    actor Gate {
        private var isOpen = false
        private var waiters: [CheckedContinuation<Void, Never>] = []

        func wait() async {
            if isOpen { return }
            await withCheckedContinuation { c in
                waiters.append(c)
            }
        }

        func open() {
            guard !isOpen else { return }
            isOpen = true
            let toResume = waiters
            waiters.removeAll()
            for c in toResume { c.resume() }
        }
    }

    actor Counter {
        private var value = 0
        func inc() { value += 1 }
        func get() -> Int { value }
    }

    func testRunCoalescesConcurrentCalls() async {
        let singleFlight = EngineReloadSingleFlight()
        let gate = Gate()
        let started = Counter()

        async let r1: EngineReloadResult = singleFlight.run(reason: "t1", debounce: 0) {
            await started.inc()
            await gate.wait()
            return .success(response: "ok")
        }

        async let r2: EngineReloadResult = singleFlight.run(reason: "t2", debounce: 0) {
            await started.inc()
            await gate.wait()
            return .success(response: "ok-should-not-run")
        }

        async let r3: EngineReloadResult = singleFlight.run(reason: "t3", debounce: 0) {
            await started.inc()
            await gate.wait()
            return .success(response: "ok-should-not-run")
        }

        while await started.get() == 0 {
            await Task.yield()
        }

        await gate.open()

        let results = await [r1, r2, r3]
        let startedCount = await started.get()
        XCTAssertEqual(startedCount, 1, "Only one operation should execute")
        XCTAssertTrue(results.allSatisfy { $0.isSuccess }, "All callers should receive success")
        XCTAssertTrue(results.allSatisfy { $0.response == "ok" }, "All callers should receive the same result")
    }

    func testRunStartsNewOperationAfterCompletion() async {
        let singleFlight = EngineReloadSingleFlight()
        let counter = Counter()

        let first = await singleFlight.run(reason: "first", debounce: 0) {
            await counter.inc()
            return .success(response: "one")
        }
        let second = await singleFlight.run(reason: "second", debounce: 0) {
            await counter.inc()
            return .success(response: "two")
        }

        let counterValue = await counter.get()
        XCTAssertEqual(counterValue, 2, "Each call after completion should execute its own operation")
        XCTAssertEqual(first.response, "one")
        XCTAssertEqual(second.response, "two")
    }
}
