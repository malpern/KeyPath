import KeyPathCore
import KeyPathWizardCore
import XCTest

final class AccessibilityPermissionIssuePresentationTests: XCTestCase {
    func testCanonicalPermissionIdentityIsPreservedWhileTitlesFollowOS() {
        for canonical in ["Accessibility", "Accessibility / effective input access"] {
            let issue = Issue.permissionMissing(app: "KeyPath", permission: canonical, action: "unchanged")
            for (major, name) in [(26, "Accessibility"), (27, "Device Control and Data Access")] {
                let suffix = canonical == "Accessibility" ? "" : " / effective input access"
                XCTAssertEqual(issue.displayTitle(accessibility: .init(macOSMajorVersion: major)),
                               "KeyPath needs \(name)\(suffix) permission")
                XCTAssertEqual(issue, .permissionMissing(app: "KeyPath", permission: canonical, action: "unchanged"))
                XCTAssertEqual(issue.action, "unchanged")
                XCTAssertFalse(issue.canAutoFix)
            }
        }
    }

    func testOtherPermissionTitlesAreUnchanged() {
        let issue = Issue.permissionMissing(app: "KeyPath", permission: "Input Monitoring", action: "")
        XCTAssertEqual(issue.displayTitle(accessibility: .init(macOSMajorVersion: 27)),
                       "KeyPath needs Input Monitoring permission")
    }
}
