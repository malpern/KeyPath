@testable import KeyPathAppKit
import XCTest

/// Tests for remap output suppression in KeyboardVisualizationViewModel.
/// Verifies that when a simple remap (A→B) is active, pressing physical A
/// does not cause physical B to light up on the overlay.
@MainActor
final class RemapOutputSuppressionTests: XCTestCase {
    // MARK: - buildRemapOutputMap Tests

    func testBuildRemapOutputMap_SimpleRemap_ReturnsCorrectMapping() {
        // Given: A→B mapping (keyCode 0 → keyCode 11)
        var layerKeyMap: [UInt16: LayerKeyInfo] = [:]
        layerKeyMap[0] = LayerKeyInfo(
            displayLabel: "B",
            outputKey: "b",
            outputKeyCode: 11,
            isTransparent: false,
            isLayerSwitch: false,
            appLaunchIdentifier: nil,
            systemActionIdentifier: nil,
            urlIdentifier: nil
        )

        // When: Build the remap output map
        let remapMap = buildRemapOutputMap(from: layerKeyMap)

        // Then: Should map input keyCode 0 to output keyCode 11
        XCTAssertEqual(remapMap[0], 11, "A (0) should map to B (11)")
    }

    func testBuildRemapOutputMap_IdentityMapping_NotIncluded() {
        // Given: A→A mapping (no actual remap)
        var layerKeyMap: [UInt16: LayerKeyInfo] = [:]
        layerKeyMap[0] = LayerKeyInfo(
            displayLabel: "A",
            outputKey: "a",
            outputKeyCode: 0, // Same as input
            isTransparent: false,
            isLayerSwitch: false,
            appLaunchIdentifier: nil,
            systemActionIdentifier: nil,
            urlIdentifier: nil
        )

        // When: Build the remap output map
        let remapMap = buildRemapOutputMap(from: layerKeyMap)

        // Then: A→A should not be in the map (not a remap)
        XCTAssertNil(remapMap[0], "Identity mapping should not be in remap map")
    }

    func testBuildRemapOutputMap_TransparentKey_NotIncluded() {
        // Given: Transparent key (passes through)
        var layerKeyMap: [UInt16: LayerKeyInfo] = [:]
        layerKeyMap[0] = LayerKeyInfo(
            displayLabel: "_",
            outputKey: nil,
            outputKeyCode: nil,
            isTransparent: true, // Transparent
            isLayerSwitch: false,
            appLaunchIdentifier: nil,
            systemActionIdentifier: nil,
            urlIdentifier: nil
        )

        // When: Build the remap output map
        let remapMap = buildRemapOutputMap(from: layerKeyMap)

        // Then: Transparent key should not be in the map
        XCTAssertNil(remapMap[0], "Transparent key should not be in remap map")
    }

    func testBuildRemapOutputMap_NoOutputKeyCode_NotIncluded() {
        // Given: Action without output keyCode (like app launch)
        var layerKeyMap: [UInt16: LayerKeyInfo] = [:]
        layerKeyMap[0] = LayerKeyInfo(
            displayLabel: "Safari",
            outputKey: nil,
            outputKeyCode: nil, // No output keyCode
            isTransparent: false,
            isLayerSwitch: false,
            appLaunchIdentifier: "com.apple.Safari",
            systemActionIdentifier: nil,
            urlIdentifier: nil
        )

        // When: Build the remap output map
        let remapMap = buildRemapOutputMap(from: layerKeyMap)

        // Then: No keyCode in map when there's no output keyCode
        XCTAssertNil(remapMap[0], "Action without output keyCode should not be in remap map")
    }

    func testBuildRemapOutputMap_MultipleRemaps() {
        // Given: Multiple remaps A→B, S→D, D→F
        var layerKeyMap: [UInt16: LayerKeyInfo] = [:]
        layerKeyMap[0] = LayerKeyInfo(
            displayLabel: "B", outputKey: "b", outputKeyCode: 11,
            isTransparent: false, isLayerSwitch: false,
            appLaunchIdentifier: nil, systemActionIdentifier: nil, urlIdentifier: nil
        )
        layerKeyMap[1] = LayerKeyInfo(
            displayLabel: "D", outputKey: "d", outputKeyCode: 2,
            isTransparent: false, isLayerSwitch: false,
            appLaunchIdentifier: nil, systemActionIdentifier: nil, urlIdentifier: nil
        )
        layerKeyMap[2] = LayerKeyInfo(
            displayLabel: "F", outputKey: "f", outputKeyCode: 3,
            isTransparent: false, isLayerSwitch: false,
            appLaunchIdentifier: nil, systemActionIdentifier: nil, urlIdentifier: nil
        )

        // When: Build the remap output map
        let remapMap = buildRemapOutputMap(from: layerKeyMap)

        // Then: All remaps should be in the map
        XCTAssertEqual(remapMap.count, 3, "Should have 3 remaps")
        XCTAssertEqual(remapMap[0], 11, "A→B")
        XCTAssertEqual(remapMap[1], 2, "S→D")
        XCTAssertEqual(remapMap[2], 3, "D→F")
    }

    // MARK: - suppressedRemapOutputKeyCodes Tests

    func testSuppressedRemapOutputKeyCodes_WhenInputPressed_SuppressesOutput() {
        // Given: A→B mapping, A (keyCode 0) is pressed
        let remapOutputMap: [UInt16: UInt16] = [0: 11]
        let tcpPressedKeyCodes: Set<UInt16> = [0] // A is pressed

        // When: Calculate suppressed keyCodes
        let suppressed = calculateSuppressedRemapOutputKeyCodes(
            tcpPressedKeyCodes: tcpPressedKeyCodes,
            remapOutputMap: remapOutputMap
        )

        // Then: B (11) should be suppressed
        XCTAssertTrue(suppressed.contains(11), "B should be suppressed when A is pressed")
    }

    func testSuppressedRemapOutputKeyCodes_WhenInputNotPressed_NothingSuppressed() {
        // Given: A→B mapping, A is NOT pressed
        let remapOutputMap: [UInt16: UInt16] = [0: 11]
        let tcpPressedKeyCodes: Set<UInt16> = [] // Nothing pressed

        // When: Calculate suppressed keyCodes
        let suppressed = calculateSuppressedRemapOutputKeyCodes(
            tcpPressedKeyCodes: tcpPressedKeyCodes,
            remapOutputMap: remapOutputMap
        )

        // Then: Nothing should be suppressed
        XCTAssertTrue(suppressed.isEmpty, "Nothing should be suppressed when A is not pressed")
    }

    func testSuppressedRemapOutputKeyCodes_MultipleInputsPressed() {
        // Given: A→B and S→D mappings, both A and S pressed
        let remapOutputMap: [UInt16: UInt16] = [0: 11, 1: 2]
        let tcpPressedKeyCodes: Set<UInt16> = [0, 1] // A and S pressed

        // When: Calculate suppressed keyCodes
        let suppressed = calculateSuppressedRemapOutputKeyCodes(
            tcpPressedKeyCodes: tcpPressedKeyCodes,
            remapOutputMap: remapOutputMap
        )

        // Then: Both B (11) and D (2) should be suppressed
        XCTAssertTrue(suppressed.contains(11), "B should be suppressed")
        XCTAssertTrue(suppressed.contains(2), "D should be suppressed")
        XCTAssertEqual(suppressed.count, 2)
    }

    func testSuppressedRemapOutputKeyCodes_UnmappedKeyPressed_NothingSuppressed() {
        // Given: A→B mapping, Z (not remapped) is pressed
        let remapOutputMap: [UInt16: UInt16] = [0: 11]
        let tcpPressedKeyCodes: Set<UInt16> = [6] // Z pressed (keyCode 6)

        // When: Calculate suppressed keyCodes
        let suppressed = calculateSuppressedRemapOutputKeyCodes(
            tcpPressedKeyCodes: tcpPressedKeyCodes,
            remapOutputMap: remapOutputMap
        )

        // Then: Nothing should be suppressed (Z has no remap)
        XCTAssertTrue(suppressed.isEmpty, "Nothing suppressed when pressing unmapped key")
    }

    // MARK: - Helper Functions (mirror the ViewModel logic for testing)

    private func buildRemapOutputMap(from mapping: [UInt16: LayerKeyInfo]) -> [UInt16: UInt16] {
        var result: [UInt16: UInt16] = [:]
        for (inputKeyCode, info) in mapping {
            guard let outputKeyCode = info.outputKeyCode,
                  outputKeyCode != inputKeyCode,
                  !info.isTransparent
            else {
                continue
            }
            result[inputKeyCode] = outputKeyCode
        }
        return result
    }

    private func calculateSuppressedRemapOutputKeyCodes(
        tcpPressedKeyCodes: Set<UInt16>,
        remapOutputMap: [UInt16: UInt16]
    ) -> Set<UInt16> {
        tcpPressedKeyCodes.reduce(into: Set<UInt16>()) { result, inputKeyCode in
            if let outputKeyCode = remapOutputMap[inputKeyCode] {
                result.insert(outputKeyCode)
            }
        }
    }
}
