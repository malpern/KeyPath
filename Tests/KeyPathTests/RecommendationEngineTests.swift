@testable import KeyPathAppKit
import XCTest

/// Tests for the contextual recommendation engine.
final class RecommendationEngineTests: XCTestCase {

    func testAlwaysRecommendsCorePacksWhenDisabled() {
        var collections = RuleCollectionCatalog().defaultCollections()
        for i in collections.indices { collections[i].isEnabled = false }

        let recs = RulesRecommendationEngine.recommendations(from: collections)
        let ids = Set(recs.map(\.collectionId))

        XCTAssertTrue(ids.contains(RuleCollectionIdentifier.capsLockRemap))
        XCTAssertTrue(ids.contains(RuleCollectionIdentifier.windowSnapping))
        XCTAssertTrue(ids.contains(RuleCollectionIdentifier.homeRowMods))
        XCTAssertTrue(ids.contains(RuleCollectionIdentifier.launcher))
    }

    func testEnabledPacksExcludedFromRecommendations() {
        var collections = RuleCollectionCatalog().defaultCollections()
        for i in collections.indices { collections[i].isEnabled = false }
        if let idx = collections.firstIndex(where: { $0.id == RuleCollectionIdentifier.capsLockRemap }) {
            collections[idx].isEnabled = true
        }

        let recs = RulesRecommendationEngine.recommendations(from: collections)
        let ids = Set(recs.map(\.collectionId))

        XCTAssertFalse(ids.contains(RuleCollectionIdentifier.capsLockRemap),
                       "Should not recommend already-enabled pack")
    }

    func testVimEnabled_RecommendsMissionControl() {
        var collections = RuleCollectionCatalog().defaultCollections()
        for i in collections.indices { collections[i].isEnabled = false }
        if let idx = collections.firstIndex(where: { $0.id == RuleCollectionIdentifier.vimNavigation }) {
            collections[idx].isEnabled = true
        }

        let recs = RulesRecommendationEngine.recommendations(from: collections)
        let ids = Set(recs.map(\.collectionId))

        XCTAssertTrue(ids.contains(RuleCollectionIdentifier.missionControl),
                      "Should recommend Mission Control when Vim is enabled")
    }

    func testCapsLockEnabled_RecommendsBackupCapsLock() {
        var collections = RuleCollectionCatalog().defaultCollections()
        for i in collections.indices { collections[i].isEnabled = false }
        if let idx = collections.firstIndex(where: { $0.id == RuleCollectionIdentifier.capsLockRemap }) {
            collections[idx].isEnabled = true
        }

        let recs = RulesRecommendationEngine.recommendations(from: collections)
        let ids = Set(recs.map(\.collectionId))

        XCTAssertTrue(ids.contains(RuleCollectionIdentifier.backupCapsLock),
                      "Should recommend Backup Caps Lock when Caps Lock Remap is enabled")
    }

    func testHRMEnabled_RecommendsVimNav() {
        var collections = RuleCollectionCatalog().defaultCollections()
        for i in collections.indices { collections[i].isEnabled = false }
        if let idx = collections.firstIndex(where: { $0.id == RuleCollectionIdentifier.homeRowMods }) {
            collections[idx].isEnabled = true
        }

        let recs = RulesRecommendationEngine.recommendations(from: collections)
        let ids = Set(recs.map(\.collectionId))

        XCTAssertTrue(ids.contains(RuleCollectionIdentifier.vimNavigation),
                      "Should recommend Vim Navigation when HRM is enabled")
    }

    func testPowerUser_RecommendsLeaderKey() {
        var collections = RuleCollectionCatalog().defaultCollections()
        for i in collections.indices { collections[i].isEnabled = false }
        // Enable 3+ productivity packs
        var enabledCount = 0
        for i in collections.indices where collections[i].category == .productivity {
            if enabledCount < 3 {
                collections[i].isEnabled = true
                enabledCount += 1
            }
        }

        let recs = RulesRecommendationEngine.recommendations(from: collections)
        let ids = Set(recs.map(\.collectionId))

        XCTAssertTrue(ids.contains(RuleCollectionIdentifier.leaderKey),
                      "Should recommend Leader Key when 3+ productivity packs enabled")
    }

    func testAllEnabled_NoRecommendations() {
        var collections = RuleCollectionCatalog().defaultCollections()
        for i in collections.indices { collections[i].isEnabled = true }

        let recs = RulesRecommendationEngine.recommendations(from: collections)

        XCTAssertTrue(recs.isEmpty, "No recommendations when everything is enabled")
    }
}
