@testable import KeyPathAppKit
import XCTest

final class OverlayLayerRevealPolicyTests: XCTestCase {
    private func holdPolicy() -> OverlayLayerRevealPolicy {
        OverlayLayerRevealPolicy(configuration: .make(displayMode: .overlayOnly, triggerMode: .holdToShow))
    }

    func testHoldingALayerRevealsAfterTheDelayAndHidesOnRelease() {
        var policy = holdPolicy()
        XCTAssertEqual(policy.layerChanged(isBase: false, overlayAlreadyVisible: false), [.scheduleReveal(after: 0.35)])
        XCTAssertEqual(policy.revealTimerFired(), [.show])
        XCTAssertEqual(policy.layerChanged(isBase: true, overlayAlreadyVisible: true), [.scheduleConceal(after: 0.15)])
        XCTAssertEqual(policy.concealTimerFired(), [.hide])
        XCTAssertEqual(policy.state, .idle)
    }

    func testAQuickMoveNeverShowsTheOverlay() {
        var policy = holdPolicy()
        _ = policy.layerChanged(isBase: false, overlayAlreadyVisible: false)
        XCTAssertEqual(policy.keyPressed(), [.cancelReveal])
        // A stale timer firing after the cancel must not show it.
        XCTAssertEqual(policy.revealTimerFired(), [])
        XCTAssertEqual(policy.layerChanged(isBase: true, overlayAlreadyVisible: false), [])
        XCTAssertEqual(policy.state, .idle)
    }

    func testReleasingBeforeTheDelayCancelsTheReveal() {
        var policy = holdPolicy()
        _ = policy.layerChanged(isBase: false, overlayAlreadyVisible: false)
        XCTAssertEqual(policy.layerChanged(isBase: true, overlayAlreadyVisible: false), [.cancelReveal])
        XCTAssertEqual(policy.revealTimerFired(), [])
    }

    func testSwitchingStraightToAnotherLayerKeepsItUp() {
        var policy = holdPolicy()
        _ = policy.layerChanged(isBase: false, overlayAlreadyVisible: false)
        _ = policy.revealTimerFired()
        _ = policy.layerChanged(isBase: true, overlayAlreadyVisible: true)
        XCTAssertEqual(policy.layerChanged(isBase: false, overlayAlreadyVisible: true), [.cancelConceal])
        XCTAssertEqual(policy.state, .revealed)
    }

    func testAnOverlayTheUserOpenedIsLeftAlone() {
        var policy = holdPolicy()
        XCTAssertEqual(policy.layerChanged(isBase: false, overlayAlreadyVisible: true), [])
        XCTAssertEqual(policy.layerChanged(isBase: true, overlayAlreadyVisible: true), [])
    }

    func testUserTakingControlStopsTheAutomaticHide() {
        var policy = holdPolicy()
        _ = policy.layerChanged(isBase: false, overlayAlreadyVisible: false)
        _ = policy.revealTimerFired()
        XCTAssertEqual(policy.userTookControl(), [.cancelConceal])
        XCTAssertEqual(policy.layerChanged(isBase: true, overlayAlreadyVisible: true), [])
    }

    func testTapTriggerRevealsAtOnceAndIgnoresKeyPresses() {
        var policy = OverlayLayerRevealPolicy(configuration: .make(displayMode: .both, triggerMode: .tapToToggle))
        XCTAssertEqual(policy.layerChanged(isBase: false, overlayAlreadyVisible: false), [.show])
        XCTAssertEqual(policy.keyPressed(), [])
        XCTAssertEqual(policy.state, .revealed)
    }

    func testListOnlyAndNothingModesNeverShowTheOverlay() {
        for mode in [ContextHUDDisplayMode.hudOnly, .none] {
            var policy = OverlayLayerRevealPolicy(configuration: .make(displayMode: mode, triggerMode: .holdToShow))
            XCTAssertEqual(policy.layerChanged(isBase: false, overlayAlreadyVisible: false), [], "\(mode)")
        }
    }
}
