@testable import KeyPathAppKit
import Testing

// MARK: - symbol(for:)

@Suite("KeyDisplayFormatter.symbol(for:)")
struct KeyDisplayFormatterSymbolTests {
    @Test("Modifier keys return correct symbols for all aliases")
    func modifierKeysReturnCorrectSymbols() {
        // Command / Meta
        for key in ["leftmeta", "rightmeta", "lmet", "rmet", "cmd", "command"] {
            #expect(KeyDisplayFormatter.symbol(for: key) == "⌘", "Expected ⌘ for \(key)")
        }
        // Option / Alt
        for key in ["leftalt", "rightalt", "lalt", "ralt", "alt", "opt", "option"] {
            #expect(KeyDisplayFormatter.symbol(for: key) == "⌥", "Expected ⌥ for \(key)")
        }
        // Shift
        for key in ["leftshift", "rightshift", "lsft", "rsft", "shift"] {
            #expect(KeyDisplayFormatter.symbol(for: key) == "⇧", "Expected ⇧ for \(key)")
        }
        // Control
        for key in ["leftctrl", "rightctrl", "lctl", "rctl", "ctrl", "control"] {
            #expect(KeyDisplayFormatter.symbol(for: key) == "⌃", "Expected ⌃ for \(key)")
        }
        // Caps Lock
        for key in ["capslock", "caps"] {
            #expect(KeyDisplayFormatter.symbol(for: key) == "⇪", "Expected ⇪ for \(key)")
        }
    }

    @Test("Composite modifiers return correct symbols")
    func compositeModifiersReturnCorrectSymbols() {
        #expect(KeyDisplayFormatter.symbol(for: "hyper") == "✦")
        #expect(KeyDisplayFormatter.symbol(for: "meh") == "◆")
    }

    @Test("Special keys return correct symbols")
    func specialKeysReturnCorrectSymbols() {
        #expect(KeyDisplayFormatter.symbol(for: "space") == "⎵")
        #expect(KeyDisplayFormatter.symbol(for: "spc") == "⎵")
        #expect(KeyDisplayFormatter.symbol(for: "sp") == "⎵")
        #expect(KeyDisplayFormatter.symbol(for: "enter") == "↩")
        #expect(KeyDisplayFormatter.symbol(for: "ret") == "↩")
        #expect(KeyDisplayFormatter.symbol(for: "return") == "↩")
        #expect(KeyDisplayFormatter.symbol(for: "tab") == "⇥")
        #expect(KeyDisplayFormatter.symbol(for: "backspace") == "⌫")
        #expect(KeyDisplayFormatter.symbol(for: "bspc") == "⌫")
        #expect(KeyDisplayFormatter.symbol(for: "delete") == "⌦")
        #expect(KeyDisplayFormatter.symbol(for: "del") == "⌦")
        #expect(KeyDisplayFormatter.symbol(for: "esc") == "⎋")
        #expect(KeyDisplayFormatter.symbol(for: "escape") == "⎋")
    }

    @Test("Arrow keys return correct symbols including aliases")
    func arrowKeysReturnCorrectSymbols() {
        #expect(KeyDisplayFormatter.symbol(for: "left") == "←")
        #expect(KeyDisplayFormatter.symbol(for: "right") == "→")
        #expect(KeyDisplayFormatter.symbol(for: "up") == "↑")
        #expect(KeyDisplayFormatter.symbol(for: "down") == "↓")
        #expect(KeyDisplayFormatter.symbol(for: "arrowleft") == "←")
        #expect(KeyDisplayFormatter.symbol(for: "arrowright") == "→")
        #expect(KeyDisplayFormatter.symbol(for: "arrowup") == "↑")
        #expect(KeyDisplayFormatter.symbol(for: "arrowdown") == "↓")
    }

    @Test("Punctuation keys return correct symbols")
    func punctuationKeysReturnCorrectSymbols() {
        #expect(KeyDisplayFormatter.symbol(for: "grave") == "`")
        #expect(KeyDisplayFormatter.symbol(for: "grv") == "`")
        #expect(KeyDisplayFormatter.symbol(for: "minus") == "-")
        #expect(KeyDisplayFormatter.symbol(for: "min") == "-")
        #expect(KeyDisplayFormatter.symbol(for: "equal") == "=")
        #expect(KeyDisplayFormatter.symbol(for: "eql") == "=")
        #expect(KeyDisplayFormatter.symbol(for: "leftbrace") == "[")
        #expect(KeyDisplayFormatter.symbol(for: "lbrc") == "[")
        #expect(KeyDisplayFormatter.symbol(for: "rightbrace") == "]")
        #expect(KeyDisplayFormatter.symbol(for: "rbrc") == "]")
        #expect(KeyDisplayFormatter.symbol(for: "backslash") == "\\")
        #expect(KeyDisplayFormatter.symbol(for: "bksl") == "\\")
        #expect(KeyDisplayFormatter.symbol(for: "semicolon") == ";")
        #expect(KeyDisplayFormatter.symbol(for: "scln") == ";")
        #expect(KeyDisplayFormatter.symbol(for: "apostrophe") == "'")
        #expect(KeyDisplayFormatter.symbol(for: "apos") == "'")
        #expect(KeyDisplayFormatter.symbol(for: "comma") == ",")
        #expect(KeyDisplayFormatter.symbol(for: "comm") == ",")
        #expect(KeyDisplayFormatter.symbol(for: "dot") == ".")
        #expect(KeyDisplayFormatter.symbol(for: "slash") == "/")
    }

    @Test("Unknown key returns nil")
    func unknownKeyReturnsNil() {
        #expect(KeyDisplayFormatter.symbol(for: "xyz") == nil)
        #expect(KeyDisplayFormatter.symbol(for: "foobar") == nil)
        #expect(KeyDisplayFormatter.symbol(for: "notakey") == nil)
    }

    @Test("Symbol lookup is case-insensitive")
    func symbolLookupIsCaseInsensitive() {
        #expect(KeyDisplayFormatter.symbol(for: "LeftMeta") == "⌘")
        #expect(KeyDisplayFormatter.symbol(for: "LCTL") == "⌃")
        #expect(KeyDisplayFormatter.symbol(for: "ESC") == "⎋")
        #expect(KeyDisplayFormatter.symbol(for: "Space") == "⎵")
        #expect(KeyDisplayFormatter.symbol(for: "LEFTSHIFT") == "⇧")
    }
}

// MARK: - format()

@Suite("KeyDisplayFormatter.format()")
struct KeyDisplayFormatterFormatTests {
    @Test("Known keys format to their symbols")
    func knownKeysFormatToSymbols() {
        #expect(KeyDisplayFormatter.format("leftmeta") == "⌘")
        #expect(KeyDisplayFormatter.format("esc") == "⎋")
        #expect(KeyDisplayFormatter.format("space") == "⎵")
        #expect(KeyDisplayFormatter.format("tab") == "⇥")
        #expect(KeyDisplayFormatter.format("left") == "←")
    }

    @Test("Single letter formats to uppercase")
    func singleLetterFormatsToUppercase() {
        #expect(KeyDisplayFormatter.format("a") == "A")
        #expect(KeyDisplayFormatter.format("z") == "Z")
        #expect(KeyDisplayFormatter.format("m") == "M")
    }

    @Test("Single digit stays as-is")
    func singleDigitStaysAsIs() {
        #expect(KeyDisplayFormatter.format("1") == "1")
        #expect(KeyDisplayFormatter.format("9") == "9")
        #expect(KeyDisplayFormatter.format("0") == "0")
    }

    @Test("Unknown multi-char key uppercases")
    func unknownMultiCharKeyUppercases() {
        #expect(KeyDisplayFormatter.format("pgup") == "PGUP")
        #expect(KeyDisplayFormatter.format("pgdn") == "PGDN")
        #expect(KeyDisplayFormatter.format("home") == "HOME")
    }

    @Test("Format trims whitespace before lookup")
    func formatTrimsWhitespace() {
        #expect(KeyDisplayFormatter.format(" a ") == "A")
        #expect(KeyDisplayFormatter.format("  esc  ") == "⎋")
        #expect(KeyDisplayFormatter.format(" 5 ") == "5")
    }

    @Test("Empty string returns empty")
    func emptyStringReturnsEmpty() {
        #expect(KeyDisplayFormatter.format("") == "")
    }

    @Test("fn key formats to fn string")
    func fnKeyFormatsToFnString() {
        #expect(KeyDisplayFormatter.format("fn") == "fn")
        #expect(KeyDisplayFormatter.format("function") == "fn")
    }
}

// MARK: - formatSequence()

@Suite("KeyDisplayFormatter.formatSequence()")
struct KeyDisplayFormatterSequenceTests {
    @Test("Single modifier prefix formats correctly")
    func singleModifierPrefix() {
        #expect(KeyDisplayFormatter.formatSequence("M-right") == "⌘→")
        #expect(KeyDisplayFormatter.formatSequence("C-a") == "⌃A")
        #expect(KeyDisplayFormatter.formatSequence("A-tab") == "⌥⇥")
        #expect(KeyDisplayFormatter.formatSequence("S-z") == "⇧Z")
    }

    @Test("Double modifier prefix formats correctly")
    func doubleModifierPrefix() {
        #expect(KeyDisplayFormatter.formatSequence("C-S-a") == "⌃⇧A")
        #expect(KeyDisplayFormatter.formatSequence("M-S-left") == "⌘⇧←")
    }

    @Test("Triple modifier prefix formats correctly")
    func tripleModifierPrefix() {
        #expect(KeyDisplayFormatter.formatSequence("C-M-A-x") == "⌃⌘⌥X")
    }

    @Test("Quadruple modifier prefix formats correctly")
    func quadrupleModifierPrefix() {
        #expect(KeyDisplayFormatter.formatSequence("C-M-A-S-j") == "⌃⌘⌥⇧J")
    }

    @Test("Multi-token sequence joins with spaces")
    func multiTokenSequenceJoinsWithSpaces() {
        #expect(KeyDisplayFormatter.formatSequence("up ret") == "↑ ↩")
        #expect(KeyDisplayFormatter.formatSequence("left down right") == "← ↓ →")
    }

    @Test("Plain key sequence formats each key")
    func plainKeySequenceFormatsEachKey() {
        #expect(KeyDisplayFormatter.formatSequence("a b c") == "A B C")
    }

    @Test("Single key with no prefix formats normally")
    func singleKeyNoPrefix() {
        #expect(KeyDisplayFormatter.formatSequence("esc") == "⎋")
        #expect(KeyDisplayFormatter.formatSequence("a") == "A")
        #expect(KeyDisplayFormatter.formatSequence("space") == "⎵")
    }
}

// MARK: - tapHoldLabel(for:)

@Suite("KeyDisplayFormatter.tapHoldLabel(for:)")
struct KeyDisplayFormatterTapHoldTests {
    @Test("Single modifier returns its symbol")
    func singleModifierReturnsSymbol() {
        #expect(KeyDisplayFormatter.tapHoldLabel(for: "lmet") == "⌘")
        #expect(KeyDisplayFormatter.tapHoldLabel(for: "lctl") == "⌃")
        #expect(KeyDisplayFormatter.tapHoldLabel(for: "lsft") == "⇧")
        #expect(KeyDisplayFormatter.tapHoldLabel(for: "lalt") == "⌥")
    }

    @Test("Space returns empty string")
    func spaceReturnsEmptyString() {
        #expect(KeyDisplayFormatter.tapHoldLabel(for: "space") == "")
        #expect(KeyDisplayFormatter.tapHoldLabel(for: "spc") == "")
        #expect(KeyDisplayFormatter.tapHoldLabel(for: "sp") == "")
    }

    @Test("Hyper combo detected with plus separator")
    func hyperComboDetectedPlus() {
        #expect(KeyDisplayFormatter.tapHoldLabel(for: "lctl+lmet+lalt+lsft") == "✦")
    }

    @Test("Hyper combo detected with space separator")
    func hyperComboDetectedSpace() {
        #expect(KeyDisplayFormatter.tapHoldLabel(for: "lctl lmet lalt lsft") == "✦")
    }

    @Test("Meh combo detected with plus separator")
    func mehComboDetectedPlus() {
        #expect(KeyDisplayFormatter.tapHoldLabel(for: "lctl+lalt+lsft") == "◆")
    }

    @Test("Meh combo detected with space separator")
    func mehComboDetectedSpace() {
        #expect(KeyDisplayFormatter.tapHoldLabel(for: "lctl lalt lsft") == "◆")
    }

    @Test("Multi-modifier builds concatenated label")
    func multiModifierBuildsLabel() {
        #expect(KeyDisplayFormatter.tapHoldLabel(for: "lctl lsft") == "⌃⇧")
        #expect(KeyDisplayFormatter.tapHoldLabel(for: "lmet+lalt") == "⌘⌥")
    }

    @Test("Empty string returns nil")
    func emptyStringReturnsNil() {
        #expect(KeyDisplayFormatter.tapHoldLabel(for: "") == nil)
    }

    @Test("Single letter returns uppercase")
    func singleLetterReturnsUppercase() {
        #expect(KeyDisplayFormatter.tapHoldLabel(for: "a") == "A")
        #expect(KeyDisplayFormatter.tapHoldLabel(for: "z") == "Z")
    }

    @Test("Whitespace-only returns nil")
    func whitespaceOnlyReturnsNil() {
        #expect(KeyDisplayFormatter.tapHoldLabel(for: "   ") == nil)
        #expect(KeyDisplayFormatter.tapHoldLabel(for: "\t") == nil)
    }
}
