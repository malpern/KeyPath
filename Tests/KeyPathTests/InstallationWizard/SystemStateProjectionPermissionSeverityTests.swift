@testable import KeyPathAppKit
@testable import KeyPathInstallationWizard
@testable import KeyPathPermissions
import KeyPathWizardCore
@preconcurrency import XCTest

/// End-to-end tests that validate the path:
/// SystemContext -> SystemStateResult projection/SystemInspector -> WizardIssue and page.
@MainActor
final class SystemStateProjectionPermissionSeverityTests: XCTestCase {
    func testKanataUnknownPermissionRequestsRuntimeEvidenceNotConsent() {
        let now = Date()

        // Represents "not verified" when effective runtime facts are unavailable.
        let permissions = PermissionOracle.Snapshot.fixture(runtimeKeyAccess: .unknown, timestamp: now)

        let context = SystemContext(
            permissions: permissions,
            services: HealthStatus(kanataRunning: false),
            conflicts: ConflictStatus(conflicts: [], canAutoResolve: false),
            components: ComponentStatus(
                kanataBinaryInstalled: true
            ),
            system: EngineSystemInfo(macOSVersion: "test"),
            timestamp: now
        )

        let result = SystemStateResult.projecting(context)

        XCTAssertEqual(result.state, .serviceNotRunning, "Unverified runtime input access is not proof of a denial")
        XCTAssertFalse(result.issues.contains { $0.identifier.isPermission },
                       "An unverified permission must not be presented as a consent the user has to give")
        let evidenceIssue = result.issues.first { $0.identifier == .daemon }
        XCTAssertNotNil(evidenceIssue, "Projection should ask the runtime for fresh evidence")
        XCTAssertEqual(evidenceIssue?.autoFixAction, .restartCommServer)
        XCTAssertFalse(
            evidenceIssue?.description.localizedCaseInsensitiveContains("denied") ?? true,
            "Unknown/not verified should not claim permission is denied"
        )

        let page = WizardRouter.route(
            state: result.state,
            issues: result.issues
        )
        XCTAssertEqual(page, .service, "Unverified permission evidence routes to the runtime, not the input monitoring page")
    }
}
