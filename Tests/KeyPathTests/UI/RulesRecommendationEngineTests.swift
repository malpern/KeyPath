import Foundation
@testable import KeyPathAppKit
import XCTest

final class RulesRecommendationEngineTests: XCTestCase {
    func testPopularRecommendationsIncludeDisabledPopularRules() {
        let collections = [
            makeCollection(id: RuleCollectionIdentifier.windowSnapping, enabled: false, category: .productivity),
            makeCollection(id: RuleCollectionIdentifier.homeRowMods, enabled: false, category: .productivity),
            makeCollection(id: RuleCollectionIdentifier.launcher, enabled: false, category: .productivity),
            makeCollection(id: RuleCollectionIdentifier.symbolLayer, enabled: false, category: .productivity)
        ]

        let recommendations = RulesRecommendationEngine.recommendations(from: collections)

        XCTAssertEqual(recommendations.map(\.collectionId), [
            RuleCollectionIdentifier.windowSnapping,
            RuleCollectionIdentifier.homeRowMods,
            RuleCollectionIdentifier.launcher,
            RuleCollectionIdentifier.symbolLayer
        ])
    }

    func testVimEnabledKeepsWindowAndHomeRowRecommended() {
        let collections = [
            makeCollection(id: RuleCollectionIdentifier.vimNavigation, enabled: true, category: .navigation),
            makeCollection(id: RuleCollectionIdentifier.windowSnapping, enabled: false, category: .productivity),
            makeCollection(id: RuleCollectionIdentifier.homeRowMods, enabled: false, category: .productivity),
            makeCollection(id: RuleCollectionIdentifier.launcher, enabled: false, category: .productivity),
            makeCollection(id: RuleCollectionIdentifier.symbolLayer, enabled: false, category: .productivity)
        ]

        let recommendations = RulesRecommendationEngine.recommendations(from: collections)
        let ids = recommendations.map(\.collectionId)

        XCTAssertTrue(ids.contains(RuleCollectionIdentifier.windowSnapping))
        XCTAssertTrue(ids.contains(RuleCollectionIdentifier.homeRowMods))
    }

    func testAlreadyEnabledRecommendationTargetIsSkipped() {
        let collections = [
            makeCollection(id: RuleCollectionIdentifier.vimNavigation, enabled: true, category: .navigation),
            makeCollection(id: RuleCollectionIdentifier.windowSnapping, enabled: true, category: .productivity),
            makeCollection(id: RuleCollectionIdentifier.homeRowMods, enabled: false, category: .productivity),
            makeCollection(id: RuleCollectionIdentifier.launcher, enabled: false, category: .productivity),
            makeCollection(id: RuleCollectionIdentifier.symbolLayer, enabled: false, category: .productivity)
        ]

        let recommendations = RulesRecommendationEngine.recommendations(from: collections)

        XCTAssertFalse(recommendations.map(\.collectionId).contains(RuleCollectionIdentifier.windowSnapping))
    }

    func testSymbolLayerEnabledRecommendsSequences() {
        let collections = [
            makeCollection(id: RuleCollectionIdentifier.symbolLayer, enabled: true, category: .productivity),
            makeCollection(id: RuleCollectionIdentifier.sequences, enabled: false, category: .productivity),
            makeCollection(id: RuleCollectionIdentifier.windowSnapping, enabled: false, category: .productivity),
            makeCollection(id: RuleCollectionIdentifier.homeRowMods, enabled: false, category: .productivity),
            makeCollection(id: RuleCollectionIdentifier.launcher, enabled: false, category: .productivity)
        ]

        let recommendations = RulesRecommendationEngine.recommendations(from: collections)

        XCTAssertTrue(recommendations.map(\.collectionId).contains(RuleCollectionIdentifier.sequences))
    }

    func testThreeEnabledProductivityRulesRecommendLeaderKey() {
        let collections = [
            makeCollection(id: RuleCollectionIdentifier.windowSnapping, enabled: true, category: .productivity),
            makeCollection(id: RuleCollectionIdentifier.homeRowMods, enabled: true, category: .productivity),
            makeCollection(id: RuleCollectionIdentifier.symbolLayer, enabled: true, category: .productivity),
            makeCollection(id: RuleCollectionIdentifier.leaderKey, enabled: false, category: .system)
        ]

        let recommendations = RulesRecommendationEngine.recommendations(from: collections)

        XCTAssertEqual(recommendations.map(\.collectionId), [RuleCollectionIdentifier.leaderKey])
    }

    private func makeCollection(id: UUID, enabled: Bool, category: RuleCollectionCategory) -> RuleCollection {
        RuleCollection(
            id: id,
            name: "Collection \(id.uuidString.prefix(6))",
            summary: "Test",
            category: category,
            mappings: [],
            isEnabled: enabled
        )
    }
}
