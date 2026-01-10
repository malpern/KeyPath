//
//  KanataDefseqParserTests.swift
//  KeyPath
//
//  Created by Claude Code on 2026-01-09.
//  MAL-45: Kanata Sequences (defseq) UI Support
//

@testable import KeyPathCore
import XCTest

final class KanataDefseqParserTests: XCTestCase {
    // MARK: - Single Sequence Format Tests

    func testParseSingleSequence_Basic() {
        let config = """
        (defseq window-leader
          (space w))
        """

        let sequences = KanataDefseqParser.parseSequences(from: config)

        XCTAssertEqual(sequences.count, 1, "Should parse one sequence")
        XCTAssertEqual(sequences[0].name, "window-leader", "Should parse sequence name")
        XCTAssertEqual(sequences[0].keys, ["space", "w"], "Should parse sequence keys")
    }

    func testParseSingleSequence_ThreeKeys() {
        let config = """
        (defseq test-seq
          (ctrl a b))
        """

        let sequences = KanataDefseqParser.parseSequences(from: config)

        XCTAssertEqual(sequences.count, 1)
        XCTAssertEqual(sequences[0].keys, ["ctrl", "a", "b"], "Should parse all three keys")
    }

    // MARK: - Multi-Sequence Format Tests

    func testParseMultiSequence_TwoSequences() {
        let config = """
        (defseq
          window-leader (space w)
          app-leader (space a))
        """

        let sequences = KanataDefseqParser.parseSequences(from: config)

        XCTAssertEqual(sequences.count, 2, "Should parse two sequences")

        let windowSeq = sequences.first { $0.name == "window-leader" }
        XCTAssertNotNil(windowSeq, "Should find window-leader")
        XCTAssertEqual(windowSeq?.keys, ["space", "w"])

        let appSeq = sequences.first { $0.name == "app-leader" }
        XCTAssertNotNil(appSeq, "Should find app-leader")
        XCTAssertEqual(appSeq?.keys, ["space", "a"])
    }

    func testParseMultiSequence_ThreeSequences() {
        let config = """
        (defseq
          seq1 (a b)
          seq2 (c d e)
          seq3 (f))
        """

        let sequences = KanataDefseqParser.parseSequences(from: config)

        XCTAssertEqual(sequences.count, 3, "Should parse three sequences")
        XCTAssertEqual(sequences[0].name, "seq1")
        XCTAssertEqual(sequences[0].keys, ["a", "b"])
        XCTAssertEqual(sequences[1].name, "seq2")
        XCTAssertEqual(sequences[1].keys, ["c", "d", "e"])
        XCTAssertEqual(sequences[2].name, "seq3")
        XCTAssertEqual(sequences[2].keys, ["f"])
    }

    // MARK: - Mixed Format Tests

    func testParseMixed_SingleAndMulti() {
        let config = """
        (defseq window-leader
          (space w))

        (defseq
          app-leader (space a)
          nav-leader (space n))
        """

        let sequences = KanataDefseqParser.parseSequences(from: config)

        XCTAssertEqual(sequences.count, 3, "Should parse all three sequences")
        XCTAssertTrue(sequences.contains { $0.name == "window-leader" }, "Should have window-leader")
        XCTAssertTrue(sequences.contains { $0.name == "app-leader" }, "Should have app-leader")
        XCTAssertTrue(sequences.contains { $0.name == "nav-leader" }, "Should have nav-leader")
    }

    // MARK: - Comment Handling Tests

    func testParseWithLineComments() {
        let config = """
        ;; Window management sequence
        (defseq window-leader
          (space w))  ;; Space followed by w
        """

        let sequences = KanataDefseqParser.parseSequences(from: config)

        XCTAssertEqual(sequences.count, 1, "Should parse sequence ignoring comments")
        XCTAssertEqual(sequences[0].name, "window-leader")
        XCTAssertEqual(sequences[0].keys, ["space", "w"])
    }

    func testParseWithBlockComments() {
        let config = """
        #|
        This is a block comment
        with multiple lines
        |#
        (defseq window-leader
          (space w))
        """

        let sequences = KanataDefseqParser.parseSequences(from: config)

        XCTAssertEqual(sequences.count, 1, "Should parse sequence ignoring block comments")
        XCTAssertEqual(sequences[0].name, "window-leader")
    }

    // MARK: - Whitespace and Formatting Tests

    func testParseWithVariousWhitespace() {
        let config = """
        (defseq   window-leader
            (space    w   ))
        """

        let sequences = KanataDefseqParser.parseSequences(from: config)

        XCTAssertEqual(sequences.count, 1, "Should handle extra whitespace")
        XCTAssertEqual(sequences[0].keys, ["space", "w"], "Should trim whitespace from keys")
    }

    func testParseMultiline() {
        let config = """
        (defseq
          window-leader
          (space w)
          app-leader
          (space a))
        """

        let sequences = KanataDefseqParser.parseSequences(from: config)

        XCTAssertEqual(sequences.count, 2, "Should parse multiline defseq")
    }

    // MARK: - Edge Cases

    func testParseEmptyConfig() {
        let sequences = KanataDefseqParser.parseSequences(from: "")

        XCTAssertTrue(sequences.isEmpty, "Empty config should return no sequences")
    }

    func testParseConfigWithoutDefseq() {
        let config = """
        (defsrc
          grv  1    2    3    4    5    6    7    8    9    0    -    =    bspc
        )
        """

        let sequences = KanataDefseqParser.parseSequences(from: config)

        XCTAssertTrue(sequences.isEmpty, "Config without defseq should return no sequences")
    }

    func testParseOnlyComments() {
        let config = """
        ;; This is just a comment
        #| And a block comment |#
        """

        let sequences = KanataDefseqParser.parseSequences(from: config)

        XCTAssertTrue(sequences.isEmpty, "Comments-only config should return no sequences")
    }

    // MARK: - Real-World Examples

    func testParseRealWorldConfig() {
        let config = """
        ;; Keyboard configuration
        (defcfg
          concurrent-tap-hold true
        )

        ;; Sequences for layer activation
        (defseq
          window-leader (space w)
          app-leader (space a)
          nav-leader (space n))

        ;; More config below...
        (defalias
          spc (tap-hold-press 200 200 spc lmet)
        )
        """

        let sequences = KanataDefseqParser.parseSequences(from: config)

        XCTAssertEqual(sequences.count, 3, "Should extract sequences from full config")
        XCTAssertTrue(sequences.contains { $0.name == "window-leader" })
        XCTAssertTrue(sequences.contains { $0.name == "app-leader" })
        XCTAssertTrue(sequences.contains { $0.name == "nav-leader" })
    }

    func testParseComplexSequences() {
        let config = """
        (defseq
          quick-launch (hyper q)
          workspace-switch (hyper space d)
          browser-nav (space b h)
          terminal-open (space t))
        """

        let sequences = KanataDefseqParser.parseSequences(from: config)

        XCTAssertEqual(sequences.count, 4)

        let workspaceSeq = sequences.first { $0.name == "workspace-switch" }
        XCTAssertEqual(workspaceSeq?.keys, ["hyper", "space", "d"], "Should parse three-key sequence")

        let browserSeq = sequences.first { $0.name == "browser-nav" }
        XCTAssertEqual(browserSeq?.keys, ["space", "b", "h"], "Should parse three-key sequence")
    }

    // MARK: - Name Validation Tests

    func testParseDifferentNameFormats() {
        let config = """
        (defseq
          simple (a b)
          with-hyphen (c d)
          with_underscore (e f)
          CamelCase (g h))
        """

        let sequences = KanataDefseqParser.parseSequences(from: config)

        XCTAssertEqual(sequences.count, 4, "Should handle various name formats")
        XCTAssertTrue(sequences.contains { $0.name == "simple" })
        XCTAssertTrue(sequences.contains { $0.name == "with-hyphen" })
        XCTAssertTrue(sequences.contains { $0.name == "with_underscore" })
        XCTAssertTrue(sequences.contains { $0.name == "CamelCase" })
    }

    // MARK: - Preservation Tests

    func testParsePreservesAllSequences() {
        let config = """
        ;; User's custom sequences (hand-written)
        (defseq custom-sequence
          (ctrl shift x))

        ;; Another custom sequence
        (defseq my-launcher
          (space l))
        """

        let sequences = KanataDefseqParser.parseSequences(from: config)

        XCTAssertEqual(sequences.count, 2, "Should preserve all user sequences")
        XCTAssertTrue(sequences.contains { $0.name == "custom-sequence" })
        XCTAssertTrue(sequences.contains { $0.name == "my-launcher" })
        XCTAssertEqual(sequences.first { $0.name == "custom-sequence" }?.keys, ["ctrl", "shift", "x"])
    }
}
