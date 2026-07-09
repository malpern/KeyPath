import Darwin
import Foundation

public struct SystemProbeClient: Sendable {
    private let processIDsHandler: @Sendable (String) async -> [pid_t]
    private let processMatchesHandler: @Sendable (String) async -> [SystemProcessMatch]
    private let launchctlPrintHandler: @Sendable (String) async -> LaunchctlPrintEvidence
    private let processIDsSynchronouslyHandler: @Sendable (String) -> [pid_t]
    private let isProcessAliveHandler: @Sendable (pid_t) -> Bool
    private let probeTCPPortHandler: @Sendable (Int, Int) -> Bool

    public init(
        processIDs: @escaping @Sendable (String) async -> [pid_t],
        processMatches: @escaping @Sendable (String) async -> [SystemProcessMatch],
        launchctlPrint: @escaping @Sendable (String) async -> LaunchctlPrintEvidence,
        processIDsSynchronously: @escaping @Sendable (String) -> [pid_t],
        isProcessAlive: @escaping @Sendable (pid_t) -> Bool,
        probeTCPPort: @escaping @Sendable (Int, Int) -> Bool
    ) {
        processIDsHandler = processIDs
        processMatchesHandler = processMatches
        launchctlPrintHandler = launchctlPrint
        processIDsSynchronouslyHandler = processIDsSynchronously
        isProcessAliveHandler = isProcessAlive
        probeTCPPortHandler = probeTCPPort
    }

    public func processIDs(matching pattern: String) async -> [pid_t] {
        await processIDsHandler(pattern)
    }

    public func processMatches(matching pattern: String) async -> [SystemProcessMatch] {
        await processMatchesHandler(pattern)
    }

    public func launchctlPrint(target: String) async -> LaunchctlPrintEvidence {
        await launchctlPrintHandler(target)
    }

    public func processIDsSynchronously(matching pattern: String) -> [pid_t] {
        processIDsSynchronouslyHandler(pattern)
    }

    public func isProcessAlive(pid: pid_t) -> Bool {
        isProcessAliveHandler(pid)
    }

    public func probeTCPPort(port: Int, timeoutMs: Int) -> Bool {
        probeTCPPortHandler(port, timeoutMs)
    }
}

public extension SystemProbeClient {
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
        launchctlPrint: { target in
            let result = await runProcess("/bin/launchctl", args: ["print", target], timeout: 10)
            return LaunchctlPrintEvidence(
                target: target,
                exitCode: result.exitCode,
                stdout: result.stdout,
                stderr: result.stderr
            )
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
        },
        probeTCPPort: { port, timeoutMs in
            probeLocalhostTCPPort(port: port, timeoutMs: timeoutMs)
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

public struct LaunchctlPrintEvidence: Equatable, Sendable {
    public let target: String
    public let exitCode: Int32?
    public let stdout: String
    public let stderr: String

    public init(target: String, exitCode: Int32?, stdout: String, stderr: String) {
        self.target = target
        self.exitCode = exitCode
        self.stdout = stdout
        self.stderr = stderr
    }

    public var hasRunningProcessEvidence: Bool {
        stdout.range(of: #"pid\s*=\s*\d+"#, options: .regularExpression) != nil
            || stdout.contains("\"PID\"")
            || stdout.contains("state = running")
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

private func probeLocalhostTCPPort(port: Int, timeoutMs: Int) -> Bool {
    guard (1 ... 65535).contains(port), timeoutMs >= 0 else { return false }

    let sock = socket(AF_INET, SOCK_STREAM, 0)
    guard sock >= 0 else { return false }
    defer { close(sock) }

    let flags = fcntl(sock, F_GETFL, 0)
    guard flags >= 0 else { return false }
    _ = fcntl(sock, F_SETFL, flags | O_NONBLOCK)

    var addr = sockaddr_in()
    addr.sin_family = sa_family_t(AF_INET)
    addr.sin_port = in_port_t(UInt16(port).bigEndian)
    addr.sin_addr = in_addr(s_addr: inet_addr("127.0.0.1"))

    var mutableAddr = addr
    let connectResult = withUnsafePointer(to: &mutableAddr) {
        $0.withMemoryRebound(to: sockaddr.self, capacity: 1) {
            connect(sock, $0, socklen_t(MemoryLayout<sockaddr_in>.size))
        }
    }

    if connectResult == 0 { return true }
    guard errno == EINPROGRESS else { return false }

    var pollFd = pollfd(fd: sock, events: Int16(POLLOUT), revents: 0)
    let pollResult = poll(&pollFd, 1, Int32(timeoutMs))
    guard pollResult > 0, (pollFd.revents & Int16(POLLOUT)) != 0 else { return false }

    var socketError: Int32 = 0
    var socketErrorLength = socklen_t(MemoryLayout<Int32>.size)
    getsockopt(sock, SOL_SOCKET, SO_ERROR, &socketError, &socketErrorLength)
    return socketError == 0
}
