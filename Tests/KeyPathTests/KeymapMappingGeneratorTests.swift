@testable import KeyPathAppKit
import XCTest

final class KeymapMappingGeneratorTests: XCTestCase {
    // MARK: - QWERTY Tests

    func testQWERTYGeneratesNoMappings() {
        let mappings = KeymapMappingGenerator.generateMappings(
            to: .qwertyUS,
            includePunctuation: false
        )

        XCTAssertTrue(mappings.isEmpty, "QWERTY should not generate any mappings (identity)")
    }

    func testQWERTYWithPunctuationStillGeneratesNoMappings() {
        let mappings = KeymapMappingGenerator.generateMappings(
            to: .qwertyUS,
            includePunctuation: true
        )

        XCTAssertTrue(mappings.isEmpty, "QWERTY with punctuation should still generate no mappings")
    }

    // MARK: - Colemak Tests

    func testColemakGeneratesCorrectMappings() {
        let mappings = KeymapMappingGenerator.generateMappings(
            to: .colemak,
            includePunctuation: false
        )

        // Colemak has many differences from QWERTY
        // Key differences include:
        // E -> F (position), R -> P, etc.
        XCTAssertFalse(mappings.isEmpty, "Colemak should generate mappings")

        // Verify some specific Colemak remappings
        // In Colemak, the physical 'e' key (QWERTY) outputs 'f'
        let eToF = mappings.first { $0.input == "e" && $0.output == "f" }
        XCTAssertNotNil(eToF, "Colemak should remap e -> f")

        // In Colemak, the physical 'r' key (QWERTY) outputs 'p'
        let rToP = mappings.first { $0.input == "r" && $0.output == "p" }
        XCTAssertNotNil(rToP, "Colemak should remap r -> p")

        // In Colemak, the physical 's' key stays as 's' - this should NOT be in mappings
        let sToS = mappings.first { $0.input == "s" && $0.output == "s" }
        XCTAssertNil(sToS, "Colemak should not have identity mappings (s -> s)")
    }

    func testColemakOnlyDifferentKeysAreMapped() {
        let mappings = KeymapMappingGenerator.generateMappings(
            to: .colemak,
            includePunctuation: false
        )

        // Keys that stay the same in Colemak: q, w, a, z, x, c, v, b, m, comma, period, slash
        let unchangedKeys = ["q", "w", "a", "z", "x", "c", "v", "b", "m", ",", ".", "/"]

        for key in unchangedKeys {
            let identityMapping = mappings.first { $0.input == key && $0.output == key }
            XCTAssertNil(identityMapping, "Key '\(key)' should not have an identity mapping")
        }
    }

    // MARK: - Colemak-DH Tests

    func testColemakDHGeneratesCorrectMappings() {
        let mappings = KeymapMappingGenerator.generateMappings(
            to: .colemakDH,
            includePunctuation: false
        )

        XCTAssertFalse(mappings.isEmpty, "Colemak-DH should generate mappings")

        // Colemak-DH specific: D and H are moved compared to regular Colemak
        // The physical 't' key in QWERTY outputs 'b' in Colemak-DH (top row position 5)
        let tToB = mappings.first { $0.input == "t" && $0.output == "b" }
        XCTAssertNotNil(tToB, "Colemak-DH should remap t -> b")

        // The physical 'd' key in QWERTY outputs 's' in Colemak-DH
        let dToS = mappings.first { $0.input == "d" && $0.output == "s" }
        XCTAssertNotNil(dToS, "Colemak-DH should remap d -> s")
    }

    // MARK: - Dvorak Tests

    func testDvorakGeneratesCorrectMappings() {
        let mappings = KeymapMappingGenerator.generateMappings(
            to: .dvorak,
            includePunctuation: false
        )

        XCTAssertFalse(mappings.isEmpty, "Dvorak should generate mappings")

        // Dvorak radically rearranges the keyboard
        // In Dvorak, the physical 'q' key (QWERTY) outputs apostrophe
        let qToApostrophe = mappings.first { $0.input == "q" && $0.output == "'" }
        XCTAssertNotNil(qToApostrophe, "Dvorak should remap q -> '")

        // In Dvorak, the physical 'a' key stays 'a'
        let aToA = mappings.first { $0.input == "a" && $0.output == "a" }
        XCTAssertNil(aToA, "Dvorak should not have identity mapping for 'a'")
    }

    func testDvorakWithPunctuationIncludesExtraLabels() {
        let mappingsWithoutPunctuation = KeymapMappingGenerator.generateMappings(
            to: .dvorak,
            includePunctuation: false
        )

        let mappingsWithPunctuation = KeymapMappingGenerator.generateMappings(
            to: .dvorak,
            includePunctuation: true
        )

        // Dvorak has punctuation remappings in extraLabels
        // With punctuation enabled, we should have more mappings
        XCTAssertGreaterThanOrEqual(
            mappingsWithPunctuation.count,
            mappingsWithoutPunctuation.count,
            "Dvorak with punctuation should have at least as many mappings"
        )
    }

    // MARK: - Workman Tests

    func testWorkmanGeneratesCorrectMappings() {
        let mappings = KeymapMappingGenerator.generateMappings(
            to: .workman,
            includePunctuation: false
        )

        XCTAssertFalse(mappings.isEmpty, "Workman should generate mappings")

        // In Workman, the physical 'w' key (QWERTY) outputs 'd'
        let wToD = mappings.first { $0.input == "w" && $0.output == "d" }
        XCTAssertNotNil(wToD, "Workman should remap w -> d")

        // In Workman, the physical 'e' key (QWERTY) outputs 'r'
        let eToR = mappings.first { $0.input == "e" && $0.output == "r" }
        XCTAssertNotNil(eToR, "Workman should remap e -> r")
    }

    // MARK: - Collection Generation Tests

    func testGenerateCollectionReturnsNilForQWERTY() {
        let collection = KeymapMappingGenerator.generateCollection(
            for: "qwerty-us",
            includePunctuation: false
        )

        XCTAssertNil(collection, "QWERTY should not generate a collection")
    }

    func testGenerateCollectionReturnsNilForInvalidId() {
        let collection = KeymapMappingGenerator.generateCollection(
            for: "invalid-layout",
            includePunctuation: false
        )

        XCTAssertNil(collection, "Invalid layout ID should not generate a collection")
    }

    func testGenerateCollectionForColemak() {
        let collection = KeymapMappingGenerator.generateCollection(
            for: "colemak",
            includePunctuation: false
        )

        XCTAssertNotNil(collection)
        XCTAssertEqual(collection?.name, "Colemak Layout")
        XCTAssertEqual(collection?.id, RuleCollectionIdentifier.keymapLayout)
        XCTAssertTrue(collection?.isEnabled ?? false)
        XCTAssertEqual(collection?.targetLayer, .base)
        XCTAssertFalse(collection?.mappings.isEmpty ?? true)
    }

    func testGenerateCollectionForDvorak() {
        let collection = KeymapMappingGenerator.generateCollection(
            for: "dvorak",
            includePunctuation: true
        )

        XCTAssertNotNil(collection)
        XCTAssertEqual(collection?.name, "Dvorak Layout")
    }

    // MARK: - Mapping Properties Tests

    func testMappingsHaveInputsAndOutputs() {
        let mappings = KeymapMappingGenerator.generateMappings(
            to: .colemak,
            includePunctuation: false
        )

        XCTAssertFalse(mappings.isEmpty, "Colemak should generate mappings")

        for mapping in mappings {
            XCTAssertFalse(mapping.input.isEmpty, "Mapping should have non-empty input")
            XCTAssertFalse(mapping.output.isEmpty, "Mapping should have non-empty output")
        }
    }

    func testNoMappingHasEmptyInputOrOutput() {
        for keymap in LogicalKeymap.all where keymap.id != LogicalKeymap.defaultId {
            let mappings = KeymapMappingGenerator.generateMappings(
                to: keymap,
                includePunctuation: true
            )

            for mapping in mappings {
                XCTAssertFalse(mapping.input.isEmpty, "Mapping input should not be empty for \(keymap.id)")
                XCTAssertFalse(mapping.output.isEmpty, "Mapping output should not be empty for \(keymap.id)")
            }
        }
    }

    func testInputAndOutputAreDifferent() {
        for keymap in LogicalKeymap.all where keymap.id != LogicalKeymap.defaultId {
            let mappings = KeymapMappingGenerator.generateMappings(
                to: keymap,
                includePunctuation: true
            )

            for mapping in mappings {
                XCTAssertNotEqual(
                    mapping.input,
                    mapping.output,
                    "Mapping should not have same input and output for \(keymap.id): \(mapping.input)"
                )
            }
        }
    }

    // MARK: - Stable Collection ID Test

    func testKeymapLayoutCollectionIdIsStable() throws {
        // The collection ID should be stable across runs for persistence
        let expectedId = try XCTUnwrap(UUID(uuidString: "AEE1A400-1A10-0000-0000-000000000000"))
        XCTAssertEqual(RuleCollectionIdentifier.keymapLayout, expectedId)
    }
}
