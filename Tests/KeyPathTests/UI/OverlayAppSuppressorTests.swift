@testable import KeyPathAppKit
import XCTest

@MainActor
final class OverlayAppSuppressorTests: XCTestCase {
    func testPermissionWindowsAreSuppressedWithoutUserExclusions() {
        for bundle in ["com.apple.systempreferences", "com.apple.SecurityAgent"] {
            XCTAssertTrue(OverlayAppSuppressor.shouldSuppress(frontBundle: bundle, userSuppressed: []))
        }
    }

    func testSuppressionBlocksLauncherActivationAndAutomaticShows() {
        let controller = LiveKeyboardOverlayController.shared
        let wasSuppressed = controller.isAppSuppressed
        let wasLauncherActive = controller.isLauncherSessionActive
        defer {
            controller.isAppSuppressed = wasSuppressed
            controller.isLauncherSessionActive = wasLauncherActive
        }
        controller.isAppSuppressed = true
        controller.isLauncherSessionActive = false
        controller.handleLauncherLayerActivated()
        XCTAssertFalse(controller.isLauncherSessionActive)
        XCTAssertFalse(controller.canAutoShow)
        XCTAssertFalse(controller.canShowOverlay(reason: "test"))
    }

    func testNormalAppsStillFollowUserExclusions() {
        XCTAssertFalse(OverlayAppSuppressor.shouldSuppress(frontBundle: "com.apple.finder", userSuppressed: []))
        XCTAssertTrue(OverlayAppSuppressor.shouldSuppress(frontBundle: "com.apple.finder", userSuppressed: ["com.apple.finder"]))
        XCTAssertFalse(OverlayAppSuppressor.shouldSuppress(frontBundle: nil, userSuppressed: []))
    }
}
