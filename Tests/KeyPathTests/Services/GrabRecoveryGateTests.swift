@testable import KeyPathAppKit
import XCTest

/// Unit tests for the #625 grab-failure auto-recovery gate — the pure suppression
/// rules that decide whether an authoritative `InputGrab` status should drive
/// recovery. The recover/give-up tail (the bounded budget) is covered separately by
/// `ServiceHealthMonitorTests`; these tests cover only the pre-guard gate so they
/// never touch the real recovery action (which would shell out to launchctl/pgrep).
final class GrabRecoveryGateTests: XCTestCase {
    typealias Gate = RuntimeCoordinator.GrabRecoveryGate

    func testActiveGrabRecordsSuccess() {
        // A healthy grab is always good news — even mid-transition or mid-recovery —
        // and should reset the recovery budget.
        XCTAssertEqual(
            RuntimeCoordinator.decideGrabRecoveryGate(active: true, isIntentionalTransition: false, isRecovering: false),
            .recordSuccess
        )
        XCTAssertEqual(
            RuntimeCoordinator.decideGrabRecoveryGate(active: true, isIntentionalTransition: true, isRecovering: true),
            .recordSuccess
        )
    }

    func testGrabFailureWhileIdleEvaluates() {
        // The real failure case: kanata up, not grabbing, no intentional transition,
        // no recovery in flight → consult the bounded guard.
        XCTAssertEqual(
            RuntimeCoordinator.decideGrabRecoveryGate(active: false, isIntentionalTransition: false, isRecovering: false),
            .evaluate
        )
    }

    func testGrabFailureDuringIntentionalTransitionIsSuppressed() {
        // Benign `active=false` from a kanata we're deliberately stopping must not
        // trigger recovery.
        XCTAssertEqual(
            RuntimeCoordinator.decideGrabRecoveryGate(active: false, isIntentionalTransition: true, isRecovering: false),
            .suppressedDuringTransition
        )
    }

    func testGrabFailureWhileRecoveringIsSuppressed() {
        // Single-flight: a recovery already tearing down/restarting kanata emits more
        // `active=false` events; they must not launch overlapping recoveries.
        XCTAssertEqual(
            RuntimeCoordinator.decideGrabRecoveryGate(active: false, isIntentionalTransition: false, isRecovering: true),
            .suppressedRecoveryInFlight
        )
    }

    func testTransitionSuppressionTakesPrecedenceOverInFlight() {
        // Both gates closed → either suppression is fine; transition is checked first.
        XCTAssertEqual(
            RuntimeCoordinator.decideGrabRecoveryGate(active: false, isIntentionalTransition: true, isRecovering: true),
            .suppressedDuringTransition
        )
    }
}
