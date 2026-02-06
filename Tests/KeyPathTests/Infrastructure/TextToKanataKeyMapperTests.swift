@testable import KeyPathAppKit
import Testing

@Suite("TextToKanataKeyMapper")
struct TextToKanataKeyMapperTests {
    @Test("Maps letters and digits")
    func mapsLettersAndDigits() {
        let result = TextToKanataKeyMapper.map(text: "aZ9")
        #expect(result == .success(["a", "S-z", "9"]))
    }

    @Test("Maps punctuation and whitespace")
    func mapsPunctuationAndWhitespace() {
        let result = TextToKanataKeyMapper.map(text: "!\n_")
        #expect(result == .success(["S-1", "ret", "S-min"]))
    }

    @Test("Detects unsupported ASCII control characters")
    func detectsUnsupportedCharacters() {
        let text = "\u{7F}"
        let unsupported = TextToKanataKeyMapper.firstUnsupportedCharacter(in: text)
        #expect(unsupported == "\u{7F}")
    }

    // MARK: - Text sequence mapping tests

    @Test("Maps text with trailing space")
    func mapsTextWithTrailingSpace() {
        let result = TextToKanataKeyMapper.map(text: "abc ")
        #expect(result == .success(["a", "b", "c", "spc"]))
    }

    @Test("Maps text with trailing period")
    func mapsTextWithTrailingPeriod() {
        let result = TextToKanataKeyMapper.map(text: "abc.")
        #expect(result == .success(["a", "b", "c", "."]))
    }

    @Test("Rejects non-ASCII characters")
    func rejectsNonASCII() {
        // These should fail because they contain non-ASCII
        #expect(TextToKanataKeyMapper.firstUnsupportedCharacter(in: "café") == "é")
        #expect(TextToKanataKeyMapper.firstUnsupportedCharacter(in: "naïve") == "ï")
        #expect(TextToKanataKeyMapper.firstUnsupportedCharacter(in: "résumé") == "é")
    }

    @Test("Maps common punctuation characters")
    func mapsCommonPunctuation() {
        // Verify common punctuation can be mapped
        #expect(TextToKanataKeyMapper.map(character: " ") == "spc")
        #expect(TextToKanataKeyMapper.map(character: ".") == ".")
        #expect(TextToKanataKeyMapper.map(character: ",") == ",")
        #expect(TextToKanataKeyMapper.map(character: "!") == "S-1")
        #expect(TextToKanataKeyMapper.map(character: "?") == "S-/")
    }

    @Test("Maps lowercase text sequences")
    func mapsLowercaseTextSequences() {
        #expect(TextToKanataKeyMapper.map(text: "abc").isSuccess)
        #expect(TextToKanataKeyMapper.map(text: "xyz").isSuccess)
        #expect(TextToKanataKeyMapper.map(text: "hello").isSuccess)
        #expect(TextToKanataKeyMapper.map(text: "world").isSuccess)
    }
}

/// Helper extension for cleaner test assertions
extension Result where Success == [String], Failure == TextToKanataKeyMapper.MappingError {
    var isSuccess: Bool {
        if case .success = self { return true }
        return false
    }
}
