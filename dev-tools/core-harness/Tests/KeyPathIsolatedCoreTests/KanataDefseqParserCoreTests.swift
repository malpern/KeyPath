import KeyPathCore
import Testing

@Suite("KanataDefseqParser Isolated Core Tests")
struct KanataDefseqParserCoreTests {
    @Test("Parses single-sequence defseq format")
    func parsesSingleSequence() {
        let config = """
        (defseq window-leader
          (space w))
        """

        let sequences = KanataDefseqParser.parseSequences(from: config)

        #expect(sequences == [
            .init(name: "window-leader", keys: ["space", "w"])
        ])
    }

    @Test("Parses multi-sequence defseq format")
    func parsesMultiSequence() {
        let config = """
        (defseq
          window-leader (space w)
          app-leader (space a)
          nav-leader (space n))
        """

        let sequences = KanataDefseqParser.parseSequences(from: config)

        #expect(sequences.count == 3)
        #expect(sequences.first { $0.name == "window-leader" }?.keys == ["space", "w"])
        #expect(sequences.first { $0.name == "app-leader" }?.keys == ["space", "a"])
        #expect(sequences.first { $0.name == "nav-leader" }?.keys == ["space", "n"])
    }

    @Test("Ignores line and block comments")
    func ignoresComments() {
        let config = """
        ;; Window management sequence
        #|
        ignored block
        |#
        (defseq window-leader
          (space w)) ;; trailing comment
        """

        let sequences = KanataDefseqParser.parseSequences(from: config)

        #expect(sequences == [
            .init(name: "window-leader", keys: ["space", "w"])
        ])
    }

    @Test("Returns no sequences when config has no defseq")
    func returnsNoSequencesWhenAbsent() {
        let config = """
        (defsrc
          grv 1 2 3 4 5 6 7 8 9 0 - = bspc
        )
        """

        #expect(KanataDefseqParser.parseSequences(from: config).isEmpty)
    }
}
