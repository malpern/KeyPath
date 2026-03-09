@testable import KeyPathAppKit
@testable import KeyPathWizardCore
@preconcurrency import XCTest

@MainActor
final class InstallerEngineSingleActionRoutingTests: KeyPathAsyncTestCase {
    func testTCPActionsRouteToRegenerateConfig() async {
        let coordinator = StubPrivilegedOperationsCoordinator()
        let broker = PrivilegeBroker(coordinator: coordinator)
        let engine = InstallerEngine()

        let tcpActions: [AutoFixAction] = [.enableTCPServer, .setupTCPAuthentication,
                                           .regenerateCommServiceConfiguration]

        for action in tcpActions {
            coordinator.calls.removeAll()
            _ = await engine.runSingleAction(action, using: broker)
            XCTAssertTrue(
                coordinator.calls.contains("regenerateServiceConfiguration"),
                "Action \(action) should regenerate service configuration"
            )
        }
    }

    func testRestartCommServerRoutesToRegenerateConfig() async {
        let coordinator = StubPrivilegedOperationsCoordinator()
        let broker = PrivilegeBroker(coordinator: coordinator)
        let engine = InstallerEngine()

        _ = await engine.runSingleAction(.restartCommServer, using: broker)

        XCTAssertTrue(
            coordinator.calls.contains("regenerateServiceConfiguration"),
            "restartCommServer should regenerate service configuration"
        )
    }

    func testStartKarabinerDaemonRoutesToVerifiedKarabinerRestart() async {
        let coordinator = StubPrivilegedOperationsCoordinator()
        let broker = PrivilegeBroker(coordinator: coordinator)
        let engine = InstallerEngine()

        _ = await engine.runSingleAction(.startKarabinerDaemon, using: broker)

        XCTAssertTrue(
            coordinator.calls.contains("restartKarabinerDaemonVerified"),
            "startKarabinerDaemon should route to verified Karabiner restart"
        )
        XCTAssertFalse(
            coordinator.calls.contains("recoverRequiredRuntimeServices"),
            "startKarabinerDaemon should not use the generic runtime recovery path"
        )
    }

    func testVHIDActionsRouteToDriverAndRepair() async {
        let coordinator = StubPrivilegedOperationsCoordinator()
        let broker = PrivilegeBroker(coordinator: coordinator)
        let engine = InstallerEngine()

        _ = await engine.runSingleAction(.repairVHIDDaemonServices, using: broker)
        XCTAssertTrue(coordinator.calls.contains("repairVHIDDaemonServices"))

        coordinator.calls.removeAll()
        _ = await engine.runSingleAction(.fixDriverVersionMismatch, using: broker)
        XCTAssertTrue(coordinator.calls.contains("downloadAndInstallCorrectVHIDDriver"))

        coordinator.calls.removeAll()
        _ = await engine.runSingleAction(.installCorrectVHIDDriver, using: broker)
        XCTAssertTrue(coordinator.calls.contains("downloadAndInstallCorrectVHIDDriver"))
    }

    func testTerminateConflictingProcessesRouteCorrectly() async {
        let coordinator = StubPrivilegedOperationsCoordinator()
        let broker = PrivilegeBroker(coordinator: coordinator)
        let engine = InstallerEngine()

        _ = await engine.runSingleAction(.terminateConflictingProcesses, using: broker)
        XCTAssertTrue(coordinator.calls.contains("killAllKanataProcesses"))
    }

    func testBundledActionsRouteToInstaller() async {
        let coordinator = StubPrivilegedOperationsCoordinator()
        let broker = PrivilegeBroker(coordinator: coordinator)
        let engine = InstallerEngine()

        _ = await engine.runSingleAction(.installBundledKanata, using: broker)
        XCTAssertTrue(coordinator.calls.contains("installBundledKanata"))

        coordinator.calls.removeAll()
        _ = await engine.runSingleAction(.replaceKanataWithBundled, using: broker)
        XCTAssertTrue(coordinator.calls.contains("installBundledKanata"))
    }

    func testInstallBundledKanataSingleActionFailsWhenCoordinatorFails() async {
        let coordinator = StubPrivilegedOperationsCoordinator()
        coordinator.failOnCall = "installBundledKanata"
        let broker = PrivilegeBroker(coordinator: coordinator)
        let engine = InstallerEngine()

        let report = await engine.runSingleAction(.installBundledKanata, using: broker)

        XCTAssertFalse(report.success)
        XCTAssertTrue(
            report.failureReason?.contains(InstallerRecipeID.installBundledKanata) ?? false
        )
    }

    func testRestartVirtualHIDDaemonUsesVHIDRepairPath() async {
        let coordinator = StubPrivilegedOperationsCoordinator()
        let broker = PrivilegeBroker(coordinator: coordinator)
        let engine = InstallerEngine()

        _ = await engine.runSingleAction(.restartVirtualHIDDaemon, using: broker)

        XCTAssertTrue(
            coordinator.calls.contains("repairVHIDDaemonServices"),
            "restartVirtualHIDDaemon should map to the VHID repair path"
        )
    }
}
