@testable import KeyPathAppKit
import KeyPathWizardCore
import XCTest

/// "Fix it" opens Settings > General only when paused Caps Lock rules are the
/// sole problem; anything the wizard can act on still opens the wizard.
@MainActor
final class StatusFixItRoutingTests: XCTestCase {
    private func route(
        driverless: Bool = true, capsPaused: Bool = true, runtimeHealthy: Bool = true,
        tcpConfigured: Bool? = true, permissionsReady: Bool = true,
        wizardSeverities: [WizardIssue.IssueSeverity] = []
    ) -> Bool {
        StatusSettingsTabView.capsPausedIsOnlyIssue(
            driverless: driverless, capsPaused: capsPaused, runtimeHealthy: runtimeHealthy,
            tcpConfigured: tcpConfigured, permissionsReady: permissionsReady, wizardSeverities: wizardSeverities
        )
    }

    func testPausedCapsAloneOpensGeneral() {
        XCTAssertTrue(route())
        XCTAssertTrue(route(tcpConfigured: nil))
        XCTAssertTrue(route(wizardSeverities: [.info]))
    }

    func testEachOtherProblemOpensTheWizard() {
        XCTAssertFalse(route(driverless: false))
        XCTAssertFalse(route(capsPaused: false))
        XCTAssertFalse(route(runtimeHealthy: false))
        XCTAssertFalse(route(tcpConfigured: false))
        XCTAssertFalse(route(permissionsReady: false))
        XCTAssertFalse(route(wizardSeverities: [.warning]))
        XCTAssertFalse(route(wizardSeverities: [.error]))
        XCTAssertFalse(route(wizardSeverities: [.critical]))
    }
}
