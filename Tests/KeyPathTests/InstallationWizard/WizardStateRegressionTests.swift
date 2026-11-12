@testable import KeyPathAppKit
import KeyPathCore
@testable import KeyPathInstallationWizard
import KeyPathPermissions
import KeyPathWizardCore
@preconcurrency import XCTest

/// Regression: wizard should not route to “Start Service” when Kanata is running.
@MainActor
final class WizardStateRegressionTests: XCTestCase {
    func testDoubleAdaptKeepsActiveStateWhenKanataRunning() {
        // Build a healthy SystemContext (Kanata running, no blocking issues)
        let perms = PermissionOracle.Snapshot.fixture()

        let health = HealthStatus(kanataRunning: true)

        let components = ComponentStatus(
            kanataBinaryInstalled: true
        )

        let context = SystemContext(
            permissions: perms,
            services: health,
            conflicts: .init(conflicts: [], canAutoResolve: false),
            components: components,
            system: EngineSystemInfo(macOSVersion: "26.0.1"),
            timestamp: Date()
        )

        // Run adapt twice to mimic reopen/open flows
        let first = SystemStateResult.projecting(context)
        let second = SystemStateResult.projecting(context)

        XCTAssertEqual(first.state, .active)
        XCTAssertEqual(second.state, .active)
        XCTAssertTrue(first.issues.isEmpty)
        XCTAssertTrue(second.issues.isEmpty)
    }

    func testRunningSessionWithoutInputCaptureRoutesToRuntimeRepair() {
        let now = Date()
        let context = SystemContext(
            permissions: .fixture(source: "independent-session", timestamp: now),
            services: HealthStatus(
                kanataProcessRunning: true, kanataTCPResponding: true,
                kanataRunning: true, kanataInputCaptureReady: false,
                kanataInputCaptureIssue: "kanata-cannot-open-built-in-keyboard"
            ),
            conflicts: .empty,
            components: ComponentStatus(
                kanataBinaryInstalled: true, requiredRuntimePayloadPresent: true
            ), system: EngineSystemInfo(macOSVersion: "27.0"),
            timestamp: now
        )
        let result = SystemStateResult.projecting(context)
        XCTAssertEqual(result.state, .serviceNotRunning)
        XCTAssertEqual(result.autoFixActions, [.startSessionRuntime])
        XCTAssertTrue(result.issues.contains { $0.identifier == .daemon })
        XCTAssertFalse(result.issues.contains { $0.category == .permissions })
    }
}
