import Darwin
import Foundation

/// Central owner for system-state evidence used by installer and runtime decisions.
///
/// Phase 1 grows this into the full snapshot provider. The first slices centralize
/// process-liveness and TCP-readiness primitives so callers share one definition.
public actor SystemStateProvider {
    public static let shared = SystemStateProvider()

    private let subprocessRunner: any SubprocessRunning

    public init(subprocessRunner: any SubprocessRunning = SubprocessRunner.shared) {
        self.subprocessRunner = subprocessRunner
    }

    public nonisolated func isProcessAlive(pid: pid_t) -> Bool {
        Self.isProcessAlive(pid: pid)
    }

    public nonisolated func isTCPPortResponding(port: Int, timeoutMs: Int = 300) async -> Bool {
        await Task.detached(priority: .utility) {
            Self.probeTCPPort(port: port, timeoutMs: timeoutMs)
        }.value
    }

    public func processIDs(matching pattern: String) async -> [pid_t] {
        let trimmedPattern = pattern.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmedPattern.isEmpty else { return [] }
        return await subprocessRunner.pgrep(trimmedPattern)
    }

    public func processMatches(matching pattern: String) async -> [SystemProcessMatch] {
        let trimmedPattern = pattern.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmedPattern.isEmpty else { return [] }

        do {
            let result = try await subprocessRunner.run(
                "/usr/bin/pgrep",
                args: ["-fl", trimmedPattern],
                timeout: 5
            )
            guard result.exitCode == 0 else { return [] }
            return Self.parseProcessMatches(result.stdout)
        } catch {
            AppLogger.shared.warn("⚠️ [SystemStateProvider] pgrep -fl failed for pattern '\(trimmedPattern)': \(error)")
            return []
        }
    }

    public func launchctlPrint(target: String) async -> LaunchctlPrintEvidence {
        let trimmedTarget = target.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmedTarget.isEmpty else {
            return LaunchctlPrintEvidence(target: "", exitCode: nil, stdout: "", stderr: "")
        }

        do {
            let result = try await subprocessRunner.launchctl("print", [trimmedTarget])
            return LaunchctlPrintEvidence(
                target: trimmedTarget,
                exitCode: result.exitCode,
                stdout: result.stdout,
                stderr: result.stderr
            )
        } catch {
            AppLogger.shared.warn("⚠️ [SystemStateProvider] launchctl print failed for target '\(trimmedTarget)': \(error)")
            return LaunchctlPrintEvidence(
                target: trimmedTarget,
                exitCode: nil,
                stdout: "",
                stderr: String(describing: error)
            )
        }
    }

    public nonisolated static func processIDsSynchronously(matching pattern: String) -> [pid_t] {
        let trimmedPattern = pattern.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmedPattern.isEmpty else { return [] }

        let result = BoundedProcess.run(
            "/usr/bin/pgrep",
            ["-f", trimmedPattern],
            timeout: 5
        )
        guard result.status == 0 else { return [] }

        return result.output
            .trimmingCharacters(in: .whitespacesAndNewlines)
            .components(separatedBy: .newlines)
            .filter { !$0.isEmpty }
            .compactMap { Int32($0.trimmingCharacters(in: .whitespaces)) }
    }

    private nonisolated static func parseProcessMatches(_ output: String) -> [SystemProcessMatch] {
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

    public nonisolated static func isProcessAlive(pid: pid_t) -> Bool {
        guard pid > 0 else { return false }
        if kill(pid, 0) == 0 { return true }
        return errno == EPERM
    }

    public nonisolated static func probeTCPPort(port: Int, timeoutMs: Int = 300) -> Bool {
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

    public nonisolated static func isKanataReady(running: Bool, responding: Bool) -> Bool {
        running && responding
    }
}

public struct KanataLivenessEvidence: Equatable, Sendable {
    public let pid: pid_t?
    public let running: Bool
    public let responding: Bool

    public init(pid: pid_t?, running: Bool, responding: Bool) {
        self.pid = pid
        self.running = running
        self.responding = responding
    }

    public var ready: Bool {
        SystemStateProvider.isKanataReady(running: running, responding: responding)
    }
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
