@testable import KeyPathAppKit
import XCTest

/// Air, 2026-10-18 12:14: launched while locked, the runtime waited for Secure
/// Input to end and the wizard was suppressed, but the splash fallback treated
/// "runtime not yet running" as incomplete setup and never hid the splash.
@MainActor
final class LaunchSetupCompletionTests: XCTestCase {
    func testPendingRuntimeRecoveryCountsAsCompletedSetup() {
        XCTAssertTrue(AppDelegate.initialSetupComplete(runtimeReady: false, runtimeRecoveryPending: true))
    }

    func testReadyRuntimeCompletesSetupAndStoppedRuntimeDoesNot() {
        XCTAssertTrue(AppDelegate.initialSetupComplete(runtimeReady: true, runtimeRecoveryPending: false))
        XCTAssertFalse(AppDelegate.initialSetupComplete(runtimeReady: false, runtimeRecoveryPending: false))
    }
}
