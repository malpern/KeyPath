import Foundation
import KeyPathPermissions
import Testing

@testable import KeyPathAppKit

@Suite("Permission Oracle Policy Tests")
struct PermissionOraclePolicyTests {
    // MARK: - Blocking message specificity

    @Test("Blocking issue names the specific KeyPath permission (AX)")
    func blockingMessageSpecificityAccessibility() {
        let now = Date()

        // KeyPath: AX denied, IM granted
        let keyPath = PermissionOracle.PermissionSet(
            accessibility: .denied,
            inputMonitoring: .granted,
            source: "test",
            confidence: .high,
            timestamp: now
        )

        // Kanata: fully granted
        let kanata = PermissionOracle.PermissionSet(
            accessibility: .granted,
            inputMonitoring: .granted,
            source: "test",
            confidence: .high,
            timestamp: now
        )

        let snap = PermissionOracle.Snapshot(keyPath: keyPath, kanata: kanata, timestamp: now)
        let issue = snap.blockingIssue ?? ""

        #expect(issue.contains("Accessibility"))
        #expect(!issue.contains("Input Monitoring"))
        #expect(issue.contains("KeyPath"))
    }

    @Test("Blocking issue names the specific KeyPath permission (IM)")
    func blockingMessageSpecificityInputMonitoring() {
        let now = Date()

        // KeyPath: AX granted, IM denied
        let keyPath = PermissionOracle.PermissionSet(
            accessibility: .granted,
            inputMonitoring: .denied,
            source: "test",
            confidence: .high,
            timestamp: now
        )

        // Kanata: fully granted
        let kanata = PermissionOracle.PermissionSet(
            accessibility: .granted,
            inputMonitoring: .granted,
            source: "test",
            confidence: .high,
            timestamp: now
        )

        let snap = PermissionOracle.Snapshot(keyPath: keyPath, kanata: kanata, timestamp: now)
        let issue = snap.blockingIssue ?? ""

        #expect(issue.contains("Input Monitoring"))
        #expect(!issue.contains("Accessibility"))
        #expect(issue.contains("KeyPath"))
    }

    // MARK: - Kanata Input Monitoring

    @Test("Kanata IM can be the blocking issue when KeyPath is unknown")
    func kanataBlocksWhenKeyPathUnknown() {
        let now = Date()

        // KeyPath: unknown is non-blocking
        let keyPath = PermissionOracle.PermissionSet(
            accessibility: .unknown,
            inputMonitoring: .unknown,
            source: "test",
            confidence: .low,
            timestamp: now
        )

        // Kanata: denied IM should create a blocking issue
        let kanata = PermissionOracle.PermissionSet(
            accessibility: .denied,
            inputMonitoring: .denied,
            source: "test",
            confidence: .high,
            timestamp: now
        )

        let snap = PermissionOracle.Snapshot(keyPath: keyPath, kanata: kanata, timestamp: now)
        let issue = snap.blockingIssue

        #expect(issue != nil, "Expected a blocking issue when Kanata IM is denied")
        #expect(issue?.contains("Kanata") == true, "Blocking issue should mention Kanata")
        #expect(issue?.contains("Input Monitoring") == true, "Blocking issue should mention Input Monitoring")
    }
}
