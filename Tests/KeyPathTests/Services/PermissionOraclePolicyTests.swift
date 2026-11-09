import Foundation
@testable import KeyPathAppKit
import KeyPathCore
import KeyPathPermissions
import Testing

@Suite("Permission Oracle Policy Tests")
struct PermissionOraclePolicyTests {
    @Test("Status.isMissing is false only when granted")
    func statusIsMissingSemantics() {
        #expect(PermissionOracle.Status.granted.isMissing == false)
        #expect(PermissionOracle.Status.unknown.isMissing == true)
        #expect(PermissionOracle.Status.denied.isMissing == true)
        #expect(PermissionOracle.Status.error("boom").isMissing == true)
    }

    @Test("Blocking issue names Device Control and Data Access, never Input Monitoring")
    func blockingMessageNamesAccessibilityOnly() {
        for snap in [
            PermissionOracle.Snapshot.fixture(accessibility: .denied),
            PermissionOracle.Snapshot.fixture(runtimeKeyAccess: .denied)
        ] {
            let issue = snap.blockingIssue ?? ""
            #expect(issue.contains(AccessibilityPermissionPresentation.current.name))
            #expect(!issue.contains("Input Monitoring"))
            #expect(issue.contains("KeyPath"))
        }
    }

    @Test("Unknown Accessibility is non-blocking; denied runtime access then asks for a relaunch")
    func runtimeBlocksWhenAccessibilityUnknown() {
        let snap = PermissionOracle.Snapshot.fixture(accessibility: .unknown, runtimeKeyAccess: .denied)
        #expect(snap.blockingIssue == "Quit and reopen KeyPath so it can use \(AccessibilityPermissionPresentation.current.name).")
        #expect(!snap.isSystemReady)
    }

    @Test("An Accessibility error blocks before a denied runtime")
    func accessibilityErrorPrecedesRuntimeDenied() {
        let snap = PermissionOracle.Snapshot.fixture(accessibility: .error("AX read failed"), runtimeKeyAccess: .denied)
        let issue = snap.blockingIssue ?? ""
        #expect(issue.contains("Enable KeyPath"))
        #expect(!issue.contains("Kanata"))
    }
}
