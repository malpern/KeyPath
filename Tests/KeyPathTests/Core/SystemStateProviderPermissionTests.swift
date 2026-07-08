@testable import KeyPathAppKit
@testable import KeyPathCore
@testable import KeyPathPermissions
@preconcurrency import XCTest

final class SystemStateProviderPermissionTests: XCTestCase {
    func testPermissionSnapshotAccessDelegatesToPermissionOracle() async {
        let provider = SystemStateProvider()

        let snapshot = await provider.currentPermissionSnapshot()

        XCTAssertEqual(snapshot.keyPath.source, "test.placeholder")
        XCTAssertEqual(snapshot.kanata.source, "test.placeholder")
        XCTAssertEqual(snapshot.keyPath.confidence, .low)
        XCTAssertEqual(snapshot.kanata.confidence, .low)
    }

    func testPermissionSnapshotRefreshBypassesCachedSnapshot() async {
        let provider = SystemStateProvider()

        let first = await provider.currentPermissionSnapshot()
        let refreshed = await provider.refreshPermissionSnapshot()

        XCTAssertGreaterThanOrEqual(refreshed.timestamp, first.timestamp)
    }
}
