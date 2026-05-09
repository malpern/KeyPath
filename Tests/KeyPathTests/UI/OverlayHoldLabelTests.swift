@testable import KeyPathAppKit
import KeyPathCore
import XCTest

/// Regression tests for hold-label resolution and rendering inputs.
@MainActor
final class OverlayHoldLabelTests: XCTestCase {
    func testHoldDisplayLabelHyperUsesStar() async throws {
        let mapper = LayerKeyMapper()
        let keyCode: UInt16 = 57
        let config = WizardSystemPaths.userConfigPath
        let layer = "base"

        do {
            let label = try await mapper.holdDisplayLabel(for: keyCode, configPath: config, startLayer: layer)
            XCTAssertEqual(label, "✦", "Hyper should resolve to star symbol for capslock hold")
        } catch is SimulatorError {
            throw XCTSkip("Kanata simulator binary not available in test environment")
        }
    }

    func testSimulatorEmitsCanonicalNameForCaps() {
        // The simulator should emit canonical Kanata names (no glyphs)
        // Using the overlay's mapping to confirm we understand the key code -> name mapping.
        let name = OverlayKeyboardView.keyCodeToKanataName(57)
        XCTAssertEqual(name, "capslock")
    }
}
