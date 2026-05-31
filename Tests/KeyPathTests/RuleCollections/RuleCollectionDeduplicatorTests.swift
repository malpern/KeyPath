@testable import KeyPathAppKit
import KeyPathCore
import XCTest

final class RuleCollectionDeduplicatorTests: XCTestCase {
    // MARK: - Conflict Detection Tests

    func testDetectsConflictWhenTwoCollectionsMapSameKey() {
        let collection1 = RuleCollection(
            name: "Vim Nav",
            summary: "Nav",
            category: .navigation,
            mappings: [KeyMapping(input: "h", action: .keystroke(key: "left"))],
            targetLayer: .navigation
        )

        let collection2 = RuleCollection(
            name: "Arrow Keys",
            summary: "Arrows",
            category: .navigation,
            mappings: [KeyMapping(input: "h", action: .keystroke(key: "home"))],
            targetLayer: .navigation
        )

        let conflicts = RuleCollectionDeduplicator.detectConflicts(in: [collection1, collection2])

        XCTAssertEqual(conflicts.count, 1)
        XCTAssertEqual(conflicts.first?.inputKey, "h")
        XCTAssertEqual(conflicts.first?.conflictingCollections, ["Vim Nav", "Arrow Keys"])
    }

    func testNoConflictWhenSameKeyDifferentLayers() {
        let collection1 = RuleCollection(
            name: "Nav Vim",
            summary: "Nav",
            category: .navigation,
            mappings: [KeyMapping(input: "h", action: .keystroke(key: "left"))],
            targetLayer: .navigation
        )

        let collection2 = RuleCollection(
            name: "Base Vim",
            summary: "Base",
            category: .productivity,
            mappings: [KeyMapping(input: "h", action: .keystroke(key: "backspace"))],
            targetLayer: .base
        )

        let conflicts = RuleCollectionDeduplicator.detectConflicts(in: [collection1, collection2])

        XCTAssertTrue(conflicts.isEmpty)
    }

    func testNoConflictWhenNoOverlappingKeys() {
        let collection1 = RuleCollection(
            name: "Vim Nav",
            summary: "Nav",
            category: .navigation,
            mappings: [KeyMapping(input: "h", action: .keystroke(key: "left"))],
            targetLayer: .navigation
        )

        let collection2 = RuleCollection(
            name: "Delete Keys",
            summary: "Del",
            category: .navigation,
            mappings: [KeyMapping(input: "d", action: .keystroke(key: "del"))],
            targetLayer: .navigation
        )

        let conflicts = RuleCollectionDeduplicator.detectConflicts(in: [collection1, collection2])

        XCTAssertTrue(conflicts.isEmpty)
    }

    func testDisabledCollectionsIgnoredInConflictDetection() {
        let enabled = RuleCollection(
            name: "Vim Nav",
            summary: "Nav",
            category: .navigation,
            mappings: [KeyMapping(input: "h", action: .keystroke(key: "left"))],
            isEnabled: true,
            targetLayer: .navigation
        )

        var disabled = RuleCollection(
            name: "Disabled",
            summary: "Disabled",
            category: .navigation,
            mappings: [KeyMapping(input: "h", action: .keystroke(key: "home"))],
            isEnabled: false,
            targetLayer: .navigation
        )
        disabled.isEnabled = false

        let conflicts = RuleCollectionDeduplicator.detectConflicts(in: [enabled, disabled])

        XCTAssertTrue(conflicts.isEmpty)
    }

    func testDetectsMultipleConflicts() {
        let collection1 = RuleCollection(
            name: "Vim",
            summary: "Vim",
            category: .navigation,
            mappings: [
                KeyMapping(input: "h", action: .keystroke(key: "left")),
                KeyMapping(input: "j", action: .keystroke(key: "down"))
            ],
            targetLayer: .navigation
        )

        let collection2 = RuleCollection(
            name: "Arrows",
            summary: "Arrows",
            category: .navigation,
            mappings: [
                KeyMapping(input: "h", action: .keystroke(key: "home")),
                KeyMapping(input: "j", action: .keystroke(key: "pgdn"))
            ],
            targetLayer: .navigation
        )

        let conflicts = RuleCollectionDeduplicator.detectConflicts(in: [collection1, collection2])

        XCTAssertEqual(conflicts.count, 2)
        let conflictKeys = conflicts.map(\.inputKey).sorted()
        XCTAssertEqual(conflictKeys, ["h", "j"])
    }

    // MARK: - Momentary Activator Conflict Detection (#466)

    func testDetectsConflictWhenTwoActivatorsTargetDifferentLayers() {
        // Two collections claim the same physical activator key ("space") but route
        // it to different layers. The silent `seenActivators` dedup in
        // buildCollectionBlocks would drop one without explanation — surface it instead.
        let navCollection = RuleCollection(
            name: "Vim Nav",
            summary: "Nav",
            category: .navigation,
            mappings: [KeyMapping(input: "h", action: .keystroke(key: "left"))],
            isEnabled: true,
            targetLayer: .navigation,
            momentaryActivator: MomentaryActivator(input: "space", targetLayer: .navigation)
        )

        let windowCollection = RuleCollection(
            name: "Window Mgmt",
            summary: "Window",
            category: .productivity,
            mappings: [KeyMapping(input: "y", action: .keystroke(key: "left"))],
            isEnabled: true,
            targetLayer: .custom("window"),
            momentaryActivator: MomentaryActivator(input: "space", targetLayer: .custom("window"))
        )

        let conflicts = RuleCollectionDeduplicator.detectConflicts(in: [navCollection, windowCollection])

        // "space" normalizes to the kanata key "spc"
        let activatorConflict = conflicts.first { $0.inputKey == "spc" }
        XCTAssertNotNil(activatorConflict, "Activator key collision on different layers should be surfaced")
        XCTAssertEqual(Set(activatorConflict?.conflictingCollections ?? []), ["Vim Nav", "Window Mgmt"])
    }

    func testNoActivatorConflictWhenSameTargetLayer() {
        // Two navigation collections sharing the same activator (space → nav) are
        // redundant, not conflicting — both want the same layer activated the same way.
        let first = RuleCollection(
            name: "Vim Nav",
            summary: "Nav",
            category: .navigation,
            mappings: [KeyMapping(input: "h", action: .keystroke(key: "left"))],
            isEnabled: true,
            targetLayer: .navigation,
            momentaryActivator: MomentaryActivator(input: "space", targetLayer: .navigation)
        )

        let second = RuleCollection(
            name: "Nav Extras",
            summary: "Nav",
            category: .navigation,
            mappings: [KeyMapping(input: "j", action: .keystroke(key: "down"))],
            isEnabled: true,
            targetLayer: .navigation,
            momentaryActivator: MomentaryActivator(input: "space", targetLayer: .navigation)
        )

        let conflicts = RuleCollectionDeduplicator.detectConflicts(in: [first, second])

        XCTAssertFalse(
            conflicts.contains { $0.inputKey == "spc" },
            "Identical activators targeting the same layer are redundant, not a conflict"
        )
    }

    func testNoActivatorConflictWhenDifferentKeys() {
        let first = RuleCollection(
            name: "Vim Nav",
            summary: "Nav",
            category: .navigation,
            mappings: [KeyMapping(input: "h", action: .keystroke(key: "left"))],
            isEnabled: true,
            targetLayer: .navigation,
            momentaryActivator: MomentaryActivator(input: "space", targetLayer: .navigation)
        )

        let second = RuleCollection(
            name: "Window Mgmt",
            summary: "Window",
            category: .productivity,
            mappings: [KeyMapping(input: "y", action: .keystroke(key: "left"))],
            isEnabled: true,
            targetLayer: .custom("window"),
            momentaryActivator: MomentaryActivator(input: "tab", targetLayer: .custom("window"))
        )

        let conflicts = RuleCollectionDeduplicator.detectConflicts(in: [first, second])

        XCTAssertTrue(conflicts.isEmpty, "Distinct activator keys do not conflict")
    }

    func testNoActivatorConflictWhenSameKeyDifferentSourceLayers() {
        // A key can carry a different binding per source layer. `f` activating one
        // layer from base and another from nav is a valid chained-layer setup
        // (e.g. Home Row Arrows on base + Function layer reached from nav), not a
        // conflict — the generator places them in separate layers.
        let fromBase = RuleCollection(
            name: "Home Row Arrows",
            summary: "Arrows",
            category: .navigation,
            mappings: [KeyMapping(input: "h", action: .keystroke(key: "left"))],
            isEnabled: true,
            targetLayer: .navigation,
            momentaryActivator: MomentaryActivator(input: "f", targetLayer: .navigation, sourceLayer: .base)
        )

        let fromNav = RuleCollection(
            name: "Function Layer",
            summary: "Function",
            category: .productivity,
            mappings: [KeyMapping(input: "j", action: .keystroke(key: "f5"))],
            isEnabled: true,
            targetLayer: .custom("function"),
            momentaryActivator: MomentaryActivator(input: "f", targetLayer: .custom("function"), sourceLayer: .navigation)
        )

        let conflicts = RuleCollectionDeduplicator.detectConflicts(in: [fromBase, fromNav])

        XCTAssertFalse(
            conflicts.contains { $0.inputKey == "f" },
            "Same activator key on different source layers is a valid chained setup, not a conflict"
        )
    }

    func testDisabledCollectionActivatorIgnoredInConflictDetection() {
        let enabled = RuleCollection(
            name: "Vim Nav",
            summary: "Nav",
            category: .navigation,
            mappings: [KeyMapping(input: "h", action: .keystroke(key: "left"))],
            isEnabled: true,
            targetLayer: .navigation,
            momentaryActivator: MomentaryActivator(input: "space", targetLayer: .navigation)
        )

        var disabled = RuleCollection(
            name: "Window Mgmt",
            summary: "Window",
            category: .productivity,
            mappings: [KeyMapping(input: "y", action: .keystroke(key: "left"))],
            isEnabled: false,
            targetLayer: .custom("window"),
            momentaryActivator: MomentaryActivator(input: "space", targetLayer: .custom("window"))
        )
        disabled.isEnabled = false

        let conflicts = RuleCollectionDeduplicator.detectConflicts(in: [enabled, disabled])

        XCTAssertFalse(
            conflicts.contains { $0.inputKey == "spc" },
            "A disabled collection's activator must not trigger a conflict"
        )
    }

    // MARK: - Leader Key vs Activator Conflict Detection (#463)

    func testDetectsConflictBetweenLeaderKeyAndCollectionActivator() {
        // The system leader key (space → nav, from base) and a collection that
        // claims the same physical key from base but routes it to a different layer
        // collide. buildCollectionBlocks inserts the leader alias into seenActivators
        // first, so the collection's activator is silently dropped — surface it.
        let leader = LeaderKeyPreference(key: "space", targetLayer: .navigation, enabled: true)

        let windowCollection = RuleCollection(
            name: "Window Mgmt",
            summary: "Window",
            category: .productivity,
            mappings: [KeyMapping(input: "y", action: .keystroke(key: "left"))],
            isEnabled: true,
            targetLayer: .custom("window"),
            momentaryActivator: MomentaryActivator(input: "space", targetLayer: .custom("window"))
        )

        let conflicts = RuleCollectionDeduplicator.detectConflicts(
            in: [windowCollection],
            leaderKey: leader
        )

        let conflict = conflicts.first { $0.inputKey == "spc" }
        XCTAssertNotNil(conflict, "Leader key colliding with a collection activator should be surfaced")
        XCTAssertTrue(conflict?.conflictingCollections.contains("Window Mgmt") ?? false)
    }

    func testNoConflictWhenLeaderKeyMatchesCollectionActivatorExactly() {
        // The leader key (space → nav) and a nav collection's own space → nav
        // activator describe the same activation — redundant, not a conflict.
        let leader = LeaderKeyPreference(key: "space", targetLayer: .navigation, enabled: true)

        let navCollection = RuleCollection(
            name: "Vim Nav",
            summary: "Nav",
            category: .navigation,
            mappings: [KeyMapping(input: "h", action: .keystroke(key: "left"))],
            isEnabled: true,
            targetLayer: .navigation,
            momentaryActivator: MomentaryActivator(input: "space", targetLayer: .navigation)
        )

        let conflicts = RuleCollectionDeduplicator.detectConflicts(
            in: [navCollection],
            leaderKey: leader
        )

        XCTAssertFalse(
            conflicts.contains { $0.inputKey == "spc" },
            "Leader key matching a collection activator exactly is redundant, not a conflict"
        )
    }

    func testNoConflictWhenLeaderKeyDisabled() {
        let leader = LeaderKeyPreference(key: "space", targetLayer: .navigation, enabled: false)

        let windowCollection = RuleCollection(
            name: "Window Mgmt",
            summary: "Window",
            category: .productivity,
            mappings: [KeyMapping(input: "y", action: .keystroke(key: "left"))],
            isEnabled: true,
            targetLayer: .custom("window"),
            momentaryActivator: MomentaryActivator(input: "space", targetLayer: .custom("window"))
        )

        let conflicts = RuleCollectionDeduplicator.detectConflicts(
            in: [windowCollection],
            leaderKey: leader
        )

        XCTAssertTrue(conflicts.isEmpty, "A disabled leader key must not produce conflicts")
    }

    func testNoConflictWhenLeaderKeyDifferentKey() {
        let leader = LeaderKeyPreference(key: "caps", targetLayer: .navigation, enabled: true)

        let windowCollection = RuleCollection(
            name: "Window Mgmt",
            summary: "Window",
            category: .productivity,
            mappings: [KeyMapping(input: "y", action: .keystroke(key: "left"))],
            isEnabled: true,
            targetLayer: .custom("window"),
            momentaryActivator: MomentaryActivator(input: "space", targetLayer: .custom("window"))
        )

        let conflicts = RuleCollectionDeduplicator.detectConflicts(
            in: [windowCollection],
            leaderKey: leader
        )

        XCTAssertTrue(conflicts.isEmpty, "Leader key on a different physical key does not conflict")
    }

    func testNoConflictWhenLeaderKeyCollidesWithChainedActivator() {
        // Leader key activates nav from base; a collection reaches another layer
        // using the same key but FROM the nav layer (chained). Different source
        // layers — valid, not a conflict.
        let leader = LeaderKeyPreference(key: "f", targetLayer: .navigation, enabled: true)

        let chained = RuleCollection(
            name: "Function Layer",
            summary: "Function",
            category: .productivity,
            mappings: [KeyMapping(input: "j", action: .keystroke(key: "f5"))],
            isEnabled: true,
            targetLayer: .custom("function"),
            momentaryActivator: MomentaryActivator(input: "f", targetLayer: .custom("function"), sourceLayer: .navigation)
        )

        let conflicts = RuleCollectionDeduplicator.detectConflicts(
            in: [chained],
            leaderKey: leader
        )

        XCTAssertTrue(conflicts.isEmpty, "Leader (base) vs chained activator (nav) on the same key is valid")
    }

    func testDetectsConflictWhenBaseMappingShadowsLeaderKey() {
        // A base-layer collection that maps the leader's physical key collides:
        // buildCollectionBlocks emits the leader's base entry and deduplicateBlocks
        // keeps it, silently dropping the user's base mapping.
        let leader = LeaderKeyPreference(key: "space", targetLayer: .navigation, enabled: true)

        let baseCollection = RuleCollection(
            name: "Custom Base",
            summary: "Base",
            category: .custom,
            mappings: [KeyMapping(input: "space", action: .keystroke(key: "backspace"))],
            isEnabled: true,
            targetLayer: .base
        )

        let conflicts = RuleCollectionDeduplicator.detectConflicts(
            in: [baseCollection],
            leaderKey: leader
        )

        let conflict = conflicts.first { $0.inputKey == "spc" }
        XCTAssertNotNil(conflict, "A base mapping of the leader key should be surfaced as a conflict")
        XCTAssertTrue(conflict?.conflictingCollections.contains("Leader Key") ?? false)
        XCTAssertTrue(conflict?.conflictingCollections.contains("Custom Base") ?? false)
    }

    func testNoConflictWhenBaseMappingDiffersFromLeaderKey() {
        let leader = LeaderKeyPreference(key: "space", targetLayer: .navigation, enabled: true)

        let baseCollection = RuleCollection(
            name: "Custom Base",
            summary: "Base",
            category: .custom,
            mappings: [KeyMapping(input: "caps", action: .keystroke(key: "escape"))],
            isEnabled: true,
            targetLayer: .base
        )

        let conflicts = RuleCollectionDeduplicator.detectConflicts(
            in: [baseCollection],
            leaderKey: leader
        )

        XCTAssertTrue(conflicts.isEmpty, "A base mapping on a different key does not conflict with the leader")
    }

    // MARK: - Deduplication Tests

    func testDisabledCollectionDoesNotClaimKeysInDedupe() {
        // A disabled collection should NOT claim keys, so an enabled collection
        // with the same key should keep its mapping
        var disabled = RuleCollection(
            name: "Disabled",
            summary: "Disabled",
            category: .navigation,
            mappings: [KeyMapping(input: "h", action: .keystroke(key: "home"))],
            isEnabled: false,
            targetLayer: .navigation
        )
        disabled.isEnabled = false

        let enabled = RuleCollection(
            name: "Enabled",
            summary: "Enabled",
            category: .navigation,
            mappings: [KeyMapping(input: "h", action: .keystroke(key: "left"))],
            isEnabled: true,
            targetLayer: .navigation
        )

        // Disabled comes first - should NOT claim the key
        let deduped = RuleCollectionDeduplicator.dedupe([disabled, enabled])

        // Disabled collection unchanged
        XCTAssertEqual(deduped[0].mappings.count, 1)
        // Enabled collection should KEEP its mapping (not be filtered out)
        XCTAssertEqual(deduped[1].mappings.count, 1)
        XCTAssertEqual(deduped[1].mappings.first?.action.outputString, "left")
    }

    func testKeepsFirstMomentaryActivator() {
        let first = RuleCollection(
            name: "Vim Nav",
            summary: "Nav layer",
            category: .navigation,
            mappings: [KeyMapping(input: "h", action: .keystroke(key: "left"))],
            isEnabled: true,
            targetLayer: .navigation,
            momentaryActivator: MomentaryActivator(input: "space", targetLayer: .navigation)
        )

        let second = RuleCollection(
            name: "Delete Enh",
            summary: "Delete",
            category: .navigation,
            mappings: [KeyMapping(input: "d", action: .keystroke(key: "del"))],
            isEnabled: true,
            targetLayer: .navigation,
            momentaryActivator: MomentaryActivator(input: "space", targetLayer: .navigation)
        )

        let deduped = RuleCollectionDeduplicator.dedupe([first, second])

        XCTAssertNotNil(deduped[0].momentaryActivator)
        XCTAssertNil(deduped[1].momentaryActivator)
    }

    func testRemovesDuplicateMappingsWithinCollection() {
        let mapping = KeyMapping(input: "caps", action: .keystroke(key: "esc"))
        let duplicate = KeyMapping(input: "caps", action: .keystroke(key: "esc"))
        let collection = RuleCollection(
            name: "Caps Remap",
            summary: "Test",
            category: .productivity,
            mappings: [mapping, duplicate]
        )

        let deduped = RuleCollectionDeduplicator.dedupe([collection])

        XCTAssertEqual(deduped.first?.mappings.count, 1)
    }

    func testKeepsFirstMappingWhenInputRepeated() {
        // Same input key with different outputs - only first should be kept
        // because Kanata doesn't allow duplicate keys in defsrc
        let first = KeyMapping(input: "caps", action: .keystroke(key: "esc"))
        let second = KeyMapping(input: "caps", action: .keystroke(key: "hyper"))
        let collection = RuleCollection(
            name: "Caps Options",
            summary: "Test",
            category: .productivity,
            mappings: [first, second]
        )

        let deduped = RuleCollectionDeduplicator.dedupe([collection])

        XCTAssertEqual(deduped.first?.mappings.count, 1)
        XCTAssertEqual(deduped.first?.mappings.first?.action.outputString, "esc")
    }

    func testRemovesDuplicateInputKeysAcrossCollections() {
        // Custom rule for F6 should win over macOS Function Keys F6
        let customRule = RuleCollection(
            name: "Launch Arc",
            summary: "Custom",
            category: .custom,
            mappings: [KeyMapping(input: "f6", action: .rawKanata("(push-msg \"launch:com.browser\")"))]
        )

        let functionKeys = RuleCollection(
            name: "macOS Function Keys",
            summary: "System",
            category: .system,
            mappings: [
                KeyMapping(input: "f5", action: .rawKanata("(push-msg \"system:dictation\")")),
                KeyMapping(input: "f6", action: .rawKanata("(push-msg \"system:dnd\")")),
                KeyMapping(input: "f7", action: .keystroke(key: "prev"))
            ]
        )

        // Custom rules come first, so they take priority
        let deduped = RuleCollectionDeduplicator.dedupe([customRule, functionKeys])

        // Custom rule should keep its F6 mapping
        XCTAssertEqual(deduped[0].mappings.count, 1)
        XCTAssertEqual(deduped[0].mappings[0].input, "f6")
        XCTAssertTrue(deduped[0].mappings[0].action.outputString.contains("launch"))

        // Function keys should have F6 removed (claimed by custom rule)
        XCTAssertEqual(deduped[1].mappings.count, 2)
        XCTAssertFalse(deduped[1].mappings.contains { $0.input == "f6" })
        XCTAssertTrue(deduped[1].mappings.contains { $0.input == "f5" })
        XCTAssertTrue(deduped[1].mappings.contains { $0.input == "f7" })
    }
}
