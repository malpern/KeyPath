@testable import KeyPathAppKit
@testable import KeyPathInstallationWizard
import XCTest

/// Every branch of Remove Old Service in Settings → Status (#1353).
@MainActor
final class LegacyRuntimeUpgradeFlowTests: KeyPathTestCase {
    private var refreshes = 0
    private var starts = 0

    private func result(success: Bool, reason: String? = nil, notice: String? = nil)
        -> InstallerEngine.LegacyRuntimeRemovalResult
    {
        .init(report: InstallerReport(success: success, failureReason: reason), virtualHIDNotice: notice)
    }

    private func run(
        _ removal: InstallerEngine.LegacyRuntimeRemovalResult,
        stillDetected: Bool = false,
        started: Bool = true,
        lastError: String? = nil
    ) async -> LegacyRuntimeUpgradeFlow.Outcome {
        await LegacyRuntimeUpgradeFlow.run(
            remove: { removal },
            refusalStillStands: { [unowned self] in
                refreshes += 1
                return stillDetected
            },
            start: { [unowned self] in
                starts += 1
                return started
            },
            lastError: { lastError }
        )
    }

    func testFailedRemovalNeverStarts() async {
        let outcome = await run(result(success: false, reason: "Administrator authorization was cancelled."))
        XCTAssertEqual(outcome, .removalFailed("Administrator authorization was cancelled."))
        XCTAssertTrue(outcome.isFailure)
        XCTAssertEqual(refreshes, 0)
        XCTAssertEqual(starts, 0)
    }

    func testStillDetectedDaemonNeverStarts() async {
        let outcome = await run(result(success: true), stillDetected: true)
        XCTAssertEqual(outcome, .stillDetected)
        XCTAssertTrue(outcome.message.contains("Restart your Mac"))
        XCTAssertEqual(starts, 0)
    }

    func testVerifiedRemovalStartsAndNamesTheDriver() async {
        let outcome = await run(result(success: true, notice: "The driver is still installed."))
        XCTAssertEqual(outcome, .started(virtualHIDNotice: "The driver is still installed."))
        XCTAssertEqual(outcome.message, "Old KeyPath service removed. KeyPath is running. The driver is still installed.")
        XCTAssertFalse(outcome.isFailure)
        XCTAssertEqual(refreshes, 1)
        XCTAssertEqual(starts, 1)
    }

    func testRemovedButNotStartedSaysWhy() async {
        let outcome = await run(result(success: true), started: false, lastError: "Accessibility is off.")
        XCTAssertEqual(outcome.message, "Old KeyPath service removed. Accessibility is off.")
        XCTAssertFalse(outcome.isFailure, "The removal itself succeeded")

        let unexplained = await run(result(success: true), started: false)
        XCTAssertEqual(unexplained.message, "Old KeyPath service removed. Turn KeyPath on with the switch above.")
    }
}
