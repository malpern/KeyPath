@testable import KeyPathAppKit
import XCTest

/// The launch poster stays up until the overlay or setup is ready, for at least
/// the minimum, and never leaves a gap with no KeyPath window.
@MainActor
final class LaunchSplashSequenceTests: XCTestCase {
    /// Margins are hundreds of milliseconds so a busy CI runner cannot reorder steps.
    private let minimum = Duration.milliseconds(500)

    private func run(showsPoster: Bool, startupTakes: Duration, complete: Bool, minimum: Duration? = nil,
                     maximum: Duration = .seconds(10))
        async -> (steps: [LaunchSplashSequence.Step], overlayAt: Duration?)
    {
        var steps: [LaunchSplashSequence.Step] = []
        var overlayAt: Duration?
        let started = ContinuousClock.now
        await LaunchSplashSequence(minimum: minimum ?? self.minimum, maximum: maximum).run(
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
        let result = await run(showsPoster: true, startupTakes: .milliseconds(1500), complete: true, minimum: .milliseconds(200))
        XCTAssertEqual(result.steps, [.showPreparing, .showOverlay, .hideSplash],
                       "The splash is not hidden until the overlay is up")
        XCTAssertGreaterThanOrEqual(result.overlayAt ?? .zero, .milliseconds(1500))
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
        let result = await run(showsPoster: true, startupTakes: .seconds(2), complete: true, minimum: .milliseconds(100), maximum: .milliseconds(700))
        XCTAssertEqual(result.steps, [.showPreparing, .hideSplash, .showOverlay])
    }

    /// After the ceiling hid the poster, setup is told so and brings the window back.
    func testStalledStartupWithSetupPendingDoesNotClaimThePosterIsUp() async {
        let result = await run(showsPoster: true, startupTakes: .seconds(2), complete: false, minimum: .milliseconds(100), maximum: .milliseconds(700))
        XCTAssertEqual(result.steps, [.showPreparing, .hideSplash, .showSetup(posterAlreadyShown: false)])
    }
}
