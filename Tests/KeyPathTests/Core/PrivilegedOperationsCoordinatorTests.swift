import XCTest

@testable import KeyPath

@MainActor
final class PrivilegedOperationsCoordinatorTests: XCTestCase {
    private var originalExecutor: AdminCommandExecutor!

    override func setUp() {
        super.setUp()
        originalExecutor = AdminCommandExecutorHolder.shared
    }

    override func tearDown() {
        AdminCommandExecutorHolder.shared = originalExecutor
        super.tearDown()
    }

    func testInstallAllLaunchDaemonServicesUsesLaunchctlBootstrap() async throws {
        let fakeExecutor = FakeAdminCommandExecutor()
        AdminCommandExecutorHolder.shared = fakeExecutor
        let coordinator = PrivilegedOperationsCoordinator()

        try await coordinator.installAllLaunchDaemonServices(
            kanataBinaryPath: "/tmp/kanata",
            kanataConfigPath: "/tmp/keypath.kbd",
            tcpPort: 45000
        )

        XCTAssertTrue(
            fakeExecutor.commands.contains {
                $0.command.contains("launchctl bootstrap system")
            },
            "Installation should bootstrap the launchctl plists"
        )
    }

    func testRestartUnhealthyServicesIssuesKickstart() async throws {
        let fakeExecutor = FakeAdminCommandExecutor()
        AdminCommandExecutorHolder.shared = fakeExecutor
        let coordinator = PrivilegedOperationsCoordinator()

        try await coordinator.restartUnhealthyServices()

        XCTAssertTrue(
            fakeExecutor.commands.contains(where: { $0.command.contains("launchctl kickstart -k system") }),
            "Restart should issue a launchctl kickstart command"
        )
    }

    func testInstallLogRotationFailsOnCommandError() async {
        let fakeExecutor = FakeAdminCommandExecutor(resultProvider: { command, description in
            if description.contains("log rotation") {
                return CommandExecutionResult(exitCode: 1, output: "Permission denied")
            }
            return CommandExecutionResult(exitCode: 0, output: "")
        })
        AdminCommandExecutorHolder.shared = fakeExecutor
        let coordinator = PrivilegedOperationsCoordinator()

        await XCTAssertThrowsErrorAsync(try await coordinator.installLogRotation()) { error in
            guard case PrivilegedOperationError.commandFailed = error else {
                XCTFail("Expected commandFailed error, got \(error)")
                return
            }
        }
    }
}
