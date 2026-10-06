@testable import KeyPathAppKit
import XCTest

@MainActor
final class ApplicationTerminationCoordinatorTests: XCTestCase {
    func testCleanupPrecedesWindowsPluginsAndReplyAndCoalescesRepeatedQuit() async {
        let coordinator = ApplicationTerminationCoordinator()
        var phases: [String] = []
        var cleanup: CheckedContinuation<Bool, Never>?
        var flush: CheckedContinuation<Void, Never>?
        let request = {
            coordinator.request(
                suppressStarts: { phases.append("hold:\($0)") },
                stop: { phases.append("stop"); return await withCheckedContinuation { cleanup = $0 } },
                updateExpected: { false },
                cleanupRefused: { _ in XCTFail("unexpected refusal") },
                finish: {
                    phases.append("windows/plugins")
                    await withCheckedContinuation { flush = $0 }
                },
                reply: { phases.append("reply:\($0)") }
            )
        }
        request()
        XCTAssertEqual(phases, ["hold:true"], "Queued starts must be invalidated before the asynchronous hop")
        request()
        while cleanup == nil {
            await Task.yield()
        }
        XCTAssertEqual(phases, ["hold:true", "stop"])
        cleanup?.resume(returning: true)
        while flush == nil {
            await Task.yield()
        }
        request()
        XCTAssertTrue(coordinator.isPending)
        XCTAssertEqual(phases, ["hold:true", "stop", "windows/plugins"], "Keep the start hold and defer reply while plugins finish")
        flush?.resume()
        while !phases.contains("reply:true") {
            await Task.yield()
        }
        XCTAssertEqual(phases, ["hold:true", "stop", "windows/plugins", "reply:true"])
        XCTAssertTrue(coordinator.isPending, "Keep runtime admission held until process exit")
    }

    func testOrdinaryQuitRefusalPreservesEvidenceAndStillQuits() async {
        let coordinator = ApplicationTerminationCoordinator()
        var phases: [String] = []
        coordinator.request(
            suppressStarts: { phases.append("hold:\($0)") }, stop: { false }, updateExpected: { false },
            cleanupRefused: { phases.append("refused/cancel:\($0)") },
            finish: { XCTFail("refused ordinary cleanup must reply without another asynchronous preparation hop") },
            reply: { phases.append("reply:\($0)") }
        )
        while !phases.contains("reply:true") {
            await Task.yield()
        }
        XCTAssertEqual(phases, ["hold:true", "refused/cancel:false", "reply:true"])
    }

    func testUpdateBecomingExpectedDuringCleanupCancelsWithoutClosingUIAndAllowsRetry() async {
        let coordinator = ApplicationTerminationCoordinator()
        let expectation = UpdateTerminationExpectation()
        var cleanup: CheckedContinuation<Bool, Never>?
        var phases: [String] = []
        coordinator.request(
            suppressStarts: { phases.append("hold:\($0)") },
            stop: { await withCheckedContinuation { cleanup = $0 } },
            updateExpected: { expectation.isExpected },
            cleanupRefused: { phases.append("refused/cancel:\($0)") },
            finish: { XCTFail("cancelled update closed windows or flushed plugins") },
            reply: { phases.append("reply:\($0)") }
        )
        while cleanup == nil {
            await Task.yield()
        }
        expectation.willExtract()
        cleanup?.resume(returning: false)
        while !phases.contains("reply:false") {
            await Task.yield()
        }
        XCTAssertEqual(phases, ["hold:true", "refused/cancel:true", "hold:false", "reply:false"])
        XCTAssertFalse(coordinator.isPending)
        coordinator.request(
            suppressStarts: { phases.append("retry-hold:\($0)") }, stop: { true },
            updateExpected: { expectation.isExpected }, cleanupRefused: { _ in XCTFail() },
            finish: { phases.append("retry-finish") }, reply: { phases.append("retry-reply:\($0)") }
        )
        while !phases.contains("retry-reply:true") {
            await Task.yield()
        }
        XCTAssertEqual(Array(phases.suffix(3)), ["retry-hold:true", "retry-finish", "retry-reply:true"])
    }

    func testAbortedExtractionClearsExpectationButStagedInstallerSurvivesLaterAbort() {
        let expectation = UpdateTerminationExpectation()
        XCTAssertFalse(expectation.isExpected)
        expectation.willExtract()
        XCTAssertTrue(expectation.isExpected)
        expectation.didAbort()
        XCTAssertFalse(expectation.isExpected)
        expectation.willInstall()
        expectation.didFinishCycle(errorOccurred: false)
        XCTAssertTrue(expectation.isExpected, "A successful cycle can leave installation scheduled for Quit")
        expectation.didAbort()
        XCTAssertTrue(expectation.isExpected, "A later check error cannot prove an external staged installer was cancelled")
    }
}
