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
    var executable = ""

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
        return SessionWorkerProcess(pid: pid, mode: mode, ownerPID: owner, executable: executable)
    }

    /// Uninstall stops workers of the bundle it removes, and orphans of any
    /// bundle; a separate KeyPath install whose app is alive keeps its worker.
    /// The owner counts as alive only if that PID is a KeyPath app running the
    /// worker's own executable: orphans outlive owners by hours, long enough
    /// for the PID to be reused by an unrelated process.
    func belongsToUninstall(of app: URL, appExecutable: (pid_t) -> String?) -> Bool {
        if executable.hasPrefix(app.standardizedFileURL.path + "/") { return true }
        guard let ownerPID, ownerPID > 0 else { return true }
        return appExecutable(ownerPID) != executable
    }
}

/// Stops every KeyPath session worker this user runs, not only the one the
/// live app tracks: orphans of an app that exited, and probes it abandoned.
/// Uninstall uses it so success means none remain (see AGENTS.md postconditions).
struct SessionWorkerSweep: Sendable {
    struct Outcome: Equatable, Sendable {
        let found: [SessionWorkerProcess]
        let remaining: [SessionWorkerProcess]
        /// False when the process table could not be read: absence unproven.
        var verified = true
        var succeeded: Bool {
            verified && remaining.isEmpty
        }

        var result: SessionWorkerSweepResult {
            guard verified else { return .unverified }
            return remaining.isEmpty ? .noneRunning : .stillRunning
        }
    }

    /// nil means the process table could not be read, never "no workers".
    var list: @Sendable () -> [SessionWorkerProcess]?
    var signal: @Sendable (pid_t, Int32) -> Void
    var sleep: @Sendable (Duration) async -> Void
    var uptime: @Sendable () -> TimeInterval = { ProcessInfo.processInfo.systemUptime }

    static func live(uninstalling app: URL) -> SessionWorkerSweep {
        SessionWorkerSweep(
            list: {
                guard let table = currentUserKeyPathProcesses() else { return nil }
                return table.workers.filter { $0.belongsToUninstall(of: app) { table.apps[$0] } }
            },
            signal: { pid, number in _ = kill(pid, number) },
            sleep: { try? await Task.sleep(for: $0) }
        )
    }

    /// A runtime worker gets SIGTERM only: its shutdown releases held keys and
    /// restores Caps mappings, and killing it would strand them. A capability
    /// probe owns nothing, so one still alive after `probeGrace` is killed.
    /// Workers that appear mid-sweep are signalled too. Graces are wall-clock.
    func stopAll(probeGrace: TimeInterval = 2, runtimeGrace: TimeInterval = 10,
                 poll: Duration = .milliseconds(100)) async -> Outcome
    {
        /// One unreadable listing may be a process exiting mid-read; two is unknown.
        func read() -> [SessionWorkerProcess]? {
            list() ?? list()
        }
        guard let found = read() else { return Outcome(found: [], remaining: [], verified: false) }
        guard !found.isEmpty else { return Outcome(found: [], remaining: []) }
        let started = uptime()
        var termed: Set<pid_t> = []
        var killed: Set<pid_t> = []
        var everFound = found
        var remaining = found
        while true {
            // A cancelled sleep returns at once; without this the loop would
            // re-read the process table as fast as it can for the whole grace.
            guard !Task.isCancelled else { return Outcome(found: everFound, remaining: remaining, verified: false) }
            let elapsed = uptime() - started
            for worker in remaining where !termed.contains(worker.pid) {
                termed.insert(worker.pid)
                signal(worker.pid, SIGTERM)
            }
            if elapsed >= probeGrace {
                for worker in remaining where worker.mode == .capabilities && !killed.contains(worker.pid) {
                    killed.insert(worker.pid)
                    signal(worker.pid, SIGKILL)
                }
            }
            guard !remaining.isEmpty, elapsed < runtimeGrace else { break }
            await sleep(poll)
            guard let listed = read() else { return Outcome(found: everFound, remaining: remaining, verified: false) }
            remaining = listed
            everFound += listed.filter { worker in !everFound.contains { $0.pid == worker.pid } }
        }
        return Outcome(found: everFound, remaining: remaining)
    }

    /// This UID's KeyPath processes: session workers, and the apps (any other
    /// KeyPath process) by PID with their executable path.
    struct ProcessTable: Equatable, Sendable {
        var workers: [SessionWorkerProcess] = []
        var apps: [pid_t: String] = [:]
    }

    static func currentUserSessionWorkers() -> [SessionWorkerProcess]? {
        currentUserKeyPathProcesses()?.workers
    }

    /// Reads the kernel process table directly: no pgrep, and only this UID.
    static func currentUserKeyPathProcesses() -> ProcessTable? {
        var mib: [Int32] = [CTL_KERN, KERN_PROC, KERN_PROC_UID, Int32(bitPattern: getuid())]
        var processes: [kinfo_proc] = []
        var size = 0
        // Processes started between sizing and reading make the read ENOMEM.
        for _ in 0 ..< 4 {
            guard sysctl(&mib, 4, nil, &size, nil, 0) == 0, size > 0 else { return nil }
            size += 32 * MemoryLayout<kinfo_proc>.stride
            processes = [kinfo_proc](repeating: kinfo_proc(), count: size / MemoryLayout<kinfo_proc>.stride)
            // Never claim more bytes than the array holds.
            size = processes.count * MemoryLayout<kinfo_proc>.stride
            if sysctl(&mib, 4, &processes, &size, nil, 0) == 0 { break }
            guard errno == ENOMEM else { return nil }
            processes = []
        }
        guard !processes.isEmpty else { return nil }
        let count = size / MemoryLayout<kinfo_proc>.stride
        let me = getpid()
        // One buffer for every process: kern.argmax is 1 MiB.
        guard let argumentMax = argumentMax() else { return nil }
        var buffer = [UInt8](repeating: 0, count: argumentMax)
        var table = ProcessTable()
        for process in processes.prefix(count) {
            let pid = process.kp_proc.p_pid
            // Only KeyPath processes pay for an argument read. A zombie has no
            // arguments and runs nothing.
            guard pid > 0, pid != me, Int32(process.kp_proc.p_stat) != SZOMB,
                  command(of: process) == "KeyPath" else { continue }
            guard let arguments = arguments(of: pid, buffer: &buffer) else {
                // Exited or became a zombie between the two reads: it runs
                // nothing. A live process whose arguments cannot be read is unknown.
                if isRunning(pid) { return nil }
                continue
            }
            if let worker = SessionWorkerProcess.parse(pid: pid, arguments: arguments) {
                table.workers.append(worker)
            } else if let executable = arguments.first {
                table.apps[pid] = executable
            }
        }
        return table
    }

    /// True while the PID exists and is not a zombie. Signalling a zombie
    /// succeeds, so kill(pid, 0) cannot tell.
    private static func isRunning(_ pid: pid_t) -> Bool {
        var mib: [Int32] = [CTL_KERN, KERN_PROC, KERN_PROC_PID, pid]
        var process = kinfo_proc()
        var size = MemoryLayout<kinfo_proc>.stride
        guard sysctl(&mib, 4, &process, &size, nil, 0) == 0, size > 0 else { return false }
        return Int32(process.kp_proc.p_stat) != SZOMB
    }

    private static func command(of process: kinfo_proc) -> String {
        withUnsafeBytes(of: process.kp_proc.p_comm) { raw in
            String(decoding: raw.prefix { $0 != 0 }, as: UTF8.self)
        }
    }

    static func argumentMax() -> Int? {
        var argumentMax: Int32 = 0
        var argumentMaxSize = MemoryLayout<Int32>.size
        var mib: [Int32] = [CTL_KERN, KERN_ARGMAX]
        guard sysctl(&mib, 2, &argumentMax, &argumentMaxSize, nil, 0) == 0, argumentMax > 0 else { return nil }
        return Int(argumentMax)
    }

    /// KERN_PROCARGS2 is argc, the executable path, padding, then argv.
    /// Returns the executable path followed by argv[1...].
    static func arguments(of pid: pid_t, buffer: inout [UInt8]) -> [String]? {
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
