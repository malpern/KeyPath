import AppKit
@testable import KeyPathAppKit
import XCTest

final class AppLaunchInfoTests: XCTestCase {
    // MARK: - kanataOutput

    func testKanataOutput_withBundleIdentifier() {
        let info = AppLaunchInfo(
            name: "Safari",
            bundleIdentifier: "com.apple.Safari",
            icon: NSImage()
        )
        XCTAssertEqual(info.kanataOutput, "(push-msg \"launch:com.apple.Safari\")")
    }

    func testKanataOutput_withoutBundleIdentifier() {
        let info = AppLaunchInfo(
            name: "MyApp",
            bundleIdentifier: nil,
            icon: NSImage()
        )
        XCTAssertEqual(info.kanataOutput, "(push-msg \"launch:MyApp\")")
    }

    func testKanataOutput_prefersBundleIdentifierOverName() {
        let info = AppLaunchInfo(
            name: "Terminal",
            bundleIdentifier: "com.apple.Terminal",
            icon: NSImage()
        )
        // Should use bundle ID, not name
        XCTAssertTrue(info.kanataOutput.contains("com.apple.Terminal"))
        XCTAssertFalse(info.kanataOutput.contains("\"launch:Terminal\""))
    }

    // MARK: - Equatable

    func testEquatable_sameValues() {
        let icon = NSImage()
        let info1 = AppLaunchInfo(name: "Safari", bundleIdentifier: "com.apple.Safari", icon: icon)
        let info2 = AppLaunchInfo(name: "Safari", bundleIdentifier: "com.apple.Safari", icon: icon)
        XCTAssertEqual(info1, info2)
    }

    func testEquatable_differentNames() {
        let icon = NSImage()
        let info1 = AppLaunchInfo(name: "Safari", bundleIdentifier: "com.apple.Safari", icon: icon)
        let info2 = AppLaunchInfo(name: "Chrome", bundleIdentifier: "com.apple.Safari", icon: icon)
        XCTAssertNotEqual(info1, info2)
    }

    func testEquatable_differentBundleIds() {
        let icon = NSImage()
        let info1 = AppLaunchInfo(name: "Safari", bundleIdentifier: "com.apple.Safari", icon: icon)
        let info2 = AppLaunchInfo(name: "Safari", bundleIdentifier: "com.google.Chrome", icon: icon)
        XCTAssertNotEqual(info1, info2)
    }
}
