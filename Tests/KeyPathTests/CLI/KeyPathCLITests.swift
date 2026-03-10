@testable import KeyPathAppKit
@testable import KeyPathCore
import KeyPathPermissions
import KeyPathWizardCore
@preconcurrency import XCTest

@MainActor
final class KeyPathCLITests: XCTestCase {
    func testStatusCommandPrintsOutputBridgeCompanionDetails() async throws {
        var context = makeSystemContext()
        context = SystemContext(
            permissions: context.permissions,
            services: context.services,
            conflicts: context.conflicts,
            components: context.components,
            helper: context.helper,
            system: EngineSystemInfo(
                macOSVersion: "15.0",
                driverCompatible: true,
                outputBridgeStatus: KanataOutputBridgeStatus(
                    available: true,
                    companionRunning: true,
                    requiresPrivilegedBridge: true,
                    socketDirectory: "/Library/KeyPath/run/kpko",
                    detail: "privileged output companion is installed and launchctl can inspect system/com.keypath.output-bridge"
                )
            ),
            timestamp: context.timestamp
        )
        let stub = InstallerEngineStub(context: context)
        let cli = KeyPathCLI(installerEngine: stub, privilegeBrokerFactory: { PrivilegeBroker() })

        let output = try await captureStandardOutput {
            _ = await cli.run(arguments: ["keypath-cli", "status"])
        }

        XCTAssertTrue(output.contains("--- Output Bridge Companion ---"))
        XCTAssertTrue(output.contains("Available: ✅"))
        XCTAssertTrue(output.contains("Running: ✅"))
        XCTAssertTrue(output.contains("Socket Directory: /Library/KeyPath/run/kpko"))
        XCTAssertTrue(output.contains("com.keypath.output-bridge"))
    }

    func testStatusCommandPrintsActiveRuntimePath() async throws {
        var context = makeSystemContext()
        context = SystemContext(
            permissions: context.permissions,
            services: HealthStatus(
                kanataRunning: true,
                karabinerDaemonRunning: true,
                vhidHealthy: true,
                activeRuntimePathTitle: "Split Runtime Host",
                activeRuntimePathDetail: "Bundled user-session host active with privileged output companion"
            ),
            conflicts: context.conflicts,
            components: context.components,
            helper: context.helper,
            system: context.system,
            timestamp: context.timestamp
        )
        let stub = InstallerEngineStub(context: context)
        let cli = KeyPathCLI(installerEngine: stub, privilegeBrokerFactory: { PrivilegeBroker() })

        let output = try await captureStandardOutput {
            _ = await cli.run(arguments: ["keypath-cli", "status"])
        }

        XCTAssertTrue(output.contains("Active Runtime Path: Split Runtime Host"))
        XCTAssertTrue(output.contains("Runtime Detail: Bundled user-session host active with privileged output companion"))
    }

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

@MainActor
private func captureStandardOutput(
    _ operation: () async throws -> Void
) async throws -> String {
    var pipeDescriptors = [Int32](repeating: 0, count: 2)
    guard pipe(&pipeDescriptors) == 0 else {
        throw POSIXError(.EIO)
    }
    let originalStdout = dup(STDOUT_FILENO)
    dup2(pipeDescriptors[1], STDOUT_FILENO)

    do {
        try await operation()
        fflush(stdout)
    } catch {
        fflush(stdout)
        dup2(originalStdout, STDOUT_FILENO)
        close(originalStdout)
        close(pipeDescriptors[1])
        close(pipeDescriptors[0])
        throw error
    }

    dup2(originalStdout, STDOUT_FILENO)
    close(originalStdout)
    close(pipeDescriptors[1])
    let readHandle = FileHandle(fileDescriptor: pipeDescriptors[0], closeOnDealloc: true)
    let data = (try? readHandle.readToEnd()) ?? Data()
    return String(decoding: data, as: UTF8.self)
}

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
