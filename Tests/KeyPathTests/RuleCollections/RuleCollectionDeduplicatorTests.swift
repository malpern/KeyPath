@testable import KeyPathAppKit
import XCTest

final class RuleCollectionDeduplicatorTests: XCTestCase {
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
