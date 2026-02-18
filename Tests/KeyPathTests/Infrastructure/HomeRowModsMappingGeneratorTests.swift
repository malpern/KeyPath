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
            splitHandDetection: false
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
            splitHandDetection: false
        )

        let mappings = KanataConfiguration.generateHomeRowModsMappings(from: config)
        XCTAssertEqual(mappings.count, 1)
        guard case let .dualRole(behavior)? = mappings.first?.behavior else {
            return XCTFail("Expected dualRole behavior")
        }

        XCTAssertEqual(behavior.tapAction, "a")
        XCTAssertEqual(behavior.holdAction, "(layer-toggle nav)")
    }

    // MARK: - Split-Hand Detection

    func testSplitHandDetectionTrue_PopulatesLeftHandKeys() {
        let config = HomeRowModsConfig(
            enabledKeys: ["a"],
            modifierAssignments: ["a": "lsft"],
            holdMode: .modifiers,
            splitHandDetection: true
        )

        let mappings = KanataConfiguration.generateHomeRowModsMappings(from: config)
        guard case let .dualRole(behavior)? = mappings.first?.behavior else {
            return XCTFail("Expected dualRole behavior")
        }

        XCTAssertEqual(behavior.customTapKeys, HomeRowModsConfig.leftHandAllKeys)
        XCTAssertFalse(behavior.activateHoldOnOtherKey)
    }

    func testSplitHandDetectionTrue_PopulatesRightHandKeys() {
        let config = HomeRowModsConfig(
            enabledKeys: ["j"],
            modifierAssignments: ["j": "rmet"],
            holdMode: .modifiers,
            splitHandDetection: true
        )

        let mappings = KanataConfiguration.generateHomeRowModsMappings(from: config)
        guard case let .dualRole(behavior)? = mappings.first?.behavior else {
            return XCTFail("Expected dualRole behavior")
        }

        XCTAssertEqual(behavior.customTapKeys, HomeRowModsConfig.rightHandAllKeys)
        XCTAssertFalse(behavior.activateHoldOnOtherKey)
    }

    func testSplitHandDetectionFalse_LeavesCustomTapKeysEmpty() {
        let config = HomeRowModsConfig(
            enabledKeys: ["a"],
            modifierAssignments: ["a": "lsft"],
            holdMode: .modifiers,
            splitHandDetection: false
        )

        let mappings = KanataConfiguration.generateHomeRowModsMappings(from: config)
        guard case let .dualRole(behavior)? = mappings.first?.behavior else {
            return XCTFail("Expected dualRole behavior")
        }

        XCTAssertTrue(behavior.customTapKeys.isEmpty)
        XCTAssertTrue(behavior.activateHoldOnOtherKey)
    }

    func testSplitHandDetection_PerKeyTimingOffsetsStillApply() {
        var timing = TimingConfig.default
        timing.tapOffsets = ["a": 20]
        timing.holdOffsets = ["a": 10]

        let config = HomeRowModsConfig(
            enabledKeys: ["a"],
            modifierAssignments: ["a": "lsft"],
            holdMode: .modifiers,
            timing: timing,
            splitHandDetection: true
        )

        let mappings = KanataConfiguration.generateHomeRowModsMappings(from: config)
        guard case let .dualRole(behavior)? = mappings.first?.behavior else {
            return XCTFail("Expected dualRole behavior")
        }

        XCTAssertEqual(behavior.tapTimeout, 220) // 200 + 20
        XCTAssertEqual(behavior.holdTimeout, 160) // 150 + 10
        XCTAssertEqual(behavior.customTapKeys, HomeRowModsConfig.leftHandAllKeys)
    }

    func testSplitHandDetection_LayerToggleMode() {
        let config = HomeRowModsConfig(
            enabledKeys: ["a"],
            layerAssignments: ["a": "nav"],
            holdMode: .layers,
            layerToggleMode: .whileHeld,
            splitHandDetection: true
        )

        let mappings = KanataConfiguration.generateHomeRowModsMappings(from: config)
        guard case let .dualRole(behavior)? = mappings.first?.behavior else {
            return XCTFail("Expected dualRole behavior")
        }

        XCTAssertEqual(behavior.holdAction, "(layer-while-held nav)")
        XCTAssertEqual(behavior.customTapKeys, HomeRowModsConfig.leftHandAllKeys)
    }

    func testSplitHandDetection_LeftOnlyKeySelection() {
        let config = HomeRowModsConfig(
            enabledKeys: Set(HomeRowModsConfig.leftHandKeys),
            modifierAssignments: HomeRowModsConfig.cagsMacDefault,
            holdMode: .modifiers,
            keySelection: .leftOnly,
            splitHandDetection: true
        )

        let mappings = KanataConfiguration.generateHomeRowModsMappings(from: config)
        // All left-hand keys should get left-hand customTapKeys
        for mapping in mappings {
            guard case let .dualRole(behavior)? = mapping.behavior else {
                XCTFail("Expected dualRole behavior"); continue
            }
            XCTAssertEqual(behavior.customTapKeys, HomeRowModsConfig.leftHandAllKeys)
        }
    }

    func testLayerTogglesMappings_SplitHandDetection() {
        let config = HomeRowLayerTogglesConfig(
            enabledKeys: ["a", "j"],
            layerAssignments: ["a": "nav", "j": "sym"],
            splitHandDetection: true
        )

        let mappings = KanataConfiguration.generateHomeRowLayerTogglesMappings(from: config)
        XCTAssertEqual(mappings.count, 2)

        for mapping in mappings {
            guard case let .dualRole(behavior)? = mapping.behavior else {
                XCTFail("Expected dualRole behavior"); continue
            }
            if mapping.input == "a" {
                XCTAssertEqual(behavior.customTapKeys, HomeRowModsConfig.leftHandAllKeys)
            } else {
                XCTAssertEqual(behavior.customTapKeys, HomeRowModsConfig.rightHandAllKeys)
            }
        }
    }

    // MARK: - Full Round-Trip Tests

    func testFullRoundTrip_SplitHandOn_AllEightKeys() {
        let config = HomeRowModsConfig(
            enabledKeys: Set(HomeRowModsConfig.allKeys),
            modifierAssignments: HomeRowModsConfig.cagsMacDefault,
            holdMode: .modifiers,
            splitHandDetection: true
        )

        let mappings = KanataConfiguration.generateHomeRowModsMappings(from: config)
        XCTAssertEqual(mappings.count, 8)

        let leftKeys = "q w e r t a s d f g z x c v b"
        let rightKeys = "y u i o p h j k l ; n m , . /"

        for mapping in mappings {
            let rendered = KanataBehaviorRenderer.render(mapping)
            XCTAssertTrue(rendered.hasPrefix("(tap-hold-release-keys"), "Should use tap-hold-release-keys: \(rendered)")

            let isLeftKey = HomeRowModsConfig.leftHandKeys.contains(mapping.input)
            let expectedKeyList = isLeftKey ? leftKeys : rightKeys
            XCTAssertTrue(rendered.contains("(\(expectedKeyList))"), "Wrong key list for \(mapping.input): \(rendered)")
        }
    }

    func testFullRoundTrip_SplitHandOff_AllProduceTapHoldPress() {
        let config = HomeRowModsConfig(
            enabledKeys: Set(HomeRowModsConfig.allKeys),
            modifierAssignments: HomeRowModsConfig.cagsMacDefault,
            holdMode: .modifiers,
            splitHandDetection: false
        )

        let mappings = KanataConfiguration.generateHomeRowModsMappings(from: config)
        for mapping in mappings {
            let rendered = KanataBehaviorRenderer.render(mapping)
            XCTAssertTrue(rendered.hasPrefix("(tap-hold-press"), "Should use tap-hold-press: \(rendered)")
        }
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
            layerToggleMode: .whileHeld,
            splitHandDetection: false
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
            layerToggleMode: .toggle,
            splitHandDetection: false
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
            layerToggleMode: .whileHeld,
            splitHandDetection: false
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
