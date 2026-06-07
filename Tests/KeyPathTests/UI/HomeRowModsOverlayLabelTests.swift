@testable import KeyPathAppKit
import KeyPathCore
import SwiftUI
import XCTest

@MainActor
final class HomeRowModsOverlayLabelTests: XCTestCase {
    func testHomeRowModShowsHoldModifierWhenTapMatchesBaseLabel() {
        let key = PhysicalKey(keyCode: 0, label: "A", x: 0, y: 0, width: 1, height: 1)
        let info = LayerKeyInfo.mapped(
            displayLabel: "⇧",
            outputKey: "lsft",
            outputKeyCode: nil,
            collectionId: RuleCollectionIdentifier.homeRowMods
        )

        let keycap = OverlayKeycapView(
            key: key,
            baseLabel: "A",
            isPressed: false,
            scale: 1.0,
            layerKeyInfo: info,
            tapHoldIdleLabel: "A"
        )

        XCTAssertEqual(keycap.effectiveLabel, "⇧")
        XCTAssertEqual(keycap.keycapAccessibilityLabel, "A, tap A, hold ⇧")
    }

    func testTapHoldPickerStyleNonMatchingIdleLabelStillShowsIdleTapLabel() {
        let key = PhysicalKey(keyCode: 57, label: "⇪", x: 0, y: 0, width: 1, height: 1)
        let info = LayerKeyInfo.mapped(
            displayLabel: "⌃",
            outputKey: "lctl",
            outputKeyCode: nil
        )

        let keycap = OverlayKeycapView(
            key: key,
            baseLabel: "⇪",
            isPressed: false,
            scale: 1.0,
            layerKeyInfo: info,
            tapHoldIdleLabel: "⎋"
        )

        XCTAssertEqual(keycap.effectiveLabel, "⎋")
        XCTAssertEqual(keycap.keycapAccessibilityLabel, "⇪, tap ⎋, hold ⌃")
    }

    func testBaseKeycapMatchesHomeRowModPrecedence() {
        let key = PhysicalKey(keyCode: 0, label: "A", x: 0, y: 0, width: 1, height: 1)
        let info = LayerKeyInfo.mapped(
            displayLabel: "⇧",
            outputKey: "lsft",
            outputKeyCode: nil,
            collectionId: RuleCollectionIdentifier.homeRowMods
        )
        let keycap = BaseKeycap(
            key: key,
            baseLabel: "A",
            scale: 1.0,
            foregroundColor: .white,
            colorway: .default,
            layerKeyInfo: info,
            holdLabel: nil,
            tapHoldIdleLabel: "A",
            useFloatingLabels: false,
            shiftLabelOverride: nil,
            isPressed: false,
            currentLayerName: "base",
            isLauncherMode: false,
            isLayerMode: false,
            isKeymapTransitioning: false,
            appIcon: nil,
            faviconImage: nil,
            systemActionIcon: nil,
            zoneSubtitle: nil,
            isLoadingLayerMap: false,
            isCapsLockOn: false,
            isInlineLayer: false,
            hasLayerMapping: true
        )

        XCTAssertEqual(keycap.effectiveLabel, "⇧")
    }
}
