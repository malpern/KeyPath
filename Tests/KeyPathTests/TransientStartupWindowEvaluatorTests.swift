@testable import KeyPathAppKit
import XCTest

final class TransientStartupWindowEvaluatorTests: XCTestCase {
    private let grace: TimeInterval = 18.0

    private func makeEvaluator(createdAt: Date) -> TransientStartupWindowEvaluator {
        TransientStartupWindowEvaluator(gracePeriod: grace, createdAt: createdAt)
    }

    func testIsStartingIsAlwaysInWindow() {
        // Even long past the grace period, an in-progress start keeps us in window.
        let created = Date(timeIntervalSince1970: 1_000_000)
        let now = created.addingTimeInterval(grace * 10)
        let evaluator = makeEvaluator(createdAt: created)

        XCTAssertTrue(evaluator.isInWindow(
            now: now,
            isStarting: true,
            lastStartAttemptAt: nil,
            isSMAppServicePending: false
        ))
    }

    func testWithinGracePeriodOfCreation() {
        let created = Date(timeIntervalSince1970: 1_000_000)
        let now = created.addingTimeInterval(grace - 1)
        let evaluator = makeEvaluator(createdAt: created)

        XCTAssertTrue(evaluator.isInWindow(
            now: now,
            isStarting: false,
            lastStartAttemptAt: nil,
            isSMAppServicePending: false
        ))
    }

    func testOutsideGracePeriodOfCreation() {
        let created = Date(timeIntervalSince1970: 1_000_000)
        let now = created.addingTimeInterval(grace + 1)
        let evaluator = makeEvaluator(createdAt: created)

        XCTAssertFalse(evaluator.isInWindow(
            now: now,
            isStarting: false,
            lastStartAttemptAt: nil,
            isSMAppServicePending: false
        ))
    }

    func testRecentStartAttemptExtendsWindow() {
        // Creation was long ago, but a recent start attempt should still count.
        let created = Date(timeIntervalSince1970: 1_000_000)
        let now = created.addingTimeInterval(grace * 5)
        let recentStart = now.addingTimeInterval(-(grace - 1))
        let evaluator = makeEvaluator(createdAt: created)

        XCTAssertTrue(evaluator.isInWindow(
            now: now,
            isStarting: false,
            lastStartAttemptAt: recentStart,
            isSMAppServicePending: false
        ))
    }

    func testStaleStartAttemptDoesNotExtendWindow() {
        let created = Date(timeIntervalSince1970: 1_000_000)
        let now = created.addingTimeInterval(grace * 5)
        let oldStart = now.addingTimeInterval(-(grace + 1))
        let evaluator = makeEvaluator(createdAt: created)

        XCTAssertFalse(evaluator.isInWindow(
            now: now,
            isStarting: false,
            lastStartAttemptAt: oldStart,
            isSMAppServicePending: false
        ))
    }

    func testSMAppServicePendingIsFallbackOnly() {
        // SMAppService pending is the last check — only matters when every
        // time-based signal has already said "out of window".
        let created = Date(timeIntervalSince1970: 1_000_000)
        let now = created.addingTimeInterval(grace * 5)
        let evaluator = makeEvaluator(createdAt: created)

        XCTAssertTrue(evaluator.isInWindow(
            now: now,
            isStarting: false,
            lastStartAttemptAt: nil,
            isSMAppServicePending: true
        ))
        XCTAssertFalse(evaluator.isInWindow(
            now: now,
            isStarting: false,
            lastStartAttemptAt: nil,
            isSMAppServicePending: false
        ))
    }
}
