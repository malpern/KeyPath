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
}
