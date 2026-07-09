@testable import KeyPathAppKit
@testable import KeyPathCore
import KeyPathRulesCore
@preconcurrency import XCTest

final class DeviceExclusionDefseqPreservationTests: XCTestCase {
    // MARK: - KanataDefchordsParser Unit Tests

    func testParseGroups_SingleGroup() {
        let config = """
        (defchords nav 200
          (a s) esc
          (d f) tab
        )
        """
        let groups = KanataDefchordsParser.parseGroups(from: config)
        XCTAssertEqual(groups.count, 1)
        XCTAssertEqual(groups.first?.name, "nav")
        XCTAssertEqual(groups.first?.timeoutToken, "200")
        XCTAssertEqual(groups.first?.chords.count, 2)
    }

    func testParseGroups_MultipleGroups() {
        let config = """
        (defchords group1 100
          (a s) x
        )
        (defchords group2 200
          (d f) y
        )
        """
        let groups = KanataDefchordsParser.parseGroups(from: config)
        XCTAssertEqual(groups.count, 2)
        XCTAssertEqual(groups[0].name, "group1")
        XCTAssertEqual(groups[1].name, "group2")
    }

    func testParseGroups_ChordKeysExtracted() {
        let config = """
        (defchords test 150
          (j k) esc
          (k l) tab
        )
        """
        let groups = KanataDefchordsParser.parseGroups(from: config)
        XCTAssertEqual(groups.first?.chords.count, 2)
        XCTAssertEqual(groups.first?.chords[0].keys, ["j", "k"])
        XCTAssertEqual(groups.first?.chords[0].action, "esc")
        XCTAssertEqual(groups.first?.chords[1].keys, ["k", "l"])
        XCTAssertEqual(groups.first?.chords[1].action, "tab")
    }

    func testParseGroups_EmptyConfig() {
        let groups = KanataDefchordsParser.parseGroups(from: "")
        XCTAssertTrue(groups.isEmpty)
    }

    func testParseGroups_NoDefchords() {
        let config = """
        (defcfg process-unmapped-keys yes)
        (defsrc a b c)
        (deflayer base a b c)
        """
        let groups = KanataDefchordsParser.parseGroups(from: config)
        XCTAssertTrue(groups.isEmpty)
    }

    func testParseGroups_WithInlineComments() {
        let config = """
        (defchords nav 200 ;; navigation chords
          (a s) esc ;; quick escape
          (d f) tab
        )
        """
        let groups = KanataDefchordsParser.parseGroups(from: config)
        XCTAssertEqual(groups.count, 1)
        XCTAssertEqual(groups.first?.chords.count, 2)
    }

    func testParseGroups_TimeoutTokenFormats() {
        let config1 = "(defchords g1 100\n  (a s) x\n)"
        let groups1 = KanataDefchordsParser.parseGroups(from: config1)
        XCTAssertEqual(groups1.first?.timeoutToken, "100")

        let config2 = "(defchords g2 $timeout\n  (a s) x\n)"
        let groups2 = KanataDefchordsParser.parseGroups(from: config2)
        XCTAssertEqual(groups2.first?.timeoutToken, "$timeout")
    }

    func testParseGroups_SingleLineGroup() {
        let config = "(defchords fast 50 (a s) esc)"
        let groups = KanataDefchordsParser.parseGroups(from: config)
        XCTAssertEqual(groups.count, 1)
        XCTAssertEqual(groups.first?.name, "fast")
    }

    func testParseGroups_KeySetComputed() {
        let config = """
        (defchords test 200
          (a s) x
          (s d) y
        )
        """
        let groups = KanataDefchordsParser.parseGroups(from: config)
        XCTAssertEqual(groups.first?.keySet, Set(["a", "s", "d"]))
    }

    // MARK: - KanataDefchordsParser.referencedChordGroups

    func testReferencedChordGroups_FindsReferences() {
        let mappings = [
            KeyMapping(input: "a", action: .keystroke(key: "(chord nav a)")),
            KeyMapping(input: "b", action: .keystroke(key: "(chord symbols b)")),
            KeyMapping(input: "c", action: .keystroke(key: "d")),
        ]
        let refs = KanataDefchordsParser.referencedChordGroups(in: mappings)
        XCTAssertEqual(refs, Set(["nav", "symbols"]))
    }

    func testReferencedChordGroups_EmptyMappings() {
        let refs = KanataDefchordsParser.referencedChordGroups(in: [])
        XCTAssertTrue(refs.isEmpty)
    }

    func testReferencedChordGroups_NoChordActions() {
        let mappings = [
            KeyMapping(input: "a", action: .keystroke(key: "b")),
            KeyMapping(input: "c", action: .keystroke(key: "d")),
        ]
        let refs = KanataDefchordsParser.referencedChordGroups(in: mappings)
        XCTAssertTrue(refs.isEmpty)
    }

    // MARK: - KanataDefseqParser Edge Cases

    func testDefseqParser_SingleSequence() {
        let config = "(defseq hello (a b c))"
        let sequences = KanataDefseqParser.parseSequences(from: config)
        XCTAssertEqual(sequences.count, 1)
        XCTAssertEqual(sequences.first?.name, "hello")
        XCTAssertEqual(sequences.first?.keys, ["a", "b", "c"])
    }

    func testDefseqParser_MultiSequence() {
        let config = """
        (defseq
          seq1 (a b)
          seq2 (c d e))
        """
        let sequences = KanataDefseqParser.parseSequences(from: config)
        XCTAssertEqual(sequences.count, 2)
        XCTAssertEqual(sequences[0].name, "seq1")
        XCTAssertEqual(sequences[1].name, "seq2")
    }

    func testDefseqParser_EmptyConfig() {
        let sequences = KanataDefseqParser.parseSequences(from: "")
        XCTAssertTrue(sequences.isEmpty)
    }

    func testDefseqParser_NoDefseq() {
        let config = "(defcfg process-unmapped-keys yes)"
        let sequences = KanataDefseqParser.parseSequences(from: config)
        XCTAssertTrue(sequences.isEmpty)
    }

    func testDefseqParser_WithComments() {
        let config = """
        ;; This is a comment
        (defseq myseq (a b c))
        ;; Another comment
        """
        let sequences = KanataDefseqParser.parseSequences(from: config)
        XCTAssertEqual(sequences.count, 1)
        XCTAssertEqual(sequences.first?.name, "myseq")
    }

    func testDefseqParser_DuplicateSequencesDeduped() {
        let config = """
        (defseq hello (a b c))
        (defseq hello (a b c))
        """
        let sequences = KanataDefseqParser.parseSequences(from: config)
        XCTAssertEqual(sequences.count, 1)
    }

    func testDefseqParser_NameWithHyphens() {
        let config = "(defseq window-leader (spc w))"
        let sequences = KanataDefseqParser.parseSequences(from: config)
        XCTAssertEqual(sequences.first?.name, "window-leader")
    }

    // MARK: - Device Exclusion Parser Tests

    #if os(macOS)
        func testParseExcludedDevices_EmptyInput() {
            let parsed = KanataConfiguration.parseExcludedMacOSDeviceNames(fromKanataList: "")
            XCTAssertTrue(parsed.isEmpty)
        }

        func testParseExcludedDevices_OnlyNonMatchingLines() {
            let output = """
            some random text
            another line
            """
            let parsed = KanataConfiguration.parseExcludedMacOSDeviceNames(fromKanataList: output)
            XCTAssertTrue(parsed.isEmpty)
        }

        func testParseExcludedDevices_VirtualHIDDetected() {
            let output = "0xABCD1234 1452 610 VirtualHIDKeyboard"
            let parsed = KanataConfiguration.parseExcludedMacOSDeviceNames(fromKanataList: output)
            XCTAssertTrue(parsed.contains("VirtualHIDKeyboard"))
            XCTAssertTrue(parsed.contains("0xABCD1234"))
        }

        func testParseExcludedDevices_PhysicalDeviceExcluded() {
            let output = "0xAAAABBBB 1452 610 Apple Internal Keyboard / Trackpad"
            let parsed = KanataConfiguration.parseExcludedMacOSDeviceNames(fromKanataList: output)
            XCTAssertTrue(
                parsed.isEmpty,
                "Physical keyboards should not appear in exclusion list"
            )
        }

        func testParseExcludedDevices_ResultIsSorted() {
            let output = """
            0xZZZZ0000 1 2 VirtualHIDKeyboard
            0xAAAA0000 1 2 Karabiner-DriverKit-VirtualHIDDevice-VirtualHIDKeyboard
            """
            let parsed = KanataConfiguration.parseExcludedMacOSDeviceNames(fromKanataList: output)
            XCTAssertEqual(parsed, parsed.sorted(), "Results should be sorted")
        }
    #endif

    // MARK: - ChordGroupConfig Model Tests

    func testChordGroupConfig_Equatable() {
        let a = ChordGroupConfig(
            name: "nav",
            timeoutToken: "200",
            chords: [ChordGroupConfig.ChordDefinition(keys: ["a", "s"], action: "esc")]
        )
        let b = ChordGroupConfig(
            name: "nav",
            timeoutToken: "200",
            chords: [ChordGroupConfig.ChordDefinition(keys: ["a", "s"], action: "esc")]
        )
        XCTAssertEqual(a, b)
    }

    func testChordGroupConfig_CodableRoundTrip() throws {
        let original = ChordGroupConfig(
            name: "test",
            timeoutToken: "150",
            chords: [
                ChordGroupConfig.ChordDefinition(keys: ["j", "k"], action: "esc"),
                ChordGroupConfig.ChordDefinition(keys: ["k", "l"], action: "tab"),
            ]
        )
        let data = try JSONEncoder().encode(original)
        let decoded = try JSONDecoder().decode(ChordGroupConfig.self, from: data)
        XCTAssertEqual(decoded, original)
    }

    func testChordDefinition_CodableRoundTrip() throws {
        let original = ChordGroupConfig.ChordDefinition(keys: ["a", "s", "d"], action: "esc")
        let data = try JSONEncoder().encode(original)
        let decoded = try JSONDecoder().decode(ChordGroupConfig.ChordDefinition.self, from: data)
        XCTAssertEqual(decoded, original)
    }

    // MARK: - ParsedSequence Model Tests

    func testParsedSequence_Equatable() {
        let a = KanataDefseqParser.ParsedSequence(name: "test", keys: ["a", "b"])
        let b = KanataDefseqParser.ParsedSequence(name: "test", keys: ["a", "b"])
        let c = KanataDefseqParser.ParsedSequence(name: "other", keys: ["a", "b"])
        XCTAssertEqual(a, b)
        XCTAssertNotEqual(a, c)
    }

    // MARK: - Config Generation With Preserved Data

    func testGenerateFromCollections_IncludesChordGroups() {
        let collection = RuleCollection(
            name: "Test",
            summary: "test",
            category: .custom,
            mappings: [KeyMapping(input: "caps", action: .keystroke(key: "esc"))],
            isEnabled: true,
            isSystemDefault: false
        )
        let chordGroups = [
            ChordGroupConfig(
                name: "nav",
                timeoutToken: "200",
                chords: [ChordGroupConfig.ChordDefinition(keys: ["a", "s"], action: "esc")]
            ),
        ]

        let config = KanataConfiguration.generateFromCollections(
            [collection],
            chordGroups: chordGroups
        )
        XCTAssertTrue(config.contains("defchords"), "Config should include chord groups")
        XCTAssertTrue(config.contains("nav"), "Config should include chord group name")
    }

    func testGenerateFromCollections_IncludesSequences() {
        let collection = RuleCollection(
            name: "Test",
            summary: "test",
            category: .custom,
            mappings: [KeyMapping(input: "caps", action: .keystroke(key: "esc"))],
            isEnabled: true,
            isSystemDefault: false
        )
        let sequences = [
            KanataDefseqParser.ParsedSequence(name: "hello-seq", keys: ["a", "b", "c"]),
        ]

        let config = KanataConfiguration.generateFromCollections(
            [collection],
            sequences: sequences
        )
        XCTAssertTrue(config.contains("defseq"), "Config should include sequences")
        XCTAssertTrue(config.contains("hello-seq"), "Config should include sequence name")
    }

    func testGenerateFromCollections_EmptyChordGroupsOmitted() {
        let collection = RuleCollection(
            name: "Test",
            summary: "test",
            category: .custom,
            mappings: [KeyMapping(input: "caps", action: .keystroke(key: "esc"))],
            isEnabled: true,
            isSystemDefault: false
        )

        let config = KanataConfiguration.generateFromCollections(
            [collection],
            chordGroups: []
        )
        XCTAssertFalse(
            config.contains("defchords"),
            "Empty chord groups should not produce defchords block"
        )
    }

    func testGenerateFromCollections_EmptySequencesOmitted() {
        let collection = RuleCollection(
            name: "Test",
            summary: "test",
            category: .custom,
            mappings: [KeyMapping(input: "caps", action: .keystroke(key: "esc"))],
            isEnabled: true,
            isSystemDefault: false
        )

        let config = KanataConfiguration.generateFromCollections(
            [collection],
            sequences: []
        )
        XCTAssertFalse(
            config.contains("defseq"),
            "Empty sequences should not produce defseq block"
        )
    }

    // MARK: - Defchords Round-Trip Tests

    func testDefchordsRoundTrip_ParsedGroupsSurviveRegeneration() {
        let originalConfig = """
        (defchords nav 200
          (a s) esc
          (d f) tab
        )
        """
        let parsed = KanataDefchordsParser.parseGroups(from: originalConfig)
        XCTAssertEqual(parsed.count, 1)

        let collection = RuleCollection(
            name: "Test",
            summary: "test",
            category: .custom,
            mappings: [KeyMapping(input: "caps", action: .keystroke(key: "esc"))],
            isEnabled: true,
            isSystemDefault: false
        )

        let regenerated = KanataConfiguration.generateFromCollections(
            [collection],
            chordGroups: parsed
        )

        let reparsed = KanataDefchordsParser.parseGroups(from: regenerated)
        XCTAssertEqual(reparsed.count, 1, "Chord group should survive regeneration")
        XCTAssertEqual(reparsed.first?.name, "nav")
        XCTAssertEqual(reparsed.first?.chords.count, 2)
    }

    // MARK: - Defseq Round-Trip Tests

    func testDefseqRoundTrip_ParsedSequencesSurviveRegeneration() {
        let originalConfig = "(defseq hello-seq (a b c))"
        let parsed = KanataDefseqParser.parseSequences(from: originalConfig)
        XCTAssertEqual(parsed.count, 1)

        let collection = RuleCollection(
            name: "Test",
            summary: "test",
            category: .custom,
            mappings: [KeyMapping(input: "caps", action: .keystroke(key: "esc"))],
            isEnabled: true,
            isSystemDefault: false
        )

        let regenerated = KanataConfiguration.generateFromCollections(
            [collection],
            sequences: parsed
        )

        let reparsed = KanataDefseqParser.parseSequences(from: regenerated)
        XCTAssertEqual(reparsed.count, 1, "Sequence should survive regeneration")
        XCTAssertEqual(reparsed.first?.name, "hello-seq")
        XCTAssertEqual(reparsed.first?.keys, ["a", "b", "c"])
    }
}
