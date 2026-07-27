@testable import KeyPathAppKit
import XCTest

final class FirstSuccessOnboardingSessionTests: XCTestCase {
    @MainActor
    func testVisualPreviewActionsRequireTheExplicitDebugEnvironmentFlag() {
        XCTAssertFalse(
            FirstSuccessOnboardingWindowController.usesNonMutatingVisualPreviewActions(
                environment: [:]
            )
        )
        XCTAssertTrue(
            FirstSuccessOnboardingWindowController.usesNonMutatingVisualPreviewActions(
                environment: ["KEYPATH_FIRST_SUCCESS_PREVIEW_ACTIONS": "1"]
            )
        )
    }

    @MainActor
    func testApplyFailureDoesNotAdvanceTheLesson() {
        let session = FirstSuccessOnboardingSession()

        session.begin(.capsLockEscape)
        session.finish(.capsLockEscape, result: .failed)

        XCTAssertEqual(session.step, .capsLock)
        XCTAssertEqual(session.capsLockPhase, .explaining)
        XCTAssertEqual(session.failure, .capsLockEscape)
    }

    @MainActor
    func testSavedButInactiveChangeStaysRetryableUntilReloadApplies() {
        let session = FirstSuccessOnboardingSession()

        session.begin(.capsLockEscape)
        session.finish(.capsLockEscape, result: .savedButNotActive)

        XCTAssertEqual(session.step, .capsLock)
        XCTAssertEqual(session.capsLockPhase, .explaining)
        XCTAssertEqual(session.failure, .capsLockEscape)
        XCTAssertEqual(session.savedButNotActive, .capsLockEscape)

        session.begin(.capsLockEscape)
        session.finish(.capsLockEscape, result: .applied)

        XCTAssertEqual(session.capsLockPhase, .installed)
        XCTAssertNil(session.failure)
        XCTAssertNil(session.savedButNotActive)
    }

    @MainActor
    func testOnlyAnAppliedReloadCompletesAnOnboardingAction() {
        XCTAssertEqual(
            FirstSuccessOnboardingWindowController.onboardingActionResult(for: .applied),
            .applied
        )
        XCTAssertEqual(
            FirstSuccessOnboardingWindowController.onboardingActionResult(
                for: .applied,
                alreadyConfigured: true
            ),
            .alreadyConfigured
        )

        for disposition in [
            ReloadDisposition.pending,
            ReloadDisposition.rejected,
            ReloadDisposition.failed,
        ] {
            XCTAssertEqual(
                FirstSuccessOnboardingWindowController.onboardingActionResult(
                    for: disposition
                ),
                .savedButNotActive
            )
        }
    }

    @MainActor
    func testInstalledChangeWaitsForAnExplicitContinue() {
        let session = FirstSuccessOnboardingSession()

        session.begin(.capsLockEscape)
        session.finish(.capsLockEscape, result: .applied)

        XCTAssertEqual(session.step, .capsLock)
        XCTAssertEqual(session.capsLockPhase, .installed)

        session.moveForward()
        XCTAssertEqual(session.step, .hyper)
    }

    @MainActor
    func testInterruptedApplyReturnsToARetryablePresentationState() {
        let session = FirstSuccessOnboardingSession()

        session.begin(.capsLockEscape)
        session.cancelApplyingAction()

        XCTAssertEqual(session.step, .capsLock)
        XCTAssertEqual(session.capsLockPhase, .explaining)
        XCTAssertFalse(session.isApplying)
        XCTAssertNil(session.failure)
        XCTAssertNil(session.savedButNotActive)
    }

    @MainActor
    func testPracticeCannotClaimSuccessBeforeInstall() {
        let session = FirstSuccessOnboardingSession()

        session.markCapsLockPracticed()
        XCTAssertEqual(session.capsLockPhase, .explaining)

        session.finish(.capsLockEscape, result: .alreadyConfigured)
        session.markCapsLockPracticed()
        XCTAssertEqual(session.capsLockPhase, .practiced)
    }
}
