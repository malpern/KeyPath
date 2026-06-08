@testable import KeyPathCore
import Testing

@Suite("KanataDefseqParser Smoke Tests")
struct KanataDefseqParserSmokeTests {
    @Test("Parses a single defseq")
    func parsesSingleSequence() {
        let config = """
        (defseq window-leader
          (space w))
        """

        let sequences = KanataDefseqParser.parseSequences(from: config)

        #expect(sequences.count == 1)
        #expect(sequences[0].name == "window-leader")
        #expect(sequences[0].keys == ["space", "w"])
    }

    @Test("Parses multiple sequences")
    func parsesMultipleSequences() {
        let config = """
        (defseq
          window-leader (space w)
          app-leader (space a))
        """

        let sequences = KanataDefseqParser.parseSequences(from: config)

        #expect(sequences.count == 2)
        #expect(sequences.first { $0.name == "window-leader" }?.keys == ["space", "w"])
        #expect(sequences.first { $0.name == "app-leader" }?.keys == ["space", "a"])
    }

    @Test("Ignores comments")
    func ignoresComments() {
        let config = """
        ;; Window management sequence
        #| block comment |#
        (defseq window-leader
          (space w))  ;; Space followed by w
        """

        let sequences = KanataDefseqParser.parseSequences(from: config)

        #expect(sequences.count == 1)
        #expect(sequences[0].name == "window-leader")
        #expect(sequences[0].keys == ["space", "w"])
    }

    @Test("Returns no sequences when absent")
    func returnsNoSequencesWhenAbsent() {
        let config = """
        (defsrc
          grv  1    2    3    4    5    6    7    8    9    0    -    =    bspc
        )
        """

        let sequences = KanataDefseqParser.parseSequences(from: config)

        #expect(sequences.isEmpty)
    }

    @Test("Extracts sequences from a real config shape")
    func extractsSequencesFromRealConfigShape() {
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

        (defalias
          spc (tap-hold-press 200 200 spc lmet)
        )
        """

        let sequences = KanataDefseqParser.parseSequences(from: config)

        #expect(sequences.count == 3)
        #expect(sequences.contains { $0.name == "window-leader" })
        #expect(sequences.contains { $0.name == "app-leader" })
        #expect(sequences.contains { $0.name == "nav-leader" })
    }
}
