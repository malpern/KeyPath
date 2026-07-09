import Foundation
@testable import KeyPathAppKit
import KeyPathRulesCore
import XCTest

final class ExternalizedDataTests: XCTestCase {
    // MARK: - Colorway JSON

    func test_colorwaysJSONLoadsCorrectly() {
        let colorways = GMKColorway.all
        XCTAssertEqual(colorways.count, 14, "Expected 14 colorways in catalog")
    }

    func test_colorwayDefaultExists() {
        XCTAssertEqual(GMKColorway.default.id, "default")
        XCTAssertEqual(GMKColorway.default.alphaBase, "#141414")
    }

    func test_colorwayFindByID() {
        XCTAssertNotNil(GMKColorway.find(id: "olivia-dark"))
        XCTAssertNotNil(GMKColorway.find(id: "laser"))
        XCTAssertNotNil(GMKColorway.find(id: "dots"))
        XCTAssertNil(GMKColorway.find(id: "nonexistent"))
    }

    func test_colorwayDotsConfig() throws {
        let dots = try XCTUnwrap(GMKColorway.find(id: "dots"))
        XCTAssertEqual(dots.legendStyle, .dots)
        XCTAssertNotNil(dots.dotsConfig)
        XCTAssertEqual(dots.dotsConfig?.colorMode, .rainbow)
    }

    func test_colorwayNoveltyConfig() throws {
        let olivia = try XCTUnwrap(GMKColorway.find(id: "olivia-dark"))
        XCTAssertEqual(olivia.noveltyConfig.escNovelty, "♥")
        XCTAssertTrue(olivia.noveltyConfig.useAccentColor)

        let wob = try XCTUnwrap(GMKColorway.find(id: "wob"))
        XCTAssertNil(wob.noveltyConfig.escNovelty)
    }

    // MARK: - Rule Collection Catalog JSON

    func test_catalogJSONLoadsCorrectly() {
        let catalog = RuleCollectionCatalog()
        let collections = catalog.defaultCollections()
        XCTAssertEqual(collections.count, 22, "Expected 22 collections in catalog")
    }

    func test_catalogContainsExpectedCollections() {
        let catalog = RuleCollectionCatalog()
        let collections = catalog.defaultCollections()
        let ids = Set(collections.map(\.id))

        XCTAssertTrue(ids.contains(RuleCollectionIdentifier.macFunctionKeys))
        XCTAssertTrue(ids.contains(RuleCollectionIdentifier.vimNavigation))
        XCTAssertTrue(ids.contains(RuleCollectionIdentifier.capsLockRemap))
        XCTAssertTrue(ids.contains(RuleCollectionIdentifier.homeRowMods))
        XCTAssertTrue(ids.contains(RuleCollectionIdentifier.numpadLayer))
        XCTAssertTrue(ids.contains(RuleCollectionIdentifier.windowSnapping))
        XCTAssertTrue(ids.contains(RuleCollectionIdentifier.launcher))
    }

    func test_catalogMappingCounts() {
        let catalog = RuleCollectionCatalog()
        let collections = catalog.defaultCollections()
        let byID = Dictionary(uniqueKeysWithValues: collections.map { ($0.id, $0) })

        XCTAssertEqual(byID[RuleCollectionIdentifier.macFunctionKeys]?.mappings.count, 12)
        XCTAssertEqual(byID[RuleCollectionIdentifier.vimNavigation]?.mappings.count, 17)
        XCTAssertEqual(byID[RuleCollectionIdentifier.numpadLayer]?.mappings.count, 16)
    }

    func test_catalogLauncherCollection() {
        let catalog = RuleCollectionCatalog()
        let launcher = catalog.launcherCollection()
        XCTAssertEqual(launcher.id, RuleCollectionIdentifier.launcher)
        XCTAssertEqual(launcher.name, "Quick Launcher")
    }

    func test_catalogUpgradePreservesUserState() throws {
        let catalog = RuleCollectionCatalog()
        var existing = try XCTUnwrap(catalog.defaultCollections().first { $0.id == RuleCollectionIdentifier.capsLockRemap })
        existing.isEnabled = false

        let upgraded = catalog.upgradedCollection(from: existing)
        XCTAssertFalse(upgraded.isEnabled)
        XCTAssertEqual(upgraded.name, "Caps Lock Remap")
    }

    func test_catalogCollectionsRoundTrip() throws {
        let catalog = RuleCollectionCatalog()
        let collections = catalog.defaultCollections()

        let encoder = JSONEncoder()
        let data = try encoder.encode(collections)
        let decoded = try JSONDecoder().decode([RuleCollection].self, from: data)

        XCTAssertEqual(decoded.count, collections.count)
        for (original, round) in zip(collections, decoded) {
            XCTAssertEqual(original.id, round.id)
            XCTAssertEqual(original.name, round.name)
            XCTAssertEqual(original.mappings.count, round.mappings.count)
        }
    }
}
