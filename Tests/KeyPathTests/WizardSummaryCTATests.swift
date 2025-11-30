@preconcurrency import XCTest

@testable import KeyPathAppKit

final class WizardSummaryCTATests: XCTestCase {
    func testHelperCTAVisibleWhenHelperMissing() async {
        let interpreter = WizardStateInterpreter()
        let show = await interpreter.shouldShowHelperCTA(helperInstalledProvider: { false })
        XCTAssertTrue(show)
    }

    func testHelperCTAHiddenWhenHelperInstalled() async {
        let interpreter = WizardStateInterpreter()
        let show = await interpreter.shouldShowHelperCTA(helperInstalledProvider: { true })
        XCTAssertFalse(show)
    }
}
