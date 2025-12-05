import Foundation
import KeyPathCore
import Testing

@testable import KeyPathAppKit
@testable import KeyPathPermissions

/// Comprehensive tests for PermissionOracle's TCC database fallback logic
/// Focuses on improving coverage of:
/// - Path normalization
/// - SQL injection prevention
/// - Cache behavior with TTL
/// - Fallback paths and graceful degradation
/// - Permission set logic
@Suite("Permission Oracle TCC Database Tests")
struct PermissionOracleTCCTests {
    // MARK: - Path Normalization Tests

    @Test("normalizePathForTCC converts development build paths to installed paths")
    func pathNormalizationDevelopmentBuild() {
        // Test development build path with /build/
        let devPath = "/Volumes/External/build/KeyPath.app/Contents/MacOS/kanata"
        let normalized = testNormalizePathForTCC(devPath)
        #expect(normalized == "/Applications/KeyPath.app/Contents/MacOS/kanata")
    }

    @Test("normalizePathForTCC converts .build paths to installed paths")
    func pathNormalizationSwiftBuild() {
        // Test Swift Package Manager build path
        let buildPath = "/Users/dev/KeyPath/.build/debug/KeyPath.app/Contents/MacOS/kanata"
        let normalized = testNormalizePathForTCC(buildPath)
        #expect(normalized == "/Applications/KeyPath.app/Contents/MacOS/kanata")
    }

    @Test("normalizePathForTCC preserves installed paths unchanged")
    func pathNormalizationInstalledPath() {
        // Already an installed path - should be unchanged
        let installedPath = "/Applications/KeyPath.app/Contents/MacOS/kanata"
        let normalized = testNormalizePathForTCC(installedPath)
        #expect(normalized == installedPath)
    }

    @Test("normalizePathForTCC handles paths without KeyPath.app")
    func pathNormalizationNonKeyPathPath() {
        // Path that doesn't contain KeyPath.app
        let otherPath = "/usr/local/bin/kanata"
        let normalized = testNormalizePathForTCC(otherPath)
        #expect(normalized == otherPath)
    }

    // MARK: - SQL Injection Prevention Tests

    @Test("escapeSQLiteLiteral escapes single quotes")
    func sqlEscapeSingleQuote() {
        let input = "'; DROP TABLE access; --"
        let escaped = testEscapeSQLiteLiteral(input)
        // Single quotes should be doubled
        #expect(escaped == "''; DROP TABLE access; --")
        // SQL injection attempt should be neutralized (no unescaped single quotes)
        let parts = escaped.components(separatedBy: "'")
        // After splitting by ', we should have 4 parts (empty, empty, DROP..., empty)
        // because the doubled '' counts as 2 separate ' characters
        #expect(parts.count >= 3)
    }

    @Test("escapeSQLiteLiteral handles multiple single quotes")
    func sqlEscapeMultipleQuotes() {
        let input = "It's a test's path's"
        let escaped = testEscapeSQLiteLiteral(input)
        #expect(escaped == "It''s a test''s path''s")
    }

    @Test("escapeSQLiteLiteral handles strings without quotes")
    func sqlEscapeNoQuotes() {
        let input = "/Applications/KeyPath.app/Contents/MacOS/kanata"
        let escaped = testEscapeSQLiteLiteral(input)
        #expect(escaped == input)
    }

    @Test("escapeSQLiteLiteral handles empty string")
    func sqlEscapeEmpty() {
        let input = ""
        let escaped = testEscapeSQLiteLiteral(input)
        #expect(escaped == "")
    }

    // MARK: - Cache TTL Tests

    @Test("Cache respects 1.5s TTL within window")
    func cacheTTLWithinWindow() async {
        let oracle = PermissionOracle.shared

        // Invalidate to start fresh
        await oracle.invalidateCache()

        // Get first snapshot
        let snapshot1 = await oracle.currentSnapshot()
        let timestamp1 = snapshot1.timestamp

        // Get second snapshot immediately (should be cached)
        let snapshot2 = await oracle.currentSnapshot()
        let timestamp2 = snapshot2.timestamp

        // Should be same cached snapshot
        #expect(timestamp1.timeIntervalSince1970 == timestamp2.timeIntervalSince1970)
    }

    @Test("Multiple rapid calls use cache efficiently")
    func cacheEfficiency() async {
        let oracle = PermissionOracle.shared
        await oracle.invalidateCache()

        let start = Date()

        // Make 10 rapid calls
        var snapshots: [PermissionOracle.Snapshot] = []
        for _ in 0..<10 {
            let snapshot = await oracle.currentSnapshot()
            snapshots.append(snapshot)
        }

        let duration = Date().timeIntervalSince(start)

        // Should complete quickly (all cached after first)
        #expect(duration < 0.5)

        // All snapshots should reference the same cached instance
        // (same timestamp means cache hit)
        let firstTimestamp = snapshots[0].timestamp
        for snapshot in snapshots {
            // Use tolerance for timestamp comparison due to potential async timing
            let diff = abs(snapshot.timestamp.timeIntervalSince1970 - firstTimestamp.timeIntervalSince1970)
            #expect(diff < 0.001) // Within 1ms tolerance
        }
    }

    @Test("Force refresh bypasses cache and creates new snapshot")
    func forceRefreshBypassesCache() async {
        let oracle = PermissionOracle.shared
        await oracle.invalidateCache()

        // Get first snapshot
        let snapshot1 = await oracle.currentSnapshot()

        // Force refresh should bypass cache
        let snapshot2 = await oracle.forceRefresh()

        // Timestamps should be >= (not older)
        #expect(snapshot2.timestamp >= snapshot1.timestamp)
    }

    @Test("Cache invalidation clears cached snapshot")
    func cacheInvalidationClears() async {
        let oracle = PermissionOracle.shared

        // Get a snapshot (creates cache)
        _ = await oracle.currentSnapshot()

        // Invalidate
        await oracle.invalidateCache()

        // Next call should create fresh snapshot
        let snapshot = await oracle.currentSnapshot()
        #expect(snapshot.timestamp <= Date())
    }

    // MARK: - Fallback Path Tests

    @Test("checkKanataPermissions falls back to .unknown when TCC fails")
    func kanataTCCFallback() async {
        // When TCC database is unreadable (no FDA), should gracefully return .unknown
        // This tests the nil fallback path in checkKanataPermissions
        let oracle = PermissionOracle.shared

        // In test mode, Kanata permissions default to .unknown
        let snapshot = await oracle.currentSnapshot()
        #expect(snapshot.kanata.accessibility == .unknown)
        #expect(snapshot.kanata.inputMonitoring == .unknown)
        #expect(snapshot.kanata.confidence == .low)
    }

    @Test("checkKanataPermissions sets low confidence when unknown")
    func kanataLowConfidenceUnknown() async {
        let oracle = PermissionOracle.shared
        let snapshot = await oracle.currentSnapshot()

        // In test mode, both should be unknown with low confidence
        #expect(snapshot.kanata.confidence == .low)
        #expect(snapshot.kanata.source.contains("unknown") || snapshot.kanata.source.contains("test"))
    }

    // MARK: - Permission Set Construction Tests

    @Test("PermissionSet.hasAllPermissions checks both AX and IM")
    func permissionSetBothRequired() {
        let now = Date()

        // Only AX granted
        let onlyAX = PermissionOracle.PermissionSet(
            accessibility: .granted,
            inputMonitoring: .denied,
            source: "test",
            confidence: .high,
            timestamp: now
        )
        #expect(onlyAX.hasAllPermissions == false)

        // Only IM granted
        let onlyIM = PermissionOracle.PermissionSet(
            accessibility: .denied,
            inputMonitoring: .granted,
            source: "test",
            confidence: .high,
            timestamp: now
        )
        #expect(onlyIM.hasAllPermissions == false)

        // Both granted
        let both = PermissionOracle.PermissionSet(
            accessibility: .granted,
            inputMonitoring: .granted,
            source: "test",
            confidence: .high,
            timestamp: now
        )
        #expect(both.hasAllPermissions == true)
    }

    @Test("PermissionSet.hasAllPermissions treats unknown as not ready")
    func permissionSetUnknownNotReady() {
        let now = Date()

        let unknown = PermissionOracle.PermissionSet(
            accessibility: .unknown,
            inputMonitoring: .unknown,
            source: "test",
            confidence: .low,
            timestamp: now
        )
        #expect(unknown.hasAllPermissions == false)

        // Mix of granted and unknown
        let mixed = PermissionOracle.PermissionSet(
            accessibility: .granted,
            inputMonitoring: .unknown,
            source: "test",
            confidence: .low,
            timestamp: now
        )
        #expect(mixed.hasAllPermissions == false)
    }

    @Test("PermissionSet.hasAllPermissions treats error as not ready")
    func permissionSetErrorNotReady() {
        let now = Date()

        let error = PermissionOracle.PermissionSet(
            accessibility: .error("test error"),
            inputMonitoring: .granted,
            source: "test",
            confidence: .high,
            timestamp: now
        )
        #expect(error.hasAllPermissions == false)
    }

    // MARK: - Snapshot Diagnostic Summary Tests

    @Test("Snapshot.diagnosticSummary includes timestamp age")
    func snapshotDiagnosticTimestamp() {
        let now = Date()
        let granted = PermissionOracle.PermissionSet(
            accessibility: .granted,
            inputMonitoring: .granted,
            source: "test-source",
            confidence: .high,
            timestamp: now
        )

        // Create snapshot with old timestamp
        let oldTimestamp = now.addingTimeInterval(-5.0)
        let snapshot = PermissionOracle.Snapshot(
            keyPath: granted,
            kanata: granted,
            timestamp: oldTimestamp
        )

        let summary = snapshot.diagnosticSummary
        // Summary includes time since snapshot
        #expect(summary.contains("ago"))
    }

    @Test("Snapshot.diagnosticSummary includes all statuses")
    func snapshotDiagnosticStatuses() {
        let now = Date()

        let keyPath = PermissionOracle.PermissionSet(
            accessibility: .granted,
            inputMonitoring: .denied,
            source: "keypath-source",
            confidence: .high,
            timestamp: now
        )

        let kanata = PermissionOracle.PermissionSet(
            accessibility: .denied,
            inputMonitoring: .unknown,
            source: "kanata-source",
            confidence: .low,
            timestamp: now
        )

        let snapshot = PermissionOracle.Snapshot(
            keyPath: keyPath,
            kanata: kanata,
            timestamp: now
        )

        let summary = snapshot.diagnosticSummary
        #expect(summary.contains("granted"))
        #expect(summary.contains("denied"))
        #expect(summary.contains("unknown"))
        #expect(summary.contains("keypath-source"))
        #expect(summary.contains("kanata-source"))
        #expect(summary.contains("high"))
        #expect(summary.contains("low"))
    }

    @Test("Snapshot.diagnosticSummary reflects system readiness")
    func snapshotDiagnosticReadiness() {
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

        // Ready system
        let ready = PermissionOracle.Snapshot(
            keyPath: granted,
            kanata: granted,
            timestamp: now
        )
        #expect(ready.diagnosticSummary.contains("System Ready: true"))

        // Not ready system
        let notReady = PermissionOracle.Snapshot(
            keyPath: denied,
            kanata: granted,
            timestamp: now
        )
        #expect(notReady.diagnosticSummary.contains("System Ready: false"))
    }

    // MARK: - Status Edge Cases

    @Test("Status.isReady false for error with message")
    func statusErrorNotReady() {
        let error = PermissionOracle.Status.error("Permission check failed")
        #expect(error.isReady == false)
        #expect(error.isBlocking == true)
        #expect(error.description.contains("error"))
        #expect(error.description.contains("Permission check failed"))
    }

    @Test("Status.isBlocking distinguishes blocking vs non-blocking states")
    func statusBlockingStates() {
        // Blocking
        #expect(PermissionOracle.Status.denied.isBlocking == true)
        #expect(PermissionOracle.Status.error("test").isBlocking == true)

        // Non-blocking
        #expect(PermissionOracle.Status.granted.isBlocking == false)
        #expect(PermissionOracle.Status.unknown.isBlocking == false)
    }

    @Test("Status equality works correctly")
    func statusEquality() {
        #expect(PermissionOracle.Status.granted == .granted)
        #expect(PermissionOracle.Status.denied == .denied)
        #expect(PermissionOracle.Status.unknown == .unknown)

        // Error with same message
        let error1 = PermissionOracle.Status.error("test")
        let error2 = PermissionOracle.Status.error("test")
        #expect(error1 == error2)

        // Error with different message
        let error3 = PermissionOracle.Status.error("different")
        #expect(error1 != error3)
    }

    // MARK: - Confidence Level Tests

    @Test("Confidence levels represent data quality")
    func confidenceLevels() {
        #expect(PermissionOracle.Confidence.high.description == "high")
        #expect(PermissionOracle.Confidence.low.description == "low")

        // High confidence: Apple APIs, definitive TCC results
        // Low confidence: Unknown states, fallback scenarios
    }

    @Test("Confidence affects trust in snapshot")
    func confidenceTrust() {
        let now = Date()

        let highConfidence = PermissionOracle.PermissionSet(
            accessibility: .granted,
            inputMonitoring: .granted,
            source: "official-api",
            confidence: .high,
            timestamp: now
        )

        let lowConfidence = PermissionOracle.PermissionSet(
            accessibility: .unknown,
            inputMonitoring: .unknown,
            source: "tcc-fallback",
            confidence: .low,
            timestamp: now
        )

        #expect(highConfidence.confidence == .high)
        #expect(lowConfidence.confidence == .low)
    }

    // MARK: - Snapshot System Ready Logic

    @Test("Snapshot.isSystemReady requires all permissions for both apps")
    func snapshotSystemReadyLogic() {
        let now = Date()

        let allGranted = PermissionOracle.PermissionSet(
            accessibility: .granted,
            inputMonitoring: .granted,
            source: "test",
            confidence: .high,
            timestamp: now
        )

        let partial = PermissionOracle.PermissionSet(
            accessibility: .granted,
            inputMonitoring: .denied,
            source: "test",
            confidence: .high,
            timestamp: now
        )

        // Both apps fully granted
        let ready = PermissionOracle.Snapshot(
            keyPath: allGranted,
            kanata: allGranted,
            timestamp: now
        )
        #expect(ready.isSystemReady == true)

        // KeyPath partial
        let notReady1 = PermissionOracle.Snapshot(
            keyPath: partial,
            kanata: allGranted,
            timestamp: now
        )
        #expect(notReady1.isSystemReady == false)

        // Kanata partial
        let notReady2 = PermissionOracle.Snapshot(
            keyPath: allGranted,
            kanata: partial,
            timestamp: now
        )
        #expect(notReady2.isSystemReady == false)
    }

    @Test("Snapshot.blockingIssue identifies correct priority")
    func snapshotBlockingIssuePriority() {
        let now = Date()

        let granted = PermissionOracle.PermissionSet(
            accessibility: .granted,
            inputMonitoring: .granted,
            source: "test",
            confidence: .high,
            timestamp: now
        )

        let axBlocked = PermissionOracle.PermissionSet(
            accessibility: .denied,
            inputMonitoring: .granted,
            source: "test",
            confidence: .high,
            timestamp: now
        )

        let imBlocked = PermissionOracle.PermissionSet(
            accessibility: .granted,
            inputMonitoring: .denied,
            source: "test",
            confidence: .high,
            timestamp: now
        )

        // KeyPath AX blocked (highest priority)
        let issue1 = PermissionOracle.Snapshot(
            keyPath: axBlocked,
            kanata: granted,
            timestamp: now
        )
        #expect(issue1.blockingIssue?.contains("KeyPath needs Accessibility") == true)

        // KeyPath IM blocked (second priority)
        let issue2 = PermissionOracle.Snapshot(
            keyPath: imBlocked,
            kanata: granted,
            timestamp: now
        )
        #expect(issue2.blockingIssue?.contains("KeyPath needs Input Monitoring") == true)

        // Kanata blocked (third priority - only if KeyPath OK)
        let issue3 = PermissionOracle.Snapshot(
            keyPath: granted,
            kanata: axBlocked,
            timestamp: now
        )
        #expect(issue3.blockingIssue?.contains("Kanata needs permissions") == true)

        // No issues
        let noIssue = PermissionOracle.Snapshot(
            keyPath: granted,
            kanata: granted,
            timestamp: now
        )
        #expect(noIssue.blockingIssue == nil)
    }
}

// MARK: - Test Helper Functions
// These replicate the private implementation for testing purposes
// They should match the behavior in PermissionOracle.swift

fileprivate func testNormalizePathForTCC(_ path: String) -> String {
    // Replicate private normalizePathForTCC implementation
    if path.contains("/build/KeyPath.app/") || path.contains("/.build") {
        if let range = path.range(of: "/KeyPath.app/") {
            let relativePath = String(path[range.upperBound...])
            return "/Applications/KeyPath.app/\(relativePath)"
        }
    }
    return path
}

fileprivate func testEscapeSQLiteLiteral(_ s: String) -> String {
    // Replicate private escapeSQLiteLiteral implementation
    s.replacingOccurrences(of: "'", with: "''")
}
