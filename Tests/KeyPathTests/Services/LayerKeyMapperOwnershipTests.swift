@testable import KeyPathAppKit
import KeyPathRulesCore
import XCTest

final class LayerKeyMapperOwnershipTests: XCTestCase {
    /// Home Row Arrows keeps its keys in the selected preset, not in `mappings`, so the
    /// overlay drew its arrows unowned (pale, no pack color).
    func testPresetRuleKeysBelongToTheirRule() throws {
        var arrows = try XCTUnwrap(RuleCollectionCatalog().defaultCollections().first { $0.id == RuleCollectionIdentifier.homeRowArrows })
        arrows.isEnabled = true
        arrows.configuration.updateSelectedPreset("vim")
        XCTAssertTrue(arrows.mappings.isEmpty, "the bug only shows for preset rules")

        let mapper = LayerKeyMapper()
        let owned = mapper.buildKeyCollectionMap(for: arrows.targetLayer.kanataName, collections: [arrows])
        for key in ["h", "j", "k", "l"] {
            XCTAssertEqual(owned[key], RuleCollectionIdentifier.homeRowArrows, key)
        }
    }
}
