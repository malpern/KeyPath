import Foundation

// MARK: - Protocol

/// Protocol for subprocess execution (enables testability)
public protocol SubprocessRunning: Sendable {
    func run(
        _ executable: String,
        args: [String],
        timeout: TimeInterval?
    ) async throws -> ProcessResult

    func pgrep(_ pattern: String) async -> [pid_t]
    func launchctl(_ subcommand: String, _ args: [String]) async throws -> ProcessResult
}

// MARK: - Result Types

/// Result of a subprocess execution
public struct ProcessResult: Sendable {
    public let exitCode: Int32
    public let stdout: String
    public let stderr: String
    public let duration: TimeInterval

    public init(exitCode: Int32, stdout: String, stderr: String, duration: TimeInterval) {
        self.exitCode = exitCode
        self.stdout = stdout
        self.stderr = stderr
        self.duration = duration
    }
}

// MARK: - SubprocessRunner Actor

/// Actor-based subprocess runner that prevents MainActor blocking
///
/// All subprocess execution is isolated to this actor, ensuring that Process().waitUntilExit()
/// never blocks the MainActor. Uses async/await with termination handlers instead of blocking waits.
public actor SubprocessRunner: SubprocessRunning {
    public static let shared = SubprocessRunner()

    private init() {}

    /// Run a subprocess with optional timeout
    ///
    /// - Parameters:
    ///   - executable: Path to the executable
    ///   - args: Command-line arguments
    ///   - timeout: Optional timeout in seconds (default: 30s)
    /// - Returns: ProcessResult with exit code, stdout, stderr, and duration
    /// - Throws: SubprocessError on failure or timeout
    public func run(
        _ executable: String,
        args: [String],
        timeout: TimeInterval? = 30
    ) async throws -> ProcessResult {
        let startTime = Date()
        let timeoutInterval = timeout ?? 30.0

        AppLogger.shared.log("⚡ [SubprocessRunner] Executing: \(executable) \(args.joined(separator: " "))")

        let task = Process()
        task.executableURL = URL(fileURLWithPath: executable)
        task.arguments = args

        let stdoutPipe = Pipe()
        let stderrPipe = Pipe()
        task.standardOutput = stdoutPipe
        task.standardError = stderrPipe

        let runContext = RunContext()

        return try await withTaskCancellationHandler(operation: {
            try await withCheckedThrowingContinuation { continuation in
                runContext.setContinuation(continuation)

                // Set up termination handler (must be set before launching)
                task.terminationHandler = { process in
                    runContext.timeoutTask?.cancel()

                    let duration = Date().timeIntervalSince(startTime)
                    let exitCode = process.terminationStatus
                    let stdoutData = stdoutPipe.fileHandleForReading.readDataToEndOfFile()
                    let stderrData = stderrPipe.fileHandleForReading.readDataToEndOfFile()
                    let stdout = String(data: stdoutData, encoding: .utf8) ?? ""
                    let stderr = String(data: stderrData, encoding: .utf8) ?? ""

                    let result = ProcessResult(
                        exitCode: exitCode,
                        stdout: stdout,
                        stderr: stderr,
                        duration: duration
                    )

                    // Log completion
                    if duration > 5.0 {
                        AppLogger.shared.warn(
                            "⚠️ [SubprocessRunner] \(executable) took \(String(format: "%.2f", duration))s (>5s threshold)"
                        )
                    } else {
                        AppLogger.shared.log(
                            "✅ [SubprocessRunner] \(executable) completed in \(String(format: "%.2f", duration))s (exit: \(exitCode))"
                        )
                    }

                    runContext.resume(with: .success(result))
                }

                // Set up timeout task
                runContext.timeoutTask = Task {
                    do {
                        try await Task.sleep(nanoseconds: UInt64(timeoutInterval * 1_000_000_000))
                    } catch {
                        // Task cancelled (process finished or parent cancelled)
                        return
                    }

                    task.terminate()
                    if runContext.resume(
                        with: .failure(SubprocessError.timeout(executable: executable, timeout: timeoutInterval))
                    ) {
                        AppLogger.shared.warn(
                            "⏱️ [SubprocessRunner] \(executable) timed out after \(String(format: "%.2f", timeoutInterval))s - terminated"
                        )
                    }
                }

                // Launch process
                do {
                    try task.run()
                } catch {
                    runContext.timeoutTask?.cancel()
                    AppLogger.shared.error("❌ [SubprocessRunner] Failed to launch \(executable): \(error)")
                    runContext.resume(
                        with: .failure(SubprocessError.launchFailed(executable: executable, error: error))
                    )
                }
            }
        }, onCancel: {
            task.terminate()
            runContext.timeoutTask?.cancel()
            runContext.resume(with: .failure(CancellationError()))
        })
    }

    /// Run pgrep to find processes matching a pattern
    ///
    /// - Parameter pattern: Process pattern to search for
    /// - Returns: Array of process IDs
    public func pgrep(_ pattern: String) async -> [pid_t] {
        do {
            let result = try await run("/usr/bin/pgrep", args: ["-f", pattern], timeout: 5)
            // pgrep returns exit code 1 when no processes found (not an error)
            if result.exitCode == 1 {
                return []
            }
            if result.exitCode != 0 {
                AppLogger.shared.warn("⚠️ [SubprocessRunner] pgrep exited with code \(result.exitCode)")
                return []
            }
            let pids = result.stdout
                .trimmingCharacters(in: .whitespacesAndNewlines)
                .components(separatedBy: .newlines)
                .filter { !$0.isEmpty }
                .compactMap { Int32($0.trimmingCharacters(in: .whitespaces)) }
            return pids
        } catch {
            AppLogger.shared.warn("⚠️ [SubprocessRunner] pgrep failed for pattern '\(pattern)': \(error)")
            return []
        }
    }

    /// Run launchctl command
    ///
    /// - Parameters:
    ///   - subcommand: launchctl subcommand (e.g., "load", "unload", "list")
    ///   - args: Additional arguments
    /// - Returns: ProcessResult
    /// - Throws: SubprocessError on failure
    public func launchctl(_ subcommand: String, _ args: [String]) async throws -> ProcessResult {
        var allArgs = [subcommand]
        allArgs.append(contentsOf: args)
        return try await run("/bin/launchctl", args: allArgs, timeout: 10)
    }
}

// MARK: - Run Context

private final class RunContext: @unchecked Sendable {
    private let resumeQueue = DispatchQueue(label: "com.keypath.subprocess.resume")
    private var hasResumed = false
    private var continuation: CheckedContinuation<ProcessResult, Error>?

    var timeoutTask: Task<Void, Never>?

    func setContinuation(_ continuation: CheckedContinuation<ProcessResult, Error>) {
        resumeQueue.sync {
            self.continuation = continuation
        }
    }

    @discardableResult
    func resume(with result: Result<ProcessResult, Error>) -> Bool {
        resumeQueue.sync {
            guard !hasResumed else { return false }
            hasResumed = true
            continuation?.resume(with: result)
            continuation = nil
            return true
        }
    }
}

// MARK: - Errors

public enum SubprocessError: Error, Sendable {
    case timeout(executable: String, timeout: TimeInterval)
    case launchFailed(executable: String, error: Error)
    case nonZeroExit(exitCode: Int32)

    var localizedDescription: String {
        switch self {
        case let .timeout(executable, timeout):
            "Subprocess '\(executable)' timed out after \(timeout)s"
        case let .launchFailed(executable, error):
            "Failed to launch '\(executable)': \(error.localizedDescription)"
        case let .nonZeroExit(exitCode):
            "Process exited with non-zero code: \(exitCode)"
        }
    }
}
