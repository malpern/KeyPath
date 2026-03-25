@testable import KeyPathAppKit
import XCTest

final class HomeRowModsMappingGeneratorTests: XCTestCase {
    func testModifiersModeGeneratesModifierHoldAction() {
        let config = HomeRowModsConfig(
            enabledKeys: ["a"],
            modifierAssignments: ["a": "lmet"],
            layerAssignments: ["a": "nav"],
            holdMode: .modifiers,
            layerToggleMode: .whileHeld,
            oppositeHandMode: .off
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
            layerToggleMode: .toggle,
            oppositeHandMode: .off
        )

        let mappings = KanataConfiguration.generateHomeRowModsMappings(from: config)
        XCTAssertEqual(mappings.count, 1)
        guard case let .dualRole(behavior)? = mappings.first?.behavior else {
            return XCTFail("Expected dualRole behavior")
        }

        XCTAssertEqual(behavior.tapAction, "a")
        XCTAssertEqual(behavior.holdAction, "(layer-toggle nav)")
    }

    // MARK: - Opposite-Hand Activation

    func testOppositeHandActivationTrue_SetsUseOppositeHand() {
        let config = HomeRowModsConfig(
            enabledKeys: ["a"],
            modifierAssignments: ["a": "lsft"],
            holdMode: .modifiers,
            oppositeHandMode: .press
        )

        let mappings = KanataConfiguration.generateHomeRowModsMappings(from: config)
        guard case let .dualRole(behavior)? = mappings.first?.behavior else {
            return XCTFail("Expected dualRole behavior")
        }

        XCTAssertTrue(behavior.useOppositeHand)
        XCTAssertTrue(behavior.customTapKeys.isEmpty, "customTapKeys should be empty when using opposite-hand")
        XCTAssertFalse(behavior.activateHoldOnOtherKey)
    }

    func testOppositeHandActivationFalse_LeavesCustomTapKeysEmpty() {
        let config = HomeRowModsConfig(
            enabledKeys: ["a"],
            modifierAssignments: ["a": "lsft"],
            holdMode: .modifiers,
            oppositeHandMode: .off
        )

        let mappings = KanataConfiguration.generateHomeRowModsMappings(from: config)
        guard case let .dualRole(behavior)? = mappings.first?.behavior else {
            return XCTFail("Expected dualRole behavior")
        }

        XCTAssertFalse(behavior.useOppositeHand)
        XCTAssertTrue(behavior.customTapKeys.isEmpty)
        XCTAssertTrue(behavior.activateHoldOnOtherKey)
    }

    func testOppositeHandActivation_PerKeyTimingOffsetsStillApply() {
        var timing = TimingConfig.default
        timing.tapOffsets = ["a": 20]
        timing.holdOffsets = ["a": 10]

        let config = HomeRowModsConfig(
            enabledKeys: ["a"],
            modifierAssignments: ["a": "lsft"],
            holdMode: .modifiers,
            timing: timing,
            oppositeHandMode: .press
        )

        let mappings = KanataConfiguration.generateHomeRowModsMappings(from: config)
        guard case let .dualRole(behavior)? = mappings.first?.behavior else {
            return XCTFail("Expected dualRole behavior")
        }

        XCTAssertEqual(behavior.tapTimeout, 220) // 200 + 20
        XCTAssertEqual(behavior.holdTimeout, 160) // 150 + 10
        XCTAssertTrue(behavior.useOppositeHand)
    }

    func testOppositeHandActivation_LayerToggleMode() {
        let config = HomeRowModsConfig(
            enabledKeys: ["a"],
            layerAssignments: ["a": "nav"],
            holdMode: .layers,
            layerToggleMode: .whileHeld,
            oppositeHandMode: .press
        )

        let mappings = KanataConfiguration.generateHomeRowModsMappings(from: config)
        guard case let .dualRole(behavior)? = mappings.first?.behavior else {
            return XCTFail("Expected dualRole behavior")
        }

        XCTAssertEqual(behavior.holdAction, "(layer-while-held nav)")
        XCTAssertTrue(behavior.useOppositeHand)
    }

    func testOppositeHandActivation_LeftOnlyKeySelection() {
        let config = HomeRowModsConfig(
            enabledKeys: Set(HomeRowModsConfig.leftHandKeys),
            modifierAssignments: HomeRowModsConfig.cagsMacDefault,
            holdMode: .modifiers,
            keySelection: .leftOnly,
            oppositeHandMode: .press
        )

        let mappings = KanataConfiguration.generateHomeRowModsMappings(from: config)
        for mapping in mappings {
            guard case let .dualRole(behavior)? = mapping.behavior else {
                XCTFail("Expected dualRole behavior"); continue
            }
            XCTAssertTrue(behavior.useOppositeHand)
        }
    }

    func testLayerTogglesMappings_OppositeHandActivation() {
        let config = HomeRowLayerTogglesConfig(
            enabledKeys: ["a", "j"],
            layerAssignments: ["a": "nav", "j": "sym"],
            oppositeHandMode: .press
        )

        let mappings = KanataConfiguration.generateHomeRowLayerTogglesMappings(from: config)
        XCTAssertEqual(mappings.count, 2)

        for mapping in mappings {
            guard case let .dualRole(behavior)? = mapping.behavior else {
                XCTFail("Expected dualRole behavior"); continue
            }
            XCTAssertTrue(behavior.useOppositeHand)
            XCTAssertTrue(behavior.customTapKeys.isEmpty)
        }
    }

    // MARK: - Full Round-Trip Tests

    func testFullRoundTrip_OppositeHandOn_AllEightKeys() {
        let config = HomeRowModsConfig(
            enabledKeys: Set(HomeRowModsConfig.allKeys),
            modifierAssignments: HomeRowModsConfig.cagsMacDefault,
            holdMode: .modifiers,
            oppositeHandMode: .press
        )

        let mappings = KanataConfiguration.generateHomeRowModsMappings(from: config)
        XCTAssertEqual(mappings.count, 8)

        for mapping in mappings {
            let rendered = KanataBehaviorRenderer.render(mapping)
            XCTAssertTrue(
                rendered.contains("tap-hold-opposite-hand"),
                "Should use tap-hold-opposite-hand: \(rendered)"
            )
        }
    }

    func testFullRoundTrip_OppositeHandOff_AllProduceTapHoldPress() {
        let config = HomeRowModsConfig(
            enabledKeys: Set(HomeRowModsConfig.allKeys),
            modifierAssignments: HomeRowModsConfig.cagsMacDefault,
            holdMode: .modifiers,
            oppositeHandMode: .off
        )

        let mappings = KanataConfiguration.generateHomeRowModsMappings(from: config)
        for mapping in mappings {
            let rendered = KanataBehaviorRenderer.render(mapping)
            XCTAssertTrue(rendered.hasPrefix("(tap-hold-press"), "Should use tap-hold-press: \(rendered)")
        }
    }

    // MARK: - End-to-End Rendering (generate → render → verify valid kanata syntax)

    func testLayersModeWhileHeld_RendersValidKanataSyntax() {
        let config = HomeRowModsConfig(
            enabledKeys: ["a", "s", "d", "f"],
            modifierAssignments: ["a": "lmet", "s": "lalt", "d": "lsft", "f": "lctl"],
            layerAssignments: ["a": "nav", "s": "sym", "d": "num", "f": "fun"],
            holdMode: .layers,
            layerToggleMode: .whileHeld,
            oppositeHandMode: .off
        )

        let mappings = KanataConfiguration.generateHomeRowModsMappings(from: config)
        XCTAssertEqual(mappings.count, 4)

        let allRendered = mappings.map { KanataBehaviorRenderer.render($0) }

        for rendered in allRendered {
            XCTAssertTrue(rendered.contains("tap-hold-press"), "Should use tap-hold-press: \(rendered)")
            XCTAssertTrue(rendered.contains("layer-while-held"), "Should use layer-while-held: \(rendered)")
            XCTAssertFalse(rendered.contains("lpar"), "Should not mangle to lpar: \(rendered)")
            XCTAssertFalse(rendered.contains("rpar"), "Should not mangle to rpar: \(rendered)")
        }

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
            layerToggleMode: .toggle,
            oppositeHandMode: .off
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
        let config = HomeRowModsConfig(
            enabledKeys: ["a"],
            modifierAssignments: ["a": "lmet"],
            layerAssignments: ["a": "nav"],
            holdMode: .modifiers,
            layerToggleMode: .whileHeld,
            oppositeHandMode: .off
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
