//
//  RuleCollectionConfigurationSequencesTests.swift
//  KeyPath
//
//  Created by Claude Code on 2026-01-09.
//  MAL-45: Integration tests for sequences in RuleCollectionConfiguration
//

import XCTest
@testable import KeyPathAppKit

final class RuleCollectionConfigurationSequencesTests: XCTestCase {

    // MARK: - Accessor Tests

    func testSequencesConfig_Accessor() {
        let config = SequencesConfig(sequences: [
            SequenceDefinition(name: "test", keys: ["a", "b"], action: .activateLayer(.navigation))
        ])
        let ruleConfig = RuleCollectionConfiguration.sequences(config)

        XCTAssertNotNil(ruleConfig.sequencesConfig, "Should return sequences config")
        XCTAssertEqual(ruleConfig.sequencesConfig?.sequences.count, 1)
        XCTAssertEqual(ruleConfig.sequencesConfig?.sequences[0].name, "test")
    }

    func testSequencesConfig_AccessorNil() {
        let ruleConfig = RuleCollectionConfiguration.table

        XCTAssertNil(ruleConfig.sequencesConfig, "Non-sequences config should return nil")
    }

    // MARK: - Mutator Tests

    func testUpdateSequencesConfig_Success() {
        var ruleConfig = RuleCollectionConfiguration.sequences(SequencesConfig())

        let newConfig = SequencesConfig(sequences: [
            SequenceDefinition(name: "updated", keys: ["x", "y"], action: .activateLayer(.navigation))
        ])

        ruleConfig.updateSequencesConfig(newConfig)

        XCTAssertEqual(ruleConfig.sequencesConfig?.sequences.count, 1)
        XCTAssertEqual(ruleConfig.sequencesConfig?.sequences[0].name, "updated")
    }

    func testUpdateSequencesConfig_WrongType() {
        var ruleConfig = RuleCollectionConfiguration.table

        let newConfig = SequencesConfig(sequences: [
            SequenceDefinition(name: "test", keys: ["a"], action: .activateLayer(.navigation))
        ])

        ruleConfig.updateSequencesConfig(newConfig)

        // Should not change type - still .table
        XCTAssertNil(ruleConfig.sequencesConfig, "Should not mutate non-sequences config")
    }

    // MARK: - Display Style Tests

    func testDisplayStyle() {
        let ruleConfig = RuleCollectionConfiguration.sequences(SequencesConfig())

        XCTAssertEqual(ruleConfig.displayStyle, .sequences, "Should have sequences display style")
    }

    // MARK: - Codable Tests

    func testCodable_RoundTrip() throws {
        let original = RuleCollectionConfiguration.sequences(SequencesConfig.defaultPresets)

        let encoder = JSONEncoder()
        let data = try encoder.encode(original)

        let decoder = JSONDecoder()
        let decoded = try decoder.decode(RuleCollectionConfiguration.self, from: data)

        XCTAssertEqual(decoded.displayStyle, .sequences, "Should preserve display style")
        XCTAssertEqual(decoded.sequencesConfig?.sequences.count, 3, "Should preserve sequences")
    }

    func testCodable_LegacyDecoding() throws {
        // Test that old configs without sequences can still be decoded
        let json = """
        {
            "type": "table"
        }
        """

        let data = json.data(using: .utf8)!
        let config = try JSONDecoder().decode(RuleCollectionConfiguration.self, from: data)

        XCTAssertEqual(config.displayStyle, .table, "Should decode legacy config")
        XCTAssertNil(config.sequencesConfig, "Should not have sequences")
    }

    // MARK: - Edge Cases

    func testEmptySequencesConfig() throws {
        let emptyConfig = SequencesConfig()
        let ruleConfig = RuleCollectionConfiguration.sequences(emptyConfig)

        let data = try JSONEncoder().encode(ruleConfig)
        let decoded = try JSONDecoder().decode(RuleCollectionConfiguration.self, from: data)

        XCTAssertEqual(decoded.sequencesConfig?.sequences.count, 0, "Should preserve empty sequences")
    }

    func testMaxSequences() {
        // Test with many sequences
        let sequences = (0..<100).map { i in
            SequenceDefinition(
                name: "seq\(i)",
                keys: ["key\(i)"],
                action: .activateLayer(.navigation)
            )
        }

        let config = SequencesConfig(sequences: sequences)
        let ruleConfig = RuleCollectionConfiguration.sequences(config)

        XCTAssertEqual(ruleConfig.sequencesConfig?.sequences.count, 100, "Should handle many sequences")
    }
}
