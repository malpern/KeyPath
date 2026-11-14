import Foundation

/// What happens between the launch poster appearing and KeyPath's first real
/// surface (the keyboard overlay, or setup).
///
/// The poster stays up until that surface is ready, for at least `minimum`, so
/// there is never a moment with no KeyPath window. If startup outlasts
/// `minimum`, the activity dots appear so the wait does not look frozen. The
/// splash window has no close button, so after `maximum` the poster goes away
/// even if startup has not finished; the overlay or setup follows when it does.
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
    var maximum: Duration = .seconds(15)
    /// The clock, injectable so tests run in virtual time.
    var sleep: @MainActor (Duration) async -> Void = { try? await Task.sleep(for: $0) }
    var now: @MainActor () -> ContinuousClock.Instant = { ContinuousClock.now }

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
        let started = now()
        let minimum = minimum
        let sleep = sleep
        let maximum = maximum
        let preparing = Task { @MainActor in
            await sleep(minimum)
            if !Task.isCancelled { await perform(.showPreparing) }
        }
        let gaveUp = Flag()
        let ceiling = Task { @MainActor in
            await sleep(maximum)
            guard !Task.isCancelled else { return }
            gaveUp.isSet = true
            await perform(.hideSplash)
        }
        let complete = await startup()
        ceiling.cancel()
        let elapsed = now() - started
        if gaveUp.isSet {
            // Let the hide finish before the overlay or setup appears.
            await ceiling.value
            await preparing.value
            // The poster has been hidden, so setup brings the window back itself.
            await perform(complete ? .showOverlay : .showSetup(posterAlreadyShown: false))
            return
        }
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

    /// The poster is skipped when macOS starts KeyPath at login.
    static func showsPoster(launchedAsLoginItem: Bool) -> Bool {
        !launchedAsLoginItem
    }

    @MainActor private final class Flag {
        var isSet = false
    }
}
