import XCTest
@testable import KeyPathAppKit

/// Regression tests for hold-label resolution and rendering inputs.
final class OverlayHoldLabelTests: XCTestCase {

    func testHoldDisplayLabelHyperUsesStar() async throws {
        let mapper = LayerKeyMapper()
        // capslock keyCode on macOS
        let keyCode: UInt16 = 57
        let config = WizardSystemPaths.userConfigPath
        let layer = "base"

        let label = try await mapper.holdDisplayLabel(for: keyCode, configPath: config, startLayer: layer)

        XCTAssertEqual(label, "✦", "Hyper should resolve to star symbol for capslock hold")
    }

    func testSimulatorEmitsCanonicalNameForCaps() throws {
        // The simulator should emit canonical Kanata names (no glyphs)
        // Using the overlay's mapping to confirm we understand the key code -> name mapping.
        let name = OverlayKeyboardView.keyCodeToKanataName(57)
        XCTAssertEqual(name, "capslock")
    }
}
