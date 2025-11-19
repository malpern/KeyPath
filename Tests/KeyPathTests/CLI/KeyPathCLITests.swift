@testable import KeyPath
import KeyPathPermissions
import KeyPathWizardCore
import XCTest

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
    let components = componentsReady
        ? ComponentStatus(
            kanataBinaryInstalled: true,
            karabinerDriverInstalled: true,
            karabinerDaemonRunning: true,
            vhidDeviceInstalled: true,
            vhidDeviceHealthy: true,
            launchDaemonServicesHealthy: true,
            vhidVersionMismatch: false
        )
        : ComponentStatus.empty

    let services = servicesHealthy
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
    private(set) var inspectCallCount = 0

    init(context: SystemContext) {
        self.context = context
        self.reportToReturn = InstallerReport(success: true)
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
}

