@testable import KeyPathAppKit
@testable import KeyPathInstallationWizard
import XCTest
import KeyPathWizardCore

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

    func testUninstallRefusesPrivilegedCleanup() async {
        let coordinator = StubPrivilegedOperationsCoordinator()
        let broker = PrivilegeBroker(coordinator: coordinator)
        for deleteConfig in [false, true] {
            let report = await InstallerEngine().uninstall(
                deleteConfig: deleteConfig, removeVirtualHID: true, allowAdminFallback: true, using: broker
            )
            XCTAssertFalse(report.success)
            XCTAssertTrue(report.failureReason?.contains("Use Uninstall KeyPath in Settings") ?? false)
            XCTAssertTrue(report.executedRecipes.isEmpty)
        }
        XCTAssertTrue(coordinator.calls.isEmpty)
    }
    func testUserUninstallDelegatesWithoutPrivilegedBroker() async {
        let previous = WizardDependencies.createUninstallCoordinator
        defer { WizardDependencies.createUninstallCoordinator = previous }
        let uninstaller = UserUninstallerStub()
        WizardDependencies.createUninstallCoordinator = { uninstaller }
        let privileged = StubPrivilegedOperationsCoordinator()
        let report = await InstallerEngine().uninstall(deleteConfig: true, using: PrivilegeBroker(coordinator: privileged))
        XCTAssertTrue(report.success)
        XCTAssertEqual(report.logs, ["Backup saved"])
        XCTAssertEqual(uninstaller.calls, 1)
        XCTAssertTrue(privileged.calls.isEmpty)
    }

    @MainActor
    private final class UserUninstallerStub: WizardUninstalling {
        var calls = 0
        func performUninstall(deleteConfig: Bool, removeVirtualHID: Bool, allowAdminFallback: Bool) async -> WizardUninstallResult {
            calls += 1
            XCTAssertTrue(deleteConfig)
            XCTAssertFalse(removeVirtualHID)
            XCTAssertFalse(allowAdminFallback)
            return WizardUninstallResult(success: true, logs: ["Backup saved"])
        }
    }

}
