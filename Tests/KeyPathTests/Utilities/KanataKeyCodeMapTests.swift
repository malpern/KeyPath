@testable import KeyPathAppKit
import Testing

@Suite("KanataKeyCodeMap")
struct KanataKeyCodeMapTests {
    @Test("maps common Kanata aliases to macOS key codes")
    func mapsCommonKanataAliasesToKeyCodes() {
        #expect(KanataKeyCodeMap.keyCode(for: "caps") == 57)
        #expect(KanataKeyCodeMap.keyCode(for: "capslock") == 57)
        #expect(KanataKeyCodeMap.keyCode(for: "space") == 49)
        #expect(KanataKeyCodeMap.keyCode(for: "spc") == 49)
        #expect(KanataKeyCodeMap.keyCode(for: "ret") == 36)
        #expect(KanataKeyCodeMap.keyCode(for: "enter") == 36)
    }

    @Test("maps semicolon aliases to the same key code")
    func mapsSemicolonAliasesToSameKeyCode() {
        #expect(KanataKeyCodeMap.keyCode(for: ";") == 41)
        #expect(KanataKeyCodeMap.keyCode(for: "scln") == 41)
        #expect(KanataKeyCodeMap.keyCode(for: "semicolon") == 41)
    }

    @Test("maps key codes to overlay names")
    func mapsKeyCodesToOverlayNames() {
        #expect(KanataKeyCodeMap.overlayName(for: 0) == "a")
        #expect(KanataKeyCodeMap.overlayName(for: 41) == "semicolon")
        #expect(KanataKeyCodeMap.overlayName(for: 24) == "equal")
        #expect(KanataKeyCodeMap.overlayName(for: 255) == "unknown-255")
    }
}
