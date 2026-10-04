@testable import KeyPathAppKit
@testable import KeyPathInstallationWizard
import XCTest

@MainActor
final class InstallerEngineBrokerForwardingTests: KeyPathTestCase {
    func testCompatibilityMutationAPIsThrowWithoutCallingBroker() async {
        let coordinator = StubPrivilegedOperationsCoordinator()
        let broker = PrivilegeBroker(coordinator: coordinator)
        let engine = InstallerEngine()
        let operations: [() async throws -> Void] = [
            { try await engine.uninstallVirtualHIDDrivers(using: broker) },
            { try await engine.disableKarabinerGrabber(using: broker) },
            { _ = try await engine.restartKarabinerDaemon(using: broker) },
            { try await engine.sudoExecuteCommand("must never run", description: "test", using: broker) }
        ]
        for operation in operations {
            do { try await operation(); XCTFail("Privileged API must refuse") }
            catch { XCTAssertTrue(error.localizedDescription.contains("unavailable in the driverless build")) }
        }
        XCTAssertTrue(coordinator.calls.isEmpty)
    }

    func testUninstallRefusesEverySystemAndConfigScope() async {
        let coordinator = StubPrivilegedOperationsCoordinator()
        let broker = PrivilegeBroker(coordinator: coordinator)
        for deleteConfig in [false, true] {
            let report = await InstallerEngine().uninstall(
                deleteConfig: deleteConfig, removeVirtualHID: true, allowAdminFallback: true, using: broker
            )
            XCTAssertFalse(report.success)
            XCTAssertTrue(report.failureReason?.contains("System uninstall is unavailable") ?? false)
            XCTAssertTrue(report.executedRecipes.isEmpty)
        }
        XCTAssertTrue(coordinator.calls.isEmpty)
    }
}
