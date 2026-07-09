@testable import KeyPathAppKit
import KeyPathCore
import KeyPathRulesCore
import XCTest

/// Tests for the save-time mapping-conflict resolvability core (#460):
/// a conflict is resolvable-by-disable only when every named party maps to a
/// real, enabled collection.
final class SaveTimeConflictResolutionTests: XCTestCase {
    private func collection(_ name: String, isEnabled: Bool = true) -> RuleCollection {
        RuleCollection(
            name: name,
            summary: name,
            category: .productivity,
            mappings: [KeyMapping(input: "a", action: .keystroke(key: "b"))],
            isEnabled: isEnabled
        )
    }

    private func conflict(_ collections: [String], key: String = ";") -> KeyPathError.MappingConflictInfo {
        KeyPathError.MappingConflictInfo(
            inputKey: key,
            layer: "Base",
            conflictingCollections: collections
        )
    }

    func testResolvableWhenAllPartiesAreRealCollections() {
        let collections = [collection("Home Row Mods"), collection("Home Row Layer Toggles")]
        let conflicts = [conflict(["Home Row Mods", "Home Row Layer Toggles"])]

        let resolvable = RuleCollectionsManager.resolvableCollectionConflict(
            conflicts: conflicts, collections: collections
        )

        XCTAssertEqual(resolvable?.map(\.name), ["Home Row Layer Toggles", "Home Row Mods"])
    }

    func testNotResolvableWhenAPartyIsSynthetic() {
        // Chord-group-name conflicts name "chord group '...'", which is not a collection.
        let collections = [collection("Chord Groups")]
        let conflicts = [conflict(["chord group 'navigation'", "chord group 'navigation'"], key: "navigation")]

        XCTAssertNil(RuleCollectionsManager.resolvableCollectionConflict(
            conflicts: conflicts, collections: collections
        ))
    }

    func testNotResolvableWhenLeaderKeyPartyHasNoCollection() {
        // The leader conflict names "Leader Key" (a preference, not a collection).
        let collections = [collection("Window Mgmt")]
        let conflicts = [conflict(["Leader Key", "Window Mgmt"], key: "spc")]

        XCTAssertNil(RuleCollectionsManager.resolvableCollectionConflict(
            conflicts: conflicts, collections: collections
        ))
    }

    func testNotResolvableWhenPartyCollectionIsDisabled() {
        // A disabled collection isn't in the active set, so it can't be matched.
        let collections = [collection("Home Row Mods"), collection("Home Row Layer Toggles", isEnabled: false)]
        let conflicts = [conflict(["Home Row Mods", "Home Row Layer Toggles"])]

        XCTAssertNil(RuleCollectionsManager.resolvableCollectionConflict(
            conflicts: conflicts, collections: collections
        ))
    }

    func testNotResolvableWhenOnlyOneDistinctCollection() {
        let collections = [collection("Home Row Mods")]
        let conflicts = [conflict(["Home Row Mods", "Home Row Mods"])]

        XCTAssertNil(RuleCollectionsManager.resolvableCollectionConflict(
            conflicts: conflicts, collections: collections
        ))
    }

    func testMixedResolvableAndSyntheticFallsBack() {
        // If any conflict in the set is non-actionable, the whole set falls back.
        let collections = [collection("Home Row Mods"), collection("Home Row Layer Toggles")]
        let conflicts = [
            conflict(["Home Row Mods", "Home Row Layer Toggles"]),
            conflict(["caps-lock / caps_lock"], key: "caps-lock / caps_lock")
        ]

        XCTAssertNil(RuleCollectionsManager.resolvableCollectionConflict(
            conflicts: conflicts, collections: collections
        ))
    }

    func testEmptyConflictsNotResolvable() {
        XCTAssertNil(RuleCollectionsManager.resolvableCollectionConflict(
            conflicts: [], collections: [collection("X")]
        ))
    }
}
