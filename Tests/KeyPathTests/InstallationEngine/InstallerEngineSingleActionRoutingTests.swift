@testable import KeyPathAppKit
@testable import KeyPathInstallationWizard
@testable import KeyPathWizardCore
import XCTest

@MainActor
final class InstallerEngineSingleActionRoutingTests: KeyPathAsyncTestCase {
    func testUnsupportedLegacyActionsExplicitlyFailWithoutCallingBroker() async {
        let coordinator = StubPrivilegedOperationsCoordinator()
        let broker = PrivilegeBroker(coordinator: coordinator)
        let engine = InstallerEngine()
        let actions: [AutoFixAction] = [
            .enableTCPServer, .setupTCPAuthentication, .regenerateCommServiceConfiguration,
            .regenerateServiceConfiguration, .installRequiredRuntimeServices,
            .installCorrectVHIDDriver, .installMissingComponents, .installLogRotation,
            .installPrivilegedHelper, .reinstallPrivilegedHelper, .startKarabinerDaemon,
            .restartVirtualHIDDaemon, .repairVHIDDaemonServices, .fixDriverVersionMismatch,
            .activateVHIDDeviceManager, .terminateConflictingProcesses, .createConfigDirectories
        ]
        for action in actions {
            let report = await engine.runSingleAction(action, using: broker)
            XCTAssertFalse(report.success, "Unsupported action \(action) must fail")
            XCTAssertTrue(report.failureReason?.contains("No recipe available") ?? false)
            XCTAssertTrue(report.executedRecipes.isEmpty)
            XCTAssertNotNil(report.planID)
            XCTAssertNotNil(report.beforeSnapshotID)
        }
        XCTAssertTrue(coordinator.calls.isEmpty)
    }
}
