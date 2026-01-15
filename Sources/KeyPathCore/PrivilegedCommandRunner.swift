import Foundation

/// Centralized utility for executing commands with administrator privileges.
/// Uses sudo -n if KEYPATH_USE_SUDO=1 is set during tests, otherwise uses osascript.
///
/// This provides a single entry point for all privileged command execution,
/// ensuring consistent behavior between test and production environments.
///
/// **Production behavior**: Shows osascript admin dialog with password prompt
/// **Test behavior** (KEYPATH_USE_SUDO=1): Uses sudo -n (NOPASSWD rules required)
///
/// - Note: For test mode to work, run `sudo ./Scripts/dev-setup-sudoers.sh` first.
/// - Warning: Remove sudoers config before public release: `sudo ./Scripts/dev-remove-sudoers.sh`
public enum PrivilegedCommandRunner {
    public struct Batch: Sendable {
        public let label: String
        public let commands: [String]
        public let prompt: String

        public init(label: String, commands: [String], prompt: String? = nil) {
            self.label = label
            self.commands = commands
            self.prompt = prompt ?? "KeyPath needs to \(label.lowercased())."
        }

        public var script: String {
            let trimmed = commands
                .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
                .filter { !$0.isEmpty }
            if trimmed.isEmpty {
                return ":"
            }
            return "set -e\n" + trimmed.joined(separator: "\n")
        }
    }

    /// Result of a privileged command execution
    public struct Result {
        public let success: Bool
        public let output: String
        public let exitCode: Int32

        public init(success: Bool, output: String, exitCode: Int32 = 0) {
            self.success = success
            self.output = output
            self.exitCode = exitCode
        }
    }

    /// Execute a shell command with administrator privileges.
    ///
    /// - Parameters:
    ///   - command: The shell command to execute
    ///   - prompt: The prompt to show in the admin dialog (osascript only, ignored in sudo mode)
    /// - Returns: Result containing success status and output
    public static func execute(command: String, prompt: String) -> Result {
        if TestEnvironment.useSudoForPrivilegedOps {
            executeWithSudo(command: command)
        } else {
            executeWithOsascript(command: command, prompt: prompt)
        }
    }

    /// Execute multiple commands in sequence with administrator privileges.
    /// All commands are joined with && and executed in a single privileged session.
    ///
    /// - Parameters:
    ///   - commands: Array of shell commands to execute
    ///   - prompt: The prompt to show in the admin dialog
    /// - Returns: Result containing success status and combined output
    public static func execute(commands: [String], prompt: String) -> Result {
        let combinedCommand = commands.joined(separator: " && ")
        return execute(command: combinedCommand, prompt: prompt)
    }

    /// Execute a batch of commands in a single privileged session.
    public static func execute(batch: Batch) -> Result {
        AppLogger.shared.log(
            "🔐 [PrivilegedCommandRunner] Executing privileged batch: \(batch.label) (\(batch.commands.count) commands)"
        )
        return execute(command: batch.script, prompt: batch.prompt)
    }

    // MARK: - Private Implementation

    /// Execute a command using sudo -n (non-interactive).
    /// Requires sudoers NOPASSWD configuration.
    private static func executeWithSudo(command: String) -> Result {
        AppLogger.shared.log("🧪 [PrivilegedCommandRunner] Using sudo for privileged operation (KEYPATH_USE_SUDO=1)")

        let task = Process()
        task.executableURL = URL(fileURLWithPath: "/usr/bin/sudo")
        // Use -n for non-interactive (fails if password required)
        task.arguments = ["-n", "/bin/bash", "-c", command]

        let pipe = Pipe()
        task.standardOutput = pipe
        task.standardError = pipe

        do {
            try task.run()
            task.waitUntilExit()

            let data = pipe.fileHandleForReading.readDataToEndOfFile()
            let output = String(data: data, encoding: .utf8) ?? ""
            let success = task.terminationStatus == 0

            if success {
                AppLogger.shared.log("✅ [PrivilegedCommandRunner] sudo command succeeded")
            } else {
                AppLogger.shared.log("❌ [PrivilegedCommandRunner] sudo command failed (exit \(task.terminationStatus)): \(output)")
            }

            return Result(success: success, output: output, exitCode: task.terminationStatus)
        } catch {
            let errorMsg = "sudo execution failed: \(error.localizedDescription)"
            AppLogger.shared.log("❌ [PrivilegedCommandRunner] \(errorMsg)")
            return Result(success: false, output: errorMsg, exitCode: -1)
        }
    }

    /// Execute a command using osascript with admin privileges dialog.
    private static func executeWithOsascript(command: String, prompt: String) -> Result {
        let escapedCommand = escapeForAppleScript(command)
        let escapedPrompt = prompt.replacingOccurrences(of: "\"", with: "\\\"")
        let osascriptCommand = """
        do shell script "\(escapedCommand)" with administrator privileges with prompt "\(escapedPrompt)"
        """

        AppLogger.shared.log("🔐 [PrivilegedCommandRunner] Requesting admin privileges via osascript")

        let task = Process()
        task.executableURL = URL(fileURLWithPath: "/usr/bin/osascript")
        task.arguments = ["-e", osascriptCommand]

        let pipe = Pipe()
        task.standardOutput = pipe
        task.standardError = pipe

        do {
            try task.run()
            task.waitUntilExit()

            let data = pipe.fileHandleForReading.readDataToEndOfFile()
            let output = String(data: data, encoding: .utf8) ?? ""
            let success = task.terminationStatus == 0

            if success {
                AppLogger.shared.log("✅ [PrivilegedCommandRunner] osascript command succeeded")
            } else {
                AppLogger.shared.log("❌ [PrivilegedCommandRunner] osascript command failed (exit \(task.terminationStatus)): \(output)")
            }

            return Result(success: success, output: output, exitCode: task.terminationStatus)
        } catch {
            let errorMsg = "osascript execution failed: \(error.localizedDescription)"
            AppLogger.shared.log("❌ [PrivilegedCommandRunner] \(errorMsg)")
            return Result(success: false, output: errorMsg, exitCode: -1)
        }
    }

    /// Escape a command string for use in AppleScript.
    private static func escapeForAppleScript(_ command: String) -> String {
        var escaped = command
        escaped = escaped.replacingOccurrences(of: "\\", with: "\\\\")
        escaped = escaped.replacingOccurrences(of: "\"", with: "\\\"")
        return escaped
    }
}

// MARK: - Convenience Extensions

public extension PrivilegedCommandRunner {
    /// Execute a launchctl command with admin privileges.
    static func launchctl(_ subcommand: String, service: String, prompt: String) -> Result {
        let command = "/bin/launchctl \(subcommand) \(service)"
        return execute(command: command, prompt: prompt)
    }

    /// Copy a file to a system location with admin privileges.
    static func copyFile(from source: String, to destination: String, prompt: String) -> Result {
        let command = "/bin/cp '\(source)' '\(destination)'"
        return execute(command: command, prompt: prompt)
    }

    /// Remove a file from a system location with admin privileges.
    static func removeFile(at path: String, prompt: String) -> Result {
        let command = "/bin/rm -f '\(path)'"
        return execute(command: command, prompt: prompt)
    }

    /// Create a directory with admin privileges.
    static func createDirectory(at path: String, prompt: String) -> Result {
        let command = "/bin/mkdir -p '\(path)'"
        return execute(command: command, prompt: prompt)
    }

    /// Kill a process by PID with admin privileges.
    static func killProcess(pid: Int32, signal: Int32 = 15, prompt: String) -> Result {
        let command = "/bin/kill -\(signal) \(pid)"
        return execute(command: command, prompt: prompt)
    }
}
