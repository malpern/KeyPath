import KeyPathPermissions
import KeyPathWizardCore
import XCTest

@testable import KeyPathAppKit

@MainActor
final class KeyPathCLITests: XCTestCase {
    func testStatusCommandReturnsSuccessWhenSystemOperational() async {
        let context = makeSystemContext()
        let stub = InstallerEngineStub(context: context)
        let cli = KeyPathCLI(installerEngine: stub, privilegeBrokerFactory: { PrivilegeBroker() })

        let exitCode = await cli.run(arguments: ["keypath-cli", "status"])

        XCTAssertEqual(exitCode, 0)
        XCTAssertEqual(stub.inspectCallCount, 1)
    }

    func testStatusCommandReturnsFailureWhenSystemHasIssues() async {
        var context = makeSystemContext()
        context = makeSystemContext(helperReady: false)
        let stub = InstallerEngineStub(context: context)
        let cli = KeyPathCLI(installerEngine: stub, privilegeBrokerFactory: { PrivilegeBroker() })

        let exitCode = await cli.run(arguments: ["keypath-cli", "status"])

        XCTAssertEqual(exitCode, 1)
    }

    func testUninstallCommandDelegatesToInstallerEngine() async {
        let stub = InstallerEngineStub(context: makeSystemContext())
        stub.uninstallReport = InstallerReport(success: true)
        let cli = KeyPathCLI(installerEngine: stub, privilegeBrokerFactory: { PrivilegeBroker() })

        let exitCode = await cli.run(arguments: ["keypath-cli", "uninstall"])

        XCTAssertEqual(exitCode, 0)
        XCTAssertEqual(stub.uninstallCallCount, 1)
        XCTAssertEqual(stub.lastDeleteConfig, false)
    }

    func testUninstallCommandPropagatesFailureAndDeleteConfigFlag() async {
        let stub = InstallerEngineStub(context: makeSystemContext())
        stub.uninstallReport = InstallerReport(success: false, failureReason: "boom")
        let cli = KeyPathCLI(installerEngine: stub, privilegeBrokerFactory: { PrivilegeBroker() })

        let exitCode = await cli.run(arguments: ["keypath-cli", "uninstall", "--delete-config"])

        XCTAssertEqual(exitCode, 1)
        XCTAssertEqual(stub.uninstallCallCount, 1)
        XCTAssertEqual(stub.lastDeleteConfig, true)
    }
}

// MARK: - Test Helpers

private func makeSystemContext(
    helperReady: Bool = true,
    componentsReady: Bool = true,
    servicesHealthy: Bool = true,
    permissionsReady: Bool = true,
    conflicts: [SystemConflict] = []
) -> SystemContext {
    let status: PermissionOracle.Status = permissionsReady ? .granted : .denied
    let permissionSet = PermissionOracle.PermissionSet(
        accessibility: status,
        inputMonitoring: status,
        source: "test",
        confidence: .high,
        timestamp: Date()
    )
    let permissions = PermissionOracle.Snapshot(
        keyPath: permissionSet,
        kanata: permissionSet,
        timestamp: Date()
    )

    let helper = HelperStatus(isInstalled: helperReady, version: "1.0", isWorking: helperReady)
    let components =
        componentsReady
            ? ComponentStatus(
                kanataBinaryInstalled: true,
                karabinerDriverInstalled: true,
                karabinerDaemonRunning: true,
                vhidDeviceInstalled: true,
                vhidDeviceHealthy: true,
                launchDaemonServicesHealthy: true,
                vhidServicesHealthy: true,
                vhidVersionMismatch: false
            )
            : ComponentStatus.empty

    let services =
        servicesHealthy
            ? HealthStatus(kanataRunning: true, karabinerDaemonRunning: true, vhidHealthy: true)
            : HealthStatus.empty

    let conflictStatus = ConflictStatus(conflicts: conflicts, canAutoResolve: !conflicts.isEmpty)

    return SystemContext(
        permissions: permissions,
        services: services,
        conflicts: conflictStatus,
        components: components,
        helper: helper,
        system: EngineSystemInfo(macOSVersion: "15.0", driverCompatible: true),
        timestamp: Date()
    )
}

@MainActor
private final class InstallerEngineStub: InstallerEngineProtocol {
    var context: SystemContext
    var reportToReturn: InstallerReport
    var uninstallReport: InstallerReport
    private(set) var inspectCallCount = 0
    private(set) var uninstallCallCount = 0
    private(set) var lastDeleteConfig: Bool?

    init(context: SystemContext) {
        self.context = context
        reportToReturn = InstallerReport(success: true)
        uninstallReport = InstallerReport(success: true)
    }

    func inspectSystem() async -> SystemContext {
        inspectCallCount += 1
        return context
    }

    func makePlan(for intent: InstallIntent, context _: SystemContext) async -> InstallPlan {
        InstallPlan(recipes: [], status: .ready, intent: intent)
    }

    func run(intent _: InstallIntent, using _: PrivilegeBroker) async -> InstallerReport {
        reportToReturn
    }

    func uninstall(deleteConfig: Bool, using _: PrivilegeBroker) async -> InstallerReport {
        uninstallCallCount += 1
        lastDeleteConfig = deleteConfig
        return uninstallReport
    }
}
