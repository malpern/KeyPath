import XCTest
@testable import KeyPath

@MainActor
final class PermissionOracleTests: XCTestCase {
    override func setUp() async throws {
        TestEnvironment.forceTestMode = true
    }

    override func tearDown() async throws {
        TestEnvironment.forceTestMode = false
    }

    func testSnapshotInTestModeIsFastAndNonBlocking() async {
        let start = Date()
        let snapshot = await PermissionOracle.shared.currentSnapshot()
        let duration = Date().timeIntervalSince(start)

        XCTAssertLessThan(duration, 1.0, "Oracle snapshot should be fast in test mode")
        XCTAssertEqual(snapshot.keyPath.confidence, .low)
        XCTAssertTrue(snapshot.keyPath.source.contains("test"))
    }

    func testSnapshotCachingHonorsTTLInTestMode() async {
        let first = await PermissionOracle.shared.currentSnapshot()
        let second = await PermissionOracle.shared.currentSnapshot()
        // In test mode, immediate second call should return cached snapshot with same timestamp
        XCTAssertEqual(first.timestamp.timeIntervalSince1970, second.timestamp.timeIntervalSince1970)
    }
}


