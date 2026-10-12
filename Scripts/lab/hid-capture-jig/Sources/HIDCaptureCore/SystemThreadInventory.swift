import Darwin
import Foundation

/// An unavailable inventory is -1, never zero. kern.num_taskthreads is a per-task
/// limit, not a live count. Ordinary proc_pidinfo cannot read every user's tasks;
/// Apple's privileged top reader can, without granting the Jig extra privileges.
public final class SystemThreadInventory: @unchecked Sendable {
    private let lock = NSLock()
    private var pending = false
    private var latest: (count: Int, observed: UInt64)?
    private let collect: @Sendable () -> Int?
    private let now: @Sendable () -> UInt64

    public convenience init() {
        self.init(collect: { Self.readSystemInventory() }, now: { DispatchTime.now().uptimeNanoseconds })
    }

    init(collect: @escaping @Sendable () -> Int?, now: @escaping @Sendable () -> UInt64) {
        self.collect = collect
        self.now = now
    }

    public func sample() -> Int {
        lock.lock()
        let current = now()
        let count = latest.flatMap { value -> Int? in
            guard current >= value.observed, current - value.observed <= 3_000_000_000 else { return nil }
            return value.count
        } ?? -1
        let start = !pending
        pending = true
        lock.unlock()
        if start {
            DispatchQueue.global(qos: .utility).async { [self] in
                let started = now()
                let result = collect()
                lock.lock()
                latest = result.flatMap { $0 > 0 ? ($0, started) : nil }
                pending = false
                lock.unlock()
            }
        }
        return count
    }

    static func parse(_ output: String) -> Int? {
        guard let first = output.split(separator: "\n").first else { return nil }
        let fields = first.split(whereSeparator: { $0 == " " || $0 == "\t" })
        guard fields.first == "Processes:", fields.last == "threads", fields.count >= 3,
              let count = Int(fields[fields.count - 2]), count > 0 else { return nil }
        return count
    }

    static func readSystemInventory(
        executable: String = "/usr/bin/top", arguments: [String] = ["-l", "1", "-n", "0"],
        timeout: TimeInterval = 2
    ) -> Int? {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: executable)
        process.arguments = arguments
        process.environment = ["PATH": "/usr/bin:/bin", "LC_ALL": "C", "LANG": "C"]
        let output = Pipe()
        process.standardOutput = output
        process.standardError = FileHandle.nullDevice
        let exited = DispatchSemaphore(value: 0)
        process.terminationHandler = { _ in exited.signal() }
        do { try process.run() } catch { return nil }
        guard exited.wait(timeout: .now() + timeout) == .success else {
            process.terminate()
            if exited.wait(timeout: .now() + 0.2) != .success, process.isRunning {
                kill(process.processIdentifier, SIGKILL)
            }
            return nil
        }
        guard process.terminationStatus == 0 else { return nil }
        return parse(String(decoding: output.fileHandleForReading.readDataToEndOfFile(), as: UTF8.self))
    }
}
