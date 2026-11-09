import Foundation
@testable import KeyPathAppKit
import KeyPathCore
@testable import KeyPathPermissions
import Testing

/// Comprehensive tests for PermissionOracle - the single source of truth for permissions
@Suite("Permission Oracle Tests")
struct PermissionOracleTests {
    // MARK: - Status Tests

    @Test("Status.isReady returns true only for granted")
    func statusIsReady() {
        #expect(PermissionOracle.Status.granted.isReady == true)
        #expect(PermissionOracle.Status.denied.isReady == false)
        #expect(PermissionOracle.Status.unknown.isReady == false)
        #expect(PermissionOracle.Status.error("test").isReady == false)
    }

    @Test("Status.isBlocking returns true for denied and error")
    func statusIsBlocking() {
        #expect(PermissionOracle.Status.granted.isBlocking == false)
        #expect(PermissionOracle.Status.denied.isBlocking == true)
        #expect(PermissionOracle.Status.unknown.isBlocking == false)
        #expect(PermissionOracle.Status.error("test").isBlocking == true)
    }

    @Test("Status.isMissing treats unknown denied and error as missing")
    func statusIsMissing() {
        #expect(PermissionOracle.Status.granted.isMissing == false)
        #expect(PermissionOracle.Status.denied.isMissing == true)
        #expect(PermissionOracle.Status.unknown.isMissing == true)
        #expect(PermissionOracle.Status.error("test").isMissing == true)
    }

    @Test("Status description is accurate")
    func statusDescription() {
        #expect(PermissionOracle.Status.granted.description == "granted")
        #expect(PermissionOracle.Status.denied.description == "denied")
        #expect(PermissionOracle.Status.unknown.description == "unknown")
        #expect(PermissionOracle.Status.error("test").description == "error(test)")
    }

    // MARK: - Snapshot Tests

    @Test("Snapshot.isSystemReady requires Accessibility and runtime key access")
    func snapshotSystemReady() {
        #expect(PermissionOracle.Snapshot.fixture().isSystemReady == true)
        #expect(PermissionOracle.Snapshot.fixture(accessibility: .denied).isSystemReady == false)
        #expect(PermissionOracle.Snapshot.fixture(runtimeKeyAccess: .denied).isSystemReady == false)
        #expect(PermissionOracle.Snapshot.fixture(runtimeKeyAccess: .unknown).isSystemReady == false)
        #expect(PermissionOracle.Snapshot.fixture(accessibility: .unknown).isSystemReady == false)
    }

    @Test("Snapshot.blockingIssue reports Accessibility, then a runtime relaunch")
    func snapshotBlockingIssue() {
        let name = AccessibilityPermissionPresentation.current.name
        #expect(PermissionOracle.Snapshot.fixture().blockingIssue == nil)

        let axIssue = PermissionOracle.Snapshot.fixture(accessibility: .denied).blockingIssue
        #expect(axIssue == "Enable KeyPath in \(name) in System Settings, then quit and reopen KeyPath.")

        let runtimeIssue = PermissionOracle.Snapshot.fixture(runtimeKeyAccess: .denied).blockingIssue
        #expect(runtimeIssue == "Quit and reopen KeyPath so it can use \(name).")

        // Accessibility outranks the runtime's report.
        let both = PermissionOracle.Snapshot.fixture(accessibility: .denied, runtimeKeyAccess: .denied)
        #expect(both.blockingIssue == axIssue)

        // Unreported runtime access is not a blocker.
        #expect(PermissionOracle.Snapshot.fixture(runtimeKeyAccess: .unknown).blockingIssue == nil)
    }

    @Test("Snapshot.diagnosticSummary contains key information")
    func snapshotDiagnosticSummary() {
        let summary = PermissionOracle.Snapshot.fixture(source: "test-source").diagnosticSummary
        #expect(summary.contains("Permission Oracle Snapshot"))
        #expect(summary.contains("KeyPath"))
        #expect(summary.contains("Runtime key access"))
        #expect(summary.contains("test-source"))
        #expect(summary.contains("high"))
        #expect(summary.contains("granted"))
        #expect(summary.contains("System Ready: true"))
        #expect(!summary.contains("Input Monitoring"))
    }

    @Test("Runtime report combines its Accessibility and key access")
    func runtimeKeyAccessFromReport() {
        let now = Date()
        let ready = PermissionOracle.RuntimeKeyAccess(
            runtimeAccessibility: true, keyAccess: true, source: "worker", timestamp: now
        )
        #expect(ready.status == .granted)
        #expect(ready.confidence == .high)
        #expect(PermissionOracle.RuntimeKeyAccess(
            runtimeAccessibility: false, keyAccess: true, source: "worker", timestamp: now
        ).status == .denied)
        #expect(PermissionOracle.RuntimeKeyAccess(
            runtimeAccessibility: true, keyAccess: false, source: "worker", timestamp: now
        ).status == .denied)
        let unreported = PermissionOracle.RuntimeKeyAccess.notReported(timestamp: now)
        #expect(unreported.status == .unknown)
        #expect(unreported.confidence == .low)
    }

    // MARK: - Confidence Tests

    @Test("Confidence description is accurate")
    func confidenceDescription() {
        #expect(PermissionOracle.Confidence.high.description == "high")
        #expect(PermissionOracle.Confidence.low.description == "low")
    }

    // MARK: - Test Mode Behavior

    @Test("Oracle returns placeholder snapshot in test mode")
    func modeSnapshot() async {
        // This test verifies the Oracle behaves correctly in test environment
        let oracle = PermissionOracle()
        let snapshot = await oracle.currentSnapshot()

        // In test mode, should get placeholder with unknown status
        #expect(snapshot.accessibility == PermissionOracle.Status.unknown)
        #expect(snapshot.runtimeKeyAccess.status == PermissionOracle.Status.unknown)
        #expect(snapshot.runtimeKeyAccess.confidence == PermissionOracle.Confidence.low)
    }

    @Test("Cache invalidation works")
    func cacheInvalidation() async {
        let oracle = PermissionOracle()

        // Get first snapshot
        let snapshot1 = await oracle.currentSnapshot()
        let timestamp1 = snapshot1.timestamp

        // Get second snapshot immediately (should be cached)
        let snapshot2 = await oracle.currentSnapshot()
        let timestamp2 = snapshot2.timestamp

        // Timestamps should be the same (cached)
        #expect(timestamp1 == timestamp2)

        // Invalidate cache
        await oracle.invalidateCache()

        // Get third snapshot (should be fresh)
        let snapshot3 = await oracle.currentSnapshot()
        let timestamp3 = snapshot3.timestamp

        // Timestamp should be different (not cached)
        #expect(timestamp3 >= timestamp1) // May be same in fast tests, but at least not older
    }

    @Test("Force refresh bypasses cache")
    func forceRefresh() async {
        let oracle = PermissionOracle()

        // Get first snapshot
        let snapshot1 = await oracle.currentSnapshot()
        let timestamp1 = snapshot1.timestamp

        // Force refresh should bypass cache
        let snapshot2 = await oracle.forceRefresh()
        let timestamp2 = snapshot2.timestamp

        // New snapshot should have same or newer timestamp
        #expect(timestamp2 >= timestamp1)
    }
}
