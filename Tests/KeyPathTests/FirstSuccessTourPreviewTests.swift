@testable import KeyPathAppKit
import XCTest

@MainActor
final class FirstSuccessTourPreviewTests: XCTestCase {
    func testEveryPageAndScenarioCanBeReachedWithoutCompletingEarlierActions() {
        let model = FirstSuccessTourPreviewModel()
        for page in FirstSuccessOnboardingSession.Step.allCases {
            for scenario in FirstSuccessTourPreviewModel.Scenario.allCases {
                model.select(page: page, scenario: scenario)
                XCTAssertEqual(model.coordinator.session.step, page)
                XCTAssertEqual(model.scenario, scenario)
                XCTAssertTrue(model.coordinator.canDismiss)
                if scenario == .selected {
                    XCTAssertEqual(model.choice.canonicalKey, "s")
                    XCTAssertNotNil(model.choice.mapping)
                }
                if scenario == .failed { XCTAssertNotNil(model.coordinator.session.failure) }
            }
        }
    }

    func testSwitchingBackToFreshClearsChoiceAndFailure() {
        let model = FirstSuccessTourPreviewModel()
        model.select(page: .launcher, scenario: .failed)
        model.select(page: .capsLock, scenario: .fresh)
        XCTAssertNil(model.choice.selectedApp)
        XCTAssertNil(model.coordinator.session.failure)
        XCTAssertEqual(model.coordinator.session.capsLockPhase, .explaining)
        XCTAssertEqual(model.coordinator.session.hyperPhase, .explaining)
    }

    func testPreviewActionsAndFinishUseOnlyInjectedPresentationCallbacks() async {
        let model = FirstSuccessTourPreviewModel()
        model.select(page: .launcher, scenario: .selected)
        var closed = false
        let dialog = model.dialog { closed = true }
        let caps = await dialog.makeCapsLockEscape()
        let hyper = await dialog.addHyperHold()
        let launcher = await dialog.saveLauncherShortcut(model.choice.mapping!)
        XCTAssertEqual(caps, .applied)
        XCTAssertEqual(hyper, .applied)
        XCTAssertEqual(launcher, .applied)
        dialog.finishInKeyboard()
        XCTAssertTrue(closed)
    }
}
