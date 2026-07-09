@testable import KeyPathAppKit
@testable import KeyPathCore
import ServiceManagement
@preconcurrency import XCTest

final class HelperManagerTests: XCTestCase {
    private var originalFactory: ((String) -> SMAppServiceProtocol)!
    private var originalSynchronousServiceFactory: ((String) -> SMAppServiceProtocol)!
    private var originalStatusProvider: SMAppServiceStatusProvider!
    private var originalSubprocessRunnerFactory: (() -> SubprocessRunning)!
    private var originalSystemStateProviderFactory: (() -> SystemStateProvider)!

    override func setUp() {
        super.setUp()
        originalFactory = HelperManager.smServiceFactory
        originalSynchronousServiceFactory = SMAppServiceStatusProvider.synchronousServiceFactory
        originalStatusProvider = SMAppServiceStatusProvider.shared
        originalSubprocessRunnerFactory = HelperManager.subprocessRunnerFactory
        originalSystemStateProviderFactory = HelperManager.systemStateProviderFactory
    }

    override func tearDown() {
        HelperManager.smServiceFactory = originalFactory
        SMAppServiceStatusProvider.synchronousServiceFactory = originalSynchronousServiceFactory
        SMAppServiceStatusProvider.shared = originalStatusProvider
        HelperManager.subprocessRunnerFactory = originalSubprocessRunnerFactory
        HelperManager.systemStateProviderFactory = originalSystemStateProviderFactory
        HelperManager.testHelperFunctionalityOverride = nil
        HelperManager.staleHelperSMAppServiceBootoutOverride = nil
        super.tearDown()
    }

    /// Point both the register/unregister seam AND the centralized status provider
    /// (#853) at the same fake so status reads and mutation calls observe one instance.
    private func installFake(_ service: SMAppServiceProtocol) {
        HelperManager.smServiceFactory = { _ in service }
        SMAppServiceStatusProvider.shared = SMAppServiceStatusProvider(
            cacheTTL: 0,
            serviceFactory: { _ in service }
        )
    }

    func testInstallHelperAttemptsRegisterWhenStatusIsNotFoundAndSurfacesError() async {
        // Arrange: Simulate .notFound and an SMAppService error with detailed description
        let expectedDescription = "Codesigning failure loading plist: com.keypath.helper code: -67028"
        let smError = NSError(
            domain: "SMAppServiceErrorDomain", code: 3,
            userInfo: [NSLocalizedDescriptionKey: expectedDescription]
        )
        installFake(FakeSMAppService(status: .notFound, registerError: smError))

        // Act + Assert
        do {
            try await HelperManager.shared.installHelper()
            XCTFail("Expected installHelper() to throw when register fails")
        } catch {
            // Verify we surface the underlying SMAppService error text
            let msg = (error as NSError).localizedDescription
            XCTAssertTrue(
                msg.contains("SMAppService register failed"), "missing SMAppService prefix: \(msg)"
            )
            XCTAssertTrue(msg.contains(expectedDescription), "missing detailed SM error: \(msg)")
        }
    }

    func testStaleHelperSMAppServiceBootoutCommandsTargetSystemDomain() {
        XCTAssertEqual(
            HelperManager.staleHelperSMAppServiceBootoutCommands(),
            ["/bin/launchctl bootout system/com.keypath.helper 2>/dev/null || true"]
        )
    }

    func testHelperNeedsLoginItemsApprovalUsesHelperManagerSMAppServiceFactory() {
        installFake(FakeSMAppService(status: .requiresApproval))

        XCTAssertTrue(HelperManager.shared.helperNeedsLoginItemsApproval())
    }

    func testInstallHelperRecoversEnabledButUnresponsiveRegistration() async throws {
        let service = FakeSMAppService(status: .enabled)
        installFake(service)

        var bootoutCalls = 0
        HelperManager.staleHelperSMAppServiceBootoutOverride = {
            bootoutCalls += 1
            return (true, "booted out")
        }

        HelperManager.testHelperFunctionalityOverride = {
            service.unregisterCalls > 0
        }

        try await HelperManager.shared.installHelper()

        XCTAssertEqual(service.registerCalls, 2)
        XCTAssertEqual(service.unregisterCalls, 1)
        XCTAssertEqual(bootoutCalls, 1)
    }

    func testIsHelperInstalledUsesInjectedSystemStateProviderForLaunchctlEvidence() async {
        installFake(FakeSMAppService(status: .notRegistered))

        let directRunner = CapturingSubprocessRunner { _, _ in
            ProcessResult(exitCode: 113, stdout: "", stderr: "direct runner should not be used", duration: 0)
        }
        HelperManager.subprocessRunnerFactory = { directRunner }

        let providerRunner = CapturingSubprocessRunner { subcommand, args in
            if subcommand == "print", args == ["system/com.keypath.helper"] {
                return ProcessResult(
                    exitCode: 0,
                    stdout: "program = /Applications/KeyPath.app/Contents/Library/HelperTools/KeyPathHelper\nstate = running\npid = 42",
                    stderr: "",
                    duration: 0
                )
            }
            return ProcessResult(exitCode: 113, stdout: "", stderr: "unexpected target", duration: 0)
        }
        HelperManager.systemStateProviderFactory = { SystemStateProvider(probes: providerRunner.systemProbeClient()) }

        let installed = await HelperManager.shared.isHelperInstalled()

        XCTAssertTrue(installed)
        let commands = await providerRunner.executedCommands
        XCTAssertEqual(commands.map(\.executable), ["/bin/launchctl"])
        XCTAssertEqual(commands.map(\.args), [["print", "system/com.keypath.helper"]])
        let directCommands = await directRunner.executedCommands
        XCTAssertTrue(directCommands.isEmpty)
    }

    func testLastHelperLogsUsesInjectedSystemStateProviderForLaunchctlEvidence() async {
        let directRunner = CapturingSubprocessRunner { _, _ in
            ProcessResult(exitCode: 113, stdout: "", stderr: "direct runner should not be used", duration: 0)
        }
        HelperManager.subprocessRunnerFactory = { directRunner }

        let providerRunner = CapturingSubprocessRunner { subcommand, args in
            if subcommand == "print", args == ["system/com.keypath.helper"] {
                return ProcessResult(
                    exitCode: 113,
                    stdout: "",
                    stderr: "Could not find service \"com.keypath.helper\" in domain for system",
                    duration: 0
                )
            }
            return ProcessResult(exitCode: 113, stdout: "", stderr: "unexpected target", duration: 0)
        }
        HelperManager.systemStateProviderFactory = { SystemStateProvider(probes: providerRunner.systemProbeClient()) }

        let logs = await HelperManager.shared.lastHelperLogs()

        XCTAssertEqual(
            logs,
            [
                "Helper not registered: launchctl has no job 'system/com.keypath.helper'",
                "Click 'Install Helper', then Test XPC again."
            ]
        )
        let commands = await providerRunner.executedCommands
        XCTAssertEqual(commands.map(\.executable), ["/bin/launchctl"])
        XCTAssertEqual(commands.map(\.args), [["print", "system/com.keypath.helper"]])
        let directCommands = await directRunner.executedCommands
        XCTAssertTrue(directCommands.isEmpty)
    }
}

// MARK: - Test Doubles

private final class FakeSMAppService: SMAppServiceProtocol, @unchecked Sendable {
    var status: SMAppService.Status
    var registerError: Error?
    var registerCalls = 0
    var unregisterCalls = 0

    init(status: SMAppService.Status, registerError: Error? = nil) {
        self.status = status
        self.registerError = registerError
    }

    func register() throws {
        registerCalls += 1
        if let registerError {
            throw registerError
        }
    }

    func unregister() async throws {
        unregisterCalls += 1
    }
}

private actor CapturingSubprocessRunner: SubprocessRunning {
    private let launchctlHandler: @Sendable (String, [String]) -> ProcessResult
    private(set) var executedCommands: [(executable: String, args: [String])] = []

    init(launchctlHandler: @escaping @Sendable (String, [String]) -> ProcessResult) {
        self.launchctlHandler = launchctlHandler
    }

    func run(_: String, args _: [String], timeout _: TimeInterval?) async throws -> ProcessResult {
        ProcessResult(exitCode: 0, stdout: "", stderr: "", duration: 0)
    }

    func pgrep(_: String) async -> [pid_t] {
        []
    }

    func launchctl(_ subcommand: String, _ args: [String]) async throws -> ProcessResult {
        executedCommands.append((executable: "/bin/launchctl", args: [subcommand] + args))
        return launchctlHandler(subcommand, args)
    }
}
