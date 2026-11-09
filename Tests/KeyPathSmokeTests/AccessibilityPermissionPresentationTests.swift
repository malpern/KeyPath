import KeyPathCore
import XCTest

final class AccessibilityPermissionPresentationTests: XCTestCase {
    func testUsesMacOS27PaneNameInDisplayedGuidance() {
        let copy = AccessibilityPermissionPresentation()
        XCTAssertEqual(copy.name, "Device Control and Data Access")
        XCTAssertEqual(copy.openButtonTitle, "Open Settings")
        XCTAssertEqual(copy.enableTitle, "Enable Device Control and Data Access")
        XCTAssertEqual(copy.enabledTitle, "Device Control and Data Access enabled")
        XCTAssertEqual(copy.openTitle, "Open Device Control and Data Access")
        XCTAssertEqual(copy.turnOnInstruction, "Turn on KeyPath under Device Control and Data Access.")
        XCTAssertEqual(copy.grantInstruction, "Open KeyPath.app and grant Device Control and Data Access in System Settings > Privacy & Security > Device Control and Data Access")
    }
}
