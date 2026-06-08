import Foundation
import KeyPathCore
import KeyPathPermissions
import Testing

@Suite("PermissionOracle Isolated Fast/Test Mode", .serialized)
struct PermissionOracleFastModeSmokeTests {
    @Test("Snapshot in test mode completes under 1 second")
    @MainActor
    func snapshotIsFastInTestMode() async {
        TestEnvironment.forceTestMode = true
        defer { TestEnvironment.forceTestMode = false }

        let start = Date()
        let snapshot = await PermissionOracle.shared.currentSnapshot()
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

        let first = await PermissionOracle.shared.currentSnapshot()
        let second = await PermissionOracle.shared.currentSnapshot()

        #expect(first.timestamp.timeIntervalSince1970 == second.timestamp.timeIntervalSince1970)
    }

    @Test("forceRefresh returns a fresh snapshot in test mode")
    @MainActor
    func forceRefreshWorksInTestMode() async {
        TestEnvironment.forceTestMode = true
        defer { TestEnvironment.forceTestMode = false }

        await PermissionOracle.shared.invalidateCache()
        let start = Date()
        let snapshot = await PermissionOracle.shared.forceRefresh()
        let duration = Date().timeIntervalSince(start)

        #expect(duration < 1.0)
        #expect(snapshot.keyPath.confidence == .low)
        #expect(!snapshot.diagnosticSummary.isEmpty)
    }
}
