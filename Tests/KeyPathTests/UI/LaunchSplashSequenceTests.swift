@testable import KeyPathAppKit
import XCTest

/// The launch poster stays up until the overlay or setup is ready, for at least
/// the minimum, and never leaves a gap with no KeyPath window.
@MainActor
final class LaunchSplashSequenceTests: XCTestCase {
    private let minimum = Duration.milliseconds(60)

    private func run(showsPoster: Bool, startupTakes: Duration, complete: Bool, maximum: Duration = .seconds(5))
        async -> (steps: [LaunchSplashSequence.Step], overlayAt: Duration?)
    {
        var steps: [LaunchSplashSequence.Step] = []
        var overlayAt: Duration?
        let started = ContinuousClock.now
        await LaunchSplashSequence(minimum: minimum, maximum: maximum).run(
            showsPoster: showsPoster,
            startup: {
                try? await Task.sleep(for: startupTakes)
                return complete
            },
            perform: { step in
                if step == .showOverlay { overlayAt = ContinuousClock.now - started }
                steps.append(step)
            }
        )
        return (steps, overlayAt)
    }

    func testFastStartupKeepsThePosterForTheMinimumThenHandsOff() async {
        let result = await run(showsPoster: true, startupTakes: .zero, complete: true)
        XCTAssertEqual(result.steps, [.showOverlay, .hideSplash], "Overlay first, then the splash goes")
        XCTAssertGreaterThanOrEqual(result.overlayAt ?? .zero, minimum)
    }

    func testSlowStartupKeepsThePosterUpAndShowsActivity() async {
        let result = await run(showsPoster: true, startupTakes: .milliseconds(250), complete: true)
        XCTAssertEqual(result.steps, [.showPreparing, .showOverlay, .hideSplash],
                       "The splash is not hidden until the overlay is up")
        XCTAssertGreaterThanOrEqual(result.overlayAt ?? .zero, .milliseconds(250))
    }

    func testIncompleteSetupReusesTheSplashWindow() async {
        let result = await run(showsPoster: true, startupTakes: .zero, complete: false)
        XCTAssertEqual(result.steps, [.showSetup(posterAlreadyShown: true)], "No hide, so no flicker before setup")
    }

    func testWithoutAPosterNothingWaitsOrHides() async {
        let overlay = await run(showsPoster: false, startupTakes: .zero, complete: true)
        XCTAssertEqual(overlay.steps, [.showOverlay])
        let setup = await run(showsPoster: false, startupTakes: .zero, complete: false)
        XCTAssertEqual(setup.steps, [.showSetup(posterAlreadyShown: false)])
    }

    /// A stalled startup does not leave the poster up: it goes after the maximum,
    /// and the overlay still appears once startup finishes. The margins are wide
    /// so a busy machine cannot reorder the steps.
    func testStalledStartupHidesThePosterAfterTheMaximum() async {
        let result = await run(showsPoster: true, startupTakes: .seconds(1), complete: true, maximum: .milliseconds(250))
        XCTAssertEqual(result.steps, [.showPreparing, .hideSplash, .showOverlay])
    }

    /// After the ceiling hid the poster, setup is told so and brings the window back.
    func testStalledStartupWithSetupPendingDoesNotClaimThePosterIsUp() async {
        let result = await run(showsPoster: true, startupTakes: .seconds(1), complete: false, maximum: .milliseconds(250))
        XCTAssertEqual(result.steps, [.showPreparing, .hideSplash, .showSetup(posterAlreadyShown: false)])
    }
}
