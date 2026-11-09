@testable import KeyPathAppKit
import KeyPathWizardCore
import XCTest

/// "Fix it" opens Settings > General only when paused Caps Lock rules are the
/// sole problem; anything the wizard can act on still opens the wizard.
@MainActor
final class StatusFixItRoutingTests: XCTestCase {
    private func route(
        capsPaused: Bool = true, runtimeHealthy: Bool = true, permissionsReady: Bool = true,
        wizardSeverities: [WizardIssue.IssueSeverity] = []
    ) -> Bool {
        StatusSettingsTabView.capsPausedIsOnlyIssue(
            capsPaused: capsPaused, runtimeHealthy: runtimeHealthy,
            permissionsReady: permissionsReady, wizardSeverities: wizardSeverities
        )
    }

    func testPausedCapsAloneOpensGeneral() {
        XCTAssertTrue(route())
        XCTAssertTrue(route(wizardSeverities: [.info]))
    }

    func testEachOtherProblemOpensTheWizard() {
        XCTAssertFalse(route(capsPaused: false))
        XCTAssertFalse(route(runtimeHealthy: false))
        XCTAssertFalse(route(permissionsReady: false))
        XCTAssertFalse(route(wizardSeverities: [.warning]))
        XCTAssertFalse(route(wizardSeverities: [.error]))
        XCTAssertFalse(route(wizardSeverities: [.critical]))
    }
}
