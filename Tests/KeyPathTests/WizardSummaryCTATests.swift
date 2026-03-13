@testable import KeyPathAppKit
@testable import KeyPathInstallationWizard
@preconcurrency import XCTest

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
