@testable import KeyPathAppKit
@testable import KeyPathInstallationWizard
import KeyPathWizardCore
import XCTest

@MainActor
final class InstallerEngineUninstallTests: KeyPathTestCase {
    func testUninstallWithoutConfigBackupIsRefused() async {
        let uninstaller = UserUninstallerStub()

        let report = await InstallerEngine(services: InstallerServices(makeUninstaller: { uninstaller }))
            .uninstall(deleteConfig: false)

        XCTAssertFalse(report.success)
        XCTAssertTrue(report.failureReason?.contains("Use Uninstall KeyPath in Settings") ?? false)
        XCTAssertTrue(report.executedRecipes.isEmpty)
        XCTAssertEqual(uninstaller.calls, 0)
    }

    func testUninstallWithoutUserUninstallerIsRefused() async {
        let report = await InstallerEngine(services: InstallerServices()).uninstall(deleteConfig: true)

        XCTAssertFalse(report.success)
        XCTAssertTrue(report.failureReason?.contains("Use Uninstall KeyPath in Settings") ?? false)
    }

    func testUserUninstallDelegatesToSessionUninstaller() async {
        let uninstaller = UserUninstallerStub()
        let report = await InstallerEngine(services: InstallerServices(makeUninstaller: { uninstaller }))
            .uninstall(deleteConfig: true)
        XCTAssertTrue(report.success)
        XCTAssertEqual(report.logs, ["Backup saved"])
        XCTAssertEqual(uninstaller.calls, 1)
    }

    @MainActor
    private final class UserUninstallerStub: WizardUninstalling {
        var calls = 0
        func performUninstall(deleteConfig: Bool) async -> WizardUninstallResult {
            calls += 1
            XCTAssertTrue(deleteConfig)
            return WizardUninstallResult(success: true, logs: ["Backup saved"])
        }
    }
}
