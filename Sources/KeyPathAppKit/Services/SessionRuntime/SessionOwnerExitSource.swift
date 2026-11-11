import Darwin
import Foundation
import KeyPathCore
import os

/// Tells the worker the moment its owning app exits (kqueue `NOTE_EXIT`), so
/// the engine stops accepting control connections at once instead of at the
/// next poll (ADR-046). The engine also checks every peer's PID version, so a
/// PID reused before this fires still cannot connect.
final class SessionOwnerExitSource: @unchecked Sendable {
    private let source: DispatchSourceProcess
    private let fired = OSAllocatedUnfairLock(initialState: false)
    private let onExit: @Sendable () -> Void

    private init(pid: Int32, queue: DispatchQueue, onExit: @escaping @Sendable () -> Void) {
        source = DispatchSource.makeProcessSource(identifier: pid, eventMask: .exit, queue: queue)
        self.onExit = onExit
    }

    /// Calls `onExit` once, on `queue`, when `pid` exits, including when it
    /// has already exited by the time the watch is registered (`ESRCH`).
    static func watch(
        pid: Int32, queue: DispatchQueue = .global(qos: .userInteractive),
        onExit: @escaping @Sendable () -> Void
    ) -> SessionOwnerExitSource {
        let watch = SessionOwnerExitSource(pid: pid, queue: queue, onExit: onExit)
        watch.source.setEventHandler { [weak watch] in watch?.fire() }
        watch.source.resume()
        // Registered first, so an exit after this check is delivered by the
        // source; one before it is caught here.
        if pid <= 0 || !SystemStateProvider.isProcessAlive(pid: pid) {
            queue.async { [weak watch] in watch?.fire() }
        }
        return watch
    }

    private func fire() {
        let first = fired.withLock { fired in
            defer { fired = true }
            return !fired
        }
        guard first else { return }
        source.cancel()
        onExit()
    }

    func cancel() {
        source.cancel()
    }

    deinit {
        source.cancel()
    }
}
