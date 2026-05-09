@testable import KeyPathAppKit
import KeyPathCore
import XCTest

final class OverlayEffectiveLabelTests: XCTestCase {

    // MARK: - effectiveLabel Priority Chain

    func testHoldLabelTakesPriorityWhenPressed() {
        let view = makeKeycapState(
            baseLabel: "a",
            isPressed: true,
            holdLabel: "✦",
            layerKeyInfo: .mapped(displayLabel: "a", outputKey: "a", outputKeyCode: nil)
        )
        XCTAssertEqual(view.effectiveLabel, "✦")
    }

    func testHoldLabelIgnoredWhenNotPressed() {
        let view = makeKeycapState(
            baseLabel: "a",
            isPressed: false,
            holdLabel: "✦",
            layerKeyInfo: .mapped(displayLabel: "b", outputKey: "b", outputKeyCode: nil)
        )
        XCTAssertNotEqual(view.effectiveLabel, "✦")
    }

    func testTapHoldIdleLabelShownOnBaseLayerWhenNotPressed() {
        let view = makeKeycapState(
            baseLabel: "a",
            isPressed: false,
            tapHoldIdleLabel: "a",
            currentLayerName: "base",
            layerKeyInfo: .mapped(displayLabel: "✦", outputKey: "lctl", outputKeyCode: nil)
        )
        XCTAssertEqual(view.effectiveLabel, "a")
    }

    func testTapHoldIdleLabelHiddenOnNonBaseLayer() {
        let view = makeKeycapState(
            baseLabel: "a",
            isPressed: false,
            tapHoldIdleLabel: "a",
            currentLayerName: "nav",
            layerKeyInfo: .mapped(displayLabel: "←", outputKey: "left", outputKeyCode: nil)
        )
        XCTAssertEqual(view.effectiveLabel, "←")
    }

    func testDisplayLabelUsedWhenNoHoldOrIdleLabel() {
        let view = makeKeycapState(
            baseLabel: "a",
            isPressed: false,
            layerKeyInfo: .mapped(displayLabel: "←", outputKey: "left", outputKeyCode: nil)
        )
        XCTAssertEqual(view.effectiveLabel, "←")
    }

    func testBaseLabelFallbackWhenNoLayerKeyInfo() {
        let view = makeKeycapState(
            baseLabel: "a",
            isPressed: false,
            layerKeyInfo: nil
        )
        XCTAssertEqual(view.effectiveLabel, "a")
    }

    func testEmptyDisplayLabelFallsBackToBaseLabel() {
        let view = makeKeycapState(
            baseLabel: "a",
            isPressed: false,
            layerKeyInfo: LayerKeyInfo(
                displayLabel: "",
                outputKey: nil,
                outputKeyCode: nil,
                isTransparent: false,
                isLayerSwitch: false
            )
        )
        XCTAssertEqual(view.effectiveLabel, "a")
    }

    func testTransparentKeyUsesBaseLabel() {
        let view = makeKeycapState(
            baseLabel: "q",
            isPressed: false,
            layerKeyInfo: LayerKeyInfo(
                displayLabel: "q",
                outputKey: "q",
                outputKeyCode: nil,
                isTransparent: true,
                isLayerSwitch: false
            )
        )
        XCTAssertEqual(view.shouldUseBaseLabel, true)
    }

    func testLayerSwitchKeyDoesNotFallBackToBaseLabel() {
        let view = makeKeycapState(
            baseLabel: "a",
            isPressed: false,
            layerKeyInfo: LayerKeyInfo(
                displayLabel: "NAV",
                outputKey: nil,
                outputKeyCode: nil,
                isTransparent: false,
                isLayerSwitch: true
            )
        )
        XCTAssertEqual(view.shouldUseBaseLabel, false)
        XCTAssertEqual(view.effectiveLabel, "NAV")
    }

    func testAppLaunchMappingDoesNotFallBackToBaseLabel() {
        let view = makeKeycapState(
            baseLabel: "s",
            isPressed: false,
            layerKeyInfo: LayerKeyInfo(
                displayLabel: "Safari",
                outputKey: nil,
                outputKeyCode: nil,
                isTransparent: false,
                isLayerSwitch: false,
                appLaunchIdentifier: "com.apple.Safari"
            )
        )
        XCTAssertEqual(view.shouldUseBaseLabel, false)
    }

    func testSystemActionDoesNotFallBackToBaseLabel() {
        let view = makeKeycapState(
            baseLabel: "d",
            isPressed: false,
            layerKeyInfo: LayerKeyInfo(
                displayLabel: "🔍",
                outputKey: nil,
                outputKeyCode: nil,
                isTransparent: false,
                isLayerSwitch: false,
                systemActionIdentifier: "spotlight"
            )
        )
        XCTAssertEqual(view.shouldUseBaseLabel, false)
    }

    func testIdentityMappingFallsBackToBaseLabel() {
        let view = makeKeycapState(
            baseLabel: "a",
            isPressed: false,
            keyCode: 0, // key code for 'a'
            layerKeyInfo: .mapped(displayLabel: "a", outputKey: "a", outputKeyCode: nil)
        )
        XCTAssertEqual(view.shouldUseBaseLabel, true)
    }

    func testHyperMappingDoesNotFallBackToBaseLabel() {
        let view = makeKeycapState(
            baseLabel: "a",
            isPressed: false,
            keyCode: 0,
            layerKeyInfo: .mapped(displayLabel: "✦", outputKey: "lctl", outputKeyCode: nil)
        )
        XCTAssertEqual(view.shouldUseBaseLabel, false)
        XCTAssertEqual(view.effectiveLabel, "✦")
    }

    // MARK: - Helpers

    private func makeKeycapState(
        baseLabel: String,
        isPressed: Bool,
        holdLabel: String? = nil,
        tapHoldIdleLabel: String? = nil,
        currentLayerName: String = "base",
        keyCode: UInt16 = 0,
        layerKeyInfo: LayerKeyInfo?
    ) -> OverlayKeycapTestProxy {
        OverlayKeycapTestProxy(
            baseLabel: baseLabel,
            isPressed: isPressed,
            holdLabel: holdLabel,
            tapHoldIdleLabel: tapHoldIdleLabel,
            currentLayerName: currentLayerName,
            keyCode: keyCode,
            layerKeyInfo: layerKeyInfo,
            isLauncherMode: false
        )
    }
}

/// Test proxy that mirrors OverlayKeycapView's effectiveLabel and shouldUseBaseLabel logic
/// without requiring SwiftUI view instantiation.
private struct OverlayKeycapTestProxy {
    let baseLabel: String
    let isPressed: Bool
    let holdLabel: String?
    let tapHoldIdleLabel: String?
    let currentLayerName: String
    let keyCode: UInt16
    let layerKeyInfo: LayerKeyInfo?
    let isLauncherMode: Bool

    var inputKeyName: String {
        OverlayKeyboardView.keyCodeToKanataName(keyCode).lowercased()
    }

    private var shouldShowTapHoldIdleLabel: Bool {
        guard !isLauncherMode else { return false }
        return currentLayerName.lowercased() == "base"
    }

    var effectiveLabel: String {
        if isPressed, let holdLabel {
            return holdLabel
        }

        if !isPressed, let tapHoldIdleLabel, shouldShowTapHoldIdleLabel {
            return tapHoldIdleLabel
        }

        guard let info = layerKeyInfo else {
            return baseLabel
        }

        if info.displayLabel.isEmpty {
            return baseLabel.isEmpty ? "" : baseLabel
        }

        if shouldUseBaseLabel, baseLabel != "" {
            return baseLabel
        }

        return info.displayLabel
    }

    var shouldUseBaseLabel: Bool {
        guard let info = layerKeyInfo else { return true }
        if info.isTransparent { return true }
        if info.isLayerSwitch { return false }
        if info.appLaunchIdentifier != nil || info.systemActionIdentifier != nil || info.urlIdentifier != nil {
            return false
        }
        if !info.displayLabel.isEmpty, info.displayLabel.lowercased() != inputKeyName {
            return false
        }
        if let outputKey = info.outputKey {
            return outputKey.lowercased() == inputKeyName
        }
        return true
    }
}
