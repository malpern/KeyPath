import Foundation
@testable import KeyPathAppKit
import KeyPathRulesCore
import XCTest

/// Project review S10: the config folder is the user's alone, and Karabiner
/// import shows what each launch or script shortcut will do.
@MainActor
final class SmallSecurityFixesTests: XCTestCase {
    func testConfigFolderIsTightenedToItsOwner() throws {
        let folder = FileManager.default.temporaryDirectory.appendingPathComponent("perm-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true,
                                                attributes: [.posixPermissions: 0o755])
        defer { try? FileManager.default.removeItem(at: folder) }
        ConfigurationService.restrictToOwner(directory: folder.path)
        let mode = try XCTUnwrap(FileManager.default.attributesOfItem(atPath: folder.path)[.posixPermissions] as? Int)
        XCTAssertEqual(mode & 0o777, 0o700)
    }

    func testCLIUninstallStopsUnlessThePersonConfirms() async {
        var asked = 0
        let withoutYes = await RuntimeControlHandler.uninstallRefusal(confirmed: false, ask: { asked += 1; return true })
        XCTAssertNotNil(withoutYes)
        XCTAssertEqual(asked, 0, "Without --yes, KeyPath does not even ask")
        let cancelled = await RuntimeControlHandler.uninstallRefusal(confirmed: true, ask: { asked += 1; return false })
        XCTAssertNotNil(cancelled)
        let confirmed = await RuntimeControlHandler.uninstallRefusal(confirmed: true, ask: { asked += 1; return true })
        XCTAssertNil(confirmed)
        XCTAssertEqual(asked, 2)
        XCTAssertLessThan(RuntimeControlHandler.cliConfirmationTimeout, 120, "The dialog closes before the CLI stops waiting")
    }

    func testImportReviewShowsTheFullTarget() {
        XCTAssertEqual(KeyAction.runScript(path: "curl x | sh", name: "Build").importReviewDescription,
                       "Runs curl x | sh")
        XCTAssertEqual(KeyAction.openURL("https://example.com/a?b").importReviewDescription,
                       "Opens https://example.com/a?b")
        XCTAssertEqual(KeyAction.openFolder(path: "~/Work", name: nil).importReviewDescription,
                       "Opens the folder ~/Work")
        XCTAssertEqual(KeyAction.launchApp(name: "Safari", bundleId: "com.apple.Safari").importReviewDescription,
                       "Opens com.apple.Safari")
    }
}
