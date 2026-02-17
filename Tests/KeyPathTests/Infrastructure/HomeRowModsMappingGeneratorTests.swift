@testable import KeyPathAppKit
import XCTest

final class HomeRowModsMappingGeneratorTests: XCTestCase {
    func testModifiersModeGeneratesModifierHoldAction() {
        let config = HomeRowModsConfig(
            enabledKeys: ["a"],
            modifierAssignments: ["a": "lmet"],
            layerAssignments: ["a": "nav"],
            holdMode: .modifiers,
            layerToggleMode: .whileHeld
        )

        let mappings = KanataConfiguration.generateHomeRowModsMappings(from: config)
        XCTAssertEqual(mappings.count, 1)
        guard case let .dualRole(behavior)? = mappings.first?.behavior else {
            return XCTFail("Expected dualRole behavior")
        }

        XCTAssertEqual(behavior.tapAction, "a")
        XCTAssertEqual(behavior.holdAction, "lmet")
    }

    func testLayersModeGeneratesLayerHoldAction() {
        let config = HomeRowModsConfig(
            enabledKeys: ["a"],
            modifierAssignments: ["a": "lmet"],
            layerAssignments: ["a": "nav"],
            holdMode: .layers,
            layerToggleMode: .toggle
        )

        let mappings = KanataConfiguration.generateHomeRowModsMappings(from: config)
        XCTAssertEqual(mappings.count, 1)
        guard case let .dualRole(behavior)? = mappings.first?.behavior else {
            return XCTFail("Expected dualRole behavior")
        }

        XCTAssertEqual(behavior.tapAction, "a")
        XCTAssertEqual(behavior.holdAction, "(layer-toggle nav)")
    }
}
