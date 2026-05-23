@testable import KeyPathAppKit
import XCTest

@MainActor
final class StuckKeyRecoveryServiceTests: KeyPathTestCase {
    private var service: StuckKeyRecoveryService!
    private var restartCallCount = 0
    private var lastRestartReason: String?

    override func setUp() async throws {
        try await super.setUp()
        service = StuckKeyRecoveryService()
        restartCallCount = 0
        lastRestartReason = nil
        service.restartKanata = { [weak self] reason in
            self?.restartCallCount += 1
            self?.lastRestartReason = reason
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
        let correlation = makeCorrelation(
            key: "t",
            suggestsUnmatchedAutorepeat: true,
            msSinceAnyKanataEvent: 5000
        )

        service.handleAutorepeatMismatch(correlation)
        try? await Task.sleep(for: .milliseconds(100))

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
        let correlation = makeCorrelation(
            suggestsUnmatchedAutorepeat: true,
            msSinceAnyKanataEvent: 5000
        )

        service.handleAutorepeatMismatch(correlation)
        try? await Task.sleep(for: .milliseconds(100))
        XCTAssertEqual(restartCallCount, 1)

        service.handleAutorepeatMismatch(correlation)
        try? await Task.sleep(for: .milliseconds(100))
        XCTAssertEqual(restartCallCount, 1, "Should not restart again within cooldown period")
    }

    func testDoesNotDoubleFireWhileRecovering() async {
        var continueRestart: CheckedContinuation<Void, Never>?
        service.restartKanata = { [weak self] reason in
            self?.restartCallCount += 1
            self?.lastRestartReason = reason
            await withCheckedContinuation { continuation in
                continueRestart = continuation
            }
            return true
        }

        let correlation = makeCorrelation(
            suggestsUnmatchedAutorepeat: true,
            msSinceAnyKanataEvent: 5000
        )

        service.handleAutorepeatMismatch(correlation)
        try? await Task.sleep(for: .milliseconds(50))

        service.handleAutorepeatMismatch(correlation)
        try? await Task.sleep(for: .milliseconds(50))

        continueRestart?.resume()
        try? await Task.sleep(for: .milliseconds(50))

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
