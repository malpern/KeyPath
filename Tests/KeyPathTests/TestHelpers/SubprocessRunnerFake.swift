import Foundation
@testable import KeyPathCore

/// Fake implementation of SubprocessRunning for testing
///
/// Allows tests to control subprocess execution without actually spawning processes.
/// Supports success, failure, timeout, and custom result scenarios.
actor SubprocessRunnerFake: SubprocessRunning {
    static let shared = SubprocessRunnerFake()

    // MARK: - Configuration

    /// Custom result provider for run() calls
    var runResultProvider: ((String, [String]) -> ProcessResult)?

    /// Default result for run() calls
    var defaultRunResult = ProcessResult(
        exitCode: 0,
        stdout: "",
        stderr: "",
        duration: 0.1
    )

    /// Custom result provider for pgrep() calls
    var pgrepResultProvider: ((String) -> [pid_t])?

    /// Default PIDs for pgrep() calls
    var defaultPgrepResult: [pid_t] = []

    /// Custom result provider for launchctl() calls
    var launchctlResultProvider: ((String, [String]) -> ProcessResult)?

    /// Default result for launchctl() calls
    var defaultLaunchctlResult = ProcessResult(
        exitCode: 0,
        stdout: "",
        stderr: "",
        duration: 0.1
    )

    /// Whether to simulate timeout errors
    var shouldTimeout = false

    /// Whether to simulate launch failures
    var shouldFailLaunch = false

    /// Track all executed commands for verification
    private(set) var executedCommands: [(executable: String, args: [String])] = []

    // MARK: - Initialization

    private init() {}

    // MARK: - Reset

    func reset() {
        runResultProvider = nil
        defaultRunResult = ProcessResult(exitCode: 0, stdout: "", stderr: "", duration: 0.1)
        pgrepResultProvider = nil
        defaultPgrepResult = []
        launchctlResultProvider = nil
        defaultLaunchctlResult = ProcessResult(exitCode: 0, stdout: "", stderr: "", duration: 0.1)
        shouldTimeout = false
        shouldFailLaunch = false
        executedCommands.removeAll()
    }

    // MARK: - SubprocessRunning Implementation

    func run(
        _ executable: String,
        args: [String],
        timeout: TimeInterval?
    ) async throws -> ProcessResult {
        executedCommands.append((executable: executable, args: args))

        if shouldFailLaunch {
            throw SubprocessError.launchFailed(
                executable: executable,
                error: NSError(domain: "TestError", code: 1, userInfo: [NSLocalizedDescriptionKey: "Simulated launch failure"])
            )
        }

        if shouldTimeout {
            throw SubprocessError.timeout(executable: executable, timeout: timeout ?? 30)
        }

        if let provider = runResultProvider {
            return provider(executable, args)
        }

        return defaultRunResult
    }

    func pgrep(_ pattern: String) async -> [pid_t] {
        executedCommands.append((executable: "/usr/bin/pgrep", args: ["-f", pattern]))

        if let provider = pgrepResultProvider {
            return provider(pattern)
        }

        return defaultPgrepResult
    }

    func launchctl(_ subcommand: String, _ args: [String]) async throws -> ProcessResult {
        var allArgs = [subcommand]
        allArgs.append(contentsOf: args)
        executedCommands.append((executable: "/bin/launchctl", args: allArgs))

        if shouldFailLaunch {
            throw SubprocessError.launchFailed(
                executable: "/bin/launchctl",
                error: NSError(domain: "TestError", code: 1, userInfo: [NSLocalizedDescriptionKey: "Simulated launch failure"])
            )
        }

        if let provider = launchctlResultProvider {
            return provider(subcommand, args)
        }

        return defaultLaunchctlResult
    }
}

