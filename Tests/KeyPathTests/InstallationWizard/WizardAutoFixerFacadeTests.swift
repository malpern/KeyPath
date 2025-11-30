@testable import KeyPathAppKit
import KeyPathCore
import KeyPathWizardCore
@preconcurrency import XCTest

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

    func testPerformAutoFixPropagatesFailure() async {
        let failingEngine = MockInstallerEngine(success: false)
        let fixer = WizardAutoFixer(
            kanataManager: RuntimeCoordinator(),
            installerEngine: failingEngine
        )

        let success = await fixer.performAutoFix(.installBundledKanata)

        XCTAssertFalse(success, "Should surface failure from InstallerEngine")
        XCTAssertEqual(failingEngine.actions, [.installBundledKanata])
    }
}

// MARK: - Test Doubles

@MainActor
private final class MockInstallerEngine: WizardInstallerEngineProtocol {
    private(set) var actions: [AutoFixAction] = []
    private let result: Bool

    init(success: Bool = true) {
        result = success
    }

    func runSingleAction(_ action: AutoFixAction, using _: PrivilegeBroker) async -> InstallerReport {
        actions.append(action)
        return InstallerReport(success: result, failureReason: result ? nil : "mock failure", executedRecipes: [], logs: [])
    }
}
