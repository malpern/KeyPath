import XCTest

@testable import KeyPathAppKit

/// Tests for LayerKeyInfo data extraction used in OverlayMapperSection.
/// Verifies that action identifiers are correctly extracted and passed to the mapper.
@MainActor
final class LayerKeyInfoExtractionTests: XCTestCase {
    // MARK: - LayerKeyInfo Field Extraction

    func testLayerKeyInfo_WithDisplayLabel_ReturnsCorrectLabel() {
        let info = LayerKeyInfo(
            displayLabel: "B",
            outputKey: "b",
            outputKeyCode: 11,
            isTransparent: false,
            isLayerSwitch: false,
            appLaunchIdentifier: nil,
            systemActionIdentifier: nil,
            urlIdentifier: nil
        )

        XCTAssertEqual(info.displayLabel, "B")
        XCTAssertEqual(info.outputKey, "b")
    }

    func testLayerKeyInfo_WithAppLaunchIdentifier_ReturnsIdentifier() {
        let info = LayerKeyInfo(
            displayLabel: "Safari",
            outputKey: nil,
            outputKeyCode: nil,
            isTransparent: false,
            isLayerSwitch: false,
            appLaunchIdentifier: "com.apple.Safari",
            systemActionIdentifier: nil,
            urlIdentifier: nil
        )

        XCTAssertEqual(info.appLaunchIdentifier, "com.apple.Safari")
        XCTAssertNil(info.systemActionIdentifier)
        XCTAssertNil(info.urlIdentifier)
    }

    func testLayerKeyInfo_WithSystemActionIdentifier_ReturnsIdentifier() {
        let info = LayerKeyInfo(
            displayLabel: "Spotlight",
            outputKey: nil,
            outputKeyCode: nil,
            isTransparent: false,
            isLayerSwitch: false,
            appLaunchIdentifier: nil,
            systemActionIdentifier: "spotlight",
            urlIdentifier: nil
        )

        XCTAssertEqual(info.systemActionIdentifier, "spotlight")
        XCTAssertNil(info.appLaunchIdentifier)
        XCTAssertNil(info.urlIdentifier)
    }

    func testLayerKeyInfo_WithURLIdentifier_ReturnsIdentifier() {
        let info = LayerKeyInfo(
            displayLabel: "github.com",
            outputKey: nil,
            outputKeyCode: nil,
            isTransparent: false,
            isLayerSwitch: false,
            appLaunchIdentifier: nil,
            systemActionIdentifier: nil,
            urlIdentifier: "https://github.com"
        )

        XCTAssertEqual(info.urlIdentifier, "https://github.com")
        XCTAssertNil(info.appLaunchIdentifier)
        XCTAssertNil(info.systemActionIdentifier)
    }

    // MARK: - Layer Key Map Lookup Simulation

    func testLayerKeyMapLookup_ReturnsCorrectInfo() {
        // Simulate a layer key map like what OverlayMapperSection receives
        var layerKeyMap: [UInt16: LayerKeyInfo] = [:]

        // A key (keyCode 0) remapped to B
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

        // S key (keyCode 1) mapped to Spotlight
        layerKeyMap[1] = LayerKeyInfo(
            displayLabel: "Spotlight",
            outputKey: nil,
            outputKeyCode: nil,
            isTransparent: false,
            isLayerSwitch: false,
            appLaunchIdentifier: nil,
            systemActionIdentifier: "spotlight",
            urlIdentifier: nil
        )

        // D key (keyCode 2) mapped to Safari launch
        layerKeyMap[2] = LayerKeyInfo(
            displayLabel: "Safari",
            outputKey: nil,
            outputKeyCode: nil,
            isTransparent: false,
            isLayerSwitch: false,
            appLaunchIdentifier: "com.apple.Safari",
            systemActionIdentifier: nil,
            urlIdentifier: nil
        )

        // F key (keyCode 3) mapped to GitHub URL
        layerKeyMap[3] = LayerKeyInfo(
            displayLabel: "github.com",
            outputKey: nil,
            outputKeyCode: nil,
            isTransparent: false,
            isLayerSwitch: false,
            appLaunchIdentifier: nil,
            systemActionIdentifier: nil,
            urlIdentifier: "https://github.com"
        )

        // Verify lookups
        let aInfo = layerKeyMap[0]
        XCTAssertNotNil(aInfo)
        XCTAssertEqual(aInfo?.displayLabel, "B")
        XCTAssertNil(aInfo?.appLaunchIdentifier)

        let sInfo = layerKeyMap[1]
        XCTAssertNotNil(sInfo)
        XCTAssertEqual(sInfo?.systemActionIdentifier, "spotlight")

        let dInfo = layerKeyMap[2]
        XCTAssertNotNil(dInfo)
        XCTAssertEqual(dInfo?.appLaunchIdentifier, "com.apple.Safari")

        let fInfo = layerKeyMap[3]
        XCTAssertNotNil(fInfo)
        XCTAssertEqual(fInfo?.urlIdentifier, "https://github.com")
    }

    func testLayerKeyMapLookup_MissingKey_ReturnsNil() {
        let layerKeyMap: [UInt16: LayerKeyInfo] = [:]

        // Key not in map should return nil
        let info = layerKeyMap[0]
        XCTAssertNil(info, "Missing key should return nil")
    }

    // MARK: - Default Value Extraction (simulating onAppear logic)

    func testDefaultKeyExtraction_WithRemapping() {
        // Simulate the logic in OverlayMapperSection.onAppear
        var layerKeyMap: [UInt16: LayerKeyInfo] = [:]

        // A key remapped to B
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

        let defaultKeyCode: UInt16 = 0
        let layerInfo = layerKeyMap[defaultKeyCode]
        let outputLabel = layerInfo?.displayLabel.lowercased() ?? "a"
        let appId = layerInfo?.appLaunchIdentifier
        let systemId = layerInfo?.systemActionIdentifier
        let urlId = layerInfo?.urlIdentifier

        XCTAssertEqual(outputLabel, "b", "Output should be 'b' from remapping")
        XCTAssertNil(appId)
        XCTAssertNil(systemId)
        XCTAssertNil(urlId)
    }

    func testDefaultKeyExtraction_WithSystemAction() {
        var layerKeyMap: [UInt16: LayerKeyInfo] = [:]

        // A key mapped to Spotlight
        layerKeyMap[0] = LayerKeyInfo(
            displayLabel: "Spotlight",
            outputKey: nil,
            outputKeyCode: nil,
            isTransparent: false,
            isLayerSwitch: false,
            appLaunchIdentifier: nil,
            systemActionIdentifier: "spotlight",
            urlIdentifier: nil
        )

        let defaultKeyCode: UInt16 = 0
        let layerInfo = layerKeyMap[defaultKeyCode]
        let outputLabel = layerInfo?.displayLabel.lowercased() ?? "a"
        let systemId = layerInfo?.systemActionIdentifier

        XCTAssertEqual(outputLabel, "spotlight")
        XCTAssertEqual(systemId, "spotlight", "System action ID should be extracted")
    }

    func testDefaultKeyExtraction_NoRemapping() {
        // Empty layer key map - should use default
        let layerKeyMap: [UInt16: LayerKeyInfo] = [:]

        let defaultKeyCode: UInt16 = 0
        let layerInfo = layerKeyMap[defaultKeyCode]
        let outputLabel = layerInfo?.displayLabel.lowercased() ?? "a"

        XCTAssertNil(layerInfo, "No layer info for unmapped key")
        XCTAssertEqual(outputLabel, "a", "Should default to 'a' when no remapping")
    }

    // MARK: - Equatable Conformance

    func testLayerKeyInfo_Equatable() {
        let info1 = LayerKeyInfo(
            displayLabel: "B",
            outputKey: "b",
            outputKeyCode: 11,
            isTransparent: false,
            isLayerSwitch: false,
            appLaunchIdentifier: nil,
            systemActionIdentifier: nil,
            urlIdentifier: nil
        )

        let info2 = LayerKeyInfo(
            displayLabel: "B",
            outputKey: "b",
            outputKeyCode: 11,
            isTransparent: false,
            isLayerSwitch: false,
            appLaunchIdentifier: nil,
            systemActionIdentifier: nil,
            urlIdentifier: nil
        )

        let info3 = LayerKeyInfo(
            displayLabel: "C",
            outputKey: "c",
            outputKeyCode: 8,
            isTransparent: false,
            isLayerSwitch: false,
            appLaunchIdentifier: nil,
            systemActionIdentifier: nil,
            urlIdentifier: nil
        )

        XCTAssertEqual(info1, info2, "Same info should be equal")
        XCTAssertNotEqual(info1, info3, "Different info should not be equal")
    }
}
