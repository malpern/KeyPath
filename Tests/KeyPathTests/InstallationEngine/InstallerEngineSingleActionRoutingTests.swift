@testable import KeyPathAppKit
@testable import KeyPathWizardCore
import XCTest

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

    func testRestartCommServerRoutesToRestartUnhealthy() async {
        let coordinator = StubPrivilegedOperationsCoordinator()
        let broker = PrivilegeBroker(coordinator: coordinator)
        let engine = InstallerEngine()

        _ = await engine.runSingleAction(.restartCommServer, using: broker)

        XCTAssertTrue(
            coordinator.calls.contains("restartUnhealthyServices"),
            "restartCommServer should restart unhealthy services"
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

    func testOrphanedProcessActionsRouteCorrectly() async {
        let coordinator = StubPrivilegedOperationsCoordinator()
        let broker = PrivilegeBroker(coordinator: coordinator)
        let engine = InstallerEngine()

        _ = await engine.runSingleAction(.adoptOrphanedProcess, using: broker)
        XCTAssertTrue(coordinator.calls.contains("installLaunchDaemonServicesWithoutLoading"))

        coordinator.calls.removeAll()
        _ = await engine.runSingleAction(.replaceOrphanedProcess, using: broker)
        XCTAssertTrue(coordinator.calls.contains("killAllKanataProcesses"))
        XCTAssertTrue(coordinator.calls.contains("installLaunchDaemonServicesWithoutLoading"))
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

    func testRestartVirtualHIDDaemonUsesRestartUnhealthy() async {
        let coordinator = StubPrivilegedOperationsCoordinator()
        let broker = PrivilegeBroker(coordinator: coordinator)
        let engine = InstallerEngine()

        _ = await engine.runSingleAction(.restartVirtualHIDDaemon, using: broker)

        XCTAssertTrue(
            coordinator.calls.contains("restartUnhealthyServices"),
            "restartVirtualHIDDaemon maps to restart-unhealthy-services recipe"
        )
    }
}
