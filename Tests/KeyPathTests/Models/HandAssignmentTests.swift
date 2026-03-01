@testable import KeyPathAppKit
import XCTest

final class HandAssignmentTests: XCTestCase {
    // MARK: - QWERTY Default

    func testQwertyDefaultHas15LeftKeys() {
        XCTAssertEqual(HandAssignment.qwertyDefault.leftKeys.count, 15)
    }

    func testQwertyDefaultHas15RightKeys() {
        XCTAssertEqual(HandAssignment.qwertyDefault.rightKeys.count, 15)
    }

    func testQwertyDefaultLeftKeysAreCorrect() {
        let expected = [
            "q", "w", "e", "r", "t",
            "a", "s", "d", "f", "g",
            "z", "x", "c", "v", "b",
        ]
        XCTAssertEqual(HandAssignment.qwertyDefault.leftKeys, expected)
    }

    func testQwertyDefaultRightKeysAreCorrect() {
        let expected = [
            "y", "u", "i", "o", "p",
            "h", "j", "k", "l", ";",
            "n", "m", ",", ".", "/",
        ]
        XCTAssertEqual(HandAssignment.qwertyDefault.rightKeys, expected)
    }

    // MARK: - Standard Keyboard Derivation

    func testDeriveFromMacBookUS_MatchesQwertyDefault() {
        let assignment = HandAssignment.derive(from: .macBookUS)
        XCTAssertEqual(assignment, HandAssignment.qwertyDefault)
    }

    func testDeriveFromANSI60Percent_MatchesQwertyDefault() {
        let assignment = HandAssignment.derive(from: .ansi60Percent)
        XCTAssertEqual(assignment, HandAssignment.qwertyDefault)
    }

    func testDeriveFromANSI100Percent_MatchesQwertyDefault() {
        let assignment = HandAssignment.derive(from: .ansi100Percent)
        XCTAssertEqual(assignment, HandAssignment.qwertyDefault)
    }

    func testAllStandardLayoutsProduceSameResult() {
        // Position-based derivation means all standard layouts produce the same result
        for layout in PhysicalLayout.usLayouts {
            let assignment = HandAssignment.derive(from: layout)
            XCTAssertEqual(
                assignment, HandAssignment.qwertyDefault,
                "Layout '\(layout.name)' should match qwertyDefault"
            )
        }
    }

    // MARK: - Split Keyboard Derivation

    func testDeriveFromCorne_SplitsViaGapDetection() {
        let assignment = HandAssignment.derive(from: .corne)
        // Corne is a 3x6 split; should have 15 keys per hand (3 rows × 5 columns for alpha)
        // The exact count depends on how many alpha keys are on the corne layout
        XCTAssertFalse(assignment.leftKeys.isEmpty, "Corne should have left-hand keys")
        XCTAssertFalse(assignment.rightKeys.isEmpty, "Corne should have right-hand keys")

        // Left hand should not contain right-hand keys
        let leftSet = Set(assignment.leftKeys)
        let rightSet = Set(assignment.rightKeys)
        XCTAssertTrue(leftSet.isDisjoint(with: rightSet), "Left and right should not overlap")
    }

    func testDeriveFromKinesisAdvantage360_SplitsCorrectly() {
        let assignment = HandAssignment.derive(from: .kinesisAdvantage360)
        XCTAssertFalse(assignment.leftKeys.isEmpty, "Kinesis should have left-hand keys")
        XCTAssertFalse(assignment.rightKeys.isEmpty, "Kinesis should have right-hand keys")

        // Left and right should not overlap
        let leftSet = Set(assignment.leftKeys)
        let rightSet = Set(assignment.rightKeys)
        XCTAssertTrue(leftSet.isDisjoint(with: rightSet), "Left and right should not overlap")
    }

    // MARK: - Backward Compatibility

    // MARK: - Codable Migration (splitHandDetection → oppositeHandActivation)

    func testHomeRowModsConfig_DecodesLegacySplitHandDetection() throws {
        let json = """
        {
            "enabledKeys": ["a"],
            "modifierAssignments": {"a": "lsft"},
            "holdMode": "modifiers",
            "splitHandDetection": true
        }
        """.data(using: .utf8)!
        let config = try JSONDecoder().decode(HomeRowModsConfig.self, from: json)
        XCTAssertTrue(config.oppositeHandActivation, "Legacy splitHandDetection:true should map to oppositeHandActivation:true")
    }

    func testHomeRowModsConfig_DecodesLegacySplitHandDetectionFalse() throws {
        let json = """
        {
            "enabledKeys": ["a"],
            "modifierAssignments": {"a": "lsft"},
            "holdMode": "modifiers",
            "splitHandDetection": false
        }
        """.data(using: .utf8)!
        let config = try JSONDecoder().decode(HomeRowModsConfig.self, from: json)
        XCTAssertFalse(config.oppositeHandActivation, "Legacy splitHandDetection:false should map to oppositeHandActivation:false")
    }

    func testHomeRowModsConfig_PrefersNewKeyOverLegacy() throws {
        let json = """
        {
            "enabledKeys": ["a"],
            "modifierAssignments": {"a": "lsft"},
            "holdMode": "modifiers",
            "oppositeHandActivation": false,
            "splitHandDetection": true
        }
        """.data(using: .utf8)!
        let config = try JSONDecoder().decode(HomeRowModsConfig.self, from: json)
        XCTAssertFalse(config.oppositeHandActivation, "New key should take precedence over legacy key")
    }

    func testHomeRowModsConfig_DefaultsTrueWhenNeitherKeyPresent() throws {
        let json = """
        {
            "enabledKeys": ["a"],
            "modifierAssignments": {"a": "lsft"},
            "holdMode": "modifiers"
        }
        """.data(using: .utf8)!
        let config = try JSONDecoder().decode(HomeRowModsConfig.self, from: json)
        XCTAssertTrue(config.oppositeHandActivation, "Should default to true when neither key is present")
    }

    func testHomeRowLayerTogglesConfig_DecodesLegacySplitHandDetection() throws {
        let json = """
        {
            "enabledKeys": ["a"],
            "layerAssignments": {"a": "nav"},
            "splitHandDetection": false
        }
        """.data(using: .utf8)!
        let config = try JSONDecoder().decode(HomeRowLayerTogglesConfig.self, from: json)
        XCTAssertFalse(config.oppositeHandActivation, "Legacy splitHandDetection should migrate to oppositeHandActivation")
    }

    func testHomeRowModsConfig_EncodesOnlyNewKey() throws {
        let config = HomeRowModsConfig(oppositeHandActivation: true)
        let data = try JSONEncoder().encode(config)
        let json = try JSONSerialization.jsonObject(with: data) as! [String: Any]
        XCTAssertNotNil(json["oppositeHandActivation"], "Should encode oppositeHandActivation")
        XCTAssertNil(json["splitHandDetection"], "Should not encode legacy splitHandDetection")
    }

    func testQwertyDefaultMatchesOldStaticProperties() {
        // Verify that qwertyDefault matches the old HomeRowModsConfig static lists
        // This ensures backward compatibility when migrating from the old approach
        let oldLeft = [
            "q", "w", "e", "r", "t",
            "a", "s", "d", "f", "g",
            "z", "x", "c", "v", "b",
        ]
        let oldRight = [
            "y", "u", "i", "o", "p",
            "h", "j", "k", "l", ";",
            "n", "m", ",", ".", "/",
        ]
        XCTAssertEqual(HandAssignment.qwertyDefault.leftKeys, oldLeft)
        XCTAssertEqual(HandAssignment.qwertyDefault.rightKeys, oldRight)
    }
}
