@testable import KeyPathAppKit
import KeyPathCore
import XCTest

@MainActor
final class SessionFailureRecoveryMessageTests: XCTestCase {
    func testConfirmedDenialExplainsBothGrantsAndRelaunch() {
        let message = ServiceLifecycleCoordinator.sessionFailureRecoveryMessage("missing-current-process-permission")
        XCTAssertTrue(message.hasPrefix("Enable \(AccessibilityPermissionPresentation.current.name)"))
        XCTAssertTrue(message.contains("quit and reopen KeyPath"))
    }

    func testDisabledTapOffersPermissionRecoveryWithoutClaimingRevocation() {
        for cause in ["tap-disabled-by-user-input", "tap-disabled-observed", "modifying-tap-unavailable", "modifying-tap-not-enabled"] {
            let message = ServiceLifecycleCoordinator.sessionFailureRecoveryMessage(cause)
            XCTAssertTrue(message.contains("If access is disabled, enable it"), cause)
            XCTAssertTrue(message.contains("quit and reopen KeyPath"), cause)
            XCTAssertFalse(message.contains("revoked"), cause)
        }
    }

    func testActualTimeoutRemainsDistinctFromPermissionDenial() {
        let message = ServiceLifecycleCoordinator.sessionFailureRecoveryMessage("tap-disabled-by-timeout")
        XCTAssertTrue(message.contains("timed out"))
        XCTAssertFalse(message.contains("System Settings"))
    }

    func testUnknownFailureKeepsItsDiagnosticAndRecoveryAction() {
        let message = ServiceLifecycleCoordinator.sessionFailureRecoveryMessage("runtime-unavailable")
        XCTAssertFalse(message.contains("runtime-unavailable"))
        XCTAssertTrue(message.contains("Quit and reopen KeyPath"))
    }

    func testCapsOwnershipFailureExplainsTheSingleKeyboardRequirement() {
        let message = ServiceLifecycleCoordinator.sessionFailureRecoveryMessage("managed-caps-ownership-lost")
        XCTAssertTrue(message.contains("second identical keyboard"))
        XCTAssertTrue(message.contains("quit and reopen KeyPath"))
        XCTAssertFalse(message.contains("System Settings"))
    }

    /// An unplugged keyboard is not an ownership fault: the message names the
    /// disconnect and the fix, and does not ask for a relaunch.
    func testCapsKeyboardDisconnectAsksToChooseAgain() {
        let message = ServiceLifecycleCoordinator.sessionFailureRecoveryMessage(SessionCapsRuntimeSupport.keyboardDisconnectedReason)
        XCTAssertTrue(message.contains("disconnected"))
        XCTAssertTrue(message.contains("Settings > General"))
        XCTAssertFalse(message.contains("quit and reopen"))
    }

    func testPausedCapsMessageNamesTheDisconnectedKeyboardAndKeepsOtherRules() throws {
        let named = try XCTUnwrap(ServiceLifecycleCoordinator.capsPausedMessage(disconnected: "cl80", setupOff: false))
        XCTAssertTrue(named.hasPrefix("cl80 was disconnected."))
        XCTAssertTrue(named.contains("other rules keep working"))
        XCTAssertTrue(named.contains("Settings > General"))
        let unchosen = try XCTUnwrap(ServiceLifecycleCoordinator.capsPausedMessage(disconnected: nil, setupOff: false))
        XCTAssertFalse(unchosen.contains("disconnected"))
        XCTAssertTrue(unchosen.contains("Caps Lock rules are paused"))
        XCTAssertNil(ServiceLifecycleCoordinator.capsPausedMessage(disconnected: "cl80", setupOff: true),
                     "Turning Caps Lock setup off is the user's choice; Settings already says so")
    }

    func testStoppedStatusSaysWhyWhenItKnows() {
        XCTAssertEqual(StatusSettingsTabView.stoppedMessage(lastError: nil), "Runtime is stopped. Use the switch above to turn it on.")
        XCTAssertEqual(StatusSettingsTabView.stoppedMessage(lastError: "Driverless remapping stopped."),
                       "Runtime is stopped. Driverless remapping stopped.")
    }
}
