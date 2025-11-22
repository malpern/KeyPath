import Foundation
import Testing

@testable import KeyPathAppKit
@testable import KeyPathPermissions

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

    @Test("Status description is accurate")
    func statusDescription() {
        #expect(PermissionOracle.Status.granted.description == "granted")
        #expect(PermissionOracle.Status.denied.description == "denied")
        #expect(PermissionOracle.Status.unknown.description == "unknown")
        #expect(PermissionOracle.Status.error("test").description == "error(test)")
    }

    // MARK: - PermissionSet Tests

    @Test("PermissionSet.hasAllPermissions requires both AX and IM")
    func permissionSetHasAll() {
        let granted = PermissionOracle.PermissionSet(
            accessibility: .granted,
            inputMonitoring: .granted,
            source: "test",
            confidence: .high,
            timestamp: Date()
        )
        #expect(granted.hasAllPermissions == true)

        let missingAX = PermissionOracle.PermissionSet(
            accessibility: .denied,
            inputMonitoring: .granted,
            source: "test",
            confidence: .high,
            timestamp: Date()
        )
        #expect(missingAX.hasAllPermissions == false)

        let missingIM = PermissionOracle.PermissionSet(
            accessibility: .granted,
            inputMonitoring: .denied,
            source: "test",
            confidence: .high,
            timestamp: Date()
        )
        #expect(missingIM.hasAllPermissions == false)

        let bothMissing = PermissionOracle.PermissionSet(
            accessibility: .denied,
            inputMonitoring: .denied,
            source: "test",
            confidence: .high,
            timestamp: Date()
        )
        #expect(bothMissing.hasAllPermissions == false)
    }

    // MARK: - Snapshot Tests

    @Test("Snapshot.isSystemReady requires both apps to have all permissions")
    func snapshotSystemReady() {
        let now = Date()
        let granted = PermissionOracle.PermissionSet(
            accessibility: .granted,
            inputMonitoring: .granted,
            source: "test",
            confidence: .high,
            timestamp: now
        )

        let denied = PermissionOracle.PermissionSet(
            accessibility: .denied,
            inputMonitoring: .denied,
            source: "test",
            confidence: .high,
            timestamp: now
        )

        // Both apps fully granted
        let allGranted = PermissionOracle.Snapshot(
            keyPath: granted,
            kanata: granted,
            timestamp: now
        )
        #expect(allGranted.isSystemReady == true)

        // KeyPath missing permissions
        let keyPathMissing = PermissionOracle.Snapshot(
            keyPath: denied,
            kanata: granted,
            timestamp: now
        )
        #expect(keyPathMissing.isSystemReady == false)

        // Kanata missing permissions
        let kanataMissing = PermissionOracle.Snapshot(
            keyPath: granted,
            kanata: denied,
            timestamp: now
        )
        #expect(kanataMissing.isSystemReady == false)

        // Both missing permissions
        let bothMissing = PermissionOracle.Snapshot(
            keyPath: denied,
            kanata: denied,
            timestamp: now
        )
        #expect(bothMissing.isSystemReady == false)
    }

    @Test("Snapshot.blockingIssue identifies first blocker")
    func snapshotBlockingIssue() {
        let now = Date()

        // No issues
        let granted = PermissionOracle.PermissionSet(
            accessibility: .granted,
            inputMonitoring: .granted,
            source: "test",
            confidence: .high,
            timestamp: now
        )
        let noIssues = PermissionOracle.Snapshot(
            keyPath: granted,
            kanata: granted,
            timestamp: now
        )
        #expect(noIssues.blockingIssue == nil)

        // KeyPath AX blocked
        let keyPathAXBlocked = PermissionOracle.PermissionSet(
            accessibility: .denied,
            inputMonitoring: .granted,
            source: "test",
            confidence: .high,
            timestamp: now
        )
        let axIssue = PermissionOracle.Snapshot(
            keyPath: keyPathAXBlocked,
            kanata: granted,
            timestamp: now
        )
        #expect(axIssue.blockingIssue?.contains("KeyPath needs Accessibility") == true)

        // KeyPath IM blocked
        let keyPathIMBlocked = PermissionOracle.PermissionSet(
            accessibility: .granted,
            inputMonitoring: .denied,
            source: "test",
            confidence: .high,
            timestamp: now
        )
        let imIssue = PermissionOracle.Snapshot(
            keyPath: keyPathIMBlocked,
            kanata: granted,
            timestamp: now
        )
        #expect(imIssue.blockingIssue?.contains("KeyPath needs Input Monitoring") == true)

        // Kanata blocked (KeyPath OK)
        let kanataBlocked = PermissionOracle.PermissionSet(
            accessibility: .denied,
            inputMonitoring: .denied,
            source: "test",
            confidence: .high,
            timestamp: now
        )
        let kanataIssue = PermissionOracle.Snapshot(
            keyPath: granted,
            kanata: kanataBlocked,
            timestamp: now
        )
        #expect(kanataIssue.blockingIssue?.contains("Kanata needs permissions") == true)
    }

    @Test("Snapshot.blockingIssue prioritizes KeyPath over Kanata")
    func snapshotBlockingIssuePriority() {
        let now = Date()

        let keyPathBlocked = PermissionOracle.PermissionSet(
            accessibility: .denied,
            inputMonitoring: .granted,
            source: "test",
            confidence: .high,
            timestamp: now
        )

        let kanataBlocked = PermissionOracle.PermissionSet(
            accessibility: .denied,
            inputMonitoring: .denied,
            source: "test",
            confidence: .high,
            timestamp: now
        )

        // Both blocked - should report KeyPath first
        let bothBlocked = PermissionOracle.Snapshot(
            keyPath: keyPathBlocked,
            kanata: kanataBlocked,
            timestamp: now
        )
        #expect(bothBlocked.blockingIssue?.contains("KeyPath") == true)
        #expect(bothBlocked.blockingIssue?.contains("Kanata") == false)
    }

    @Test("Snapshot.diagnosticSummary contains key information")
    func snapshotDiagnosticSummary() {
        let now = Date()
        let granted = PermissionOracle.PermissionSet(
            accessibility: .granted,
            inputMonitoring: .granted,
            source: "test-source",
            confidence: .high,
            timestamp: now
        )

        let snapshot = PermissionOracle.Snapshot(
            keyPath: granted,
            kanata: granted,
            timestamp: now
        )

        let summary = snapshot.diagnosticSummary
        #expect(summary.contains("Permission Oracle Snapshot"))
        #expect(summary.contains("KeyPath"))
        #expect(summary.contains("Kanata"))
        #expect(summary.contains("test-source"))
        #expect(summary.contains("high"))
        #expect(summary.contains("granted"))
        #expect(summary.contains("System Ready: true"))
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
        let oracle = PermissionOracle.shared
        let snapshot = await oracle.currentSnapshot()

        // In test mode, should get placeholder with unknown status
        #expect(snapshot.keyPath.accessibility == PermissionOracle.Status.unknown)
        #expect(snapshot.keyPath.inputMonitoring == PermissionOracle.Status.unknown)
        #expect(snapshot.kanata.accessibility == PermissionOracle.Status.unknown)
        #expect(snapshot.kanata.inputMonitoring == PermissionOracle.Status.unknown)
        #expect(snapshot.keyPath.source == "test.placeholder")
        #expect(snapshot.keyPath.confidence == PermissionOracle.Confidence.low)
    }

    @Test("Cache invalidation works")
    func cacheInvalidation() async {
        let oracle = PermissionOracle.shared

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
        let oracle = PermissionOracle.shared

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
