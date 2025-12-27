@testable import KeyPathAppKit
import KeyPathCore
import KeyPathPermissions
import KeyPathWizardCore
@preconcurrency import XCTest

@MainActor
final class KarabinerComponentsStatusEvaluatorTests: XCTestCase {
    private func makeIssue(
        category: WizardIssue.IssueCategory,
        identifier: IssueIdentifier
    ) -> WizardIssue {
        WizardIssue(
            identifier: identifier,
            severity: .critical,
            category: category,
            title: "t",
            description: "d",
            autoFixAction: nil,
            userAction: nil
        )
    }

    func testDriverNotRedWhenOnlyKanataServiceIssue() {
        let daemonIssue = makeIssue(
            category: .daemon,
            identifier: IssueIdentifier.component(.kanataService)
        )

        let overall = KarabinerComponentsStatusEvaluator.evaluate(
            systemState: .ready,
            issues: [daemonIssue]
        )
        let driver = KarabinerComponentsStatusEvaluator.getIndividualComponentStatus(
            .driver,
            in: [daemonIssue]
        )
        let services = KarabinerComponentsStatusEvaluator.getIndividualComponentStatus(
            .backgroundServices,
            in: [daemonIssue]
        )

        XCTAssertEqual(driver, InstallationStatus.completed, "Driver should stay green when only Kanata service is pending")
        XCTAssertEqual(services, InstallationStatus.completed, "Background services row should stay green for Kanata-only issues")
        XCTAssertEqual(overall, InstallationStatus.completed, "Overall Karabiner status should stay green for Kanata-only issues")
    }

    // MARK: - SystemContextAdapter Integration Tests

    /// Regression test: When VHID services are healthy but Kanata service is not installed,
    /// the Karabiner Components page should NOT show issues. Only a Kanata-specific issue should appear.
    /// This was the root cause of the "wizard stuck on Karabiner Driver Required" bug.
    func testNoLaunchDaemonServicesIssueWhenOnlyKanataUnhealthy() {
        // Setup: VHID healthy, Kanata not running
        let now = Date()
        let perms = PermissionOracle.Snapshot(
            keyPath: PermissionOracle.PermissionSet(
                accessibility: .granted, inputMonitoring: .granted,
                source: "test", confidence: .high, timestamp: now
            ),
            kanata: PermissionOracle.PermissionSet(
                accessibility: .granted, inputMonitoring: .granted,
                source: "test", confidence: .high, timestamp: now
            ),
            timestamp: now
        )

        // Key scenario: vhidServicesHealthy=true but launchDaemonServicesHealthy=false (Kanata not installed)
        let components = ComponentStatus(
            kanataBinaryInstalled: true,
            karabinerDriverInstalled: true,
            karabinerDaemonRunning: true,
            vhidDeviceInstalled: true,
            vhidDeviceHealthy: true,
            launchDaemonServicesHealthy: false, // All services (including Kanata) - FALSE
            vhidServicesHealthy: true, // VHID only - TRUE (this is the key!)
            vhidVersionMismatch: false
        )

        let services = HealthStatus(
            kanataRunning: false, // Kanata not running
            karabinerDaemonRunning: true,
            vhidHealthy: true
        )

        let context = SystemContext(
            permissions: perms,
            services: services,
            conflicts: ConflictStatus(conflicts: [], canAutoResolve: false),
            components: components,
            helper: HelperStatus(isInstalled: true, version: "1.0", isWorking: true),
            system: EngineSystemInfo(macOSVersion: "15.0", driverCompatible: true),
            timestamp: now
        )

        // Act: Adapt the context to wizard format
        let result = SystemContextAdapter.adapt(context)

        // Assert: No launchDaemonServices issue with .installation category
        // (that's what the Karabiner page looks for)
        let karabinerRelatedIssues = result.issues.filter { issue in
            if case .component(.launchDaemonServices) = issue.identifier,
               issue.category == WizardIssue.IssueCategory.installation {
                return true
            }
            return false
        }

        XCTAssertTrue(
            karabinerRelatedIssues.isEmpty,
            "When VHID services are healthy, no .launchDaemonServices issue should be generated " +
                "for the Karabiner page. Found: \(karabinerRelatedIssues)"
        )

        // Should have a Kanata-specific issue instead
        let kanataIssues = result.issues.filter { issue in
            if case .component(.kanataService) = issue.identifier {
                return true
            }
            return false
        }

        XCTAssertFalse(
            kanataIssues.isEmpty,
            "A .kanataService issue should be generated when Kanata is not running but VHID is healthy"
        )
    }

    /// Verify that when VHID services are unhealthy, the .launchDaemonServices issue IS generated
    func testLaunchDaemonServicesIssueWhenVHIDUnhealthy() {
        let now = Date()
        let perms = PermissionOracle.Snapshot(
            keyPath: PermissionOracle.PermissionSet(
                accessibility: .granted, inputMonitoring: .granted,
                source: "test", confidence: .high, timestamp: now
            ),
            kanata: PermissionOracle.PermissionSet(
                accessibility: .granted, inputMonitoring: .granted,
                source: "test", confidence: .high, timestamp: now
            ),
            timestamp: now
        )

        // VHID services unhealthy
        let components = ComponentStatus(
            kanataBinaryInstalled: true,
            karabinerDriverInstalled: true,
            karabinerDaemonRunning: true,
            vhidDeviceInstalled: true,
            vhidDeviceHealthy: true,
            launchDaemonServicesHealthy: false,
            vhidServicesHealthy: false, // VHID unhealthy!
            vhidVersionMismatch: false
        )

        let services = HealthStatus(
            kanataRunning: false,
            karabinerDaemonRunning: true,
            vhidHealthy: true
        )

        let context = SystemContext(
            permissions: perms,
            services: services,
            conflicts: ConflictStatus(conflicts: [], canAutoResolve: false),
            components: components,
            helper: HelperStatus(isInstalled: true, version: "1.0", isWorking: true),
            system: EngineSystemInfo(macOSVersion: "15.0", driverCompatible: true),
            timestamp: now
        )

        let result = SystemContextAdapter.adapt(context)

        // Should have a launchDaemonServices issue when VHID is unhealthy
        let vhidIssues = result.issues.filter { issue in
            if case .component(.launchDaemonServices) = issue.identifier,
               issue.category == WizardIssue.IssueCategory.installation {
                return true
            }
            return false
        }

        XCTAssertFalse(
            vhidIssues.isEmpty,
            "When VHID services are unhealthy, a .launchDaemonServices issue should be generated"
        )
    }
}
