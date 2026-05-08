@testable import KeyPathAppKit
import KeyPathCore
import XCTest

/// Tests for the outputKey vs displayLabel distinction in mapper notification payloads.
/// This is a critical data flow boundary — mixing these up causes config validation errors.
final class MapperNotificationPayloadTests: XCTestCase {

    // MARK: - outputKey Resolution

    func testOutputKeyPrefersLayerInfoOutputKey() {
        let layerInfo = LayerKeyInfo.mapped(displayLabel: "✦", outputKey: "lctl", outputKeyCode: nil)
        let outputKey = resolveOutputKey(inputKey: "capslock", layerInfo: layerInfo)
        XCTAssertEqual(outputKey, "lctl", "Should use layerInfo.outputKey when available")
    }

    func testOutputKeyFallsBackToDisplayLabel() {
        let layerInfo = LayerKeyInfo(
            displayLabel: "NAV",
            outputKey: nil,
            outputKeyCode: nil,
            isTransparent: false,
            isLayerSwitch: true
        )
        let outputKey = resolveOutputKey(inputKey: "space", layerInfo: layerInfo)
        XCTAssertEqual(outputKey, "NAV", "Should fall back to displayLabel when outputKey is nil")
    }

    func testOutputKeyFallsBackToInputKeyWhenNoLayerInfo() {
        let outputKey = resolveOutputKey(inputKey: "a", layerInfo: nil)
        XCTAssertEqual(outputKey, "a", "Should fall back to inputKey when no layer info")
    }

    func testOutputKeyDoesNotUseGlyphSymbol() {
        let layerInfo = LayerKeyInfo.mapped(displayLabel: "✦", outputKey: "C-S-M-A-", outputKeyCode: nil)
        let outputKey = resolveOutputKey(inputKey: "capslock", layerInfo: layerInfo)
        XCTAssertNotEqual(outputKey, "✦", "Should never use glyph as outputKey")
    }

    func testDisplayLabelPassedSeparatelyFromOutputKey() {
        let layerInfo = LayerKeyInfo.mapped(displayLabel: "✦", outputKey: "lctl", outputKeyCode: nil)
        let payload = buildNotificationPayload(keyCode: 57, inputKey: "capslock", layerInfo: layerInfo)

        XCTAssertEqual(payload["outputKey"] as? String, "lctl")
        XCTAssertEqual(payload["displayLabel"] as? String, "✦")
        XCTAssertNotEqual(
            payload["outputKey"] as? String,
            payload["displayLabel"] as? String,
            "outputKey and displayLabel should be distinct for Hyper-type mappings"
        )
    }

    func testEmptyDisplayLabelNotIncludedInPayload() {
        let layerInfo = LayerKeyInfo.mapped(displayLabel: "", outputKey: "b", outputKeyCode: nil)
        let payload = buildNotificationPayload(keyCode: 0, inputKey: "a", layerInfo: layerInfo)

        XCTAssertNil(payload["displayLabel"], "Empty displayLabel should not be in payload")
    }

    func testAppIdentifierIncludedInPayload() {
        let layerInfo = LayerKeyInfo(
            displayLabel: "Safari",
            outputKey: nil,
            outputKeyCode: nil,
            isTransparent: false,
            isLayerSwitch: false,
            appLaunchIdentifier: "com.apple.Safari"
        )
        let payload = buildNotificationPayload(keyCode: 1, inputKey: "s", layerInfo: layerInfo)

        XCTAssertEqual(payload["appIdentifier"] as? String, "com.apple.Safari")
    }

    func testSystemActionIncludedInPayload() {
        let layerInfo = LayerKeyInfo(
            displayLabel: "🔍",
            outputKey: nil,
            outputKeyCode: nil,
            isTransparent: false,
            isLayerSwitch: false,
            systemActionIdentifier: "spotlight"
        )
        let payload = buildNotificationPayload(keyCode: 2, inputKey: "d", layerInfo: layerInfo)

        XCTAssertEqual(payload["systemActionIdentifier"] as? String, "spotlight")
    }

    func testUrlIdentifierIncludedInPayload() {
        let layerInfo = LayerKeyInfo(
            displayLabel: "GH",
            outputKey: nil,
            outputKeyCode: nil,
            isTransparent: false,
            isLayerSwitch: false,
            urlIdentifier: "https://github.com"
        )
        let payload = buildNotificationPayload(keyCode: 5, inputKey: "g", layerInfo: layerInfo)

        XCTAssertEqual(payload["urlIdentifier"] as? String, "https://github.com")
    }

    // MARK: - Helpers

    /// Mirrors the outputKey resolution logic from LiveKeyboardOverlayController+KeyClickHandling
    private func resolveOutputKey(inputKey: String, layerInfo: LayerKeyInfo?) -> String {
        if let simpleOutput = layerInfo?.outputKey {
            return simpleOutput
        } else if let displayLabel = layerInfo?.displayLabel, !displayLabel.isEmpty {
            return displayLabel
        } else {
            return inputKey
        }
    }

    /// Mirrors the notification payload construction
    private func buildNotificationPayload(
        keyCode: UInt16,
        inputKey: String,
        layerInfo: LayerKeyInfo?
    ) -> [String: Any] {
        let outputKey = resolveOutputKey(inputKey: inputKey, layerInfo: layerInfo)

        var userInfo: [String: Any] = [
            "keyCode": keyCode,
            "inputKey": inputKey,
            "outputKey": outputKey,
            "layer": "base",
        ]
        if let displayLabel = layerInfo?.displayLabel, !displayLabel.isEmpty {
            userInfo["displayLabel"] = displayLabel
        }
        if let appId = layerInfo?.appLaunchIdentifier {
            userInfo["appIdentifier"] = appId
        }
        if let systemId = layerInfo?.systemActionIdentifier {
            userInfo["systemActionIdentifier"] = systemId
        }
        if let urlId = layerInfo?.urlIdentifier {
            userInfo["urlIdentifier"] = urlId
        }
        return userInfo
    }
}
