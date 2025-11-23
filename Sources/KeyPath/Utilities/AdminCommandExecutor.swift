import Foundation

public struct CommandExecutionResult: Sendable {
    public let exitCode: Int32
    public let output: String
}

public protocol AdminCommandExecutor: Sendable {
    func execute(command: String, description: String) async throws -> CommandExecutionResult
}

// MARK: - Privileged Command Runner

/// Centralized entry point for all privileged (admin) command execution.
///
/// ## TODO: TEMPORARY - Remove sudo mode before shipping
///
/// This module supports two modes:
/// - **Production (default):** Uses osascript with "administrator privileges" dialog
/// - **Test/Dev mode:** Uses sudo (requires sudoers configuration)
///
/// Set `KEYPATH_USE_SUDO=1` to enable sudo mode for automated testing.
/// See `Scripts/setup-test-sudo.sh` for sudoers configuration.
///
/// ## Grep marker for removal:
/// Search for `KEYPATH_USE_SUDO` to find all related code.
public enum PrivilegedCommandRunner {

    /// Whether to use sudo instead of osascript for privileged operations.
    /// Set `KEYPATH_USE_SUDO=1` environment variable to enable.
    public static var useSudo: Bool {
        ProcessInfo.processInfo.environment["KEYPATH_USE_SUDO"] == "1"
    }

    /// Execute a shell command with administrator privileges.
    ///
    /// - Parameters:
    ///   - command: The shell command to execute (will be run via /bin/bash -c)
    ///   - prompt: Description shown in the admin dialog (ignored in sudo mode)
    /// - Returns: Result containing exit code and combined stdout/stderr output
    public static func run(
        _ command: String,
        prompt: String = "KeyPath needs administrator privileges"
    ) -> CommandExecutionResult {
        if useSudo {
            return runWithSudo(command)
        } else {
            return runWithOsascript(command, prompt: prompt)
        }
    }

    /// Async version of run for use in async contexts.
    public static func runAsync(
        _ command: String,
        prompt: String = "KeyPath needs administrator privileges"
    ) async -> CommandExecutionResult {
        run(command, prompt: prompt)
    }

    // MARK: - Private Implementation

    /// TODO: TEMPORARY - sudo mode for test automation. Remove before shipping.
    private static func runWithSudo(_ command: String) -> CommandExecutionResult {
        let task = Process()
        task.executableURL = URL(fileURLWithPath: "/usr/bin/sudo")
        task.arguments = ["/bin/bash", "-c", command]

        let pipe = Pipe()
        task.standardOutput = pipe
        task.standardError = pipe

        do {
            try task.run()
            task.waitUntilExit()

            let outputData = pipe.fileHandleForReading.readDataToEndOfFile()
            let output = String(data: outputData, encoding: .utf8) ?? ""
            return CommandExecutionResult(exitCode: task.terminationStatus, output: output)
        } catch {
            return CommandExecutionResult(exitCode: -1, output: "Failed to execute sudo: \(error)")
        }
    }

    private static func runWithOsascript(_ command: String, prompt: String) -> CommandExecutionResult {
        let escapedCommand = escapeForAppleScript(command)
        let osascriptCommand = """
        do shell script "\(escapedCommand)" with administrator privileges with prompt "\(prompt)"
        """

        let task = Process()
        task.executableURL = URL(fileURLWithPath: "/usr/bin/osascript")
        task.arguments = ["-e", osascriptCommand]

        let pipe = Pipe()
        task.standardOutput = pipe
        task.standardError = pipe

        do {
            try task.run()
            task.waitUntilExit()

            let outputData = pipe.fileHandleForReading.readDataToEndOfFile()
            let output = String(data: outputData, encoding: .utf8) ?? ""
            return CommandExecutionResult(exitCode: task.terminationStatus, output: output)
        } catch {
            return CommandExecutionResult(exitCode: -1, output: "Failed to execute osascript: \(error)")
        }
    }

    private static func escapeForAppleScript(_ command: String) -> String {
        command
            .replacingOccurrences(of: "\\", with: "\\\\")
            .replacingOccurrences(of: "\"", with: "\\\"")
            .replacingOccurrences(of: "\n", with: "\\n")
            .replacingOccurrences(of: "\r", with: "\\r")
    }
}

// MARK: - Legacy Protocol Support

public final class DefaultAdminCommandExecutor: AdminCommandExecutor {
    public init() {}

    public func execute(command: String, description: String) async throws -> CommandExecutionResult {
        PrivilegedCommandRunner.run(command, prompt: description)
    }
}

@MainActor
public enum AdminCommandExecutorHolder {
    public static var shared: AdminCommandExecutor = DefaultAdminCommandExecutor()
}
