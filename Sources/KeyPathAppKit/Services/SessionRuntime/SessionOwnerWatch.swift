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

/// Bounds an owner-exit retirement that the worker's run loop never runs. An
/// orderly shutdown cancels it when it begins, so a slow Caps restore or key
/// release is never cut off; the HID join it waits on stays unbounded.
final class SessionShutdownFallback: @unchecked Sendable {
    static let shared = SessionShutdownFallback()

    private let lock = NSLock()
    private var shutdownBegan = false
    private var pending: DispatchWorkItem?

    /// Arms `action` after `grace`. Returns false, arming nothing, when an
    /// orderly shutdown already began.
    @discardableResult
    func arm(after grace: TimeInterval, queue: DispatchQueue = .global(qos: .utility),
             action: @escaping @Sendable () -> Void) -> Bool
    {
        lock.lock()
        defer { lock.unlock() }
        guard !shutdownBegan, pending == nil else { return !shutdownBegan }
        let item = DispatchWorkItem(block: action)
        pending = item
        queue.asyncAfter(deadline: .now() + grace, execute: item)
        return true
    }

    func shutdownBegins() {
        lock.lock()
        shutdownBegan = true
        pending?.cancel()
        pending = nil
        lock.unlock()
    }
}
