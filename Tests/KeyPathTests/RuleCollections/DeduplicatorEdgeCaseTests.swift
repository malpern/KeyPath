@testable import KeyPathAppKit
import KeyPathRulesCore
import XCTest

/// Edge case tests for RuleCollectionDeduplicator.
/// Verifies merge logic when multiple collections map the same key.
final class DeduplicatorEdgeCaseTests: XCTestCase {
    // MARK: - Same Key, Different Collections

    func testFirstCollectionWins_SameKeyOnSameLayer() {
        let collection1 = makeCollection(name: "First", mappings: [
            KeyMapping(input: "a", action: .keystroke(key: "b")),
        ])
        let collection2 = makeCollection(name: "Second", mappings: [
            KeyMapping(input: "a", action: .keystroke(key: "c")),
        ])

        let deduped = RuleCollectionDeduplicator.dedupe([collection1, collection2])
        let allMappings = deduped.flatMap(\.mappings)
        let aMappings = allMappings.filter { $0.input == "a" }

        XCTAssertEqual(aMappings.count, 1, "Should have exactly one mapping for 'a'")
        XCTAssertEqual(aMappings.first?.action.outputString, "b", "First collection should win")
    }

    func testDifferentLayers_BothSurvive() {
        let collection1 = makeCollection(name: "Base", mappings: [
            KeyMapping(input: "h", action: .keystroke(key: "left")),
        ], layer: .base)
        let collection2 = makeCollection(name: "Nav", mappings: [
            KeyMapping(input: "h", action: .keystroke(key: "home")),
        ], layer: .navigation)

        let deduped = RuleCollectionDeduplicator.dedupe([collection1, collection2])
        let allMappings = deduped.flatMap(\.mappings)
        let hMappings = allMappings.filter { $0.input == "h" }

        XCTAssertEqual(hMappings.count, 2, "Same key on different layers should both survive")
    }

    func testDisabledCollection_DoesNotClaimKeys() {
        let disabled = makeCollection(name: "Disabled", mappings: [
            KeyMapping(input: "a", action: .keystroke(key: "b")),
        ], isEnabled: false)
        let enabled = makeCollection(name: "Enabled", mappings: [
            KeyMapping(input: "a", action: .keystroke(key: "c")),
        ])

        let deduped = RuleCollectionDeduplicator.dedupe([disabled, enabled])
        let enabledMappings = deduped.filter(\.isEnabled).flatMap(\.mappings)
        let aMappings = enabledMappings.filter { $0.input == "a" }

        XCTAssertEqual(aMappings.first?.action.outputString, "c", "Enabled collection should win over disabled")
    }

    // MARK: - Conflict Detection

    func testConflictDetection_IdentifiesOverlappingKeys() {
        let collection1 = makeCollection(name: "Pack A", mappings: [
            KeyMapping(input: "a", action: .keystroke(key: "b")),
            KeyMapping(input: "s", action: .keystroke(key: "d")),
        ])
        let collection2 = makeCollection(name: "Pack B", mappings: [
            KeyMapping(input: "a", action: .keystroke(key: "x")),
            KeyMapping(input: "f", action: .keystroke(key: "g")),
        ])

        let conflicts = RuleCollectionDeduplicator.detectConflicts(in: [collection1, collection2])
        XCTAssertFalse(conflicts.isEmpty, "Should detect conflict on key 'a'")
    }

    func testConflictDetection_NoConflict_DifferentKeys() {
        let collection1 = makeCollection(name: "Pack A", mappings: [
            KeyMapping(input: "a", action: .keystroke(key: "b")),
        ])
        let collection2 = makeCollection(name: "Pack B", mappings: [
            KeyMapping(input: "s", action: .keystroke(key: "d")),
        ])

        let conflicts = RuleCollectionDeduplicator.detectConflicts(in: [collection1, collection2])
        XCTAssertTrue(conflicts.isEmpty, "No conflict when keys don't overlap")
    }

    // MARK: - Multiple Overlapping Collections

    func testThreeCollections_FirstStillWins() {
        let c1 = makeCollection(name: "First", mappings: [KeyMapping(input: "a", action: .keystroke(key: "1"))])
        let c2 = makeCollection(name: "Second", mappings: [KeyMapping(input: "a", action: .keystroke(key: "2"))])
        let c3 = makeCollection(name: "Third", mappings: [KeyMapping(input: "a", action: .keystroke(key: "3"))])

        let deduped = RuleCollectionDeduplicator.dedupe([c1, c2, c3])
        let aMappings = deduped.flatMap(\.mappings).filter { $0.input == "a" }

        XCTAssertEqual(aMappings.count, 1)
        XCTAssertEqual(aMappings.first?.action.outputString, "1", "First collection should still win with 3 conflicts")
    }

    func testPartialOverlap_NonConflictingKeysPreserved() {
        let c1 = makeCollection(name: "First", mappings: [
            KeyMapping(input: "a", action: .keystroke(key: "b")),
            KeyMapping(input: "s", action: .keystroke(key: "d")),
        ])
        let c2 = makeCollection(name: "Second", mappings: [
            KeyMapping(input: "a", action: .keystroke(key: "x")),
            KeyMapping(input: "f", action: .keystroke(key: "g")),
        ])

        let deduped = RuleCollectionDeduplicator.dedupe([c1, c2])
        let allMappings = deduped.flatMap(\.mappings)

        XCTAssertTrue(allMappings.contains { $0.input == "s" && $0.action.outputString == "d" },
                      "Non-conflicting key 's' from first collection should survive")
        XCTAssertTrue(allMappings.contains { $0.input == "f" && $0.action.outputString == "g" },
                      "Non-conflicting key 'f' from second collection should survive")
    }

    // MARK: - Empty Collections

    func testEmptyCollection_DoesNotAffectOthers() {
        let empty = makeCollection(name: "Empty", mappings: [])
        let normal = makeCollection(name: "Normal", mappings: [
            KeyMapping(input: "a", action: .keystroke(key: "b")),
        ])

        let deduped = RuleCollectionDeduplicator.dedupe([empty, normal])
        let allMappings = deduped.flatMap(\.mappings)

        XCTAssertEqual(allMappings.count, 1)
        XCTAssertEqual(allMappings.first?.input, "a")
    }

    // MARK: - Helpers

    private func makeCollection(
        name: String,
        mappings: [KeyMapping],
        layer: RuleCollectionLayer = .base,
        isEnabled: Bool = true
    ) -> RuleCollection {
        RuleCollection(
            name: name,
            summary: "",
            category: .productivity,
            mappings: mappings,
            isEnabled: isEnabled,
            targetLayer: layer
        )
    }
}
