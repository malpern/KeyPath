import KeyPathCore
import XCTest

final class AccessibilityPermissionPresentationTests: XCTestCase {
    func testMacOS26UsesAccessibilityInDisplayedGuidance() {
        let copy = AccessibilityPermissionPresentation(macOSMajorVersion: 26)
        XCTAssertEqual(copy.name, "Accessibility")
        XCTAssertEqual(copy.openButtonTitle, "Open Accessibility")
        XCTAssertEqual(copy.enableTitle, "Enable Accessibility")
        XCTAssertEqual(copy.turnOnInstruction, "Turn on KeyPath under Accessibility.")
        XCTAssertEqual(copy.settingsPath, "System Settings > Privacy & Security > Accessibility")
    }

    func testMacOS27UsesRenamedPaneInDisplayedGuidance() {
        let copy = AccessibilityPermissionPresentation(macOSMajorVersion: 27)
        XCTAssertEqual(copy.name, "Device Control and Data Access")
        XCTAssertEqual(copy.openButtonTitle, "Open Settings")
        XCTAssertEqual(copy.enableTitle, "Enable Device Control and Data Access")
        XCTAssertEqual(copy.enabledTitle, "Device Control and Data Access enabled")
        XCTAssertEqual(copy.openTitle, "Open Device Control and Data Access")
        XCTAssertEqual(copy.turnOnInstruction, "Turn on KeyPath under Device Control and Data Access.")
        XCTAssertEqual(copy.grantInstruction, "Open KeyPath.app and grant Device Control and Data Access in System Settings > Privacy & Security > Device Control and Data Access")
    }
}
