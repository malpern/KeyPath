@testable import KeyPathInstallationWizard
import XCTest

final class ServiceActionCompletionEvaluatorTests: XCTestCase {
    func testSuccessfulStartUsesVerifiedRunningPostcondition() {
        let completion = ServiceActionCompletionEvaluator.evaluate(
            operationSucceeded: true,
            target: .running
        )

        XCTAssertEqual(completion, .verifiedRunning)
    }

    func testSuccessfulRestartUsesVerifiedRunningPostcondition() {
        let completion = ServiceActionCompletionEvaluator.evaluate(
            operationSucceeded: true,
            target: .running
        )

        XCTAssertEqual(completion, .verifiedRunning)
    }

    func testSuccessfulStopUsesVerifiedStoppedPostcondition() {
        let completion = ServiceActionCompletionEvaluator.evaluate(
            operationSucceeded: true,
            target: .stopped
        )

        XCTAssertEqual(completion, .verifiedStopped)
    }

    func testFailedActionRequiresFreshStatusSnapshot() {
        for target in [ServiceActionTarget.running, .stopped] {
            let completion = ServiceActionCompletionEvaluator.evaluate(
                operationSucceeded: false,
                target: target
            )

            XCTAssertEqual(completion, .refreshRequired)
        }
    }
}
