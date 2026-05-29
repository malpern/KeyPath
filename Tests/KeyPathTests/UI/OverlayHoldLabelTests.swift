@testable import KeyPathAppKit
import XCTest

/// Regression tests for hold-label resolution and rendering inputs.
@MainActor
final class OverlayHoldLabelTests: XCTestCase {
    func testHoldDisplayLabelHyperUsesStar() {
        // When a hold resolves to all four modifiers (Ctrl+Cmd+Alt+Shift) the overlay
        // labels it with the Hyper star. This exercises the label-resolution contract
        // directly rather than driving the kanata simulator against the live user
        // config, which made the test non-deterministic (skip locally when the bundled
        // simulator is absent, fail in CI when the config has no caps→Hyper mapping).
        let hyperOutputs: Set = ["lctl", "lmet", "lalt", "lsft"]
        let label = LayerKeyMapper.labelForOutputKeys(hyperOutputs) { $0 }
        XCTAssertEqual(label, "✦", "Hyper (Ctrl+Cmd+Alt+Shift) should resolve to the star symbol")
    }

    func testHoldDisplayLabelHyperUsesStarWithModifierAliases() {
        // Right-side and spelled-out modifier aliases normalize to the same Hyper set.
        let hyperOutputs: Set = ["rctl", "cmd", "ralt", "shift"]
        let label = LayerKeyMapper.labelForOutputKeys(hyperOutputs) { $0 }
        XCTAssertEqual(label, "✦", "Aliased Hyper modifiers should still resolve to the star symbol")
    }

    func testSimulatorEmitsCanonicalNameForCaps() {
        // The simulator should emit canonical Kanata names (no glyphs)
        // Using the overlay's mapping to confirm we understand the key code -> name mapping.
        let name = OverlayKeyboardView.keyCodeToKanataName(57)
        XCTAssertEqual(name, "capslock")
    }
}
