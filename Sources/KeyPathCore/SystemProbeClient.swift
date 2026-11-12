import Darwin
import Foundation

public struct SystemProbeClient: Sendable {
    private let processIDsHandler: @Sendable (String) async -> [pid_t]
    private let processMatchesHandler: @Sendable (String) async -> [SystemProcessMatch]
    private let processIDsSynchronouslyHandler: @Sendable (String) -> [pid_t]
    private let isProcessAliveHandler: @Sendable (pid_t) -> Bool

    public init(
        processIDs: @escaping @Sendable (String) async -> [pid_t],
        processMatches: @escaping @Sendable (String) async -> [SystemProcessMatch],
        processIDsSynchronously: @escaping @Sendable (String) -> [pid_t],
        isProcessAlive: @escaping @Sendable (pid_t) -> Bool
    ) {
        processIDsHandler = processIDs
        processMatchesHandler = processMatches
        processIDsSynchronouslyHandler = processIDsSynchronously
        isProcessAliveHandler = isProcessAlive
    }

    public func processIDs(matching pattern: String) async -> [pid_t] {
        await processIDsHandler(pattern)
    }

    public func processMatches(matching pattern: String) async -> [SystemProcessMatch] {
        await processMatchesHandler(pattern)
    }

    public func processIDsSynchronously(matching pattern: String) -> [pid_t] {
        processIDsSynchronouslyHandler(pattern)
    }

    public func isProcessAlive(pid: pid_t) -> Bool {
        isProcessAliveHandler(pid)
    }
}

public extension SystemProbeClient {
    /// A successful zero-signal probe, unlike liveness, does not admit EPERM.
    /// Used by the bounded timeout experiment before delaying a live callback.
    static func canSignalProcess(pid: pid_t) -> Bool {
        pid > 0 && kill(pid, 0) == 0
    }

    static let live = SystemProbeClient(
        processIDs: { pattern in
            let result = await runProcess("/usr/bin/pgrep", args: ["-f", pattern], timeout: 5)
            guard result.exitCode == 0 else { return [] }
            return parseProcessIDs(result.stdout)
        },
        processMatches: { pattern in
            let result = await runProcess("/usr/bin/pgrep", args: ["-fl", pattern], timeout: 5)
            guard result.exitCode == 0 else { return [] }
            return parseProcessMatches(result.stdout)
        },
        processIDsSynchronously: { pattern in
            let result = runProcessSynchronously("/usr/bin/pgrep", args: ["-f", pattern], timeout: 5)
            guard result.exitCode == 0 else { return [] }
            return parseProcessIDs(result.stdout)
        },
        isProcessAlive: { pid in
            guard pid > 0 else { return false }
            if kill(pid, 0) == 0 { return true }
            return errno == EPERM
        }
    )
}

public struct SystemProcessMatch: Equatable, Sendable {
    public let pid: pid_t
    public let command: String

    public init(pid: pid_t, command: String) {
        self.pid = pid
        self.command = command
    }
}

private struct ProbeProcessResult: Sendable {
    let exitCode: Int32
    let stdout: String
    let stderr: String
}

private func parseProcessIDs(_ output: String) -> [pid_t] {
    output
        .trimmingCharacters(in: .whitespacesAndNewlines)
        .components(separatedBy: .newlines)
        .filter { !$0.isEmpty }
        .compactMap { Int32($0.trimmingCharacters(in: .whitespaces)) }
}

private func parseProcessMatches(_ output: String) -> [SystemProcessMatch] {
    output
        .components(separatedBy: .newlines)
        .compactMap { rawLine in
            let line = rawLine.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !line.isEmpty else { return nil }

            let parts = line.split(separator: " ", maxSplits: 1, omittingEmptySubsequences: true)
            guard parts.count == 2, let pid = pid_t(parts[0]) else { return nil }
            return SystemProcessMatch(pid: pid, command: String(parts[1]))
        }
}

private func runProcess(_ executable: String, args: [String], timeout: TimeInterval) async -> ProbeProcessResult {
    await Task.detached(priority: .utility) {
        runProcessSynchronously(executable, args: args, timeout: timeout)
    }.value
}

private func runProcessSynchronously(_ executable: String, args: [String], timeout: TimeInterval) -> ProbeProcessResult {
    let process = Process()
    process.executableURL = URL(fileURLWithPath: executable)
    process.arguments = args

    let stdoutPipe = Pipe()
    let stderrPipe = Pipe()
    process.standardOutput = stdoutPipe
    process.standardError = stderrPipe

    do {
        try process.run()
    } catch {
        return ProbeProcessResult(exitCode: 127, stdout: "", stderr: String(describing: error))
    }

    let deadline = Date().addingTimeInterval(timeout)
    while process.isRunning, Date() < deadline {
        usleep(50000)
    }

    if process.isRunning {
        process.terminate()
        usleep(200_000)
        if process.isRunning {
            kill(process.processIdentifier, SIGKILL)
        }
    }

    process.waitUntilExit()
    let stdout = String(data: stdoutPipe.fileHandleForReading.readDataToEndOfFile(), encoding: .utf8) ?? ""
    let stderr = String(data: stderrPipe.fileHandleForReading.readDataToEndOfFile(), encoding: .utf8) ?? ""
    return ProbeProcessResult(exitCode: process.terminationStatus, stdout: stdout, stderr: stderr)
}
