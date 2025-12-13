import Foundation
import Testing

@testable import KeyPathPermissions
@testable import KeyPathWizardCore

/// Tests for Kanata Input Monitoring requirement.
/// These tests verify that remapping readiness depends on Kanata having Input Monitoring.
@Suite("Kanata Input Monitoring Requirement Tests")
struct SystemSnapshotADR026Tests {
    // MARK: - Test Helpers

    private func makePermissionSet(
        accessibility: PermissionOracle.Status,
        inputMonitoring: PermissionOracle.Status
    ) -> PermissionOracle.PermissionSet {
        PermissionOracle.PermissionSet(
            accessibility: accessibility,
            inputMonitoring: inputMonitoring,
            source: "test",
            confidence: .high,
            timestamp: Date()
        )
    }

    private func makeSnapshot(
        keyPathAX: PermissionOracle.Status = .granted,
        keyPathIM: PermissionOracle.Status = .granted,
        kanataAX: PermissionOracle.Status = .denied,
        kanataIM: PermissionOracle.Status = .denied
    ) -> SystemSnapshot {
        let keyPath = makePermissionSet(accessibility: keyPathAX, inputMonitoring: keyPathIM)
        let kanata = makePermissionSet(accessibility: kanataAX, inputMonitoring: kanataIM)
        let permissions = PermissionOracle.Snapshot(keyPath: keyPath, kanata: kanata, timestamp: Date())

        return SystemSnapshot(
            permissions: permissions,
            components: .empty,
            conflicts: .empty,
            health: .empty,
            helper: HelperStatus(isInstalled: true, version: "1.0", isWorking: true),
            timestamp: Date()
        )
    }

    // MARK: - Kanata IM Requirement Tests

    @Test("Kanata IM missing creates a permission issue")
    func kanataInputMonitoringMissingCreatesIssue() {
        // KeyPath is fully granted, Kanata IM is denied
        let snapshot = makeSnapshot(
            keyPathAX: .granted,
            keyPathIM: .granted,
            kanataAX: .denied,
            kanataIM: .denied
        )

        let issues = snapshot.blockingIssues

        // Should include a Kanata Input Monitoring permission issue
        let permissionIssues = issues.filter { issue in
            if case .permissionMissing = issue { return true }
            return false
        }

        #expect(
            permissionIssues.contains(where: { issue in
                if case let .permissionMissing(app, permission, _) = issue {
                    return app == "Kanata" && permission == "Input Monitoring"
                }
                return false
            }),
            "Expected a Kanata Input Monitoring permission issue"
        )
    }

    @Test("Kanata AX state does not create issues")
    func kanataAccessibilityDoesNotCreateIssue() {
        // KeyPath is fully granted, Kanata AX denied but IM granted
        let snapshot = makeSnapshot(
            keyPathAX: .granted,
            keyPathIM: .granted,
            kanataAX: .denied,
            kanataIM: .granted
        )

        let issues = snapshot.blockingIssues

        let permissionIssues = issues.filter { issue in
            if case .permissionMissing = issue { return true }
            return false
        }

        #expect(permissionIssues.isEmpty, "No permission issues expected when KeyPath and Kanata IM are granted")
    }

    @Test("validate() does not assert for Kanata IM denied")
    func validatePassesWithKanataDenied() {
        let snapshot = makeSnapshot(
            keyPathAX: .granted,
            keyPathIM: .granted,
            kanataAX: .denied,
            kanataIM: .denied
        )

        // Should not assert
        snapshot.validate()
    }
}
