import Foundation
@testable import KeyPathCore
import XCTest

/// Tests for SubprocessRunner actor
/// Verifies that subprocess execution works correctly and doesn't block MainActor
final class SubprocessRunnerTests: XCTestCase {
    var fakeRunner: SubprocessRunnerFake!

    override func setUp() async throws {
        try await super.setUp()
        fakeRunner = SubprocessRunnerFake.shared
        await fakeRunner.reset()
    }

    override func tearDown() async throws {
        fakeRunner = nil
        try await super.tearDown()
    }

    // MARK: - Success Scenarios

    func testRunSuccess() async throws {
        // Setup fake to return success
        await fakeRunner.configureRunResult { _, _ in
            ProcessResult(
                exitCode: 0,
                stdout: "test output",
                stderr: "",
                duration: 0.1
            )
        }

        let result = try await fakeRunner.run("/usr/bin/echo", args: ["hello"], timeout: 5)

        XCTAssertEqual(result.exitCode, 0)
        XCTAssertEqual(result.stdout, "test output")
        XCTAssertEqual(result.stderr, "")
        let commands = await fakeRunner.executedCommands
        XCTAssertEqual(commands.count, 1)
        XCTAssertEqual(commands[0].executable, "/usr/bin/echo")
        XCTAssertEqual(commands[0].args, ["hello"])
    }

    func testRunNonZeroExit() async throws {
        // Setup fake to return non-zero exit
        await fakeRunner.configureRunResult { _, _ in
            ProcessResult(
                exitCode: 1,
                stdout: "",
                stderr: "command not found",
                duration: 0.05
            )
        }

        let result = try await fakeRunner.run("/usr/bin/nonexistent", args: [], timeout: 5)

        XCTAssertEqual(result.exitCode, 1)
        XCTAssertEqual(result.stderr, "command not found")
    }

    func testPgrepSuccess() async {
        await fakeRunner.configurePgrepResult { _ in
            [1234, 5678]
        }

        let pids = await fakeRunner.pgrep("kanata.*--cfg")

        XCTAssertEqual(pids, [1234, 5678])
        let commands = await fakeRunner.executedCommands
        XCTAssertEqual(commands.count, 1)
        XCTAssertEqual(commands[0].executable, "/usr/bin/pgrep")
    }

    func testLaunchctlSuccess() async throws {
        await fakeRunner.configureLaunchctlResult { _, _ in
            ProcessResult(
                exitCode: 0,
                stdout: "program = /usr/bin/kanata",
                stderr: "",
                duration: 0.1
            )
        }

        let result = try await fakeRunner.launchctl("print", ["system/com.keypath.kanata"])

        XCTAssertEqual(result.exitCode, 0)
        XCTAssertTrue(result.stdout.contains("program"))
        let commands = await fakeRunner.executedCommands
        XCTAssertEqual(commands.count, 1)
        XCTAssertEqual(commands[0].executable, "/bin/launchctl")
    }

    // MARK: - Error Scenarios

    func testRunThrowsError() async {
        await fakeRunner.setShouldFailLaunch(true)

        do {
            _ = try await fakeRunner.run("/usr/bin/test", args: [], timeout: 5)
            XCTFail("Expected error to be thrown")
        } catch {
            if let subprocessError = error as? SubprocessError {
                switch subprocessError {
                case .launchFailed:
                    // Expected
                    break
                default:
                    XCTFail("Unexpected error type: \(subprocessError)")
                }
            } else {
                XCTFail("Unexpected error type: \(error)")
            }
        }
    }

    func testLaunchctlThrowsError() async {
        await fakeRunner.setShouldFailLaunch(true)

        do {
            _ = try await fakeRunner.launchctl("print", ["system/com.keypath.kanata"])
            XCTFail("Expected error to be thrown")
        } catch {
            if let subprocessError = error as? SubprocessError {
                switch subprocessError {
                case .launchFailed:
                    // Expected
                    break
                default:
                    XCTFail("Unexpected error type: \(subprocessError)")
                }
            } else {
                XCTFail("Unexpected error type: \(error)")
            }
        }
    }

    // MARK: - Timeout Scenarios

    func testTimeoutHandling() async {
        // Setup fake to simulate timeout
        await fakeRunner.setShouldTimeout(true)

        do {
            _ = try await fakeRunner.run("/usr/bin/test", args: [], timeout: 10)
            XCTFail("Expected timeout error")
        } catch {
            if let subprocessError = error as? SubprocessError {
                switch subprocessError {
                case .timeout:
                    // Expected
                    break
                default:
                    XCTFail("Unexpected error type: \(subprocessError)")
                }
            } else {
                XCTFail("Unexpected error type: \(error)")
            }
        }
    }

    // MARK: - Real SubprocessRunner Tests

    func testRealSubprocessRunnerEcho() async throws {
        // Test with real SubprocessRunner using a simple command
        let result = try await SubprocessRunner.shared.run(
            "/bin/echo",
            args: ["test"],
            timeout: 5
        )

        XCTAssertEqual(result.exitCode, 0)
        XCTAssertTrue(result.stdout.contains("test") || result.stdout.trimmingCharacters(in: .whitespacesAndNewlines) == "test")
    }

    func testRealSubprocessRunnerNonExistentCommand() async {
        // Test error handling for non-existent command
        do {
            _ = try await SubprocessRunner.shared.run(
                "/usr/bin/nonexistent_command_12345",
                args: [],
                timeout: 2
            )
            XCTFail("Expected error for non-existent command")
        } catch {
            // Should throw SubprocessError.launchFailed
            XCTAssertTrue(error is SubprocessError)
        }
    }

    func testRealSubprocessRunnerPgrep() async {
        // Test pgrep with a pattern that won't match (to avoid flakiness)
        let pids = await SubprocessRunner.shared.pgrep("nonexistent_process_pattern_12345")

        // Should return empty array for non-matching pattern
        XCTAssertTrue(pids.isEmpty)
    }

    func testRunCancellationTerminatesProcess() async {
        let longRunningTask = Task {
            try await SubprocessRunner.shared.run(
                "/bin/sleep",
                args: ["5"],
                timeout: 30
            )
        }

        // Allow the process to start
        try? await Task.sleep(nanoseconds: 200_000_000)

        longRunningTask.cancel()

        do {
            _ = try await longRunningTask.value
            XCTFail("Expected cancellation to throw")
        } catch {
            XCTAssertTrue(error is CancellationError, "Expected CancellationError, got \(error)")
        }
    }
}

