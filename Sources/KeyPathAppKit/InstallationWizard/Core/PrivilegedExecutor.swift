import Foundation
import KeyPathCore

/// Handles privileged command execution via sudo or osascript.
/// Provides a unified interface for operations requiring admin rights.
///
/// Two execution modes:
/// 1. `sudo -n` (non-interactive) - used when KEYPATH_USE_SUDO=1 is set (dev/test)
/// 2. `osascript` with admin dialog - used in production for user-facing prompts
///
/// **Production behavior**: Shows osascript admin dialog with password prompt
/// **Test behavior** (KEYPATH_USE_SUDO=1): Uses sudo -n (NOPASSWD rules required)
///
/// - Note: For test mode to work, run `sudo ./Scripts/dev-setup-sudoers.sh` first.
/// - Warning: Remove sudoers config before public release: `sudo ./Scripts/dev-remove-sudoers.sh`
///
/// ## Thread Safety
/// - `executeWithOsascript` may show a modal dialog that blocks the thread
/// - For UI contexts, consider calling from a background thread or using async wrappers
final class PrivilegedExecutor: @unchecked Sendable {
    // MARK: - Singleton

    /// Shared instance for privileged command execution.
    /// Thread-safe: The class has no mutable state.
    static let shared = PrivilegedExecutor()

    private init() {}

    // MARK: - Main Entry Point

    /// Execute command with appropriate privilege escalation (sudo or osascript).
    /// Automatically chooses based on `TestEnvironment.useSudoForPrivilegedOps`.
    ///
    /// - Parameters:
    ///   - command: The shell command to execute
    ///   - prompt: The prompt to show in the admin dialog (osascript only, ignored in sudo mode)
    /// - Returns: Tuple of (success, output)
    ///
    /// - Note: In osascript mode, this may show a modal dialog that blocks the calling thread.
    func executeWithPrivileges(command: String, prompt: String) -> (success: Bool, output: String) {
        // Check if we should skip admin operations entirely (test mode)
        if TestEnvironment.shouldSkipAdminOperations {
            AppLogger.shared.log(
                "🧪 [PrivilegedExecutor] Skipping admin operation in test mode")
            return (true, "Skipped in test mode")
        }

        // Check if we should use sudo instead of osascript (for testing)
        if TestEnvironment.useSudoForPrivilegedOps {
            return executeWithSudo(command: command)
        } else {
            return executeWithOsascript(command: command, prompt: prompt)
        }
    }

    // MARK: - Sudo Execution

    /// Execute a command using sudo -n (non-interactive, requires sudoers setup).
    ///
    /// Requires: `sudo ./Scripts/dev-setup-sudoers.sh` to configure NOPASSWD rules.
    ///
    /// - Parameter command: The shell command to execute
    /// - Returns: Tuple of (success, output)
    func executeWithSudo(command: String) -> (success: Bool, output: String) {
        AppLogger.shared.log(
            "🧪 [PrivilegedExecutor] Using sudo for privileged operation (KEYPATH_USE_SUDO=1)")

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

            if task.terminationStatus == 0 {
                AppLogger.shared.log("✅ [PrivilegedExecutor] sudo command succeeded")
                return (true, output)
            } else {
                AppLogger.shared.log(
                    "❌ [PrivilegedExecutor] sudo command failed (status \(task.terminationStatus)): \(output)"
                )
                return (false, output)
            }
        } catch {
            AppLogger.shared.log("❌ [PrivilegedExecutor] Failed to execute sudo: \(error)")
            return (false, error.localizedDescription)
        }
    }

    // MARK: - OSAScript Execution

    /// Execute a command using osascript with admin privileges dialog.
    ///
    /// - Parameters:
    ///   - command: The shell command to execute
    ///   - prompt: The prompt to show in the admin dialog
    /// - Returns: Tuple of (success, output)
    ///
    /// - Warning: This method shows a modal admin dialog that may block the calling thread.
    ///   In production, this is called from main thread to ensure the dialog appears.
    func executeWithOsascript(command: String, prompt: String) -> (success: Bool, output: String) {
        let escapedCommand = escapeForAppleScript(command)
        let osascriptCommand = """
            do shell script "\(escapedCommand)" with administrator privileges with prompt "\(prompt)"
            """

        AppLogger.shared.log(
            "🔐 [PrivilegedExecutor] Requesting admin privileges via osascript")

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

            if task.terminationStatus == 0 {
                AppLogger.shared.log("✅ [PrivilegedExecutor] osascript command succeeded")
            } else {
                AppLogger.shared.log(
                    "❌ [PrivilegedExecutor] osascript command failed (exit \(task.terminationStatus)): \(output)"
                )
            }

            return (task.terminationStatus == 0, output)
        } catch {
            let errorMsg = "osascript execution failed: \(error.localizedDescription)"
            AppLogger.shared.log("❌ [PrivilegedExecutor] \(errorMsg)")
            return (false, error.localizedDescription)
        }
    }

    // MARK: - Admin Dialog Testing

    /// Test if admin dialog can be shown (useful for pre-flight checks).
    ///
    /// This runs a simple echo command to verify the admin dialog mechanism works.
    /// Useful for diagnosing osascript issues before attempting actual installations.
    ///
    /// - Returns: `true` if admin dialog test succeeded, `false` otherwise
    ///
    /// - Warning: This is a blocking operation that should not be called during startup
    ///   as it may freeze the UI waiting for user input.
    func testAdminDialog() -> Bool {
        AppLogger.shared.log("🔧 [PrivilegedExecutor] Testing admin dialog capability...")
        AppLogger.shared.log(
            "🔧 [PrivilegedExecutor] Current thread: \(Thread.isMainThread ? "main" : "background")"
        )

        // Skip test if called during startup to prevent freezes
        if ProcessInfo.processInfo.environment["KEYPATH_SKIP_ADMIN_TEST"] == "1" {
            AppLogger.shared.log(
                "⚠️ [PrivilegedExecutor] Skipping admin dialog test during startup")
            return true  // Assume it works to avoid blocking
        }

        let testCommand = "echo 'Admin dialog test successful'"
        let result = executeWithPrivileges(
            command: testCommand,
            prompt:
                "KeyPath Admin Dialog Test - This is a test of the admin password dialog. Please enter your password to confirm it's working."
        )

        AppLogger.shared.log(
            "🔧 [PrivilegedExecutor] Admin dialog test result: \(result.success)")
        return result.success
    }

    // MARK: - String Escaping

    /// Escape a command string for safe use in AppleScript.
    ///
    /// AppleScript requires special escaping for backslashes and quotes.
    ///
    /// - Parameter command: The raw command string
    /// - Returns: The escaped string safe for embedding in AppleScript
    func escapeForAppleScript(_ command: String) -> String {
        var escaped = command.replacingOccurrences(of: "\\", with: "\\\\")
        escaped = escaped.replacingOccurrences(of: "\"", with: "\\\"")
        return escaped
    }
}

// MARK: - Convenience Extensions

extension PrivilegedExecutor {
    /// Execute multiple commands in sequence with administrator privileges.
    /// All commands are joined with && and executed in a single privileged session.
    ///
    /// - Parameters:
    ///   - commands: Array of shell commands to execute
    ///   - prompt: The prompt to show in the admin dialog
    /// - Returns: Tuple of (success, output)
    func executeWithPrivileges(commands: [String], prompt: String) -> (success: Bool, output: String)
    {
        let combinedCommand = commands.joined(separator: " && ")
        return executeWithPrivileges(command: combinedCommand, prompt: prompt)
    }

    /// Execute a launchctl command with admin privileges.
    ///
    /// - Parameters:
    ///   - subcommand: The launchctl subcommand (e.g., "bootstrap", "bootout")
    ///   - service: The service identifier or path
    ///   - prompt: The prompt to show in the admin dialog
    /// - Returns: Tuple of (success, output)
    func launchctl(_ subcommand: String, service: String, prompt: String) -> (
        success: Bool, output: String
    ) {
        let command = "/bin/launchctl \(subcommand) \(service)"
        return executeWithPrivileges(command: command, prompt: prompt)
    }

    /// Copy a file to a system location with admin privileges.
    ///
    /// - Parameters:
    ///   - source: Source file path
    ///   - destination: Destination file path
    ///   - prompt: The prompt to show in the admin dialog
    /// - Returns: Tuple of (success, output)
    func copyFile(from source: String, to destination: String, prompt: String) -> (
        success: Bool, output: String
    ) {
        let command = "/bin/cp '\(source)' '\(destination)'"
        return executeWithPrivileges(command: command, prompt: prompt)
    }

    /// Remove a file from a system location with admin privileges.
    ///
    /// - Parameters:
    ///   - path: Path to the file to remove
    ///   - prompt: The prompt to show in the admin dialog
    /// - Returns: Tuple of (success, output)
    func removeFile(at path: String, prompt: String) -> (success: Bool, output: String) {
        let command = "/bin/rm -f '\(path)'"
        return executeWithPrivileges(command: command, prompt: prompt)
    }

    /// Create a directory with admin privileges.
    ///
    /// - Parameters:
    ///   - path: Path to the directory to create
    ///   - prompt: The prompt to show in the admin dialog
    /// - Returns: Tuple of (success, output)
    func createDirectory(at path: String, prompt: String) -> (success: Bool, output: String) {
        let command = "/bin/mkdir -p '\(path)'"
        return executeWithPrivileges(command: command, prompt: prompt)
    }

    /// Kill a process by PID with admin privileges.
    ///
    /// - Parameters:
    ///   - pid: Process ID to kill
    ///   - signal: Signal to send (default: 15 / SIGTERM)
    ///   - prompt: The prompt to show in the admin dialog
    /// - Returns: Tuple of (success, output)
    func killProcess(pid: Int32, signal: Int32 = 15, prompt: String) -> (
        success: Bool, output: String
    ) {
        let command = "/bin/kill -\(signal) \(pid)"
        return executeWithPrivileges(command: command, prompt: prompt)
    }
}
