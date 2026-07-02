import Foundation

/// Runs a subprocess with a hard deadline, draining stdout+stderr concurrently.
///
/// Shared by the app (`PrivilegedCommandRunner`) and the privileged helper
/// (`HelperService`, which statically links KeyPathCore): a blocked child
/// (e.g. `launchctl kickstart -k` on an unrunnable service, #927/#930) must
/// never hang its caller, and output is read while the child runs so a chatty
/// command can't deadlock on a full pipe buffer.
///
/// Callers do their own logging — this type is used from both NSLog (helper)
/// and AppLogger (app) contexts.
public enum BoundedProcess {
    /// Exit status reported when the child exceeds its deadline and is killed.
    public static let timedOutStatus: Int32 = 124

    public struct Outcome: Sendable {
        /// Termination status; `timedOutStatus` (124) when killed on deadline,
        /// 127 when the process could not be launched at all.
        public let status: Int32
        /// Combined stdout+stderr captured so far (raw — no synthetic prefix).
        public let output: String
        public let timedOut: Bool
    }

    /// Launch `launchPath args` and wait at most `timeout` seconds.
    public static func run(
        _ launchPath: String, _ args: [String], timeout: TimeInterval
    ) -> Outcome {
        let p = Process()
        p.launchPath = launchPath
        p.arguments = args
        return run(p, timeout: timeout)
    }

    /// Run a caller-configured (not yet launched) Process with a hard deadline.
    /// The process's stdout/stderr are replaced with a captured pipe.
    public static func run(_ process: Process, timeout: TimeInterval) -> Outcome {
        let pipe = Pipe()
        process.standardOutput = pipe
        process.standardError = pipe

        let buffer = OutputBuffer()
        let readDone = DispatchSemaphore(value: 0)
        pipe.fileHandleForReading.readabilityHandler = { handle in
            let chunk = handle.availableData
            if chunk.isEmpty {
                handle.readabilityHandler = nil
                readDone.signal()
            } else {
                buffer.append(chunk)
            }
        }

        do { try process.run() } catch {
            pipe.fileHandleForReading.readabilityHandler = nil
            return Outcome(status: 127, output: "run failed: \(error)", timedOut: false)
        }

        let deadline = Date().addingTimeInterval(timeout)
        while process.isRunning, Date() < deadline {
            usleep(50000)
        }

        var timedOut = false
        if process.isRunning {
            timedOut = true
            process.terminate()
            usleep(200_000)
            if process.isRunning {
                kill(process.processIdentifier, SIGKILL)
            }
        }
        process.waitUntilExit()

        // Bounded wait for EOF so the output tail is captured. A killed child
        // may leave the pipe's write end open in orphaned grandchildren; don't
        // block on them.
        _ = readDone.wait(timeout: .now() + 2)
        pipe.fileHandleForReading.readabilityHandler = nil

        return Outcome(
            status: timedOut ? timedOutStatus : process.terminationStatus,
            output: buffer.text,
            timedOut: timedOut
        )
    }

    /// Thread-safe accumulator for output read via readabilityHandler.
    private final class OutputBuffer: @unchecked Sendable {
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
}
