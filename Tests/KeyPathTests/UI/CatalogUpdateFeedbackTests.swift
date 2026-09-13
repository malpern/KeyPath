@testable import KeyPathAppKit
import KeyPathCore
import XCTest

final class CatalogUpdateFeedbackTests: XCTestCase {
    func testRestoredRuleStateReportsPendingRuntimeRecovery() {
        let reload = ReloadResult(success: true, response: nil, errorMessage: nil, protocol: nil, disposition: .pending)
        let result = KeyPathAppKit.SaveResult.failure(
            KeyPathError.configuration(.validationFailed(errors: ["Rejected"])),
            recoveryResult: KeyPathAppKit.SaveRecoveryResult.restoredPreviousRuleState(reloadResult: reload)
        )

        XCTAssertEqual(
            CatalogUpdateFeedback.failureMessage(for: result),
            "The catalog update was not accepted. Your previous rules were restored. The restored rules are saved and will apply when the engine is available."
        )
    }

    func testRuleStateRecoveryFailureIsNotReportedAsAnOrdinarySaveFailure() {
        let result = KeyPathAppKit.SaveResult.failure(
            KeyPathError.configuration(.validationFailed(errors: ["Rejected"])),
            recoveryResult: KeyPathAppKit.SaveRecoveryResult.ruleStateRecoveryFailed(TestFailure())
        )

        XCTAssertEqual(
            CatalogUpdateFeedback.failureMessage(for: result),
            "The catalog update was not accepted, and restoring your previous rules also failed. Please review your configuration and backup."
        )
    }

    private struct TestFailure: Error {}
}
