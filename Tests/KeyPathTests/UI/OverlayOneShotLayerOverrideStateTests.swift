@testable import KeyPathAppKit
import XCTest

@MainActor
final class OverlayOneShotLayerOverrideStateTests: XCTestCase {
    private let modifierKeys: Set<String> = [
        "leftshift",
        "rightshift",
        "leftalt",
        "rightalt",
        "leftctrl",
        "rightctrl",
        "leftmeta",
        "rightmeta",
        "capslock",
        "fn"
    ]

    func testActivateKeepsLayerUntilCleared() {
        let state = OneShotLayerOverrideState(timeoutNanoseconds: 1_000_000_000, sleep: Self.cancelAwareSleep)

        state.activate("nav")
        XCTAssertEqual(state.currentLayer, "nav")

        state.clear()
        XCTAssertNil(state.currentLayer)
    }

    func testClearOnKeyPressIgnoresModifierKeys() {
        let state = OneShotLayerOverrideState(timeoutNanoseconds: 1_000_000_000, sleep: Self.cancelAwareSleep)

        state.activate("nav")
        let cleared = state.clearOnKeyPress("leftshift", modifierKeys: modifierKeys)

        XCTAssertNil(cleared)
        XCTAssertEqual(state.currentLayer, "nav")

        state.clear()
    }

    func testClearOnKeyPressReturnsLayerForNonModifier() {
        let state = OneShotLayerOverrideState(timeoutNanoseconds: 1_000_000_000, sleep: Self.cancelAwareSleep)

        state.activate("nav")
        let cleared = state.clearOnKeyPress("a", modifierKeys: modifierKeys)

        XCTAssertEqual(cleared, "nav")
        XCTAssertNil(state.currentLayer)
    }

    func testImmediateTimeoutClearsLayer() async {
        let state = OneShotLayerOverrideState(timeoutNanoseconds: 1, sleep: { _ in })

        state.activate("nav")
        await Task.yield()

        XCTAssertNil(state.currentLayer)
    }

    nonisolated static let cancelAwareSleep: @Sendable (UInt64) async -> Void = { _ in
        while !Task.isCancelled {
            await Task.yield()
        }
    }
}
