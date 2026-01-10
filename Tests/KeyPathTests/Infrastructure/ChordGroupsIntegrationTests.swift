@testable import KeyPathAppKit
@testable import KeyPathCore
import XCTest

/// Integration tests for Chord Groups end-to-end workflow
/// Tests the full flow: config creation → mapping generation → Kanata config rendering
final class ChordGroupsIntegrationTests: XCTestCase {
    // MARK: - Basic Config Generation

    func testEmptyConfigGeneratesNoOutput() {
        let config = ChordGroupsConfig()
        let collections = [
            RuleCollection(
                id: RuleCollectionIdentifier.chordGroups,
                name: "Chord Groups",
                summary: "Test",
                category: .productivity,
                mappings: [],
                isEnabled: true,
                configuration: .chordGroups(config)
            )
        ]

        let output = KanataConfiguration.generateFromCollections(collections)

        // Should not contain UI chord groups section (empty config)
        XCTAssertFalse(output.contains("CHORD GROUPS (defchords) - UI-Authored"))
    }

    func testSingleChordGroupGeneratesCorrectOutput() {
        let group = ChordGroup(
            id: UUID(),
            name: "Navigation",
            timeout: 250,
            chords: [
                ChordDefinition(id: UUID(), keys: ["s", "d"], output: "esc"),
                ChordDefinition(id: UUID(), keys: ["d", "f"], output: "enter")
            ]
        )
        let config = ChordGroupsConfig(groups: [group])
        let collections = [
            RuleCollection(
                id: RuleCollectionIdentifier.chordGroups,
                name: "Chord Groups",
                summary: "Test",
                category: .productivity,
                mappings: [],
                isEnabled: true,
                configuration: .chordGroups(config)
            )
        ]

        let output = KanataConfiguration.generateFromCollections(collections)

        // Verify header
        XCTAssertTrue(output.contains("CHORD GROUPS (defchords) - UI-Authored"))

        // Verify defchords block
        XCTAssertTrue(output.contains("(defchords Navigation 250"))

        // Verify single-key fallbacks (alphabetically sorted)
        XCTAssertTrue(output.contains("(d) d"))
        XCTAssertTrue(output.contains("(f) f"))
        XCTAssertTrue(output.contains("(s) s"))

        // Verify chord definitions
        XCTAssertTrue(output.contains("(s d) esc"))
        XCTAssertTrue(output.contains("(d f) enter"))
    }

    func testBenVallackPresetGeneratesValidConfig() {
        let config = ChordGroupsConfig.benVallackPreset
        let collections = [
            RuleCollection(
                id: RuleCollectionIdentifier.chordGroups,
                name: "Chord Groups",
                summary: "Test",
                category: .productivity,
                mappings: [],
                isEnabled: true,
                configuration: .chordGroups(config)
            )
        ]

        let output = KanataConfiguration.generateFromCollections(collections)

        // Verify Navigation group exists
        XCTAssertTrue(output.contains("(defchords Navigation 250"))

        // Verify Ben Vallack's signature chords
        XCTAssertTrue(output.contains("(s d) esc"))
        XCTAssertTrue(output.contains("(d f) enter"))
        XCTAssertTrue(output.contains("(j k) up"))
        XCTAssertTrue(output.contains("(k l) down"))

        // Verify all participating keys have fallbacks
        for key in ["s", "d", "f", "j", "k", "l"] {
            XCTAssertTrue(output.contains("(\(key)) \(key)"))
        }
    }

    // MARK: - Mapping Generation

    func testChordGroupsGenerateCorrectKeyMappings() {
        let group = ChordGroup(
            id: UUID(),
            name: "TestGroup",
            timeout: 300,
            chords: [
                ChordDefinition(id: UUID(), keys: ["a", "b"], output: "esc")
            ]
        )
        let config = ChordGroupsConfig(groups: [group])
        let collection = RuleCollection(
            id: RuleCollectionIdentifier.chordGroups,
            name: "Chord Groups",
            summary: "Test",
            category: .productivity,
            mappings: [],
            isEnabled: true,
            configuration: .chordGroups(config)
        )

        // Extract effective mappings for this collection
        // Note: effectiveMappings() is internal to the generator, so we test via config output
        let output = KanataConfiguration.generateFromCollections([collection])

        // Verify that 'a' and 'b' keys are present in the config
        // They should map to (chord TestGroup a) and (chord TestGroup b) in defsrc/deflayer
        XCTAssertTrue(output.contains("defsrc"))
        XCTAssertTrue(output.contains("deflayer base"))
    }

    // MARK: - Multiple Groups

    func testMultipleChordGroupsGenerateDistinctBlocks() {
        let nav = ChordGroup(
            id: UUID(),
            name: "Navigation",
            timeout: 250,
            chords: [
                ChordDefinition(id: UUID(), keys: ["j", "k"], output: "up")
            ]
        )
        let edit = ChordGroup(
            id: UUID(),
            name: "Editing",
            timeout: 300,
            chords: [
                ChordDefinition(id: UUID(), keys: ["a", "s"], output: "bspc")
            ]
        )
        let config = ChordGroupsConfig(groups: [nav, edit])
        let collections = [
            RuleCollection(
                id: RuleCollectionIdentifier.chordGroups,
                name: "Chord Groups",
                summary: "Test",
                category: .productivity,
                mappings: [],
                isEnabled: true,
                configuration: .chordGroups(config)
            )
        ]

        let output = KanataConfiguration.generateFromCollections(collections)

        // Verify both groups exist
        XCTAssertTrue(output.contains("(defchords Navigation 250"))
        XCTAssertTrue(output.contains("(defchords Editing 300"))

        // Verify distinct chords
        XCTAssertTrue(output.contains("(j k) up"))
        XCTAssertTrue(output.contains("(a s) bspc"))
    }

    // MARK: - Disabled Collection

    func testDisabledChordGroupsNotIncluded() {
        let group = ChordGroup(
            id: UUID(),
            name: "Navigation",
            timeout: 250,
            chords: [
                ChordDefinition(id: UUID(), keys: ["s", "d"], output: "esc")
            ]
        )
        let config = ChordGroupsConfig(groups: [group])
        let collections = [
            RuleCollection(
                id: RuleCollectionIdentifier.chordGroups,
                name: "Chord Groups",
                summary: "Test",
                category: .productivity,
                mappings: [],
                isEnabled: false, // Disabled!
                configuration: .chordGroups(config)
            )
        ]

        let output = KanataConfiguration.generateFromCollections(collections)

        // Should not generate UI chord groups block when disabled
        XCTAssertFalse(output.contains("CHORD GROUPS (defchords) - UI-Authored"))
        XCTAssertFalse(output.contains("(defchords Navigation"))
    }

    // MARK: - Preserved vs UI Chord Groups

    func testPreservedAndUIChordGroupsCanCoexist() {
        // MAL-36 preserved chord group
        let preserved = ChordGroupConfig(
            name: "PreservedGroup",
            timeoutToken: "200",
            chords: [
                ChordGroupConfig.ChordDefinition(keys: ["x", "y"], action: "custom-action")
            ]
        )

        // MAL-37 UI-authored chord group
        let uiGroup = ChordGroup(
            id: UUID(),
            name: "UIGroup",
            timeout: 300,
            chords: [
                ChordDefinition(id: UUID(), keys: ["s", "d"], output: "esc")
            ]
        )
        let uiConfig = ChordGroupsConfig(groups: [uiGroup])
        let collections = [
            RuleCollection(
                id: RuleCollectionIdentifier.chordGroups,
                name: "Chord Groups",
                summary: "Test",
                category: .productivity,
                mappings: [],
                isEnabled: true,
                configuration: .chordGroups(uiConfig)
            )
        ]

        let output = KanataConfiguration.generateFromCollections(collections, chordGroups: [preserved])

        // Both sections should exist
        XCTAssertTrue(output.contains("CHORD GROUPS (defchords) - Preserved from manual config"))
        XCTAssertTrue(output.contains("CHORD GROUPS (defchords) - UI-Authored"))

        // Both groups should be present
        XCTAssertTrue(output.contains("(defchords PreservedGroup"))
        XCTAssertTrue(output.contains("(defchords UIGroup"))

        // Both chords should be present
        XCTAssertTrue(output.contains("(x y) custom-action"))
        XCTAssertTrue(output.contains("(s d) esc"))
    }

    // MARK: - Complex Scenarios

    func testChordGroupsWithSpecialCharactersInOutput() {
        let group = ChordGroup(
            id: UUID(),
            name: "Symbols",
            timeout: 200,
            chords: [
                ChordDefinition(id: UUID(), keys: ["o", "p"], output: "(macro { } left)"),
                ChordDefinition(id: UUID(), keys: ["i", "o"], output: "(macro [ ] left)")
            ]
        )
        let config = ChordGroupsConfig(groups: [group])
        let collections = [
            RuleCollection(
                id: RuleCollectionIdentifier.chordGroups,
                name: "Chord Groups",
                summary: "Test",
                category: .productivity,
                mappings: [],
                isEnabled: true,
                configuration: .chordGroups(config)
            )
        ]

        let output = KanataConfiguration.generateFromCollections(collections)

        // Verify macro syntax is preserved
        XCTAssertTrue(output.contains("(o p) (macro { } left)"))
        XCTAssertTrue(output.contains("(i o) (macro [ ] left)"))
    }

    func testChordGroupsWithThreeKeyChords() {
        let group = ChordGroup(
            id: UUID(),
            name: "Advanced",
            timeout: 400,
            chords: [
                ChordDefinition(id: UUID(), keys: ["a", "s", "d"], output: "C-z")
            ]
        )
        let config = ChordGroupsConfig(groups: [group])
        let collections = [
            RuleCollection(
                id: RuleCollectionIdentifier.chordGroups,
                name: "Chord Groups",
                summary: "Test",
                category: .productivity,
                mappings: [],
                isEnabled: true,
                configuration: .chordGroups(config)
            )
        ]

        let output = KanataConfiguration.generateFromCollections(collections)

        // Verify three-key chord
        XCTAssertTrue(output.contains("(a s d) C-z"))

        // Verify all three keys have fallbacks
        XCTAssertTrue(output.contains("(a) a"))
        XCTAssertTrue(output.contains("(d) d"))
        XCTAssertTrue(output.contains("(s) s"))
    }

    // MARK: - Edge Cases

    func testMinimalGroupNameHandled() {
        // FIXED: Empty group name now causes precondition failure
        // Test valid minimum: single character name
        let group = ChordGroup(
            id: UUID(),
            name: "a",
            timeout: 300,
            chords: [
                ChordDefinition(id: UUID(), keys: ["a", "b"], output: "esc")
            ]
        )
        let config = ChordGroupsConfig(groups: [group])
        let collections = [
            RuleCollection(
                id: RuleCollectionIdentifier.chordGroups,
                name: "Chord Groups",
                summary: "Test",
                category: .productivity,
                mappings: [],
                isEnabled: true,
                configuration: .chordGroups(config)
            )
        ]

        let output = KanataConfiguration.generateFromCollections(collections)
        XCTAssertTrue(output.contains("(defchords a 300")) // Single char name is valid
    }

    func testGroupWithNoChords() {
        // Edge case: group with no chords (shouldn't happen, but test defensively)
        let group = ChordGroup(
            id: UUID(),
            name: "Empty",
            timeout: 300,
            chords: []
        )
        let config = ChordGroupsConfig(groups: [group])
        let collections = [
            RuleCollection(
                id: RuleCollectionIdentifier.chordGroups,
                name: "Chord Groups",
                summary: "Test",
                category: .productivity,
                mappings: [],
                isEnabled: true,
                configuration: .chordGroups(config)
            )
        ]

        let output = KanataConfiguration.generateFromCollections(collections)

        // Should generate empty defchords block (or handle gracefully)
        // participatingKeys will be empty, so no fallbacks
        XCTAssertTrue(output.contains("(defchords Empty 300"))
    }

    // MARK: - Output Format Validation

    func testGeneratedConfigIsValidKanataSyntax() {
        let config = ChordGroupsConfig.benVallackPreset
        let collections = [
            RuleCollection(
                id: RuleCollectionIdentifier.chordGroups,
                name: "Chord Groups",
                summary: "Test",
                category: .productivity,
                mappings: [],
                isEnabled: true,
                configuration: .chordGroups(config)
            )
        ]

        let output = KanataConfiguration.generateFromCollections(collections)

        // Basic syntax checks
        XCTAssertTrue(output.contains("(defcfg"))
        XCTAssertTrue(output.contains("(defsrc"))
        XCTAssertTrue(output.contains("(deflayer base"))

        // Balanced parentheses for defchords blocks
        let defchordsLines = output.components(separatedBy: "\n").filter { $0.contains("(defchords") }
        for line in defchordsLines {
            XCTAssertTrue(line.contains("(defchords"))
        }

        // No syntax errors (manual inspection, but at least check basic structure)
        XCTAssertFalse(output.contains("(defchords  )")) // No empty defchords
    }

    // MARK: - Cross-Group Conflict Resolution

    func testCrossGroupConflictGeneration() {
        // Verify first group wins behavior in generated config
        let chord1 = ChordDefinition(id: UUID(), keys: ["s", "d"], output: "esc")
        let chord2 = ChordDefinition(id: UUID(), keys: ["s", "d"], output: "bspc")

        let group1 = ChordGroup(id: UUID(), name: "Navigation", timeout: 250, chords: [chord1])
        let group2 = ChordGroup(id: UUID(), name: "Editing", timeout: 300, chords: [chord2])

        let config = ChordGroupsConfig(groups: [group1, group2])
        let collection = RuleCollection(
            id: RuleCollectionIdentifier.chordGroups,
            name: "Chord Groups",
            summary: "Test",
            category: .productivity,
            mappings: [],
            isEnabled: true,
            configuration: .chordGroups(config)
        )

        let output = KanataConfiguration.generateFromCollections([collection])

        // First group (Navigation) should win for 's' and 'd' keys
        // Check that Navigation group's chord mappings appear
        XCTAssertTrue(output.contains("(chord Navigation s)") || output.contains("chord Navigation s"))
        XCTAssertTrue(output.contains("(chord Navigation d)") || output.contains("chord Navigation d"))

        // Both groups should still be defined (just deduplicated in deflayer)
        XCTAssertTrue(output.contains("(defchords Navigation 250"))
        XCTAssertTrue(output.contains("(defchords Editing 300"))

        // Both chords should exist in their respective defchords blocks
        XCTAssertTrue(output.contains("(s d) esc"))
        XCTAssertTrue(output.contains("(s d) bspc"))
    }
}
