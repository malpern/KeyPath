import Foundation
import KeyPathCore

/// Retires a worker whose owning app is gone. It polls on a background queue,
/// so a worker wedged before its main-loop tick exists still exits: on
/// 2026-11-03 two capability probes outlived their owner by hours this way.
final class SessionOwnerWatch: @unchecked Sendable {
    enum Verdict: Equatable, Sendable {
        case ownerExited
        case deadlineExceeded
    }

    /// Owner death wins over the deadline; a worker without an owner PID is
    /// bounded only by its deadline.
    nonisolated static func verdict(ownerPID: Int32, ownerAlive: Bool, elapsed: TimeInterval,
                                    deadline: TimeInterval?) -> Verdict?
    {
        if ownerPID > 0, !ownerAlive { return .ownerExited }
        if let deadline, elapsed >= deadline { return .deadlineExceeded }
        return nil
    }

    private let lock = NSLock()
    private var handler: @Sendable (Verdict) -> Void
    private let timer: DispatchSourceTimer

    /// The resumed timer retains itself, and its handler retains the watch,
    /// until the first verdict cancels it.
    init(
        ownerPID: Int32, deadline: TimeInterval?, interval: TimeInterval = 0.25,
        isAlive: @escaping @Sendable (Int32) -> Bool = { SystemStateProvider.isProcessAlive(pid: $0) },
        uptime: @escaping @Sendable () -> TimeInterval = { ProcessInfo.processInfo.systemUptime },
        queue: DispatchQueue = DispatchQueue(label: "com.keypath.session-owner-watch", qos: .utility),
        handler: @escaping @Sendable (Verdict) -> Void
    ) {
        self.handler = handler
        timer = DispatchSource.makeTimerSource(queue: queue)
        let started = uptime()
        // The first check runs immediately: the owner may already be gone.
        timer.schedule(deadline: .now(), repeating: interval)
        timer.setEventHandler { [self] in
            guard let verdict = Self.verdict(ownerPID: ownerPID, ownerAlive: isAlive(ownerPID),
                                             elapsed: uptime() - started, deadline: deadline)
            else { return }
            timer.cancel()
            lock.lock()
            let current = self.handler
            lock.unlock()
            current(verdict)
        }
        timer.resume()
    }

    /// The runtime hands off from a hard exit to an orderly shutdown once it
    /// may own outputs or a Caps mapping.
    func setHandler(_ handler: @escaping @Sendable (Verdict) -> Void) {
        lock.lock()
        self.handler = handler
        lock.unlock()
    }
}
