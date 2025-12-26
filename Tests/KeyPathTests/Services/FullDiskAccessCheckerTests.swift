@testable import KeyPathAppKit
@preconcurrency import XCTest

@MainActor
final class FullDiskAccessCheckerTests: XCTestCase {
    override func tearDown() async throws {
        // Ensure we don't leak test seams into other tests.
        FullDiskAccessChecker.probeOverride = nil
        FullDiskAccessChecker.shared.resetCache()
        try await super.tearDown()
    }

    func testHasFullDiskAccessCachesWithinTTL() {
        FullDiskAccessChecker.shared.resetCache()

        var probeCalls = 0
        FullDiskAccessChecker.probeOverride = {
            probeCalls += 1
            return false
        }

        let a = FullDiskAccessChecker.shared.hasFullDiskAccess()
        let b = FullDiskAccessChecker.shared.hasFullDiskAccess()

        XCTAssertFalse(a)
        XCTAssertFalse(b)
        XCTAssertEqual(probeCalls, 1, "Second call should be served from cache")
    }

    func testRefreshBypassesCache() {
        FullDiskAccessChecker.shared.resetCache()

        var probeValue = false
        var probeCalls = 0
        FullDiskAccessChecker.probeOverride = {
            probeCalls += 1
            return probeValue
        }

        XCTAssertFalse(FullDiskAccessChecker.shared.hasFullDiskAccess())
        XCTAssertEqual(probeCalls, 1)

        probeValue = true
        XCTAssertTrue(FullDiskAccessChecker.shared.refresh())
        XCTAssertEqual(probeCalls, 2, "refresh() should force a new probe")

        // Subsequent call should use the refreshed cached value.
        XCTAssertTrue(FullDiskAccessChecker.shared.hasFullDiskAccess())
        XCTAssertEqual(probeCalls, 2)
    }
}
