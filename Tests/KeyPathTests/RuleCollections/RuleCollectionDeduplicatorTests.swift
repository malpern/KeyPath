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
