@testable import KeyPathInstallationWizard
@testable import KeyPathWizardCore
import XCTest

@MainActor
final class WizardRulesHandoffTests: XCTestCase {
    func testVerifiedSessionQueuesRulesBeforeSynchronousDismissalWithoutCapsTour() {
        var events: [String] = []
        let view = InstallationWizardView(
            onFirstSuccess: { events.append("tour") },
            onOpenRules: { events.append("rules") },
            didShowWelcomePage: true,
            postStartStateDetector: { fatalError("No refresh expected") },
            dismissHandler: { events.append("dismiss") }
        )
        view.stateMachine.updateWizardState(.active, issues: [])
        view.dismissAndRefreshMainScreen()
        XCTAssertEqual(events, ["rules", "dismiss"])
    }

    func testIncompleteSetupClosesWithoutOpeningRules() {
        for state: WizardSystemState in [.initializing, .ready, .serviceNotRunning] {
            var opened = false
            let view = InstallationWizardView(
                onOpenRules: { opened = true },
                postStartStateDetector: { fatalError("No refresh expected") },
                dismissHandler: {}
            )
            view.stateMachine.updateWizardState(state, issues: [])
            view.dismissAndRefreshMainScreen()
            XCTAssertFalse(opened)
        }
    }

    func testActiveStateWithUnresolvedIssueDoesNotOpenRules() {
        var opened = false
        let view = InstallationWizardView(
            onOpenRules: { opened = true },
            postStartStateDetector: { fatalError("No refresh expected") },
            dismissHandler: {}
        )
        let issue = WizardIssue(
            identifier: .permission(.keyPathInputMonitoring), severity: .warning,
            category: .permissions, title: "Not verified", description: "",
            autoFixAction: nil, userAction: ""
        )
        view.stateMachine.updateWizardState(.active, issues: [issue])
        view.dismissAndRefreshMainScreen()
        XCTAssertFalse(opened)
    }
}
