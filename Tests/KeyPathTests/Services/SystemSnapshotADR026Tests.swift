import Foundation
import Testing

@testable import KeyPathPermissions
@testable import KeyPathWizardCore

/// Tests for ADR-026: Kanata Does NOT Need TCC Permissions
/// These tests verify the invariant that system readiness only depends on KeyPath permissions.
@Suite("ADR-026: Kanata TCC Invariant Tests")
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

    // MARK: - ADR-026 Invariant Tests

    @Test("ADR-026: SystemSnapshot.blockingIssues never includes Kanata permission issues")
    func blockingIssuesNeverIncludeKanataPermissions() {
        // Create snapshot where KeyPath has all permissions but Kanata doesn't
        let snapshot = makeSnapshot(
            keyPathAX: .granted,
            keyPathIM: .granted,
            kanataAX: .denied,
            kanataIM: .denied
        )

        let issues = snapshot.blockingIssues

        // Should have no permission issues (KeyPath is fine, Kanata doesn't matter)
        let permissionIssues = issues.filter { issue in
            if case .permissionMissing = issue { return true }
            return false
        }

        #expect(
            permissionIssues.isEmpty,
            "No permission issues should be generated when KeyPath has all permissions"
        )

        // Verify no issues mention "Kanata" in permission context
        for issue in issues {
            if case let .permissionMissing(app, _, _) = issue {
                #expect(app != "Kanata", "Permission issues should never be for Kanata")
                #expect(app != "kanata", "Permission issues should never be for kanata")
            }
        }
    }

    @Test("ADR-026: Only KeyPath permission issues are generated")
    func onlyKeyPathPermissionIssuesGenerated() {
        // Create snapshot where both KeyPath and Kanata lack permissions
        let snapshot = makeSnapshot(
            keyPathAX: .denied,
            keyPathIM: .denied,
            kanataAX: .denied,
            kanataIM: .denied
        )

        let issues = snapshot.blockingIssues

        // Should have exactly 2 permission issues - both for KeyPath
        let permissionIssues = issues.filter { issue in
            if case .permissionMissing = issue { return true }
            return false
        }

        #expect(permissionIssues.count == 2, "Should have 2 permission issues (AX + IM for KeyPath)")

        for issue in permissionIssues {
            if case let .permissionMissing(app, _, _) = issue {
                #expect(app == "KeyPath", "Permission issues should only be for KeyPath, got: \(app)")
            }
        }
    }

    @Test("ADR-026: validate() passes when KeyPath has permissions but Kanata doesn't")
    func validatePassesWithKeyPathPermissionsOnly() {
        // This test verifies the assertion in validateKanataTCCInvariant() doesn't fire
        let snapshot = makeSnapshot(
            keyPathAX: .granted,
            keyPathIM: .granted,
            kanataAX: .denied,
            kanataIM: .denied
        )

        // Should not assert - Kanata permissions don't matter
        snapshot.validate()

        // And isSystemReady via permissions should be true
        #expect(snapshot.permissions.isSystemReady == true)
    }

    @Test("ADR-026: Kanata permission states don't affect blockingIssues count")
    func kanataStatesDoNotAffectIssueCount() {
        // Test with various Kanata states - issue count should be the same
        let kanataStates: [(PermissionOracle.Status, PermissionOracle.Status)] = [
            (.granted, .granted),
            (.denied, .denied),
            (.unknown, .unknown),
            (.error("test"), .error("test")),
            (.denied, .granted),
            (.granted, .denied),
        ]

        // With KeyPath fully granted
        for (kanataAX, kanataIM) in kanataStates {
            let snapshot = makeSnapshot(
                keyPathAX: .granted,
                keyPathIM: .granted,
                kanataAX: kanataAX,
                kanataIM: kanataIM
            )

            let permissionIssues = snapshot.blockingIssues.filter { issue in
                if case .permissionMissing = issue { return true }
                return false
            }

            #expect(
                permissionIssues.isEmpty,
                "Should have 0 permission issues regardless of Kanata state: \(kanataAX), \(kanataIM)"
            )
        }

        // With KeyPath missing AX only
        for (kanataAX, kanataIM) in kanataStates {
            let snapshot = makeSnapshot(
                keyPathAX: .denied,
                keyPathIM: .granted,
                kanataAX: kanataAX,
                kanataIM: kanataIM
            )

            let permissionIssues = snapshot.blockingIssues.filter { issue in
                if case .permissionMissing = issue { return true }
                return false
            }

            #expect(
                permissionIssues.count == 1,
                "Should have 1 permission issue regardless of Kanata state: \(kanataAX), \(kanataIM)"
            )
        }
    }

    @Test("ADR-026: Issue.title never mentions Kanata for permission issues")
    func issueTitleNeverMentionsKanataForPermissions() {
        // When KeyPath lacks permissions, the issue titles should mention KeyPath
        let snapshot = makeSnapshot(
            keyPathAX: .denied,
            keyPathIM: .denied,
            kanataAX: .denied,
            kanataIM: .denied
        )

        for issue in snapshot.blockingIssues {
            if case .permissionMissing = issue {
                #expect(
                    issue.title.contains("KeyPath"),
                    "Permission issue title should mention KeyPath: \(issue.title)"
                )
                #expect(
                    !issue.title.lowercased().contains("kanata"),
                    "Permission issue title should NOT mention Kanata: \(issue.title)"
                )
            }
        }
    }
}
