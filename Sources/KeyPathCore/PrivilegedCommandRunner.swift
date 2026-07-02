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
            return Self.scriptPrelude + "\n" + trimmed.joined(separator: "\n")
        }

        /// Shell prelude for every batch: fail-fast, plus a `kp_timeout <secs> <cmd...>`
        /// watchdog for steps that can block indefinitely (`launchctl kickstart -k` on
        /// an unrunnable service hung a root script for 18+ minutes in #927).
        public static let scriptPrelude = """
        set -e
        kp_timeout() {
          local t="$1"; shift
          "$@" &
          local cmd_pid=$!
          ( sleep "$t"; /bin/kill -9 "$cmd_pid" 2>/dev/null ) >/dev/null 2>&1 &
          local watchdog_pid=$!
          local rc=0
          wait "$cmd_pid" || rc=$?
          /bin/kill "$watchdog_pid" 2>/dev/null || true
          return "$rc"
        }
        """
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
        // Tests should never trigger interactive admin prompts. Prefer skipping privileged work
        // in tests; opt-in real privileged behavior uses `KEYPATH_USE_SUDO=1`.
        if TestEnvironment.shouldSkipAdminOperations {
            AppLogger.shared.log("🧪 [PrivilegedCommandRunner] Skipping privileged command in test mode")
            return Result(success: true, output: "Skipped in test mode", exitCode: 0)
        }

        if TestEnvironment.useSudoForPrivilegedOps {
            return executeWithSudo(command: command)
        } else {
            return executeWithOsascript(command: command, prompt: prompt)
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

    /// Direct entry points for callers that must force one mechanism
    /// (e.g. PrivilegedExecutor delegation). Same bounded execution as
    /// `execute(command:prompt:)`.
    public static func executeSudoDirect(command: String) -> Result {
        executeWithSudo(command: command)
    }

    public static func executeOsascriptDirect(command: String, prompt: String) -> Result {
        executeWithOsascript(command: command, prompt: prompt)
    }

    // MARK: - Private Implementation

    /// Hard ceiling on any privileged execution. The osascript path includes the
    /// admin password dialog, so this must leave the user time to type — but a
    /// hung script must never outlive it (#927: a root script ran 18+ minutes).
    static let osascriptTimeout: TimeInterval = 300
    static let sudoTimeout: TimeInterval = 120

    /// Exit code reported when the privileged process is killed on timeout.
    public static let timedOutExitCode: Int32 = 124

    /// Execute a command using sudo -n (non-interactive).
    /// Requires sudoers NOPASSWD configuration.
    private static func executeWithSudo(command: String) -> Result {
        AppLogger.shared.log("🧪 [PrivilegedCommandRunner] Using sudo for privileged operation (KEYPATH_USE_SUDO=1)")

        let task = Process()
        task.executableURL = URL(fileURLWithPath: "/usr/bin/sudo")
        // Use -n for non-interactive (fails if password required)
        task.arguments = ["-n", "/bin/bash", "-c", command]

        let run = runBounded(task, timeout: Self.sudoTimeout, label: "sudo")
        if run.success {
            AppLogger.shared.log("✅ [PrivilegedCommandRunner] sudo command succeeded")
        } else {
            AppLogger.shared.log("❌ [PrivilegedCommandRunner] sudo command failed (exit \(run.exitCode)): \(run.output)")
        }
        return run
    }

    /// Execute a command using osascript with admin privileges dialog.
    private static func executeWithOsascript(command: String, prompt: String) -> Result {
        let scriptURL: URL
        do {
            scriptURL = try writeTemporaryShellScript(command: command)
        } catch {
            let errorMsg = "failed to prepare privileged script: \(error.localizedDescription)"
            AppLogger.shared.log("❌ [PrivilegedCommandRunner] \(errorMsg)")
            return Result(success: false, output: errorMsg, exitCode: -1)
        }

        defer {
            try? FileManager.default.removeItem(at: scriptURL)
        }

        let escapedCommand = escapeForAppleScript("/bin/bash \(shellSingleQuoted(scriptURL.path))")
        let escapedPrompt = prompt.replacingOccurrences(of: "\"", with: "\\\"")
        let osascriptCommand = """
        do shell script "\(escapedCommand)" with administrator privileges with prompt "\(escapedPrompt)"
        """

        AppLogger.shared.log("🔐 [PRIVILEGED-TRIGGER] Requesting admin privileges via osascript")
        AppLogger.shared.log("🔐 [PRIVILEGED-TRIGGER] Command: \(command.prefix(100))...")
        AppLogger.shared.log("🔐 [PRIVILEGED-TRIGGER] Prompt: \(prompt)")
        AppLogger.shared.log("🔐 [PRIVILEGED-TRIGGER] Script path: \(scriptURL.path)")
        // Log stack trace to identify caller
        let callStack = Thread.callStackSymbols.prefix(10).joined(separator: "\n")
        AppLogger.shared.log("🔐 [PRIVILEGED-TRIGGER] Call stack:\n\(callStack)")

        let task = Process()
        task.executableURL = URL(fileURLWithPath: "/usr/bin/osascript")
        task.arguments = ["-e", osascriptCommand]

        let run = runBounded(task, timeout: Self.osascriptTimeout, label: "osascript")
        if run.success {
            AppLogger.shared.log("✅ [PrivilegedCommandRunner] osascript command succeeded")
        } else {
            AppLogger.shared.log("❌ [PrivilegedCommandRunner] osascript command failed (exit \(run.exitCode)): \(run.output)")
        }
        return run
    }

    /// Run a prepared Process with a hard deadline, draining output concurrently
    /// so a chatty child can't deadlock on a full pipe buffer.
    private static func runBounded(_ task: Process, timeout: TimeInterval, label: String) -> Result {
        let pipe = Pipe()
        task.standardOutput = pipe
        task.standardError = pipe

        let buffer = PrivilegedOutputBuffer()
        pipe.fileHandleForReading.readabilityHandler = { handle in
            let chunk = handle.availableData
            if chunk.isEmpty {
                handle.readabilityHandler = nil
            } else {
                buffer.append(chunk)
            }
        }

        do {
            try task.run()
        } catch {
            pipe.fileHandleForReading.readabilityHandler = nil
            let errorMsg = "\(label) execution failed: \(error.localizedDescription)"
            AppLogger.shared.log("❌ [PrivilegedCommandRunner] \(errorMsg)")
            return Result(success: false, output: errorMsg, exitCode: -1)
        }

        let deadline = Date().addingTimeInterval(timeout)
        while task.isRunning, Date() < deadline {
            usleep(100_000)
        }

        if task.isRunning {
            AppLogger.shared.log(
                "⏱️ [PrivilegedCommandRunner] \(label) exceeded \(Int(timeout))s — killing. A privileged step is stuck; see #927."
            )
            task.terminate()
            usleep(500_000)
            if task.isRunning {
                kill(task.processIdentifier, SIGKILL)
            }
            task.waitUntilExit()
            pipe.fileHandleForReading.readabilityHandler = nil
            return Result(
                success: false,
                output: "timed out after \(Int(timeout))s\n\(buffer.text)",
                exitCode: Self.timedOutExitCode
            )
        }

        task.waitUntilExit()
        // Give the reader a beat to drain the tail, then detach.
        usleep(50000)
        pipe.fileHandleForReading.readabilityHandler = nil
        let output = buffer.text
        return Result(
            success: task.terminationStatus == 0,
            output: output,
            exitCode: task.terminationStatus
        )
    }

    /// Escape a command string for use in AppleScript.
    private static func escapeForAppleScript(_ command: String) -> String {
        var escaped = command
        escaped = escaped.replacingOccurrences(of: "\\", with: "\\\\")
        escaped = escaped.replacingOccurrences(of: "\"", with: "\\\"")
        return escaped
    }

    private static func writeTemporaryShellScript(command: String) throws -> URL {
        let url = FileManager.default.temporaryDirectory
            .appendingPathComponent("keypath-privileged-\(UUID().uuidString).sh")
        let script = """
        #!/bin/bash
        \(command)
        """
        try script.write(to: url, atomically: true, encoding: .utf8)
        try FileManager.default.setAttributes([.posixPermissions: 0o700], ofItemAtPath: url.path)
        return url
    }

    private static func shellSingleQuoted(_ value: String) -> String {
        "'\(value.replacingOccurrences(of: "'", with: "'\"'\"'"))'"
    }
}

/// Thread-safe accumulator for subprocess output read via readabilityHandler.
private final class PrivilegedOutputBuffer: @unchecked Sendable {
    private let lock = NSLock()
    private var data = Data()

    func append(_ chunk: Data) {
        lock.lock()
        data.append(chunk)
        lock.unlock()
    }

    var text: String {
        lock.lock()
        defer { lock.unlock() }
        return String(data: data, encoding: .utf8) ?? ""
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
