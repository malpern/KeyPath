import Foundation
@testable import KeyPathAppKit
@testable import KeyPathCore
@testable import KeyPathPermissions
import Testing

@Suite("PermissionOracle Fast/Test Mode", .serialized)
struct PermissionOracleFastModeTests {
    @Test("Snapshot in test mode completes under 1 second")
    @MainActor
    func snapshotIsFastInTestMode() async {
        TestEnvironment.forceTestMode = true
        defer { TestEnvironment.forceTestMode = false }

        let oracle = PermissionOracle()
        let start = Date()
        let snapshot = await oracle.currentSnapshot()
        let duration = Date().timeIntervalSince(start)

        #expect(duration < 1.0)
        #expect(snapshot.keyPath.confidence == .low)
        #expect(snapshot.keyPath.source.contains("test"))
    }

    @Test("Cached snapshot has same timestamp on immediate re-read")
    @MainActor
    func snapshotCachingHonorsTTL() async {
        TestEnvironment.forceTestMode = true
        defer { TestEnvironment.forceTestMode = false }

        let oracle = PermissionOracle()
        let first = await oracle.currentSnapshot()
        let second = await oracle.currentSnapshot()
        #expect(first.timestamp.timeIntervalSince1970 == second.timestamp.timeIntervalSince1970)
    }

    @Test("Kanata permission set also uses low confidence in test mode")
    @MainActor
    func kanataConfidenceLowInTestMode() async {
        TestEnvironment.forceTestMode = true
        defer { TestEnvironment.forceTestMode = false }

        let oracle = PermissionOracle()
        let snapshot = await oracle.currentSnapshot()
        #expect(snapshot.kanata.confidence == .low)
    }

    @Test("Snapshot has a recent timestamp")
    @MainActor
    func snapshotTimestampIsRecent() async {
        TestEnvironment.forceTestMode = true
        defer { TestEnvironment.forceTestMode = false }

        let oracle = PermissionOracle()
        let before = Date()
        let snapshot = await oracle.currentSnapshot()
        #expect(snapshot.timestamp >= before.addingTimeInterval(-1))
    }

    @Test("forceRefresh returns a fresh snapshot in test mode")
    @MainActor
    func forceRefreshWorksInTestMode() async {
        TestEnvironment.forceTestMode = true
        defer { TestEnvironment.forceTestMode = false }

        let oracle = PermissionOracle()
        await oracle.invalidateCache()
        let start = Date()
        let snapshot = await oracle.forceRefresh()
        let duration = Date().timeIntervalSince(start)

        #expect(duration < 1.0)
        #expect(snapshot.keyPath.confidence == .low)
    }

    @Test("diagnosticSummary is non-empty in test mode")
    @MainActor
    func diagnosticSummaryNonEmpty() async {
        TestEnvironment.forceTestMode = true
        defer { TestEnvironment.forceTestMode = false }

        let oracle = PermissionOracle()
        let snapshot = await oracle.currentSnapshot()
        #expect(!snapshot.diagnosticSummary.isEmpty)
        #expect(snapshot.diagnosticSummary.contains("Permission Oracle"))
    }
}
