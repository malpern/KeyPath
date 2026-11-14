@testable import KeyPathAppKit
import XCTest

/// The launch poster stays up until the overlay or setup is ready, for at least
/// the minimum, and never leaves a gap with no KeyPath window. Runs in virtual
/// time, so the order of steps never depends on how busy the machine is.
@MainActor
final class LaunchSplashSequenceTests: XCTestCase {
    /// Virtual time: sleepers wait until `advance` moves the clock past them.
    @MainActor
    private final class VirtualClock {
        private struct Sleeper {
            let id: Int
            let wake: Duration
            let resume: CheckedContinuation<Void, Never>
        }

        private(set) var elapsed: Duration = .zero
        private var sleepers: [Sleeper] = []
        private var nextID = 0
        private let origin = ContinuousClock.now

        var now: ContinuousClock.Instant {
            origin + elapsed
        }

        func sleep(_ duration: Duration) async {
            let id = nextID
            nextID += 1
            await withTaskCancellationHandler {
                await withCheckedContinuation { continuation in
                    if Task.isCancelled { continuation.resume(); return }
                    sleepers.append(Sleeper(id: id, wake: elapsed + duration, resume: continuation))
                }
            } onCancel: {
                Task { @MainActor in self.wake(id: id) }
            }
        }

        private func wake(id: Int) {
            guard let index = sleepers.firstIndex(where: { $0.id == id }) else { return }
            sleepers.remove(at: index).resume.resume()
        }

        /// Lets every runnable task reach its next sleep.
        func settle() async {
            for _ in 0 ..< 50 {
                await Task.yield()
            }
        }

        /// Runs until `done` reports true, waking sleepers in time order.
        func run(until done: () -> Bool) async {
            await settle()
            while !done() {
                guard let next = sleepers.min(by: { $0.wake < $1.wake }) else {
                    XCTFail("Nothing left to wake, but the sequence has not finished")
                    return
                }
                elapsed = max(elapsed, next.wake)
                wake(id: next.id)
                await settle()
            }
        }
    }

    private let minimum = Duration.milliseconds(1200)

    private func run(
        showsPoster: Bool,
        startupTakes: Duration,
        complete: Bool,
        maximum: Duration = .seconds(15)
    ) async -> (steps: [LaunchSplashSequence.Step], overlayAt: Duration?) {
        let clock = VirtualClock()
        var steps: [LaunchSplashSequence.Step] = []
        var overlayAt: Duration?
        var finished = false
        var sequence = LaunchSplashSequence(minimum: minimum, maximum: maximum)
        sequence.sleep = { await clock.sleep($0) }
        sequence.now = { clock.now }
        let task = Task { @MainActor in
            await sequence.run(
                showsPoster: showsPoster,
                startup: {
                    if startupTakes > .zero { await clock.sleep(startupTakes) }
                    return complete
                },
                perform: { step in
                    if step == .showOverlay { overlayAt = clock.elapsed }
                    steps.append(step)
                }
            )
            finished = true
        }
        await clock.run { finished }
        await task.value
        return (steps, overlayAt)
    }

    func testFastStartupKeepsThePosterForTheMinimumThenHandsOff() async {
        let result = await run(showsPoster: true, startupTakes: .milliseconds(300), complete: true)
        XCTAssertEqual(result.steps, [.showOverlay, .hideSplash], "Overlay first, then the splash goes")
        XCTAssertEqual(result.overlayAt, minimum)
    }

    func testSlowStartupKeepsThePosterUpAndShowsActivity() async {
        let result = await run(showsPoster: true, startupTakes: .seconds(4), complete: true)
        XCTAssertEqual(result.steps, [.showPreparing, .showOverlay, .hideSplash],
                       "The splash is not hidden until the overlay is up")
        XCTAssertEqual(result.overlayAt, .seconds(4))
    }

    func testIncompleteSetupReusesTheSplashWindow() async {
        let result = await run(showsPoster: true, startupTakes: .zero, complete: false)
        XCTAssertEqual(result.steps, [.showSetup(posterAlreadyShown: true)], "No hide, so no flicker before setup")
    }

    func testWithoutAPosterNothingWaitsOrHides() async {
        let overlay = await run(showsPoster: false, startupTakes: .seconds(3), complete: true)
        XCTAssertEqual(overlay.steps, [.showOverlay])
        XCTAssertEqual(overlay.overlayAt, .seconds(3))
        let setup = await run(showsPoster: false, startupTakes: .zero, complete: false)
        XCTAssertEqual(setup.steps, [.showSetup(posterAlreadyShown: false)])
    }

    /// A stalled startup does not leave the poster up: it goes after the maximum,
    /// and the overlay still appears once startup finishes.
    func testStalledStartupHidesThePosterAfterTheMaximum() async {
        let result = await run(showsPoster: true, startupTakes: .seconds(20), complete: true)
        XCTAssertEqual(result.steps, [.showPreparing, .hideSplash, .showOverlay])
        XCTAssertEqual(result.overlayAt, .seconds(20))
    }

    /// After the ceiling hid the poster, setup is told so and brings the window back.
    func testStalledStartupWithSetupPendingDoesNotClaimThePosterIsUp() async {
        let result = await run(showsPoster: true, startupTakes: .seconds(20), complete: false)
        XCTAssertEqual(result.steps, [.showPreparing, .hideSplash, .showSetup(posterAlreadyShown: false)])
    }
}
