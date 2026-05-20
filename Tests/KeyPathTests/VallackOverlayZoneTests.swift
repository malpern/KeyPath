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

    // MARK: - Zone Subtitles

    func testHomeSubtitlesContainModifierSymbols() {
        let subs = VallackZoneMap.homeSubtitles
        XCTAssertEqual(subs[12], "⌃", "Q should have Control subtitle")
        XCTAssertEqual(subs[13], "⌥", "W should have Option subtitle")
        XCTAssertEqual(subs[14], "⌘", "E should have Command subtitle")
        XCTAssertEqual(subs[32], "⌘", "U should have Command subtitle")
        XCTAssertEqual(subs[34], "⌥", "I should have Option subtitle")
        XCTAssertEqual(subs[31], "⌃", "O should have Control subtitle")
    }

    func testHomeSubtitlesDoNotContainFJNav() {
        let subs = VallackZoneMap.homeSubtitles
        XCTAssertNil(subs[3], "F should not have a subtitle (color is sufficient)")
        XCTAssertNil(subs[38], "J should not have a subtitle (color is sufficient)")
    }

    func testResolverReturnsSubtitlesOnBaseLayer() {
        let subs = PackZoneResolver.activeZoneSubtitles(
            installedPackIDs: [PackRegistry.vallackSystem.id],
            layerName: "base"
        )
        XCTAssertEqual(subs[12], "⌃")
        XCTAssertEqual(subs[14], "⌘")
        XCTAssertEqual(subs.count, 6)
    }

    func testResolverReturnsNoSubtitlesOnNavLayer() {
        let subs = PackZoneResolver.activeZoneSubtitles(
            installedPackIDs: [PackRegistry.vallackSystem.id],
            layerName: "vallack-nav"
        )
        XCTAssertTrue(subs.isEmpty, "Nav layer should not have subtitles")
    }

    func testResolverReturnsNoSubtitlesWithoutPack() {
        let subs = PackZoneResolver.activeZoneSubtitles(
            installedPackIDs: [],
            layerName: "base"
        )
        XCTAssertTrue(subs.isEmpty)
    }

    // MARK: - Layer Preview Config

    func testLayerPreviewConfigReturnsActivatorsWhenVallackInstalled() {
        let config = PackZoneResolver.layerPreviewConfig(
            installedPackIDs: [PackRegistry.vallackSystem.id]
        )
        XCTAssertNotNil(config)
        XCTAssertEqual(config?.activatorKeyCodes, Set<UInt16>([3, 38]))
        XCTAssertEqual(config?.targets[3], "vallack-nav")
        XCTAssertEqual(config?.targets[38], "vallack-nav")
    }

    func testLayerPreviewConfigReturnsNilWithoutPack() {
        let config = PackZoneResolver.layerPreviewConfig(installedPackIDs: [])
        XCTAssertNil(config)
    }

    // MARK: - owningPackID (Pack-Internal Collections)

    func testVallackNavCollectionIsNotPackOwned() {
        let catalog = RuleCollectionCatalog().defaultCollections()
        let collection = catalog.first { $0.id == RuleCollectionIdentifier.vallackNavigation }
        XCTAssertNil(collection?.owningPackID, "Vallack Nav is the pack's identity row — visible in Rules tab")
    }

    func testHomeRowLayerTogglesIsPackOwned() {
        let catalog = RuleCollectionCatalog().defaultCollections()
        let collection = catalog.first { $0.id == RuleCollectionIdentifier.homeRowLayerToggles }
        XCTAssertEqual(collection?.owningPackID, PackRegistry.vallackSystem.id)
    }

    func testHomeRowModsIsNotPackOwned() {
        let catalog = RuleCollectionCatalog().defaultCollections()
        let collection = catalog.first { $0.id == RuleCollectionIdentifier.homeRowMods }
        XCTAssertNil(collection?.owningPackID, "Home Row Mods is shared, not pack-internal")
    }

    func testOnlyInternalSubcomponentsAreHiddenFromRulesTab() {
        let catalog = RuleCollectionCatalog().defaultCollections()
        let visible = catalog.filter { $0.owningPackID == nil }
        let hidden = catalog.filter { $0.owningPackID != nil }

        XCTAssertTrue(visible.contains { $0.id == RuleCollectionIdentifier.vallackNavigation },
                       "Vallack pack row should be visible")
        XCTAssertFalse(visible.contains { $0.id == RuleCollectionIdentifier.homeRowLayerToggles },
                        "Layer Toggles should be hidden")
        XCTAssertTrue(hidden.contains { $0.id == RuleCollectionIdentifier.homeRowLayerToggles })
    }

    // MARK: - KeyMapping sectionLabel Codable

    func testSectionLabelRoundTrips() throws {
        let mapping = KeyMapping(
            input: "h",
            action: .keystroke(key: "left"),
            description: "Left",
            sectionBreak: true,
            sectionLabel: "🤚 Right hand"
        )
        let data = try JSONEncoder().encode(mapping)
        let decoded = try JSONDecoder().decode(KeyMapping.self, from: data)
        XCTAssertEqual(decoded.sectionLabel, "🤚 Right hand")
        XCTAssertTrue(decoded.sectionBreak)
    }

    func testSectionLabelNilByDefault() throws {
        let mapping = KeyMapping(input: "a", action: .keystroke(key: "b"))
        let data = try JSONEncoder().encode(mapping)
        let decoded = try JSONDecoder().decode(KeyMapping.self, from: data)
        XCTAssertNil(decoded.sectionLabel)
    }

    func testSectionLabelBackwardCompatible() throws {
        let mapping = KeyMapping(input: "q", action: .keystroke(key: "tab"), description: "Tab", sectionBreak: true)
        let data = try JSONEncoder().encode(mapping)
        var json = try JSONSerialization.jsonObject(with: data) as! [String: Any]
        json.removeValue(forKey: "sectionLabel")
        let strippedData = try JSONSerialization.data(withJSONObject: json)
        let decoded = try JSONDecoder().decode(KeyMapping.self, from: strippedData)
        XCTAssertNil(decoded.sectionLabel, "Legacy JSON without sectionLabel should decode as nil")
        XCTAssertTrue(decoded.sectionBreak)
    }

    // MARK: - owningPackID Codable

    func testOwningPackIDRoundTrips() throws {
        let catalog = RuleCollectionCatalog().defaultCollections()
        let collection = catalog.first { $0.id == RuleCollectionIdentifier.homeRowLayerToggles }!

        let data = try JSONEncoder().encode(collection)
        let decoded = try JSONDecoder().decode(RuleCollection.self, from: data)
        XCTAssertEqual(decoded.owningPackID, PackRegistry.vallackSystem.id)
    }

    func testOwningPackIDNilBackwardCompatible() throws {
        let catalog = RuleCollectionCatalog().defaultCollections()
        let collection = catalog.first { $0.id == RuleCollectionIdentifier.homeRowMods }!

        let data = try JSONEncoder().encode(collection)
        let json = String(data: data, encoding: .utf8)!
        XCTAssertFalse(json.contains("owningPackID"), "Nil owningPackID should not appear in JSON")

        let decoded = try JSONDecoder().decode(RuleCollection.self, from: data)
        XCTAssertNil(decoded.owningPackID)
    }

    // MARK: - Home Row Mods Customization Detection

    func testDefaultHomeRowModsConfigMatchesDefault() {
        let config = HomeRowModsConfig()
        let defaultConfig = HomeRowModsConfig()
        XCTAssertEqual(config, defaultConfig, "Fresh config should equal default")
    }

    func testCustomizedHomeRowModsConfigDiffersFromDefault() {
        var config = HomeRowModsConfig()
        config.timing = TimingConfig(tapWindow: 300, holdDelay: 200)
        let defaultConfig = HomeRowModsConfig()
        XCTAssertNotEqual(config, defaultConfig, "Modified timing should differ from default")
    }

    // MARK: - Vallack Nav Collection Labels

    func testNavSubtitlesMatchDesign() {
        let subs = VallackZoneMap.navSubtitles
        XCTAssertEqual(subs[12], "tab")     // Q
        XCTAssertEqual(subs[13], "esc")     // W
        XCTAssertEqual(subs[14], "◀tab")    // E
        XCTAssertEqual(subs[15], "tab▶")    // R
        XCTAssertEqual(subs[17], "⌘[")      // T
        XCTAssertEqual(subs[16], "⌘C")      // Y
        XCTAssertEqual(subs[32], "⌫")       // U
        XCTAssertEqual(subs[34], "↵")       // I
        XCTAssertEqual(subs[0], "⌘tab")     // A
        XCTAssertEqual(subs[1], "home")     // S
        XCTAssertEqual(subs[2], "end")      // D
        XCTAssertEqual(subs[41], "⌘V")      // ;
        XCTAssertEqual(subs[9], "⌘]")       // V
        XCTAssertEqual(subs[4], "←")        // H
        XCTAssertEqual(subs[38], "↓")       // J
        XCTAssertEqual(subs[40], "↑")       // K
        XCTAssertEqual(subs[37], "→")       // L
    }

    func testVallackNavDescriptionsAvoidVerboseLabels() {
        let catalog = RuleCollectionCatalog().defaultCollections()
        let collection = catalog.first { $0.id == RuleCollectionIdentifier.vallackNavigation }!
        for mapping in collection.mappings {
            let desc = mapping.description ?? ""
            XCTAssertFalse(desc.contains("Backspace"), "'\(mapping.input)' should not use verbose 'Backspace': got '\(desc)'")
            XCTAssertFalse(desc.contains("Escape"), "'\(mapping.input)' should not use verbose 'Escape': got '\(desc)'")
            XCTAssertFalse(desc.contains("Previous Tab"), "'\(mapping.input)' should use '◀tab' not 'Previous Tab': got '\(desc)'")
            XCTAssertFalse(desc.contains("Browser"), "'\(mapping.input)' should use '⌘['/']' not 'Browser': got '\(desc)'")
        }
    }

    func testVallackNavHasLeftHandFirst() {
        let catalog = RuleCollectionCatalog().defaultCollections()
        let collection = catalog.first { $0.id == RuleCollectionIdentifier.vallackNavigation }!
        let firstMapping = collection.mappings.first!
        XCTAssertEqual(firstMapping.sectionLabel, "✋ Left hand", "First section should be left hand")
        let rightHandMapping = collection.mappings.first { $0.sectionLabel == "🤚 Right hand" }
        XCTAssertNotNil(rightHandMapping, "Should have right hand section")
        let rightIndex = collection.mappings.firstIndex { $0.sectionLabel == "🤚 Right hand" }!
        XCTAssertGreaterThan(rightIndex, 0, "Right hand should come after left hand")
    }
}
