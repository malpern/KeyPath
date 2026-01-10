//
//  SequencesConfigTests.swift
//  KeyPath
//
//  Created by Claude Code on 2026-01-09.
//  MAL-45: Kanata Sequences (defseq) UI Support
//

@testable import KeyPathAppKit
import XCTest

final class SequencesConfigTests: XCTestCase {
    // MARK: - Initialization Tests

    func testDefaultInit() {
        let config = SequencesConfig()

        XCTAssertEqual(config.sequences.count, 0, "Default config should have no sequences")
        XCTAssertNil(config.activeSequenceID, "Default config should have no active sequence")
        XCTAssertEqual(config.globalTimeout, 500, "Default timeout should be 500ms")
    }

    func testPresets() {
        let config = SequencesConfig.defaultPresets

        XCTAssertEqual(config.sequences.count, 3, "Default presets should have 3 sequences")
        XCTAssertEqual(config.globalTimeout, 500, "Preset timeout should be 500ms")

        // Verify window management preset
        let windowSeq = config.sequences.first { $0.name == "Window Management" }
        XCTAssertNotNil(windowSeq, "Should have Window Management preset")
        XCTAssertEqual(windowSeq?.keys, ["space", "w"], "Window preset should have space → w keys")
        if case let .activateLayer(layer) = windowSeq?.action {
            XCTAssertEqual(layer, .custom("window"), "Window preset should activate window layer")
        } else {
            XCTFail("Window preset should have activateLayer action")
        }

        // Verify app launcher preset
        let appSeq = config.sequences.first { $0.name == "App Launcher" }
        XCTAssertNotNil(appSeq, "Should have App Launcher preset")
        XCTAssertEqual(appSeq?.keys, ["space", "a"], "App preset should have space → a keys")

        // Verify navigation preset
        let navSeq = config.sequences.first { $0.name == "Navigation" }
        XCTAssertNotNil(navSeq, "Should have Navigation preset")
        XCTAssertEqual(navSeq?.keys, ["space", "n"], "Nav preset should have space → n keys")
    }

    // MARK: - Conflict Detection Tests

    func testConflictDetection_SameKeys() {
        let seq1 = SequenceDefinition(
            name: "Test1",
            keys: ["space", "w"],
            action: .activateLayer(.navigation)
        )
        let seq2 = SequenceDefinition(
            name: "Test2",
            keys: ["space", "w"],
            action: .activateLayer(.custom("window"))
        )

        let config = SequencesConfig(sequences: [seq1, seq2])
        let conflicts = config.detectConflicts()

        XCTAssertEqual(conflicts.count, 1, "Should detect one conflict")
        if let conflict = conflicts.first {
            XCTAssertEqual(conflict.type, .sameKeys, "Conflict should be same keys type")
            XCTAssertTrue(
                (conflict.sequence1.id == seq1.id && conflict.sequence2.id == seq2.id) ||
                    (conflict.sequence1.id == seq2.id && conflict.sequence2.id == seq1.id),
                "Conflict should reference both sequences"
            )
        }
    }

    func testConflictDetection_PrefixOverlap() {
        let seq1 = SequenceDefinition(
            name: "Short",
            keys: ["space"],
            action: .activateLayer(.navigation)
        )
        let seq2 = SequenceDefinition(
            name: "Long",
            keys: ["space", "w"],
            action: .activateLayer(.custom("window"))
        )

        let config = SequencesConfig(sequences: [seq1, seq2])
        let conflicts = config.detectConflicts()

        XCTAssertEqual(conflicts.count, 1, "Should detect one prefix overlap conflict")
        if let conflict = conflicts.first {
            XCTAssertEqual(conflict.type, .prefixOverlap, "Conflict should be prefix overlap type")
        }
    }

    func testConflictDetection_NoConflicts() {
        let seq1 = SequenceDefinition(
            name: "Test1",
            keys: ["space", "w"],
            action: .activateLayer(.navigation)
        )
        let seq2 = SequenceDefinition(
            name: "Test2",
            keys: ["space", "a"],
            action: .activateLayer(.custom("launcher"))
        )

        let config = SequencesConfig(sequences: [seq1, seq2])
        let conflicts = config.detectConflicts()

        XCTAssertTrue(conflicts.isEmpty, "Should have no conflicts")
        XCTAssertFalse(config.hasConflicts, "hasConflicts should be false")
    }

    func testConflictDetection_MultipleConflicts() {
        let seq1 = SequenceDefinition(name: "A", keys: ["a"], action: .activateLayer(.navigation))
        let seq2 = SequenceDefinition(name: "B", keys: ["a", "b"], action: .activateLayer(.navigation))
        let seq3 = SequenceDefinition(name: "C", keys: ["a"], action: .activateLayer(.custom("test")))

        let config = SequencesConfig(sequences: [seq1, seq2, seq3])
        let conflicts = config.detectConflicts()

        // Should detect: seq1-seq2 (prefix), seq1-seq3 (same), seq2-seq3 (prefix)
        XCTAssertGreaterThan(conflicts.count, 0, "Should detect multiple conflicts")
    }

    // MARK: - Validation Tests

    func testSequenceValidation_Valid() {
        let valid = SequenceDefinition(
            name: "Valid",
            keys: ["space", "w"],
            action: .activateLayer(.navigation)
        )

        XCTAssertTrue(valid.isValid, "Sequence with name and 2 keys should be valid")
    }

    func testSequenceValidation_EmptyKeys() {
        let emptyKeys = SequenceDefinition(
            name: "Invalid",
            keys: [],
            action: .activateLayer(.navigation)
        )

        XCTAssertFalse(emptyKeys.isValid, "Sequence with empty keys should be invalid")
    }

    func testSequenceValidation_TooManyKeys() {
        let tooMany = SequenceDefinition(
            name: "TooMany",
            keys: ["a", "b", "c", "d", "e", "f"],
            action: .activateLayer(.navigation)
        )

        XCTAssertFalse(tooMany.isValid, "Sequence with 6 keys should be invalid (max 5)")
    }

    func testSequenceValidation_EmptyName() {
        let emptyName = SequenceDefinition(
            name: "",
            keys: ["space", "w"],
            action: .activateLayer(.navigation)
        )

        XCTAssertFalse(emptyName.isValid, "Sequence with empty name should be invalid")
    }

    func testSequenceValidation_MaxKeys() {
        let maxKeys = SequenceDefinition(
            name: "MaxKeys",
            keys: ["a", "b", "c", "d", "e"],
            action: .activateLayer(.navigation)
        )

        XCTAssertTrue(maxKeys.isValid, "Sequence with exactly 5 keys should be valid")
    }

    // MARK: - Formatting Tests

    func testPrettyKeys() {
        let sequence = SequenceDefinition(
            name: "Test",
            keys: ["space", "w", "h"],
            action: .activateLayer(.navigation)
        )

        XCTAssertEqual(sequence.prettyKeys, "Space → W → H", "Should format keys with arrows and capitalization")
    }

    func testActionDisplayName() {
        let action = SequenceAction.activateLayer(.navigation)
        XCTAssertEqual(action.displayName, "Activate Navigation", "Should have correct display name")

        let customAction = SequenceAction.activateLayer(.custom("window"))
        XCTAssertEqual(customAction.displayName, "Activate Window", "Should handle custom layer names")
    }

    // MARK: - Codable Tests

    func testCodableRoundTrip() throws {
        let original = SequencesConfig.defaultPresets

        let encoder = JSONEncoder()
        let data = try encoder.encode(original)

        let decoder = JSONDecoder()
        let decoded = try decoder.decode(SequencesConfig.self, from: data)

        XCTAssertEqual(original, decoded, "Config should survive JSON encoding/decoding")
        XCTAssertEqual(decoded.sequences.count, original.sequences.count, "Should preserve sequence count")
        XCTAssertEqual(decoded.globalTimeout, original.globalTimeout, "Should preserve timeout")
    }

    func testSequenceDefinitionCodable() throws {
        let original = SequenceDefinition(
            id: UUID(),
            name: "Test",
            keys: ["space", "w"],
            action: .activateLayer(.custom("window")),
            description: "Test sequence"
        )

        let data = try JSONEncoder().encode(original)
        let decoded = try JSONDecoder().decode(SequenceDefinition.self, from: data)

        XCTAssertEqual(original, decoded, "SequenceDefinition should survive encoding/decoding")
        XCTAssertEqual(decoded.id, original.id, "Should preserve ID")
        XCTAssertEqual(decoded.name, original.name, "Should preserve name")
        XCTAssertEqual(decoded.keys, original.keys, "Should preserve keys")
        XCTAssertEqual(decoded.description, original.description, "Should preserve description")
    }

    // MARK: - Timeout Presets Tests

    func testTimeoutPresets() {
        XCTAssertEqual(SequenceTimeout.fast.rawValue, 300, "Fast should be 300ms")
        XCTAssertEqual(SequenceTimeout.moderate.rawValue, 500, "Moderate should be 500ms")
        XCTAssertEqual(SequenceTimeout.relaxed.rawValue, 1000, "Relaxed should be 1000ms")

        XCTAssertEqual(SequenceTimeout.fast.displayName, "Fast (300ms)")
        XCTAssertEqual(SequenceTimeout.moderate.displayName, "Moderate (500ms)")
        XCTAssertEqual(SequenceTimeout.relaxed.displayName, "Relaxed (1000ms)")
    }
}
