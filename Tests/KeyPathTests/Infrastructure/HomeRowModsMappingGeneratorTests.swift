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

    // MARK: - End-to-End Rendering (generate → render → verify valid kanata syntax)

    func testLayersModeWhileHeld_RendersValidKanataSyntax() {
        // REGRESSION: S-expression holdAction "(layer-while-held nav)" was being mangled
        // by convertAction() into "(multi lpar rpar)" because it split by whitespace
        let config = HomeRowModsConfig(
            enabledKeys: ["a", "s", "d", "f"],
            modifierAssignments: ["a": "lmet", "s": "lalt", "d": "lsft", "f": "lctl"],
            layerAssignments: ["a": "nav", "s": "sym", "d": "num", "f": "fun"],
            holdMode: .layers,
            layerToggleMode: .whileHeld
        )

        let mappings = KanataConfiguration.generateHomeRowModsMappings(from: config)
        XCTAssertEqual(mappings.count, 4)

        let allRendered = mappings.map { KanataBehaviorRenderer.render($0) }

        // Every mapping must use tap-hold-press with a layer-while-held action
        for rendered in allRendered {
            XCTAssertTrue(rendered.contains("tap-hold-press"), "Should use tap-hold-press: \(rendered)")
            XCTAssertTrue(rendered.contains("layer-while-held"), "Should use layer-while-held: \(rendered)")
            XCTAssertFalse(rendered.contains("lpar"), "Should not mangle to lpar: \(rendered)")
            XCTAssertFalse(rendered.contains("rpar"), "Should not mangle to rpar: \(rendered)")
        }

        // All 4 layer assignments should appear across the rendered output (order may vary)
        let joined = allRendered.joined(separator: " ")
        for layer in ["nav", "sym", "num", "fun"] {
            XCTAssertTrue(
                joined.contains("(layer-while-held \(layer))"),
                "Should contain layer-while-held \(layer)"
            )
        }
    }

    func testLayersModeToggle_RendersValidKanataSyntax() {
        let config = HomeRowModsConfig(
            enabledKeys: ["a"],
            modifierAssignments: ["a": "lmet"],
            layerAssignments: ["a": "nav"],
            holdMode: .layers,
            layerToggleMode: .toggle
        )

        let mappings = KanataConfiguration.generateHomeRowModsMappings(from: config)
        let rendered = KanataBehaviorRenderer.render(mappings[0])

        XCTAssertTrue(
            rendered.contains("(layer-toggle nav)"),
            "Should contain layer-toggle, got: \(rendered)"
        )
        XCTAssertFalse(rendered.contains("lpar"), "Should not mangle to lpar")
    }

    func testModifierMode_RendersValidKanataSyntax() {
        // Sanity: modifier mode should produce simple modifier holdAction
        let config = HomeRowModsConfig(
            enabledKeys: ["a"],
            modifierAssignments: ["a": "lmet"],
            layerAssignments: ["a": "nav"],
            holdMode: .modifiers,
            layerToggleMode: .whileHeld
        )

        let mappings = KanataConfiguration.generateHomeRowModsMappings(from: config)
        let rendered = KanataBehaviorRenderer.render(mappings[0])

        XCTAssertTrue(
            rendered.contains("lmet"),
            "Modifier mode should use simple modifier, got: \(rendered)"
        )
        XCTAssertFalse(rendered.contains("layer-"), "Modifier mode should not contain layer actions")
    }
}
