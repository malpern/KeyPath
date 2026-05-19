@testable import KeyPathAppKit
import KeyPathCore
import SwiftUI
import XCTest

final class VallackOverlayZoneTests: XCTestCase {
    // MARK: - Home Layer Zone Mapping

    func testHomeZonesMapModifierKeyCodes() {
        let zones = VallackZoneMap.homeZones()
        for keyCode: UInt16 in [12, 13, 14, 32, 34, 31] {
            XCTAssertEqual(zones[keyCode], .modifier, "Key code \(keyCode) should be .modifier on home layer")
        }
    }

    func testHomeZonesMapActivatorKeyCodes() {
        let zones = VallackZoneMap.homeZones()
        XCTAssertEqual(zones[3], .activator, "F (keyCode 3) should be .activator")
        XCTAssertEqual(zones[38], .activator, "J (keyCode 38) should be .activator")
    }

    func testHomeZonesDoNotIncludeNavMappings() {
        let zones = VallackZoneMap.homeZones()
        XCTAssertNil(zones[4], "H should not be zoned on home layer")
        XCTAssertNil(zones[40], "K should not be zoned on home layer")
        XCTAssertNil(zones[37], "L should not be zoned on home layer")
    }

    // MARK: - Nav Layer Zone Mapping

    func testNavZonesMapAllNavKeys() {
        let zones = VallackZoneMap.navZones()
        let expectedNavKeyCodes: Set<UInt16> = [
            4, 38, 40, 37, 32, 34, 16, 41,
            12, 13, 14, 15, 0, 1, 2, 5, 17, 9,
        ]
        for keyCode in expectedNavKeyCodes {
            XCTAssertEqual(zones[keyCode], .navMapping, "Key code \(keyCode) should be .navMapping on nav layer")
        }
    }

    func testNavZonesDoNotIncludeUnmappedKeys() {
        let zones = VallackZoneMap.navZones()
        XCTAssertNil(zones[45], "N (keyCode 45) should not be zoned on nav layer")
    }

    // MARK: - Layer Routing

    func testZonesForLayerReturnsHomeZonesOnBaseLayer() {
        let zones = VallackZoneMap.zones(forLayer: "base")
        XCTAssertEqual(zones?[12], .modifier)
        XCTAssertEqual(zones?[3], .activator)
    }

    func testZonesForLayerReturnsNavZonesOnVallackNavLayer() {
        let zones = VallackZoneMap.zones(forLayer: "vallack-nav")
        XCTAssertEqual(zones?[4], .navMapping)
    }

    // MARK: - PackZoneResolver (generic overlay interface)

    func testResolverReturnsColorsWhenVallackInstalled() {
        let colors = PackZoneResolver.activeZoneColors(
            installedPackIDs: [PackRegistry.vallackSystem.id],
            layerName: "base"
        )
        XCTAssertNotNil(colors[12], "Q should have a zone color when Vallack installed")
        XCTAssertNotNil(colors[3], "F should have a zone color when Vallack installed")
    }

    func testResolverReturnsNavColorsOnVallackNavLayer() {
        let colors = PackZoneResolver.activeZoneColors(
            installedPackIDs: [PackRegistry.vallackSystem.id],
            layerName: "vallack-nav"
        )
        XCTAssertNotNil(colors[4], "H should have a zone color on vallack-nav")
    }

    func testResolverReturnsEmptyWhenNoPackInstalled() {
        let colors = PackZoneResolver.activeZoneColors(
            installedPackIDs: [],
            layerName: "base"
        )
        XCTAssertTrue(colors.isEmpty)
    }

    func testResolverReturnsEmptyForUnrelatedPacks() {
        let colors = PackZoneResolver.activeZoneColors(
            installedPackIDs: ["com.keypath.pack.home-row-mods", "com.keypath.pack.kindavim"],
            layerName: "base"
        )
        XCTAssertTrue(colors.isEmpty)
    }

    func testResolverReturnsColorsMatchingZoneDefinitions() {
        let colors = PackZoneResolver.activeZoneColors(
            installedPackIDs: [PackRegistry.vallackSystem.id],
            layerName: "base"
        )
        let modifierColor = KeyboardZone.modifier.color
        let activatorColor = KeyboardZone.activator.color
        XCTAssertEqual(
            String(describing: colors[12]!),
            String(describing: modifierColor),
            "Q zone color should match KeyboardZone.modifier.color"
        )
        XCTAssertEqual(
            String(describing: colors[3]!),
            String(describing: activatorColor),
            "F zone color should match KeyboardZone.activator.color"
        )
    }

    func testResolverFirstMatchWinsWithMultiplePacks() {
        let colors = PackZoneResolver.activeZoneColors(
            installedPackIDs: [
                PackRegistry.vallackSystem.id,
                "com.keypath.pack.hypothetical-other-system",
            ],
            layerName: "base"
        )
        XCTAssertFalse(colors.isEmpty, "First matching pack should provide zones")
    }

    // MARK: - backgroundColor Priority

    func testZoneColorYieldsToPressedState() {
        let view = OverlayKeycapView(
            key: PhysicalKey(keyCode: 12, label: "Q", x: 0, y: 0, width: 1, height: 1),
            baseLabel: "Q",
            isPressed: true,
            scale: 1.0,
            zoneColor: Color.blue.opacity(0.45)
        )
        let bg = view.backgroundColor
        XCTAssertNotEqual(
            String(describing: bg),
            String(describing: Color.blue.opacity(0.45)),
            "Pressed state should override zone color"
        )
    }

    func testZoneColorYieldsToOneShotState() {
        let view = OverlayKeycapView(
            key: PhysicalKey(keyCode: 12, label: "Q", x: 0, y: 0, width: 1, height: 1),
            baseLabel: "Q",
            isPressed: false,
            scale: 1.0,
            isOneShot: true,
            zoneColor: Color.blue.opacity(0.45)
        )
        let bg = view.backgroundColor
        let oneShotColor = Color(red: 0.2, green: 0.7, blue: 0.8)
        XCTAssertEqual(
            String(describing: bg),
            String(describing: oneShotColor),
            "One-shot state should override zone color"
        )
    }

    func testZoneColorAppliesWhenNotPressedOrOneShot() {
        let zoneColor = Color.blue.opacity(0.45)
        let view = OverlayKeycapView(
            key: PhysicalKey(keyCode: 12, label: "Q", x: 0, y: 0, width: 1, height: 1),
            baseLabel: "Q",
            isPressed: false,
            scale: 1.0,
            zoneColor: zoneColor
        )
        let bg = view.backgroundColor
        XCTAssertEqual(
            String(describing: bg),
            String(describing: zoneColor),
            "Zone color should apply when key is idle"
        )
    }

    func testZoneColorTakesPriorityOverLayerModeCollectionColor() {
        let zoneColor = Color.green.opacity(0.45)
        let view = OverlayKeycapView(
            key: PhysicalKey(keyCode: 4, label: "H", x: 5, y: 2, width: 1, height: 1),
            baseLabel: "H",
            isPressed: false,
            scale: 1.0,
            currentLayerName: "vallack-nav",
            layerKeyInfo: .mapped(displayLabel: "←", outputKey: "left", outputKeyCode: 123, collectionId: RuleCollectionIdentifier.vallackNavigation),
            zoneColor: zoneColor
        )
        let bg = view.backgroundColor
        XCTAssertEqual(
            String(describing: bg),
            String(describing: zoneColor),
            "Zone color should take priority over collection color in layer mode"
        )
    }

    func testNoZoneColorFallsBackToNormalBehavior() {
        let view = OverlayKeycapView(
            key: PhysicalKey(keyCode: 4, label: "H", x: 5, y: 2, width: 1, height: 1),
            baseLabel: "H",
            isPressed: false,
            scale: 1.0
        )
        let bg = view.backgroundColor
        let defaultAlpha = GMKColorway.default.alphaBaseColor
        XCTAssertEqual(
            String(describing: bg),
            String(describing: defaultAlpha),
            "Without zone color, should use normal colorway"
        )
    }

    // MARK: - Zone Color Consistency

    func testModifierZoneColorIsBlue() {
        XCTAssertEqual(String(describing: KeyboardZone.modifier.color), String(describing: Color.blue.opacity(0.45)))
    }

    func testActivatorZoneColorIsOrange() {
        XCTAssertEqual(String(describing: KeyboardZone.activator.color), String(describing: Color.orange.opacity(0.5)))
    }

    func testNavMappingZoneColorIsGreen() {
        XCTAssertEqual(String(describing: KeyboardZone.navMapping.color), String(describing: Color.green.opacity(0.45)))
    }

    // MARK: - Collection Color for Vallack Nav

    func testCollectionColorForVallackNavReturnsGreen() {
        let keycapView = OverlayKeycapView(
            key: PhysicalKey(keyCode: 4, label: "H", x: 5, y: 2, width: 1, height: 1),
            baseLabel: "H",
            isPressed: false,
            scale: 1.0
        )
        let color = keycapView.collectionColor(for: RuleCollectionIdentifier.vallackNavigation)
        let expected = Color(red: 0.2, green: 0.7, blue: 0.4)
        XCTAssertEqual(String(describing: color), String(describing: expected))
    }

    // MARK: - Key Code Constants

    func testModifierKeyCodesMatchHomeRowModsVallackTopRow() {
        XCTAssertEqual(VallackZoneMap.modifierKeyCodes, Set<UInt16>([12, 13, 14, 32, 34, 31]))
    }

    func testActivatorKeyCodesAreFAndJ() {
        XCTAssertEqual(VallackZoneMap.activatorKeyCodes, Set<UInt16>([3, 38]))
    }
}
