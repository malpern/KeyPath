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

    func testImportReviewShowsTheFullTarget() {
        XCTAssertEqual(WizardKarabinerImportPage.importReviewDescription(.runScript(path: "curl x | sh", name: "Build")),
                       "Runs curl x | sh")
        XCTAssertEqual(WizardKarabinerImportPage.importReviewDescription(.openURL("https://example.com/a?b")),
                       "Opens https://example.com/a?b")
        XCTAssertEqual(WizardKarabinerImportPage.importReviewDescription(.openFolder(path: "~/Work", name: nil)),
                       "Opens the folder ~/Work")
        XCTAssertEqual(WizardKarabinerImportPage.importReviewDescription(.launchApp(name: "Safari", bundleId: "com.apple.Safari")),
                       "Opens com.apple.Safari")
    }
}
