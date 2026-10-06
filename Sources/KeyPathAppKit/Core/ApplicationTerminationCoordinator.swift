import Foundation

/// Defers graceful termination until admitted runtime cleanup has returned.
/// A cleanup refusal keeps known update termination alive, but ordinary Quit
/// remains usable with its recovery evidence retained by the lifecycle owner.
@MainActor
final class ApplicationTerminationCoordinator {
    private(set) var isPending = false

    func request(
        suppressStarts: @escaping @MainActor (Bool) -> Void,
        stop: @escaping @MainActor () async -> Bool,
        updateExpected: @escaping @MainActor () -> Bool,
        cleanupRefused: @escaping @MainActor (Bool) -> Void,
        finish: @escaping @MainActor () async -> Void,
        reply: @escaping @MainActor (Bool) -> Void
    ) {
        guard !isPending else { return }
        isPending = true
        // Invalidate queued starts before the first asynchronous hop.
        suppressStarts(true)
        Task { @MainActor in
            let stopped = await stop()
            // Read after the await too: an update may have become staged while
            // cleanup was waiting for lifecycle admission.
            let cancel = !stopped && updateExpected()
            if !stopped { cleanupRefused(cancel) }
            if cancel {
                isPending = false
                suppressStarts(false)
                reply(false)
                return
            }
            if !stopped {
                // Ordinary Quit remains usable. Do not introduce a plugin-flush
                // suspension where an update could become staged after this
                // refusal decision. Process exit closes windows automatically.
                reply(true)
                return
            }
            // Keep starts suppressed through plugin flushing and process exit.
            await finish()
            reply(true)
        }
    }
}
