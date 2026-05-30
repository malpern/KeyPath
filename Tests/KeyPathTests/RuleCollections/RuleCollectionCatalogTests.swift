@testable import KeyPathAppKit
import XCTest

final class RuleCollectionCatalogTests: XCTestCase {
    // MARK: - Default Collections

    func testDefaultCollections_IsNonEmpty() {
        let catalog = RuleCollectionCatalog()
        XCTAssertFalse(catalog.defaultCollections().isEmpty)
    }

    func testDefaultCollections_HasUniqueIDs() {
        let collections = RuleCollectionCatalog().defaultCollections()
        let ids = collections.map(\.id)
        XCTAssertEqual(Set(ids).count, ids.count, "Duplicate collection IDs found")
    }

    func testDefaultCollections_HasUniqueNames() {
        let collections = RuleCollectionCatalog().defaultCollections()
        let names = collections.map(\.name)
        XCTAssertEqual(Set(names).count, names.count, "Duplicate collection names found")
    }

    func testDefaultCollections_ContainsExpectedCollections() {
        let ids = Set(RuleCollectionCatalog().defaultCollections().map(\.id))
        XCTAssertTrue(ids.contains(RuleCollectionIdentifier.macFunctionKeys))
        XCTAssertTrue(ids.contains(RuleCollectionIdentifier.capsLockRemap))
        XCTAssertTrue(ids.contains(RuleCollectionIdentifier.homeRowMods))
        XCTAssertTrue(ids.contains(RuleCollectionIdentifier.vimNavigation))
        XCTAssertTrue(ids.contains(RuleCollectionIdentifier.windowSnapping))
        XCTAssertTrue(ids.contains(RuleCollectionIdentifier.missionControl))
        XCTAssertTrue(ids.contains(RuleCollectionIdentifier.numpadLayer))
        XCTAssertTrue(ids.contains(RuleCollectionIdentifier.symbolLayer))
        XCTAssertTrue(ids.contains(RuleCollectionIdentifier.funLayer))
        XCTAssertTrue(ids.contains(RuleCollectionIdentifier.launcher))
    }

    func testDefaultCollections_MacOSFunctionKeysIsFirstAndEnabled() {
        let collections = RuleCollectionCatalog().defaultCollections()
        let macFK = collections.first
        XCTAssertEqual(macFK?.id, RuleCollectionIdentifier.macFunctionKeys)
        XCTAssertTrue(macFK?.isEnabled ?? false)
    }

    func testDefaultCollections_AllHaveNonEmptyNames() {
        let collections = RuleCollectionCatalog().defaultCollections()
        for collection in collections {
            XCTAssertFalse(collection.name.isEmpty, "Collection \(collection.id) has empty name")
        }
    }

    func testDefaultCollections_AllHaveNonEmptySummaries() {
        let collections = RuleCollectionCatalog().defaultCollections()
        for collection in collections {
            XCTAssertFalse(collection.summary.isEmpty, "Collection \(collection.name) has empty summary")
        }
    }

    // MARK: - Upgraded Collection

    func testUpgradedCollection_PreservesEnabledState() {
        let catalog = RuleCollectionCatalog()
        var original = catalog.defaultCollections().first!
        original.isEnabled = true

        let upgraded = catalog.upgradedCollection(from: original)
        XCTAssertTrue(upgraded.isEnabled)
    }

    func testUpgradedCollection_PreservesDisabledState() {
        let catalog = RuleCollectionCatalog()
        var original = catalog.defaultCollections().first!
        original.isEnabled = false

        let upgraded = catalog.upgradedCollection(from: original)
        XCTAssertFalse(upgraded.isEnabled)
    }

    func testUpgradedCollection_UnknownCollectionReturnsSelf() {
        let catalog = RuleCollectionCatalog()
        let unknown = RuleCollection(
            id: UUID(),
            name: "Unknown",
            summary: "Not in catalog",
            category: .custom,
            mappings: [],
            isEnabled: true,
            icon: "star",
            tags: [],
            targetLayer: .base,
            configuration: .list
        )

        let upgraded = catalog.upgradedCollection(from: unknown)
        XCTAssertEqual(upgraded.id, unknown.id)
        XCTAssertEqual(upgraded.name, "Unknown")
    }

    // MARK: - Launcher Collection

    func testLauncherCollection_HasCorrectID() {
        let launcher = RuleCollectionCatalog().launcherCollection()
        XCTAssertEqual(launcher.id, RuleCollectionIdentifier.launcher)
    }

    func testLauncherCollection_HasLauncherConfiguration() {
        let launcher = RuleCollectionCatalog().launcherCollection()
        if case .launcherGrid = launcher.configuration {
            // Expected — launcher uses grid config
        } else {
            XCTFail("Launcher collection should have launcherGrid configuration")
        }
    }

    // MARK: - Collection Categories

    func testMacOSFunctionKeys_IsSystemCategory() {
        let collections = RuleCollectionCatalog().defaultCollections()
        let macFK = collections.first(where: { $0.id == RuleCollectionIdentifier.macFunctionKeys })
        XCTAssertEqual(macFK?.category, .system)
    }

    // MARK: - Collection Target Layers

    func testBaseLayerCollections_TargetBaseLayer() {
        let baseCollections = [
            RuleCollectionIdentifier.capsLockRemap,
            RuleCollectionIdentifier.escapeRemap,
            RuleCollectionIdentifier.homeRowMods,
        ]
        let collections = RuleCollectionCatalog().defaultCollections()

        for id in baseCollections {
            let collection = collections.first(where: { $0.id == id })
            XCTAssertEqual(collection?.targetLayer, .base, "\(collection?.name ?? "?") should target base layer")
        }
    }

    func testNavLayerCollections_TargetNavigationLayer() {
        let navCollections = [
            RuleCollectionIdentifier.windowSnapping,
            RuleCollectionIdentifier.missionControl,
            RuleCollectionIdentifier.numpadLayer,
            RuleCollectionIdentifier.symbolLayer,
            RuleCollectionIdentifier.funLayer,
        ]
        let collections = RuleCollectionCatalog().defaultCollections()

        for id in navCollections {
            let collection = collections.first(where: { $0.id == id })
            XCTAssertNotNil(collection, "Missing collection for \(id)")
            XCTAssertNotEqual(collection?.targetLayer, .base, "\(collection?.name ?? "?") should not target base layer")
        }
    }
}
