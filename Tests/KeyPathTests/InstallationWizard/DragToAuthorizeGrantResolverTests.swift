@testable import KeyPathInstallationWizard
import KeyPathPermissions
@preconcurrency import XCTest

/// Covers the pure grant decision used by the drag-to-authorize overlay (#933).
/// KeyPath.app is the only permission identity, so the overlay polls KeyPath's
/// own Accessibility grant and ignores the runtime's report.
final class DragToAuthorizeGrantResolverTests: XCTestCase {
    private func resolve(_ snapshot: PermissionOracle.Snapshot) -> Bool {
        DragToAuthorizeController.grantResolved(
            target: .accessibility, subject: .keyPath, snapshot: snapshot
        )
    }

    func testAccessibilityReadsKeyPathsGrant() {
        XCTAssertTrue(resolve(.fixture(accessibility: .granted, runtimeKeyAccess: .denied)))
        XCTAssertFalse(resolve(.fixture(accessibility: .denied, runtimeKeyAccess: .granted)))
    }

    func testNonGrantedStatusesAreNotTreatedAsGranted() {
        for status in [PermissionOracle.Status.denied, .unknown, .error("x")] {
            XCTAssertFalse(resolve(.fixture(accessibility: status)), "\(status) must not count as granted")
        }
    }
}
