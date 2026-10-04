import Foundation
@preconcurrency import XCTest

/// The session-only bundle has no launcher that users can grant permission to.
final class SessionPermissionUIContractTests: XCTestCase {
    private func source(_ path: String) throws -> String {
        let root = URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent().deletingLastPathComponent()
            .deletingLastPathComponent().deletingLastPathComponent()
        return try String(contentsOf: root.appendingPathComponent(path), encoding: .utf8)
    }

    func testPermissionPagesOnlyOfferKeyPathGrantSubject() throws {
        for page in ["WizardAccessibilityPage", "WizardInputMonitoringPage"] {
            let text = try source("Sources/KeyPathInstallationWizard/UI/Pages/\(page).swift")
            XCTAssertFalse(text.contains("kanata-launcher"))
            XCTAssertFalse(text.contains("setServiceBounceNeeded"))
            XCTAssertFalse(text.contains("Full Disk Access"))
            let grantActions = text.components(separatedBy: "\n")
                .filter { $0.contains("DragToAuthorizeController.shared.present") }
            XCTAssertFalse(grantActions.isEmpty)
            XCTAssertTrue(grantActions.allSatisfy { $0.contains("subject: .keyPath") })
        }
    }

    func testEffectiveInputAccessAndMissingWorkerEvidenceRemainDistinct() throws {
        let text = try source("Sources/KeyPathInstallationWizard/UI/Pages/WizardInputMonitoringPage.swift")
        XCTAssertFalse(text.contains("snapshot.keyPath.inputMonitoring"))
        XCTAssertTrue(text.contains("snapshot.kanata.inputMonitoring"))
        XCTAssertTrue(text.contains("if case .unknown = snapshot.kanata.inputMonitoring"))
        XCTAssertTrue(text.contains("if !sessionInputNeedsVerification, keyPathGuidance == .manualFallback"))
        XCTAssertTrue(text.contains("startKanata(reason: \"Wizard verifying session input access\")"))
    }

    func testFinderPermissionHelperDoesNotRevealOrModifyRemovedLauncher() throws {
        let text = try source("Sources/KeyPathInstallationWizard/UI/Helpers/WizardPermissionFinderHelper.swift")
        XCTAssertTrue(text.contains("Bundle.main.bundleURL"))
        XCTAssertTrue(text.contains("Bundle.main.bundlePath"))
        for forbidden in ["bundledKanataLauncherPath", "chflags", "setIcon", "SubprocessRunner", "kanata-launcher"] {
            XCTAssertFalse(text.contains(forbidden), "Unexpected permission helper operation: \(forbidden)")
        }
    }
}
