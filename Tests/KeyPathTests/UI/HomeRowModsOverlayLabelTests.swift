@testable import KeyPathAppKit
import KeyPathCore
import KeyPathRulesCore
import XCTest

@MainActor
final class HomeRowModsOverlayLabelTests: XCTestCase {
    func testHomeRowModKeepsAlphaPrimaryAndShowsHoldModifierAsSubtitle() {
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
            tapHoldIdleLabel: "A",
            zoneColor: KeycapSymbols.collectionColor(for: RuleCollectionIdentifier.homeRowMods),
            zoneSubtitle: "⇧"
        )

        XCTAssertEqual(keycap.effectiveLabel, "A")
        XCTAssertTrue(keycap.rendersHomeRowModSubtitle)
        XCTAssertTrue(keycap.zoneSubtitleRenderedInline)
        XCTAssertEqual(
            String(describing: keycap.backgroundColor),
            String(describing: KeyPathColors.layerModifier)
        )
        XCTAssertEqual(keycap.keycapAccessibilityLabel, "A, tap A, hold ⇧")
    }

    func testResolvedHomeRowModHoldShowsSingleHoldOutput() {
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
            isPressed: true,
            scale: 1.0,
            layerKeyInfo: info,
            holdLabel: "⇧",
            isHoldActive: true,
            tapHoldIdleLabel: "A",
            zoneColor: KeycapSymbols.collectionColor(for: RuleCollectionIdentifier.homeRowMods),
            zoneSubtitle: "⇧"
        )

        XCTAssertEqual(keycap.effectiveLabel, "⇧")
        XCTAssertTrue(keycap.isResolvedHomeRowModHold)
        XCTAssertFalse(keycap.zoneSubtitleRenderedInline)
        XCTAssertEqual(
            String(describing: keycap.backgroundColor),
            String(describing: KeyPathColors.layerModifier)
        )
        XCTAssertEqual(keycap.keycapAccessibilityValue, "held")
    }

    func testHomeRowModSemicolonUsesModifierSubtitleInsteadOfShiftedPunctuation() {
        let key = PhysicalKey(keyCode: 41, label: ";", x: 0, y: 0, width: 1, height: 1)
        let info = LayerKeyInfo.mapped(
            displayLabel: "⇧",
            outputKey: "rsft",
            outputKeyCode: nil,
            collectionId: RuleCollectionIdentifier.homeRowMods
        )

        let keycap = OverlayKeycapView(
            key: key,
            baseLabel: ";",
            isPressed: false,
            scale: 1.0,
            layerKeyInfo: info,
            tapHoldIdleLabel: ";",
            zoneSubtitle: "⇧"
        )

        XCTAssertEqual(keycap.effectiveLabel, ";")
        XCTAssertTrue(keycap.zoneSubtitleRenderedInline)
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
            isHoldActive: false,
            currentLayerName: "base",
            isLauncherMode: false,
            isLayerMode: false,
            isKeymapTransitioning: false,
            appIcon: nil,
            faviconImage: nil,
            systemActionIcon: nil,
            zoneSubtitle: "⇧",
            isLoadingLayerMap: false,
            isCapsLockOn: false,
            isInlineLayer: false,
            hasLayerMapping: true
        )

        XCTAssertEqual(keycap.effectiveLabel, "A")
        XCTAssertTrue(keycap.rendersHomeRowModSubtitle)
        XCTAssertTrue(keycap.zoneSubtitleRenderedInline)
    }

    func testBaseKeycapResolvedHomeRowModHoldSuppressesSubtitle() {
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
            holdLabel: "⇧",
            tapHoldIdleLabel: "A",
            useFloatingLabels: false,
            shiftLabelOverride: nil,
            isPressed: true,
            isHoldActive: true,
            currentLayerName: "base",
            isLauncherMode: false,
            isLayerMode: false,
            isKeymapTransitioning: false,
            appIcon: nil,
            faviconImage: nil,
            systemActionIcon: nil,
            zoneSubtitle: "⇧",
            isLoadingLayerMap: false,
            isCapsLockOn: false,
            isInlineLayer: false,
            hasLayerMapping: true
        )

        XCTAssertEqual(keycap.effectiveLabel, "⇧")
        XCTAssertTrue(keycap.isResolvedHomeRowModHold)
        XCTAssertFalse(keycap.zoneSubtitleRenderedInline)
    }
}
