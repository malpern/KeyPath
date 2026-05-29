@testable import KeyPathAppKit
import XCTest

@MainActor
final class StuckKeyRecoveryServiceTests: KeyPathTestCase {
    private var service: StuckKeyRecoveryService!
    private var restartCallCount = 0
    private var lastRestartReason: String?
    /// Fulfilled each time the (default) restart handler runs, so positive tests can
    /// wait for the recovery Task to actually reach the restart instead of sleeping a
    /// fixed interval. The recovery Task now does an awaited diagnostic snapshot before
    /// restarting (StuckKeyRecoveryService.swift:57), so fixed sleeps are racy.
    private var restartExpectation: XCTestExpectation?

    override func setUp() async throws {
        try await super.setUp()
        service = StuckKeyRecoveryService()
        restartCallCount = 0
        lastRestartReason = nil
        restartExpectation = nil
        service.restartKanata = { [weak self] reason in
            self?.restartCallCount += 1
            self?.lastRestartReason = reason
            self?.restartExpectation?.fulfill()
            return true
        }
    }

    // MARK: - Detection Threshold

    func testIgnoresNormalAutorepeat() async {
        let correlation = makeCorrelation(
            suggestsUnmatchedAutorepeat: true,
            msSinceAnyKanataEvent: 100
        )

        service.handleAutorepeatMismatch(correlation)
        try? await Task.sleep(for: .milliseconds(50))

        XCTAssertEqual(restartCallCount, 0, "Should not restart for normal autorepeat with active kanata")
    }

    func testIgnoresNonAutorepeat() async {
        let correlation = makeCorrelation(
            suggestsUnmatchedAutorepeat: false,
            msSinceAnyKanataEvent: 5000
        )

        service.handleAutorepeatMismatch(correlation)
        try? await Task.sleep(for: .milliseconds(50))

        XCTAssertEqual(restartCallCount, 0, "Should not restart if not an unmatched autorepeat")
    }

    func testTriggersRecoveryForStuckKey() async {
        let expectation = expectation(description: "restart triggered for stuck key")
        restartExpectation = expectation

        let correlation = makeCorrelation(
            key: "t",
            suggestsUnmatchedAutorepeat: true,
            msSinceAnyKanataEvent: 5000
        )

        service.handleAutorepeatMismatch(correlation)
        await fulfillment(of: [expectation], timeout: 5.0)

        XCTAssertEqual(restartCallCount, 1)
        XCTAssertTrue(lastRestartReason?.contains("t") == true)
    }

    func testIgnoresNilKanataEventTime() async {
        let correlation = makeCorrelation(
            suggestsUnmatchedAutorepeat: true,
            msSinceAnyKanataEvent: nil
        )

        service.handleAutorepeatMismatch(correlation)
        try? await Task.sleep(for: .milliseconds(50))

        XCTAssertEqual(restartCallCount, 0, "Should not restart if kanata event time is unknown")
    }

    // MARK: - Debouncing

    func testDebouncesPreviousRecoveries() async {
        let firstRestart = expectation(description: "first restart")
        restartExpectation = firstRestart

        let correlation = makeCorrelation(
            suggestsUnmatchedAutorepeat: true,
            msSinceAnyKanataEvent: 5000
        )

        service.handleAutorepeatMismatch(correlation)
        await fulfillment(of: [firstRestart], timeout: 5.0)
        XCTAssertEqual(restartCallCount, 1)

        // Give the first recovery Task time to settle, then fire a second mismatch. It is
        // suppressed either by the in-flight guard (if the Task tail hasn't run) or by the
        // 30s cooldown (once lastRecoveryAt is set) — either way no second restart fires.
        restartExpectation = nil
        for _ in 0 ..< 10 {
            await Task.yield()
        }
        service.handleAutorepeatMismatch(correlation)
        try? await Task.sleep(for: .milliseconds(150))
        XCTAssertEqual(restartCallCount, 1, "Should not restart again within cooldown period")
    }

    func testDoesNotDoubleFireWhileRecovering() async {
        let firstRestartEntered = expectation(description: "first restart entered")
        var continueRestart: CheckedContinuation<Void, Never>?
        service.restartKanata = { [weak self] reason in
            self?.restartCallCount += 1
            self?.lastRestartReason = reason
            firstRestartEntered.fulfill()
            await withCheckedContinuation { continuation in
                continueRestart = continuation
            }
            return true
        }

        let correlation = makeCorrelation(
            suggestsUnmatchedAutorepeat: true,
            msSinceAnyKanataEvent: 5000
        )

        // Wait until the first restart is actually in-flight (isRecovering == true) before
        // sending the second mismatch — deterministic regardless of snapshot latency.
        service.handleAutorepeatMismatch(correlation)
        await fulfillment(of: [firstRestartEntered], timeout: 5.0)

        // Second mismatch while the first restart is still suspended must be ignored.
        service.handleAutorepeatMismatch(correlation)
        try? await Task.sleep(for: .milliseconds(150))

        continueRestart?.resume()
        XCTAssertEqual(restartCallCount, 1, "Should not fire second restart while first is in progress")
    }

    // MARK: - Helpers

    private func makeCorrelation(
        key: String = "t",
        suggestsUnmatchedAutorepeat: Bool,
        msSinceAnyKanataEvent: Int?
    ) -> InvestigationSystemEventCorrelation {
        InvestigationSystemEventCorrelation(
            key: key,
            keyCode: 17,
            eventType: "keyDown",
            isAutorepeat: suggestsUnmatchedAutorepeat,
            flagsRawValue: 0,
            sourcePID: nil,
            observedAt: Date(),
            previousKanataAction: .press,
            previousKanataSessionID: 1,
            sameKeyGapMs: 33,
            msSinceAnyKanataEvent: msSinceAnyKanataEvent,
            suggestsUnmatchedAutorepeat: suggestsUnmatchedAutorepeat
        )
    }
}
