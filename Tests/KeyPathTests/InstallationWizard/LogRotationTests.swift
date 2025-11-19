import XCTest

@testable import KeyPath

@MainActor
final class LogRotationTests: XCTestCase {
    func testInstallLogRotationFailsWhenCommandFails() async {
        let fake = FakeAdminCommandExecutor(resultProvider: { _, _ in
            CommandExecutionResult(exitCode: 1, output: "Permission denied")
        })
        AdminCommandExecutorHolder.shared = fake
        let installer = LaunchDaemonInstaller()

        let success = await installer.installLogRotationService()

        XCTAssertFalse(success)
        XCTAssertTrue(fake.commands.contains { $0.description.contains("log rotation") })
    }

    func testInstallLogRotationSucceedsWhenCommandSucceeds() async {
        let fake = FakeAdminCommandExecutor()
        AdminCommandExecutorHolder.shared = fake
        let installer = LaunchDaemonInstaller()

        let success = await installer.installLogRotationService()

        XCTAssertTrue(success)
        XCTAssertEqual(fake.commands.count, 1)
    }
}
