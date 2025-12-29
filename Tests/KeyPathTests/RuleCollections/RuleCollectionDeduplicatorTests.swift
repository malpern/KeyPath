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
            mappings: [KeyMapping(input: "h", output: "left")],
            targetLayer: .navigation
        )

        let collection2 = RuleCollection(
            name: "Arrow Keys",
            summary: "Arrows",
            category: .navigation,
            mappings: [KeyMapping(input: "h", output: "home")],
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
            mappings: [KeyMapping(input: "h", output: "left")],
            targetLayer: .navigation
        )

        let collection2 = RuleCollection(
            name: "Base Vim",
            summary: "Base",
            category: .productivity,
            mappings: [KeyMapping(input: "h", output: "backspace")],
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
            mappings: [KeyMapping(input: "h", output: "left")],
            targetLayer: .navigation
        )

        let collection2 = RuleCollection(
            name: "Delete Keys",
            summary: "Del",
            category: .navigation,
            mappings: [KeyMapping(input: "d", output: "del")],
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
            mappings: [KeyMapping(input: "h", output: "left")],
            isEnabled: true,
            targetLayer: .navigation
        )

        var disabled = RuleCollection(
            name: "Disabled",
            summary: "Disabled",
            category: .navigation,
            mappings: [KeyMapping(input: "h", output: "home")],
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
                KeyMapping(input: "h", output: "left"),
                KeyMapping(input: "j", output: "down")
            ],
            targetLayer: .navigation
        )

        let collection2 = RuleCollection(
            name: "Arrows",
            summary: "Arrows",
            category: .navigation,
            mappings: [
                KeyMapping(input: "h", output: "home"),
                KeyMapping(input: "j", output: "pgdn")
            ],
            targetLayer: .navigation
        )

        let conflicts = RuleCollectionDeduplicator.detectConflicts(in: [collection1, collection2])

        XCTAssertEqual(conflicts.count, 2)
        let conflictKeys = conflicts.map(\.inputKey).sorted()
        XCTAssertEqual(conflictKeys, ["h", "j"])
    }

    // MARK: - Deduplication Tests

    func testDisabledCollectionDoesNotClaimKeysInDedupe() {
        // A disabled collection should NOT claim keys, so an enabled collection
        // with the same key should keep its mapping
        var disabled = RuleCollection(
            name: "Disabled",
            summary: "Disabled",
            category: .navigation,
            mappings: [KeyMapping(input: "h", output: "home")],
            isEnabled: false,
            targetLayer: .navigation
        )
        disabled.isEnabled = false

        let enabled = RuleCollection(
            name: "Enabled",
            summary: "Enabled",
            category: .navigation,
            mappings: [KeyMapping(input: "h", output: "left")],
            isEnabled: true,
            targetLayer: .navigation
        )

        // Disabled comes first - should NOT claim the key
        let deduped = RuleCollectionDeduplicator.dedupe([disabled, enabled])

        // Disabled collection unchanged
        XCTAssertEqual(deduped[0].mappings.count, 1)
        // Enabled collection should KEEP its mapping (not be filtered out)
        XCTAssertEqual(deduped[1].mappings.count, 1)
        XCTAssertEqual(deduped[1].mappings.first?.output, "left")
    }

    func testKeepsFirstMomentaryActivator() {
        let first = RuleCollection(
            name: "Vim Nav",
            summary: "Nav layer",
            category: .navigation,
            mappings: [KeyMapping(input: "h", output: "left")],
            isEnabled: true,
            targetLayer: .navigation,
            momentaryActivator: MomentaryActivator(input: "space", targetLayer: .navigation)
        )

        let second = RuleCollection(
            name: "Delete Enh",
            summary: "Delete",
            category: .navigation,
            mappings: [KeyMapping(input: "d", output: "del")],
            isEnabled: true,
            targetLayer: .navigation,
            momentaryActivator: MomentaryActivator(input: "space", targetLayer: .navigation)
        )

        let deduped = RuleCollectionDeduplicator.dedupe([first, second])

        XCTAssertNotNil(deduped[0].momentaryActivator)
        XCTAssertNil(deduped[1].momentaryActivator)
    }

    func testRemovesDuplicateMappingsWithinCollection() {
        let mapping = KeyMapping(input: "caps", output: "esc")
        let duplicate = KeyMapping(input: "caps", output: "esc")
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
        let first = KeyMapping(input: "caps", output: "esc")
        let second = KeyMapping(input: "caps", output: "hyper")
        let collection = RuleCollection(
            name: "Caps Options",
            summary: "Test",
            category: .productivity,
            mappings: [first, second]
        )

        let deduped = RuleCollectionDeduplicator.dedupe([collection])

        XCTAssertEqual(deduped.first?.mappings.count, 1)
        XCTAssertEqual(deduped.first?.mappings.first?.output, "esc")
    }

    func testRemovesDuplicateInputKeysAcrossCollections() {
        // Custom rule for F6 should win over macOS Function Keys F6
        let customRule = RuleCollection(
            name: "Launch Arc",
            summary: "Custom",
            category: .custom,
            mappings: [KeyMapping(input: "f6", output: "(push-msg \"launch:com.browser\")")]
        )

        let functionKeys = RuleCollection(
            name: "macOS Function Keys",
            summary: "System",
            category: .system,
            mappings: [
                KeyMapping(input: "f5", output: "(push-msg \"system:dictation\")"),
                KeyMapping(input: "f6", output: "(push-msg \"system:dnd\")"),
                KeyMapping(input: "f7", output: "prev")
            ]
        )

        // Custom rules come first, so they take priority
        let deduped = RuleCollectionDeduplicator.dedupe([customRule, functionKeys])

        // Custom rule should keep its F6 mapping
        XCTAssertEqual(deduped[0].mappings.count, 1)
        XCTAssertEqual(deduped[0].mappings[0].input, "f6")
        XCTAssertTrue(deduped[0].mappings[0].output.contains("launch"))

        // Function keys should have F6 removed (claimed by custom rule)
        XCTAssertEqual(deduped[1].mappings.count, 2)
        XCTAssertFalse(deduped[1].mappings.contains { $0.input == "f6" })
        XCTAssertTrue(deduped[1].mappings.contains { $0.input == "f5" })
        XCTAssertTrue(deduped[1].mappings.contains { $0.input == "f7" })
    }
}
