import Darwin
import Foundation

/// One KeyPath session worker found in this user's process table.
struct SessionWorkerProcess: Equatable, Sendable {
    enum Mode: Equatable, Sendable {
        case runtime
        case capabilities
    }

    let pid: pid_t
    let mode: Mode
    let ownerPID: pid_t?

    /// `arguments[0]` is the executable path. Matches any KeyPath bundle,
    /// including one already moved to the Trash, but never the app itself.
    static func parse(pid: pid_t, arguments: [String]) -> SessionWorkerProcess? {
        guard let executable = arguments.first, executable.hasSuffix(".app/Contents/MacOS/KeyPath") else { return nil }
        let mode: Mode
        if arguments.contains("--session-runtime") {
            mode = .runtime
        } else if arguments.contains("--session-capabilities") {
            mode = .capabilities
        } else {
            return nil
        }
        let owner = arguments.firstIndex(of: "--session-owner")
            .flatMap { arguments.index(after: $0) < arguments.endIndex ? arguments[arguments.index(after: $0)] : nil }
            .flatMap(pid_t.init)
        return SessionWorkerProcess(pid: pid, mode: mode, ownerPID: owner)
    }
}

/// Stops every KeyPath session worker this user runs, not only the one the
/// live app tracks: orphans of an app that exited, and probes it abandoned.
/// Uninstall uses it so success means none remain (see AGENTS.md postconditions).
struct SessionWorkerSweep: Sendable {
    struct Outcome: Equatable, Sendable {
        let found: [SessionWorkerProcess]
        let remaining: [SessionWorkerProcess]
        var succeeded: Bool { remaining.isEmpty }
    }

    var list: @Sendable () -> [SessionWorkerProcess]
    var signal: @Sendable (pid_t, Int32) -> Void
    var sleep: @Sendable (Duration) async -> Void

    static let live = SessionWorkerSweep(
        list: { currentUserSessionWorkers() },
        signal: { pid, number in _ = kill(pid, number) },
        sleep: { try? await Task.sleep(for: $0) }
    )

    /// A runtime worker gets SIGTERM only: its shutdown releases held keys and
    /// restores Caps mappings, and killing it would strand them. A capability
    /// probe owns nothing, so one still alive after `probeGrace` is killed.
    func stopAll(probeGrace: Duration = .seconds(2), runtimeGrace: Duration = .seconds(10),
                 poll: Duration = .milliseconds(100)) async -> Outcome
    {
        let found = list()
        guard !found.isEmpty else { return Outcome(found: [], remaining: []) }
        for worker in found {
            signal(worker.pid, SIGTERM)
        }
        var waited = Duration.zero
        var killedProbes = false
        var remaining = found
        while !remaining.isEmpty, waited < runtimeGrace {
            await sleep(poll)
            waited += poll
            remaining = list()
            if !killedProbes, waited >= probeGrace {
                killedProbes = true
                for worker in remaining where worker.mode == .capabilities {
                    signal(worker.pid, SIGKILL)
                }
            }
        }
        return Outcome(found: found, remaining: remaining)
    }

    /// Reads the kernel process table directly: no pgrep, and only this UID.
    static func currentUserSessionWorkers() -> [SessionWorkerProcess] {
        var mib: [Int32] = [CTL_KERN, KERN_PROC, KERN_PROC_UID, Int32(bitPattern: getuid())]
        var size = 0
        guard sysctl(&mib, 4, nil, &size, nil, 0) == 0, size > 0 else { return [] }
        // Headroom for processes started between the two calls.
        size += 32 * MemoryLayout<kinfo_proc>.stride
        var processes = [kinfo_proc](repeating: kinfo_proc(), count: size / MemoryLayout<kinfo_proc>.stride)
        guard sysctl(&mib, 4, &processes, &size, nil, 0) == 0 else { return [] }
        let count = size / MemoryLayout<kinfo_proc>.stride
        let me = getpid()
        return processes.prefix(count).compactMap { process in
            let pid = process.kp_proc.p_pid
            guard pid > 0, pid != me, let arguments = arguments(of: pid) else { return nil }
            return SessionWorkerProcess.parse(pid: pid, arguments: arguments)
        }
    }

    /// KERN_PROCARGS2 is argc, the executable path, padding, then argv.
    /// Returns the executable path followed by argv[1...].
    static func arguments(of pid: pid_t) -> [String]? {
        var argumentMax: Int32 = 0
        var argumentMaxSize = MemoryLayout<Int32>.size
        var maxMib: [Int32] = [CTL_KERN, KERN_ARGMAX]
        guard sysctl(&maxMib, 2, &argumentMax, &argumentMaxSize, nil, 0) == 0, argumentMax > 0 else { return nil }
        var buffer = [UInt8](repeating: 0, count: Int(argumentMax))
        var size = buffer.count
        var mib: [Int32] = [CTL_KERN, KERN_PROCARGS2, pid]
        guard sysctl(&mib, 3, &buffer, &size, nil, 0) == 0 else { return nil }
        return parseProcArgs(Array(buffer.prefix(size)))
    }

    static func parseProcArgs(_ bytes: [UInt8]) -> [String]? {
        let intSize = MemoryLayout<Int32>.size
        guard bytes.count > intSize else { return nil }
        let argc = bytes.prefix(intSize).withUnsafeBytes { Int($0.loadUnaligned(as: Int32.self)) }
        guard argc > 0 else { return nil }
        var index = intSize
        func nextString() -> String? {
            guard index < bytes.count, let end = bytes[index...].firstIndex(of: 0) else { return nil }
            let value = String(decoding: bytes[index ..< end], as: UTF8.self)
            index = end + 1
            return value
        }
        guard let executable = nextString() else { return nil }
        while index < bytes.count, bytes[index] == 0 {
            index += 1
        }
        var argv: [String] = []
        for _ in 0 ..< argc {
            guard let argument = nextString() else { break }
            argv.append(argument)
        }
        return [executable] + argv.dropFirst()
    }
}
