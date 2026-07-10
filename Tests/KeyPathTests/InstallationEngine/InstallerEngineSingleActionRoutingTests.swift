@testable import KeyPathAppKit
import KeyPathDaemonLifecycle
@testable import KeyPathInstallationWizard
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
        let initialContext = SystemContextBuilder(
            conflicts: [
                .kanataProcessRunning(pid: 42, command: "kanata"),
                .karabinerGrabberRunning(pid: 43)
            ]
        ).build()
        let finalContext = SystemContextBuilder(conflicts: []).build()
        let engine = InstallerEngine(
            processLifecycleManager: ProcessLifecycleManager(),
            systemValidator: StubSystemValidator(contexts: [initialContext, finalContext])
        )

        let report = await engine.runSingleAction(.terminateConflictingProcesses, using: broker)

        XCTAssertTrue(report.success)
        XCTAssertTrue(coordinator.calls.contains("killAllKanataProcesses"))
        XCTAssertTrue(coordinator.calls.contains("disableKarabinerGrabber"))
    }

    func testTerminateConflictingProcessesRejectsUnsupportedConflict() async {
        let context = SystemContextBuilder(
            conflicts: [
                .exclusiveDeviceAccess(device: "Built-in Keyboard"),
                .kanataProcessRunning(pid: 42, command: "kanata")
            ]
        ).build()
        let coordinator = StubPrivilegedOperationsCoordinator()
        let engine = InstallerEngine(
            processLifecycleManager: ProcessLifecycleManager(),
            systemValidator: StubSystemValidator(context: context)
        )

        let report = await engine.runSingleAction(
            .terminateConflictingProcesses,
            using: PrivilegeBroker(coordinator: coordinator)
        )

        XCTAssertFalse(report.success)
        XCTAssertTrue(report.failureReason?.contains("Unsupported automatic conflict resolution") ?? false)
        XCTAssertTrue(
            coordinator.calls.contains("killAllKanataProcesses"),
            "Resolvable conflicts should be handled before unsupported conflicts are reported"
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
