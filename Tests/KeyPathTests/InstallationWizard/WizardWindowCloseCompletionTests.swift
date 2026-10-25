@testable import KeyPathAppKit
import XCTest

@MainActor
final class WizardWindowCloseCompletionTests: XCTestCase {
    func testScheduledActionWaitsForCloseAndRunsOnlyOnce() {
        var completion = WizardWindowCloseCompletion()
        var invocationCount = 0

        completion.schedule {
            invocationCount += 1
        }

        XCTAssertEqual(invocationCount, 0)

        completion.runIfScheduled()
        completion.runIfScheduled()

        XCTAssertEqual(invocationCount, 1)
    }
}
