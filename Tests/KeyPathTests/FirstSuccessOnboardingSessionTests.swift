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
    func testReplayCanDescribePreservedHyperWithoutSkippingItsLesson() {
        let session = FirstSuccessOnboardingSession()

        session.begin(.capsLockEscape)
        session.recordCapsLockHold(isHyper: true)
        session.finish(.capsLockEscape, result: .alreadyConfigured)

        XCTAssertTrue(session.capsLockHoldIsHyper)
        XCTAssertEqual(session.capsLockPhase, .installed)
        XCTAssertEqual(session.hyperPhase, .explaining)
    }

    @MainActor
    func testReturningToCapsDescribesHyperAddedByTheSecondLesson() {
        let session = FirstSuccessOnboardingSession()

        session.finish(.capsLockEscape, result: .applied)
        session.moveForward()
        session.finish(.hyper, result: .applied)
        session.moveBack()

        XCTAssertEqual(session.step, .capsLock)
        XCTAssertTrue(session.capsLockHasHyperHold)
    }

    @MainActor
    func testLauncherShortcutMustApplyBeforeTheThirdWinCompletes() {
        let session = FirstSuccessOnboardingSession()
        session.step = .launcher

        XCTAssertTrue(session.isLauncherChoiceEditable)
        XCTAssertTrue(session.begin(.launcherShortcut))
        XCTAssertEqual(session.launcherPhase, .applying)
        XCTAssertFalse(session.isLauncherChoiceEditable)
        XCTAssertFalse(session.moveForward())

        session.finish(.launcherShortcut, result: .failed)
        XCTAssertEqual(session.step, .launcher)
        XCTAssertEqual(session.launcherPhase, .explaining)
        XCTAssertEqual(session.failure, .launcherShortcut)
        XCTAssertTrue(session.isLauncherChoiceEditable)

        XCTAssertTrue(session.begin(.launcherShortcut))
        session.finish(.launcherShortcut, result: .applied)
        XCTAssertEqual(session.launcherPhase, .installed)
        XCTAssertFalse(session.isLauncherChoiceEditable)
        XCTAssertTrue(session.moveForward())
        XCTAssertEqual(session.step, .rules)
    }

    @MainActor
    func testBlockedLauncherChoiceCanBeCorrected() {
        let session = FirstSuccessOnboardingSession()

        session.begin(.launcherShortcut)
        session.finish(.launcherShortcut, result: .needsRules)

        XCTAssertEqual(session.launcherPhase, .blocked)
        XCTAssertTrue(session.isLauncherChoiceEditable)
    }

    @MainActor
    func testSavedLauncherChoiceStaysLockedWhileActivationRetries() {
        let session = FirstSuccessOnboardingSession()

        session.begin(.launcherShortcut)
        session.finish(.launcherShortcut, result: .savedButNotActive)

        XCTAssertEqual(session.launcherPhase, .explaining)
        XCTAssertEqual(session.savedButNotActive, .launcherShortcut)
        XCTAssertFalse(session.isLauncherChoiceEditable)

        XCTAssertTrue(session.begin(.launcherShortcut))
        session.finish(.launcherShortcut, result: .applied)

        XCTAssertEqual(session.launcherPhase, .installed)
        XCTAssertNil(session.savedButNotActive)
    }

    @MainActor
    func testApplyingSessionBlocksNavigationAndASecondBegin() {
        let session = FirstSuccessOnboardingSession()

        XCTAssertTrue(session.begin(.capsLockEscape))
        session.finish(.capsLockEscape, result: .applied)
        XCTAssertTrue(session.moveForward())
        XCTAssertEqual(session.step, .hyper)

        XCTAssertTrue(session.begin(.hyper))

        XCTAssertFalse(session.moveBack())
        XCTAssertFalse(session.moveForward())
        XCTAssertFalse(session.begin(.capsLockEscape))
        XCTAssertEqual(session.step, .hyper)
        XCTAssertEqual(session.hyperPhase, .applying)
    }

    @MainActor
    func testSuspendedDurableActionDisablesButtonsAndRemainsSingleFlight() async {
        let session = FirstSuccessOnboardingSession()
        XCTAssertTrue(session.begin(.capsLockEscape))
        session.finish(.capsLockEscape, result: .applied)
        XCTAssertTrue(session.moveForward())

        let coordinator = FirstSuccessOnboardingActionCoordinator(session: session)
        let gate = FirstSuccessActionGate()
        let mutationStarts = FirstSuccessActionCounter()

        let firstStarted = coordinator.start(
            .hyper,
            initialPresentationDelay: .zero,
            minimumPresentation: .zero
        ) {
            await mutationStarts.increment()
            await gate.wait()
            return .applied
        }
        XCTAssertTrue(firstStarted)

        XCTAssertEqual(
            coordinator.buttonState,
            FirstSuccessOnboardingButtonState(
                skipTourEnabled: false,
                backEnabled: false,
                primaryEnabled: false
            )
        )
        XCTAssertFalse(coordinator.canDismiss)
        XCTAssertFalse(coordinator.moveBack())

        var dismissCount = 0
        XCTAssertFalse(coordinator.requestDismiss { dismissCount += 1 })
        XCTAssertEqual(dismissCount, 0)

        let secondStarted = coordinator.start(
            .capsLockEscape,
            initialPresentationDelay: .zero,
            minimumPresentation: .zero
        ) {
            await mutationStarts.increment()
            return .applied
        }
        XCTAssertFalse(secondStarted)

        for _ in 0 ..< 50 {
            if await gate.waiterCount == 1 { break }
            await Task.yield()
        }
        let suspendedWaiters = await gate.waiterCount
        let startsWhileSuspended = await mutationStarts.value
        XCTAssertEqual(suspendedWaiters, 1)
        XCTAssertEqual(startsWhileSuspended, 1)
        XCTAssertEqual(session.step, .hyper)

        await gate.open()
        for _ in 0 ..< 50 {
            if !coordinator.isActionInFlight { break }
            await Task.yield()
        }

        XCTAssertFalse(coordinator.isActionInFlight)
        XCTAssertEqual(session.hyperPhase, .installed)
        let completedMutationStarts = await mutationStarts.value
        XCTAssertEqual(completedMutationStarts, 1)
        XCTAssertEqual(
            coordinator.buttonState,
            FirstSuccessOnboardingButtonState(
                skipTourEnabled: true,
                backEnabled: true,
                primaryEnabled: true
            )
        )
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

private actor FirstSuccessActionGate {
    private var isOpen = false
    private var continuations: [CheckedContinuation<Void, Never>] = []
    private(set) var waiterCount = 0

    func wait() async {
        waiterCount += 1
        guard !isOpen else { return }
        await withCheckedContinuation { continuation in
            continuations.append(continuation)
        }
    }

    func open() {
        guard !isOpen else { return }
        isOpen = true
        let pending = continuations
        continuations.removeAll()
        pending.forEach { $0.resume() }
    }
}

private actor FirstSuccessActionCounter {
    private(set) var value = 0

    func increment() {
        value += 1
    }
}
