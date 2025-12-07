@testable import KeyPathAppKit
import XCTest

/// Comprehensive tests for chord (simultaneous key) and sequence (ordered key) support.
/// These tests ensure the multi-key input feature doesn't unexpectedly break.
final class ChordsAndSequencesTests: XCTestCase {
    // MARK: - InputType Enum Tests

    func testInputTypeEnumHasAllCases() {
        // Ensure all expected input types exist
        XCTAssertEqual(InputType.single.rawValue, "single")
        XCTAssertEqual(InputType.chord.rawValue, "chord")
        XCTAssertEqual(InputType.sequence.rawValue, "sequence")
    }

    func testInputTypeCodableRoundTrip() throws {
        let encoder = JSONEncoder()
        let decoder = JSONDecoder()

        for inputType in [InputType.single, InputType.chord, InputType.sequence] {
            let data = try encoder.encode(inputType)
            let decoded = try decoder.decode(InputType.self, from: data)
            XCTAssertEqual(decoded, inputType, "InputType \(inputType) should survive JSON round-trip")
        }
    }

    // MARK: - CustomRule with InputType Tests

    func testCustomRuleDefaultsToSingleInputType() {
        let rule = CustomRule(input: "caps", output: "esc")
        XCTAssertEqual(rule.inputType, .single, "New rules should default to .single inputType")
    }

    func testCustomRulePreservesChordInputType() {
        let rule = CustomRule(input: "j k", output: "esc", inputType: .chord)
        XCTAssertEqual(rule.inputType, .chord)
        XCTAssertEqual(rule.input, "j k")
    }

    func testCustomRulePreservesSequenceInputType() {
        let rule = CustomRule(input: "j k", output: "esc", inputType: .sequence)
        XCTAssertEqual(rule.inputType, .sequence)
    }

    func testCustomRuleCodableWithInputType() throws {
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601

        // Test chord
        let chordRule = CustomRule(input: "lsft rsft", output: "caps", inputType: .chord)
        let chordData = try encoder.encode(chordRule)
        let decodedChord = try decoder.decode(CustomRule.self, from: chordData)
        XCTAssertEqual(decodedChord.inputType, .chord)
        XCTAssertEqual(decodedChord.input, "lsft rsft")

        // Test sequence
        let seqRule = CustomRule(input: "j k", output: "esc", inputType: .sequence)
        let seqData = try encoder.encode(seqRule)
        let decodedSeq = try decoder.decode(CustomRule.self, from: seqData)
        XCTAssertEqual(decodedSeq.inputType, .sequence)
    }

    func testCustomRuleLegacyJSONDefaultsToSingle() throws {
        // Simulate legacy JSON without inputType field
        let legacyJSON = """
        {
            "id": "12345678-1234-1234-1234-123456789012",
            "title": "Test",
            "input": "caps",
            "output": "esc",
            "isEnabled": true,
            "createdAt": "2025-01-01T00:00:00Z"
        }
        """
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        let rule = try decoder.decode(CustomRule.self, from: legacyJSON.data(using: .utf8)!)
        XCTAssertEqual(rule.inputType, .single, "Legacy JSON without inputType should default to .single")
    }

    func testCustomRuleAsKeyMappingPropagatesInputType() {
        let chordRule = CustomRule(input: "j k", output: "esc", inputType: .chord)
        let mapping = chordRule.asKeyMapping()
        XCTAssertEqual(mapping.inputType, .chord, "asKeyMapping() should preserve inputType")

        let seqRule = CustomRule(input: "j k", output: "esc", inputType: .sequence)
        let seqMapping = seqRule.asKeyMapping()
        XCTAssertEqual(seqMapping.inputType, .sequence)
    }

    // MARK: - KeyMapping with InputType Tests

    func testKeyMappingDefaultsToSingleInputType() {
        let mapping = KeyMapping(input: "caps", output: "esc")
        XCTAssertEqual(mapping.inputType, .single)
    }

    func testKeyMappingPreservesInputType() {
        let chordMapping = KeyMapping(input: "j k", output: "esc", inputType: .chord)
        XCTAssertEqual(chordMapping.inputType, .chord)

        let seqMapping = KeyMapping(input: "j k", output: "esc", inputType: .sequence)
        XCTAssertEqual(seqMapping.inputType, .sequence)
    }

    func testKeyMappingCodableWithInputType() throws {
        let encoder = JSONEncoder()
        let decoder = JSONDecoder()

        let mapping = KeyMapping(input: "lsft rsft", output: "caps", inputType: .chord)
        let data = try encoder.encode(mapping)
        let decoded = try decoder.decode(KeyMapping.self, from: data)

        XCTAssertEqual(decoded.inputType, .chord)
        XCTAssertEqual(decoded.input, "lsft rsft")
        XCTAssertEqual(decoded.output, "caps")
    }

    func testKeyMappingLegacyJSONDefaultsToSingle() throws {
        let legacyJSON = """
        {"input": "caps", "output": "esc"}
        """
        let decoder = JSONDecoder()
        let mapping = try decoder.decode(KeyMapping.self, from: legacyJSON.data(using: .utf8)!)
        XCTAssertEqual(mapping.inputType, .single, "Legacy JSON without inputType should default to .single")
    }

    // MARK: - Validator Tests for Multi-Key Inputs

    func testValidatorAcceptsMultiKeyInput() {
        // Validator should accept space-separated keys for chords/sequences
        let errors = CustomRuleValidator.validateKeys(input: "j k", output: "esc")
        XCTAssertTrue(errors.isEmpty, "Multi-key input 'j k' should be valid. Errors: \(errors)")
    }

    func testValidatorAcceptsThreeKeyInput() {
        let errors = CustomRuleValidator.validateKeys(input: "j k l", output: "esc")
        XCTAssertTrue(errors.isEmpty, "Three-key input 'j k l' should be valid")
    }

    func testValidatorAcceptsModifierChord() {
        let errors = CustomRuleValidator.validateKeys(input: "lsft rsft", output: "caps")
        XCTAssertTrue(errors.isEmpty, "Modifier chord 'lsft rsft' should be valid")
    }

    func testValidatorRejectsInvalidKeyInMultiKeyInput() {
        let errors = CustomRuleValidator.validateKeys(input: "j invalidkey", output: "esc")
        XCTAssertFalse(errors.isEmpty, "Invalid key in multi-key input should be rejected")
        XCTAssertTrue(errors.contains { error in
            if case let .invalidInputKey(key) = error {
                return key == "invalidkey"
            }
            return false
        })
    }

    func testValidatorAcceptsMultiKeyOutput() {
        // Output sequences should also be valid
        let errors = CustomRuleValidator.validateKeys(input: "caps", output: "esc ret")
        XCTAssertTrue(errors.isEmpty, "Multi-key output 'esc ret' should be valid")
    }

    func testValidatorTokenizesCorrectly() {
        let tokens = CustomRuleValidator.tokenize("j k l")
        XCTAssertEqual(tokens, ["j", "k", "l"])

        let tokensWithSpaces = CustomRuleValidator.tokenize("  j   k  ")
        XCTAssertEqual(tokensWithSpaces, ["j", "k"])
    }

    // MARK: - Config Generation: Chord Tests

    func testChordMappingGeneratesDefchordsv2Block() {
        let collection = RuleCollection(
            name: "Chord Test",
            summary: "Test chord",
            category: .custom,
            mappings: [KeyMapping(input: "lsft rsft", output: "caps", inputType: .chord)],
            isEnabled: true
        )

        let config = KanataConfiguration.generateFromCollections([collection])

        XCTAssertTrue(config.contains("(defchordsv2"), "Config must contain defchordsv2 block")
        XCTAssertTrue(config.contains("(lsft rsft) caps"), "Chord syntax must be correct")
        XCTAssertTrue(config.contains("50 all-released"), "Chord must have timeout and release behavior")
    }

    func testChordMappingDoesNotAppearInDefsrc() {
        let collection = RuleCollection(
            name: "Chord Test",
            summary: "Test chord",
            category: .custom,
            mappings: [KeyMapping(input: "j k", output: "esc", inputType: .chord)],
            isEnabled: true
        )

        let config = KanataConfiguration.generateFromCollections([collection])
        let defsrcSection = extractSection(from: config, startMarker: "(defsrc", endMarker: ")")

        XCTAssertFalse(defsrcSection.contains("j k"), "Chord input should NOT appear in defsrc")
        XCTAssertFalse(defsrcSection.contains("j") && defsrcSection.contains("k"),
                       "Individual chord keys should NOT appear in defsrc if only used in chord")
    }

    func testLegacyChordMappingStillWorks() {
        // Legacy mappings with spaces but no explicit inputType should still generate chords
        let collection = RuleCollection(
            name: "Legacy Chord",
            summary: "Legacy chord without inputType",
            category: .custom,
            mappings: [KeyMapping(input: "lsft rsft", output: "caps")], // No inputType specified
            isEnabled: true
        )

        let config = KanataConfiguration.generateFromCollections([collection])

        XCTAssertTrue(config.contains("(defchordsv2"), "Legacy chord mapping must still generate defchordsv2")
        XCTAssertTrue(config.contains("(lsft rsft) caps"), "Legacy chord syntax must be correct")
    }

    func testDisabledChordDoesNotGenerateDefchordsv2() {
        let collection = RuleCollection(
            name: "Disabled Chord",
            summary: "Disabled",
            category: .custom,
            mappings: [KeyMapping(input: "j k", output: "esc", inputType: .chord)],
            isEnabled: false
        )

        let config = KanataConfiguration.generateFromCollections([collection])
        XCTAssertFalse(config.contains("(defchordsv2"), "Disabled chord should NOT generate defchordsv2")
    }

    func testMultipleChordsInOneConfig() {
        let collection = RuleCollection(
            name: "Multi Chord",
            summary: "Multiple chords",
            category: .custom,
            mappings: [
                KeyMapping(input: "j k", output: "esc", inputType: .chord),
                KeyMapping(input: "lsft rsft", output: "caps", inputType: .chord)
            ],
            isEnabled: true
        )

        let config = KanataConfiguration.generateFromCollections([collection])

        XCTAssertTrue(config.contains("(j k) esc"), "First chord should be present")
        XCTAssertTrue(config.contains("(lsft rsft) caps"), "Second chord should be present")
    }

    // MARK: - Config Generation: Sequence Tests

    func testSequenceMappingGeneratesDefseqBlock() {
        let collection = RuleCollection(
            name: "Sequence Test",
            summary: "Test sequence",
            category: .custom,
            mappings: [KeyMapping(input: "j k", output: "esc", inputType: .sequence)],
            isEnabled: true
        )

        let config = KanataConfiguration.generateFromCollections([collection])

        XCTAssertTrue(config.contains("(defseq"), "Config must contain defseq block for sequences")
        XCTAssertTrue(config.contains("(j k)"), "Sequence keys should be in defseq")
    }

    func testSequenceMappingGeneratesAlias() {
        let collection = RuleCollection(
            name: "Sequence Test",
            summary: "Test sequence",
            category: .custom,
            mappings: [KeyMapping(input: "j k", output: "esc", inputType: .sequence)],
            isEnabled: true
        )

        let config = KanataConfiguration.generateFromCollections([collection])

        // Sequences need an alias to define what they do
        XCTAssertTrue(config.contains("(defalias"), "Config must contain defalias for sequence action")
        XCTAssertTrue(config.contains("seq-"), "Sequence alias name should start with 'seq-'")
        XCTAssertTrue(config.contains("(macro esc)") || config.contains("esc"),
                      "Sequence should output esc via macro or direct")
    }

    func testSequenceMappingDoesNotAppearInDefsrc() {
        let collection = RuleCollection(
            name: "Sequence Test",
            summary: "Test sequence",
            category: .custom,
            mappings: [KeyMapping(input: "j k", output: "esc", inputType: .sequence)],
            isEnabled: true
        )

        let config = KanataConfiguration.generateFromCollections([collection])
        let defsrcSection = extractSection(from: config, startMarker: "(defsrc", endMarker: ")")

        // Sequence input keys should not be in defsrc unless also used as regular mappings
        XCTAssertFalse(defsrcSection.contains("j k"), "Sequence input should NOT appear in defsrc")
    }

    func testDisabledSequenceDoesNotGenerateDefseq() {
        let collection = RuleCollection(
            name: "Disabled Sequence",
            summary: "Disabled",
            category: .custom,
            mappings: [KeyMapping(input: "j k", output: "esc", inputType: .sequence)],
            isEnabled: false
        )

        let config = KanataConfiguration.generateFromCollections([collection])
        XCTAssertFalse(config.contains("(defseq"), "Disabled sequence should NOT generate defseq")
    }

    func testMultipleSequencesInOneConfig() {
        let collection = RuleCollection(
            name: "Multi Sequence",
            summary: "Multiple sequences",
            category: .custom,
            mappings: [
                KeyMapping(input: "j k", output: "esc", inputType: .sequence),
                KeyMapping(input: "f d", output: "ret", inputType: .sequence)
            ],
            isEnabled: true
        )

        let config = KanataConfiguration.generateFromCollections([collection])

        XCTAssertTrue(config.contains("(j k)"), "First sequence should be present")
        XCTAssertTrue(config.contains("(f d)"), "Second sequence should be present")
    }

    func testSequenceWithMultiKeyOutput() {
        let collection = RuleCollection(
            name: "Sequence Multi Output",
            summary: "Sequence with multi-key output",
            category: .custom,
            mappings: [KeyMapping(input: "j k", output: "esc ret", inputType: .sequence)],
            isEnabled: true
        )

        let config = KanataConfiguration.generateFromCollections([collection])

        XCTAssertTrue(config.contains("(defseq"), "Should have defseq")
        // Multi-key output should be wrapped in macro
        XCTAssertTrue(config.contains("(macro"), "Multi-key output should use macro")
    }

    // MARK: - Mixed Mappings Tests

    func testMixedSingleChordAndSequenceMappings() {
        let collection = RuleCollection(
            name: "Mixed",
            summary: "Mixed mapping types",
            category: .custom,
            mappings: [
                KeyMapping(input: "caps", output: "esc", inputType: .single),
                KeyMapping(input: "lsft rsft", output: "caps", inputType: .chord),
                KeyMapping(input: "j k", output: "ret", inputType: .sequence)
            ],
            isEnabled: true
        )

        let config = KanataConfiguration.generateFromCollections([collection])

        // Single mapping should be in defsrc/deflayer
        XCTAssertTrue(config.contains("(defsrc"), "Should have defsrc for single mapping")
        XCTAssertTrue(config.contains("caps"), "Single mapping input should be in defsrc")

        // Chord should be in defchordsv2
        XCTAssertTrue(config.contains("(defchordsv2"), "Should have defchordsv2 for chord")
        XCTAssertTrue(config.contains("(lsft rsft) caps"), "Chord should be correct")

        // Sequence should be in defseq
        XCTAssertTrue(config.contains("(defseq"), "Should have defseq for sequence")
        XCTAssertTrue(config.contains("(j k)"), "Sequence should be correct")
    }

    func testSameKeysUsedDifferentlyInDifferentCollections() {
        let singleCollection = RuleCollection(
            name: "Single J",
            summary: "J as single key",
            category: .custom,
            mappings: [KeyMapping(input: "j", output: "left", inputType: .single)],
            isEnabled: true
        )

        let chordCollection = RuleCollection(
            name: "Chord JK",
            summary: "J+K chord",
            category: .custom,
            mappings: [KeyMapping(input: "j k", output: "esc", inputType: .chord)],
            isEnabled: true
        )

        let config = KanataConfiguration.generateFromCollections([singleCollection, chordCollection])

        // Both should work together
        XCTAssertTrue(config.contains("(defsrc") && config.contains("j"), "Single j mapping should be in defsrc")
        XCTAssertTrue(config.contains("(defchordsv2") && config.contains("(j k)"), "Chord should be in defchordsv2")
    }

    // MARK: - Backward Compatibility Tests

    func testBackupCapsLockFromCatalogGeneratesChord() {
        // This is a critical test - the Backup Caps Lock collection uses lsft rsft chord
        let catalog = RuleCollectionCatalog()
        var collections = catalog.defaultCollections()

        // Enable Backup Caps Lock
        if let index = collections.firstIndex(where: { $0.id == RuleCollectionIdentifier.backupCapsLock }) {
            collections[index].isEnabled = true
        }

        let config = KanataConfiguration.generateFromCollections(collections)

        XCTAssertTrue(config.contains("(defchordsv2"), "Backup Caps Lock must generate defchordsv2")
        XCTAssertTrue(config.contains("(lsft rsft) caps"), "Backup Caps Lock chord syntax must be correct")
    }

    // MARK: - Helper Methods

    private func extractSection(from config: String, startMarker: String, endMarker _: String) -> String {
        guard let startRange = config.range(of: startMarker) else { return "" }
        let suffix = config[startRange.lowerBound...]

        // Find the matching closing paren (simple heuristic - first ) on its own line)
        var depth = 0
        var endIndex = suffix.endIndex
        for i in suffix.indices {
            let char = suffix[i]
            if char == "(" { depth += 1 } else if char == ")" {
                depth -= 1
                if depth == 0 {
                    endIndex = suffix.index(after: i)
                    break
                }
            }
        }

        return String(suffix[..<endIndex])
    }
}
