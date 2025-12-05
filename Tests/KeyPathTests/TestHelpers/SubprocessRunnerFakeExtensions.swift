import Foundation
@testable import KeyPathCore

/// Extensions to SubprocessRunnerFake for advanced test scenarios
extension SubprocessRunnerFake {
    /// Configure specific exit codes for commands
    func setExitCode(_ exitCode: Int32, for executable: String) {
        configureRunResult { exec, _ in
            if exec == executable {
                return ProcessResult(exitCode: exitCode, stdout: "", stderr: "", duration: 0.1)
            }
            return self.defaultRunResult
        }
    }

    /// Configure exit code with stderr output
    func setExitCode(_ exitCode: Int32, stderr: String, for executable: String) {
        configureRunResult { exec, _ in
            if exec == executable {
                return ProcessResult(exitCode: exitCode, stdout: "", stderr: stderr, duration: 0.1)
            }
            return self.defaultRunResult
        }
    }

    /// Configure command to fail with specific stdout/stderr
    func setCommandOutput(
        exitCode: Int32,
        stdout: String = "",
        stderr: String = "",
        duration: TimeInterval = 0.1,
        for executable: String
    ) {
        configureRunResult { exec, _ in
            if exec == executable {
                return ProcessResult(exitCode: exitCode, stdout: stdout, stderr: stderr, duration: duration)
            }
            return self.defaultRunResult
        }
    }

    /// Check if a specific command was executed
    func wasExecuted(_ executable: String) -> Bool {
        executedCommands.contains { $0.executable == executable }
    }

    /// Count how many times a command was executed
    func executionCount(_ executable: String) -> Int {
        executedCommands.filter { $0.executable == executable }.count
    }

    /// Get all arguments passed to a specific command
    func getArguments(for executable: String) -> [[String]] {
        executedCommands.filter { $0.executable == executable }.map { $0.args }
    }

    /// Verify command was called with specific arguments
    func wasCalledWith(_ executable: String, args: [String]) -> Bool {
        executedCommands.contains { command in
            command.executable == executable && command.args == args
        }
    }
}
