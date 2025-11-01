@testable import KeyPath
import XCTest

final class WizardSummaryCTATests: XCTestCase {
    func testHelperCTAVisibleWhenHelperMissing() {
        let interpreter = WizardStateInterpreter()
        let show = interpreter.shouldShowHelperCTA(helperInstalledProvider: { false })
        XCTAssertTrue(show)
    }

    func testHelperCTAHiddenWhenHelperInstalled() {
        let interpreter = WizardStateInterpreter()
        let show = interpreter.shouldShowHelperCTA(helperInstalledProvider: { true })
        XCTAssertFalse(show)
    }
}
