@testable import KeyPathAppKit
import XCTest

@MainActor
final class HomeRowModsConfigTests: XCTestCase {
    func testDefaultMappingUsesMacCAGS() {
        let config = HomeRowModsConfig()
        XCTAssertEqual(config.modifierAssignments["a"], "lsft")
        XCTAssertEqual(config.modifierAssignments["s"], "lctl")
        XCTAssertEqual(config.modifierAssignments["d"], "lalt")
        XCTAssertEqual(config.modifierAssignments["f"], "lmet")
        XCTAssertEqual(config.modifierAssignments["j"], "rmet")
        XCTAssertEqual(config.modifierAssignments["k"], "ralt")
        XCTAssertEqual(config.modifierAssignments["l"], "rctl")
        XCTAssertEqual(config.modifierAssignments[";"], "rsft")
    }

    func testTimingDefaultsDisableQuickTapAndOffsets() {
        let timing = HomeRowModsConfig().timing
        XCTAssertFalse(timing.quickTapEnabled)
        XCTAssertTrue(timing.tapOffsets.isEmpty)
        XCTAssertEqual(timing.quickTapTermMs, 0)
    }

    func testLegacyDecodingDefaultsNewFields() throws {
        let legacyJSON = """
        {
          "enabledKeys": ["a","s","d","f","j","k","l",";"],
          "modifierAssignments": {
            "a":"lsft","s":"lctl","d":"lalt","f":"lmet",
            "j":"rmet","k":"ralt","l":"rctl",";":"rsft"
          },
          "timing": {
            "tapWindow": 200,
            "holdDelay": 150,
            "quickTapEnabled": false,
            "quickTapTermMs": 0,
            "tapOffsets": {},
            "holdOffsets": {}
          },
          "keySelection": "both",
          "showAdvanced": false
        }
        """

        let data = try XCTUnwrap(legacyJSON.data(using: .utf8))
        let decoded = try JSONDecoder().decode(HomeRowModsConfig.self, from: data)

        XCTAssertEqual(decoded.holdMode, .modifiers)
        XCTAssertEqual(decoded.layerToggleMode, .whileHeld)
        XCTAssertEqual(decoded.layerAssignments, HomeRowModsConfig.defaultLayerAssignments)
    }

    func testNewLayerAssignmentNormalizesAndAssignsPendingKey() {
        var config = HomeRowModsConfig(holdMode: .layers)

        HomeRowModsNewLayerAssignment.assign(layerName: " QA-Temp ", to: "a", config: &config)

        XCTAssertEqual(config.layerAssignments["a"], "qa-temp")
    }

    func testNewLayerAssignmentIgnoresBlankLayerName() {
        var config = HomeRowModsConfig(holdMode: .layers)
        let original = config.layerAssignments["a"]

        HomeRowModsNewLayerAssignment.assign(layerName: "   ", to: "a", config: &config)

        XCTAssertEqual(config.layerAssignments["a"], original)
    }

    func testEnableKeyPreservesCustomLayerAssignment() {
        var config = HomeRowModsConfig(holdMode: .layers)
        config.layerAssignments["a"] = "nav"
        config.enabledKeys.remove("a")

        config.enableKeyPreservingAssignment("a")

        XCTAssertTrue(config.enabledKeys.contains("a"))
        XCTAssertEqual(config.layerAssignments["a"], "nav")
        XCTAssertEqual(config.keySelection, .custom)
    }

    func testEnableKeyRestoresFallbackOnlyWhenAssignmentMissing() {
        var config = HomeRowModsConfig(holdMode: .layers)
        config.layerAssignments["a"] = nil
        config.enabledKeys.remove("a")

        config.enableKeyPreservingAssignment("a")

        XCTAssertTrue(config.enabledKeys.contains("a"))
        XCTAssertEqual(config.layerAssignments["a"], HomeRowModsConfig.defaultLayerAssignments["a"])
    }
}
