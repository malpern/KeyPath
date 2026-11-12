import Foundation

/// Runs a shell command with administrator privileges through the macOS admin
/// password dialog (osascript). Its one caller is installing the `keypath-cli`
/// link in /usr/local/bin. Tests never run it: they get a skipped success.
public enum PrivilegedCommandRunner {
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
    ///   - prompt: The prompt to show in the admin dialog
    /// - Returns: Result containing success status and output
    public static func execute(command: String, prompt: String) -> Result {
        // Tests never trigger the interactive admin dialog.
        if TestEnvironment.shouldSkipAdminOperations {
            AppLogger.shared.log("🧪 [PrivilegedCommandRunner] Skipping privileged command in test mode")
            return Result(success: true, output: "Skipped in test mode", exitCode: 0)
        }

        return executeWithOsascript(command: command, prompt: prompt)
    }

    // MARK: - Private Implementation

    /// Hard ceiling on the osascript CLIENT process. The deadline includes the
    /// admin password dialog, so it is deliberately generous — a user who steps
    /// away mid-dialog must not get a spurious failure. The privileged script
    /// itself is bounded separately by its own self-watchdog
    /// (`scriptSelfTimeout`), because killing osascript cannot reach the root
    /// child (#927).
    static let osascriptTimeout: TimeInterval = 900

    /// Exit code reported when the privileged process is killed on timeout.
    public static let timedOutExitCode: Int32 = BoundedProcess.timedOutStatus

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

    /// Run a prepared Process with a hard deadline via the shared BoundedProcess
    /// runner (concurrent output draining, terminate-then-SIGKILL on expiry).
    private static func runBounded(_ task: Process, timeout: TimeInterval, label: String) -> Result {
        let outcome = BoundedProcess.run(task, timeout: timeout)
        if outcome.timedOut {
            AppLogger.shared.log(
                "⏱️ [PrivilegedCommandRunner] \(label) exceeded \(Int(timeout))s — killed. A privileged step is stuck; see #927."
            )
            return Result(
                success: false,
                output: "timed out after \(Int(timeout))s\n\(outcome.output)",
                exitCode: outcome.status
            )
        }
        return Result(
            success: outcome.status == 0,
            output: outcome.output,
            exitCode: outcome.status
        )
    }

    /// Escape a command string for use in AppleScript.
    /// Internal (not private) so tests cover the escaping actually executed.
    static func escapeForAppleScript(_ command: String) -> String {
        var escaped = command
        escaped = escaped.replacingOccurrences(of: "\\", with: "\\\\")
        escaped = escaped.replacingOccurrences(of: "\"", with: "\\\"")
        return escaped
    }

    /// Hard ceiling the privileged script applies to ITSELF. The script runs as
    /// root under the security trampoline, so the unprivileged app cannot signal
    /// it after a timeout — killing our osascript client merely orphans it
    /// (#927's 18-minute root script). A self-watchdog is the only reliable
    /// bound. The identity re-check via the unique script name prevents a
    /// recycled PID from being killed.
    static let scriptSelfTimeout: TimeInterval = 300

    private static func writeTemporaryShellScript(command: String) throws -> URL {
        let scriptName = "keypath-privileged-\(UUID().uuidString).sh"
        let url = FileManager.default.temporaryDirectory
            .appendingPathComponent(scriptName)
        let script = """
        #!/bin/bash
        KP_SELF=$$
        ( sleep \(Int(scriptSelfTimeout)); if ps -o command= -p "$KP_SELF" 2>/dev/null | grep -qF '\(scriptName)'; then /bin/kill -9 "$KP_SELF"; fi ) >/dev/null 2>&1 &
        KP_SELF_WATCHDOG=$!
        trap '/bin/kill "$KP_SELF_WATCHDOG" 2>/dev/null' EXIT
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
