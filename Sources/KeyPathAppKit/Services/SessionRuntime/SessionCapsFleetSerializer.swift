import Dispatch
import Synchronization

/// Serializes a session worker's Caps fleet work: the periodic keyboard check
/// and the restore at exit.
///
/// A check holds every keyboard's lease lock while it reconciles. The restore at
/// exit takes the same locks without waiting, so a restore that ran beside a
/// check failed `busy`; when the app had been killed, nothing else restored the
/// mapping and Caps Lock stayed remapped until KeyPath next launched. The flag
/// stops a check queued later from re-applying the mapping after the restore.
final class SessionCapsFleetSerializer: Sendable {
    private let queue: DispatchQueue
    private let shutDown = Mutex(false)

    init(label: String = "com.keypath.session-caps-fleet") {
        queue = DispatchQueue(label: label, qos: .userInitiated)
    }

    /// Runs `work` after any earlier check. Skipped once the restore has begun.
    func check(_ work: @escaping @Sendable () -> Void) {
        queue.async {
            guard !self.shutDown.withLock({ $0 }) else { return }
            work()
        }
    }

    /// Waits for a check in flight, stops every later one, then restores.
    func restoreAtExit<T>(_ restore: () throws -> T) rethrows -> T {
        try queue.sync {
            shutDown.withLock { $0 = true }
            return try restore()
        }
    }
}
