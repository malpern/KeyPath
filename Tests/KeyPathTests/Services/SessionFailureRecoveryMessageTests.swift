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
        XCTAssertTrue(message.contains("Connect only the selected keyboard"))
        XCTAssertTrue(message.contains("quit and reopen KeyPath"))
        XCTAssertFalse(message.contains("System Settings"))
    }
}
