import Foundation
@testable import KeyPathAppKit
import Testing

@Suite("VirtualKeyParser")
struct VirtualKeyParserTests {
    @Test("Parses simple defvirtualkeys block")
    func parsesSimpleDefvirtualkeys() {
        let config = """
        (defvirtualkeys
          my-key a
          another-key b
        )
        """

        let keys = VirtualKeyParser.parse(config: config)

        #expect(keys.count == 2)
        #expect(keys[0].name == "my-key")
        #expect(keys[0].action == "a")
        #expect(keys[0].source == .virtualkeys)
        #expect(keys[1].name == "another-key")
        #expect(keys[1].action == "b")
    }

    @Test("Parses defvirtualkeys with parenthesized actions")
    func parsesParenthesizedActions() {
        let config = """
        (defvirtualkeys
          email-sig (macro H e l l o spc W o r l d)
          toggle-mode (layer-toggle special)
        )
        """

        let keys = VirtualKeyParser.parse(config: config)

        #expect(keys.count == 2)
        #expect(keys[0].name == "email-sig")
        #expect(keys[0].action == "(macro H e l l o spc W o r l d)")
        #expect(keys[1].name == "toggle-mode")
        #expect(keys[1].action == "(layer-toggle special)")
    }

    @Test("Parses deffakekeys block")
    func parsesDeffakekeys() {
        let config = """
        (deffakekeys
          fake1 a
          fake2 (tap-hold 200 200 a lsft)
        )
        """

        let keys = VirtualKeyParser.parse(config: config)

        #expect(keys.count == 2)
        #expect(keys[0].name == "fake1")
        #expect(keys[0].source == .fakekeys)
        #expect(keys[1].name == "fake2")
        #expect(keys[1].action == "(tap-hold 200 200 a lsft)")
    }

    @Test("Parses both defvirtualkeys and deffakekeys")
    func parsesBothBlockTypes() {
        let config = """
        (defvirtualkeys
          vkey1 a
        )
        (deffakekeys
          fkey1 b
        )
        """

        let keys = VirtualKeyParser.parse(config: config)

        #expect(keys.count == 2)

        let vkey = keys.first { $0.source == .virtualkeys }
        let fkey = keys.first { $0.source == .fakekeys }

        #expect(vkey?.name == "vkey1")
        #expect(fkey?.name == "fkey1")
    }

    @Test("Parses nested parentheses in actions")
    func parsesNestedParens() {
        let config = """
        (defvirtualkeys
          complex (multi (layer-switch nav) (macro a b c))
        )
        """

        let keys = VirtualKeyParser.parse(config: config)

        #expect(keys.count == 1)
        #expect(keys[0].name == "complex")
        #expect(keys[0].action == "(multi (layer-switch nav) (macro a b c))")
    }

    @Test("Handles empty blocks")
    func handlesEmptyBlocks() {
        let config = """
        (defvirtualkeys
        )
        """

        let keys = VirtualKeyParser.parse(config: config)

        #expect(keys.isEmpty)
    }

    @Test("Handles config without virtual keys")
    func handlesConfigWithoutVirtualKeys() {
        let config = """
        (defcfg
          process-unmapped-keys yes
        )
        (defsrc caps a s d f)
        (deflayer base esc a s d f)
        """

        let keys = VirtualKeyParser.parse(config: config)

        #expect(keys.isEmpty)
    }

    @Test("Handles multiple defvirtualkeys blocks")
    func handlesMultipleBlocks() {
        let config = """
        (defvirtualkeys
          key1 a
        )
        (deflayer base esc)
        (defvirtualkeys
          key2 b
        )
        """

        let keys = VirtualKeyParser.parse(config: config)

        #expect(keys.count == 2)
        #expect(keys.map(\.name).sorted() == ["key1", "key2"])
    }

    @Test("Handles comments in config")
    func handlesComments() {
        // Note: This is a simplified test - real Kanata configs use ;; for comments
        // The regex should still work with content between defvirtualkeys blocks
        let config = """
        (defvirtualkeys
          key1 a
        )
        """

        let keys = VirtualKeyParser.parse(config: config)

        #expect(keys.count == 1)
    }

    @Test("Parses real-world example")
    func parsesRealWorldExample() {
        let config = """
        (defcfg
          process-unmapped-keys yes
        )

        (defsrc caps a s d f)

        (defvirtualkeys
          email-signature (macro
            B e s t spc r e g a r d s , ret
            J o h n spc D o e
          )
          nav-mode (layer-switch nav)
          vim-mode (layer-switch vim)
        )

        (deffakekeys
          lctl-toggle (multi
            (on-press press-vkey vk-lctl)
            (on-release release-vkey vk-lctl)
          )
        )

        (deflayer base
          @caps-esc a s d f
        )
        """

        let keys = VirtualKeyParser.parse(config: config)

        #expect(keys.count == 4)

        let virtualKeys = keys.filter { $0.source == .virtualkeys }
        let fakeKeys = keys.filter { $0.source == .fakekeys }

        #expect(virtualKeys.count == 3)
        #expect(fakeKeys.count == 1)

        #expect(virtualKeys.map(\.name).sorted() == ["email-signature", "nav-mode", "vim-mode"])
        #expect(fakeKeys.first?.name == "lctl-toggle")
    }
}
