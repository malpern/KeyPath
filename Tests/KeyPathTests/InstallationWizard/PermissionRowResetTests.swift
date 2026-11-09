@testable import KeyPathInstallationWizard
@preconcurrency import XCTest

final class PermissionRowResetTests: XCTestCase {
    func testResetsOnlyThisAppsOwnRowForTheService() {
        var calls: [(String, [String])] = []
        let ok = PermissionRowReset.reset(.accessibility, bundleID: "com.keypath.KeyPath") { path, args in
            calls.append((path, args))
            return 0
        }
        XCTAssertTrue(ok)
        XCTAssertEqual(calls.count, 1)
        XCTAssertEqual(calls.first?.0, "/usr/bin/tccutil")
        XCTAssertEqual(calls.first?.1, ["reset", "Accessibility", "com.keypath.KeyPath"])
    }

    func testRefusesWithoutABundleIDRatherThanResettingEveryApp() {
        var ran = false
        XCTAssertFalse(PermissionRowReset.reset(.accessibility, bundleID: nil) { _, _ in ran = true; return 0 })
        XCTAssertFalse(PermissionRowReset.reset(.accessibility, bundleID: "") { _, _ in ran = true; return 0 })
        XCTAssertFalse(ran, "tccutil reset without a bundle ID would clear every app's row")
    }

    func testReportsFailureWhenTccutilFails() {
        XCTAssertFalse(PermissionRowReset.reset(.accessibility, bundleID: "com.keypath.KeyPath") { _, _ in 1 })
    }
}
