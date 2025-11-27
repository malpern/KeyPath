import XCTest
@testable import KeyPathAppKit
import KeyPathWizardCore
import KeyPathCore

@MainActor
final class WizardAutoFixerFacadeTests: XCTestCase {
    func testPerformAutoFixDelegatesToInstallerEngine() async {
        let mockEngine = MockInstallerEngine()
        let fixer = WizardAutoFixer(
            kanataManager: RuntimeCoordinator(),
            installerEngine: mockEngine
        )

        let actions: [AutoFixAction] = [
            .installPrivilegedHelper,
            .reinstallPrivilegedHelper,
            .terminateConflictingProcesses,
            .startKarabinerDaemon,
            .restartVirtualHIDDaemon,
            .installMissingComponents,
            .createConfigDirectories,
            .activateVHIDDeviceManager,
            .installLaunchDaemonServices,
            .installBundledKanata,
            .repairVHIDDaemonServices,
            .synchronizeConfigPaths,
            .restartUnhealthyServices,
            .adoptOrphanedProcess,
            .replaceOrphanedProcess,
            .installLogRotation,
            .replaceKanataWithBundled,
            .enableTCPServer,
            .setupTCPAuthentication,
            .regenerateCommServiceConfiguration,
            .restartCommServer,
            .fixDriverVersionMismatch,
            .installCorrectVHIDDriver
        ]

        for action in actions {
            let success = await fixer.performAutoFix(action)
            XCTAssertTrue(success, "Action \(action) should succeed via façade")
        }

        XCTAssertEqual(mockEngine.actions, actions)
    }
}

// MARK: - Test Doubles

@MainActor
private final class MockInstallerEngine: WizardInstallerEngineProtocol {
    private(set) var actions: [AutoFixAction] = []

    func runSingleAction(_ action: AutoFixAction, using _: PrivilegeBroker) async -> InstallerReport {
        actions.append(action)
        return InstallerReport(success: true, failureReason: nil, executedRecipes: [], logs: [])
    }
}
