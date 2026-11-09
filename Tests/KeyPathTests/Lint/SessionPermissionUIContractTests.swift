import Foundation
@preconcurrency import XCTest

/// The session-only bundle has no launcher that users can grant permission to,
/// and KeyPath asks for exactly one permission.
final class SessionPermissionUIContractTests: XCTestCase {
    private func source(_ path: String) throws -> String {
        let root = URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent().deletingLastPathComponent()
            .deletingLastPathComponent().deletingLastPathComponent()
        return try String(contentsOf: root.appendingPathComponent(path), encoding: .utf8)
    }

    func testPermissionPageOnlyOffersKeyPathGrantSubject() throws {
        let text = try source("Sources/KeyPathInstallationWizard/UI/Pages/WizardAccessibilityPage.swift")
        XCTAssertFalse(text.contains("kanata-launcher"))
        XCTAssertFalse(text.contains("setServiceBounceNeeded"))
        XCTAssertFalse(text.contains("Full Disk Access"))
        XCTAssertFalse(text.contains("inputMonitoring"))
        let grantActions = text.components(separatedBy: "\n")
            .filter { $0.contains("DragToAuthorizeController.shared.present") }
        XCTAssertFalse(grantActions.isEmpty)
        XCTAssertTrue(grantActions.allSatisfy { $0.contains("subject: .keyPath") })
    }

    func testInputMonitoringPageIsGone() {
        let root = URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent().deletingLastPathComponent()
            .deletingLastPathComponent().deletingLastPathComponent()
        let page = root.appendingPathComponent("Sources/KeyPathInstallationWizard/UI/Pages/WizardInputMonitoringPage.swift")
        XCTAssertFalse(FileManager.default.fileExists(atPath: page.path))
    }

    func testFinderPermissionHelperDoesNotRevealOrModifyRemovedLauncher() throws {
        let text = try source("Sources/KeyPathInstallationWizard/UI/Helpers/WizardPermissionFinderHelper.swift")
        XCTAssertTrue(text.contains("Bundle.main.bundleURL"))
        XCTAssertTrue(text.contains("Bundle.main.bundlePath"))
        for forbidden in ["bundledKanataLauncherPath", "chflags", "setIcon", "SubprocessRunner", "kanata-launcher", "ListenEvent"] {
            XCTAssertFalse(text.contains(forbidden), "Unexpected permission helper operation: \(forbidden)")
        }
    }
}
