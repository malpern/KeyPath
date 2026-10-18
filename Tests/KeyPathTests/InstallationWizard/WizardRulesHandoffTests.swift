@testable import KeyPathInstallationWizard
@testable import KeyPathWizardCore
import XCTest

@MainActor
final class WizardRulesHandoffTests: XCTestCase {
    func testFreshVerifiedSessionQueuesTourBeforeSynchronousDismissal() {
        let defaults = UserDefaults.standard
        let previous = defaults.object(forKey: FirstSuccessOnboardingGate.hasShownKey)
        defaults.set(false, forKey: FirstSuccessOnboardingGate.hasShownKey)
        defer {
            if let previous { defaults.set(previous, forKey: FirstSuccessOnboardingGate.hasShownKey) }
            else { defaults.removeObject(forKey: FirstSuccessOnboardingGate.hasShownKey) }
        }
        var events: [String] = []
        let view = InstallationWizardView(
            onFirstSuccess: { events.append("tour") },
            onOpenKeyboard: { events.append("keyboard") },
            didShowWelcomePage: true,
            postStartStateDetector: { fatalError("No refresh expected") },
            dismissHandler: { events.append("dismiss") }
        )
        view.stateMachine.updateWizardState(.active, issues: [])
        view.dismissAndRefreshMainScreen()
        XCTAssertEqual(events, ["tour", "dismiss"])
    }

    func testPreviouslyPresentedTourQueuesKeyboardBeforeDismissal() {
        let defaults = UserDefaults.standard
        let previous = defaults.object(forKey: FirstSuccessOnboardingGate.hasShownKey)
        defaults.set(true, forKey: FirstSuccessOnboardingGate.hasShownKey)
        defer {
            if let previous { defaults.set(previous, forKey: FirstSuccessOnboardingGate.hasShownKey) }
            else { defaults.removeObject(forKey: FirstSuccessOnboardingGate.hasShownKey) }
        }
        var events: [String] = []
        let view = InstallationWizardView(
            onFirstSuccess: { events.append("tour") },
            onOpenKeyboard: { events.append("keyboard") },
            didShowWelcomePage: true,
            postStartStateDetector: { fatalError("No refresh expected") },
            dismissHandler: { events.append("dismiss") }
        )
        view.stateMachine.updateWizardState(.active, issues: [])
        view.dismissAndRefreshMainScreen()
        XCTAssertEqual(events, ["keyboard", "dismiss"])
    }

    func testFailedPostStartVerificationKeepsRepairOpen() async {
        var dismissed = false
        var opened = false
        let view = InstallationWizardView(
            onOpenKeyboard: { opened = true },
            postStartStateDetector: {
                SystemStateResult(
                    state: .serviceNotRunning, issues: [], autoFixActions: [],
                    detectionTimestamp: Date()
                )
            },
            dismissHandler: { dismissed = true }
        )
        await view.refreshPostStartStateAndDismiss()
        XCTAssertFalse(dismissed)
        XCTAssertFalse(opened)
        XCTAssertEqual(view.stateMachine.wizardState, .serviceNotRunning)
    }

    func testIncompleteSetupClosesWithoutOpeningKeyboard() {
        for state: WizardSystemState in [.initializing, .ready, .serviceNotRunning] {
            var opened = false
            let view = InstallationWizardView(
                onOpenKeyboard: { opened = true },
                postStartStateDetector: { fatalError("No refresh expected") },
                dismissHandler: {}
            )
            view.stateMachine.updateWizardState(state, issues: [])
            view.dismissAndRefreshMainScreen()
            XCTAssertFalse(opened)
        }
    }

    func testActiveStateWithUnresolvedIssueDoesNotOpenKeyboard() {
        var opened = false
        let view = InstallationWizardView(
            onOpenKeyboard: { opened = true },
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
