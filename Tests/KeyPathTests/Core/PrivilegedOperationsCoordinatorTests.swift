import XCTest

@testable import KeyPath
@testable import KeyPathCore

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
        let fakeExecutor = FakeAdminCommandExecutor()
        fakeExecutor.resultProvider = { command, description in
            if description.contains("log rotation") {
                return CommandExecutionResult(exitCode: 1, output: "Permission denied")
            }
            return CommandExecutionResult(exitCode: 0, output: "")
        }
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

private final class FakeAdminCommandExecutor: AdminCommandExecutor {
    var commands: [(command: String, description: String)] = []
    var resultProvider: ((String, String) -> CommandExecutionResult)?

    func execute(command: String, description: String) async throws -> CommandExecutionResult {
        commands.append((command, description))
        if let provider = resultProvider {
            return provider(command, description)
        }
        return CommandExecutionResult(exitCode: 0, output: "")
    }
}

private extension XCTestCase {
    func XCTAssertThrowsErrorAsync<T>(
        _ expression: @autoclosure @escaping () async throws -> T,
        _ message: @autoclosure () -> String = "",
        file: StaticString = #file,
        line: UInt = #line,
        _ handler: (_ error: Error) -> Void
    ) async {
        do {
            _ = try await expression()
            XCTFail(message(), file: file, line: line)
        } catch {
            handler(error)
        }
    }
}
