import Foundation

/// What happens between the launch poster appearing and KeyPath's first real
/// surface (the keyboard overlay, or setup).
///
/// The poster stays up until that surface is ready, for at least `minimum`, so
/// there is never a moment with no KeyPath window. If startup outlasts
/// `minimum`, the activity dots appear so the wait does not look frozen.
@MainActor
struct LaunchSplashSequence {
    enum Step: Equatable {
        case showPreparing
        case showOverlay
        case hideSplash
        /// Setup reuses the splash window, so it is not hidden first.
        case showSetup(posterAlreadyShown: Bool)
    }

    var minimum: Duration
    var sleep: @MainActor (Duration) async -> Void = { try? await Task.sleep(for: $0) }

    /// - Parameters:
    ///   - showsPoster: the poster is on screen now.
    ///   - startup: waits for the runtime, then returns whether setup is complete.
    func run(
        showsPoster: Bool,
        startup: @escaping @MainActor () async -> Bool,
        perform: @escaping @MainActor (Step) async -> Void
    ) async {
        guard showsPoster else {
            await perform(startup() ? .showOverlay : .showSetup(posterAlreadyShown: false))
            return
        }
        let started = ContinuousClock.now
        let minimum = minimum
        let sleep = sleep
        let preparing = Task { @MainActor in
            await sleep(minimum)
            if !Task.isCancelled { await perform(.showPreparing) }
        }
        let complete = await startup()
        let elapsed = ContinuousClock.now - started
        if elapsed < minimum {
            preparing.cancel()
            await sleep(minimum - elapsed)
        } else {
            await preparing.value
        }
        if complete {
            await perform(.showOverlay)
            await perform(.hideSplash)
        } else {
            await perform(.showSetup(posterAlreadyShown: true))
        }
    }
}
