@testable import KeyPathAppKit
import XCTest

/// Tests for KanataBehaviorRenderer's chord rendering and advanced action conversion.
final class KanataBehaviorRendererChordTests: XCTestCase {
    // MARK: - Chord rendering

    func testRenderChord_ReturnsAliasReference() {
        let chord = ChordBehavior(keys: ["j", "k"], output: .keystroke(key: "esc"))
        let mapping = KeyMapping(input: "j", action: .keystroke(key: "_"), behavior: .chord(chord))
        let rendered = KanataBehaviorRenderer.render(mapping)
        XCTAssertEqual(rendered, "@kp-chord-j-k")
    }

    func testRenderChord_ThreeKeys_SortedGroupName() {
        let chord = ChordBehavior(keys: ["k", "j", "l"], output: .keystroke(key: "esc"))
        let mapping = KeyMapping(input: "j", action: .keystroke(key: "_"), behavior: .chord(chord))
        let rendered = KanataBehaviorRenderer.render(mapping)
        XCTAssertEqual(rendered, "@kp-chord-j-k-l")
    }

    // MARK: - Chord definition rendering

    func testRenderChordDefinition_BasicTwoKey() {
        let chord = ChordBehavior(keys: ["j", "k"], output: .keystroke(key: "esc"), timeout: 200)
        let definition = KanataBehaviorRenderer.renderChordDefinition(chord)
        XCTAssertTrue(definition.contains("defchords kp-chord-j-k 200"))
        XCTAssertTrue(definition.contains("(j k)"))
        XCTAssertTrue(definition.contains("esc"))
    }

    func testRenderChordDefinition_CustomTimeout() {
        let chord = ChordBehavior(keys: ["s", "d"], output: .keystroke(key: "enter"), timeout: 150)
        let definition = KanataBehaviorRenderer.renderChordDefinition(chord)
        XCTAssertTrue(definition.contains("150"))
    }

    func testRenderChordDefinition_MultiKeyOutput() {
        let chord = ChordBehavior(keys: ["j", "k"], output: .rawKanata("C-z"))
        let definition = KanataBehaviorRenderer.renderChordDefinition(chord)
        XCTAssertTrue(definition.contains("C-z"))
    }

    func testRenderChordDefinition_HyperOutput() {
        let chord = ChordBehavior(keys: ["a", "s"], output: .hyper)
        let definition = KanataBehaviorRenderer.renderChordDefinition(chord)
        XCTAssertTrue(definition.contains("multi lctl lmet lalt lsft"))
    }

    // MARK: - parseActionString

    func testParseActionString_SimpleKey() {
        let action = KanataBehaviorRenderer.parseActionString("esc")
        XCTAssertEqual(action, .keystroke(key: "esc"))
    }

    func testParseActionString_Hyper() {
        let action = KanataBehaviorRenderer.parseActionString("hyper")
        XCTAssertEqual(action, .hyper)
    }

    func testParseActionString_Meh() {
        let action = KanataBehaviorRenderer.parseActionString("meh")
        XCTAssertEqual(action, .meh)
    }

    func testParseActionString_MultiHyper() {
        let action = KanataBehaviorRenderer.parseActionString("(multi lctl lmet lalt lsft)")
        XCTAssertEqual(action, .hyper)
    }

    func testParseActionString_MultiMeh() {
        let action = KanataBehaviorRenderer.parseActionString("(multi lctl lalt lsft)")
        XCTAssertEqual(action, .meh)
    }

    func testParseActionString_LayerWhileHeld_IsRawKanata() {
        let action = KanataBehaviorRenderer.parseActionString("(layer-while-held nav)")
        XCTAssertTrue(action.isRawKanata || action.isActivateLayer,
                      "layer-while-held should parse to rawKanata or activateLayer")
    }

    func testParseActionString_LayerSwitch() {
        let action = KanataBehaviorRenderer.parseActionString("(layer-switch base)")
        XCTAssertTrue(action.isActivateLayer || action.isRawKanata,
                      "layer-switch should parse to activateLayer or rawKanata")
    }

    func testParseActionString_RawKanataFallback() {
        let action = KanataBehaviorRenderer.parseActionString("(some-unknown-expr foo bar)")
        XCTAssertEqual(action, .rawKanata("(some-unknown-expr foo bar)"))
    }

    func testParseActionString_ModifiedKey() {
        let action = KanataBehaviorRenderer.parseActionString("S--")
        XCTAssertEqual(action, .keystroke(key: "S--"))
    }

    // MARK: - Render + parse round-trip for all dual-role variants

    func testRoundTrip_TapHoldBasic() {
        let dr = DualRoleBehavior(
            tapAction: .keystroke(key: "a"),
            holdAction: .keystroke(key: "lctl"),
            tapTimeout: 180,
            holdTimeout: 220
        )
        let mapping = KeyMapping(input: "a", action: .keystroke(key: "a"), behavior: .dualRole(dr))
        let rendered = KanataBehaviorRenderer.render(mapping)
        let parsed = KanataBehaviorParser.parse(rendered)

        if case let .dualRole(result) = parsed {
            XCTAssertEqual(result.tapAction, .keystroke(key: "a"))
            XCTAssertEqual(result.holdAction, .keystroke(key: "lctl"))
            XCTAssertEqual(result.tapTimeout, 180)
            XCTAssertEqual(result.holdTimeout, 220)
        } else {
            XCTFail("Expected dualRole after round-trip")
        }
    }

    func testRoundTrip_TapHoldPress() {
        let dr = DualRoleBehavior(
            tapAction: .keystroke(key: "f"),
            holdAction: .keystroke(key: "lmet"),
            activateHoldOnOtherKey: true
        )
        let mapping = KeyMapping(input: "f", action: .keystroke(key: "f"), behavior: .dualRole(dr))
        let rendered = KanataBehaviorRenderer.render(mapping)

        XCTAssertTrue(rendered.contains("tap-hold-press"))

        let parsed = KanataBehaviorParser.parse(rendered)
        if case let .dualRole(result) = parsed {
            XCTAssertTrue(result.activateHoldOnOtherKey)
        } else {
            XCTFail("Expected dualRole")
        }
    }

    func testRoundTrip_TapHoldRelease() {
        let dr = DualRoleBehavior(
            tapAction: .keystroke(key: "j"),
            holdAction: .keystroke(key: "rsft"),
            quickTap: true
        )
        let mapping = KeyMapping(input: "j", action: .keystroke(key: "j"), behavior: .dualRole(dr))
        let rendered = KanataBehaviorRenderer.render(mapping)

        XCTAssertTrue(rendered.contains("tap-hold-release"))

        let parsed = KanataBehaviorParser.parse(rendered)
        if case let .dualRole(result) = parsed {
            XCTAssertTrue(result.quickTap)
        } else {
            XCTFail("Expected dualRole")
        }
    }

    func testRoundTrip_OppositeHand() {
        let dr = DualRoleBehavior(
            tapAction: .keystroke(key: "a"),
            holdAction: .keystroke(key: "lctl"),
            useOppositeHand: true
        )
        let mapping = KeyMapping(input: "a", action: .keystroke(key: "a"), behavior: .dualRole(dr))
        let rendered = KanataBehaviorRenderer.render(mapping)

        XCTAssertTrue(rendered.contains("tap-hold"), "Opposite hand should produce a tap-hold variant")
    }

    func testRoundTrip_Macro() {
        let macro = MacroBehavior(outputs: ["h", "e", "l", "l", "o"], source: .keys)
        let mapping = KeyMapping(input: "m", action: .keystroke(key: "m"), behavior: .macro(macro))
        let rendered = KanataBehaviorRenderer.render(mapping)

        XCTAssertTrue(rendered.contains("macro"))
        XCTAssertTrue(rendered.contains("h"))
        XCTAssertTrue(rendered.contains("o"))
    }

    // MARK: - Timeout variables

    func testDualRole_Default200_UsesVariable() {
        let dr = DualRoleBehavior(
            tapAction: .keystroke(key: "a"),
            holdAction: .keystroke(key: "lctl"),
            tapTimeout: 200,
            holdTimeout: 200
        )
        let mapping = KeyMapping(input: "a", action: .keystroke(key: "a"), behavior: .dualRole(dr))
        let rendered = KanataBehaviorRenderer.render(mapping)
        XCTAssertTrue(rendered.contains("$tap-timeout"))
        XCTAssertTrue(rendered.contains("$hold-timeout"))
    }

    func testDualRole_NonDefault_UsesLiteralValues() {
        let dr = DualRoleBehavior(
            tapAction: .keystroke(key: "a"),
            holdAction: .keystroke(key: "lctl"),
            tapTimeout: 180,
            holdTimeout: 250
        )
        let mapping = KeyMapping(input: "a", action: .keystroke(key: "a"), behavior: .dualRole(dr))
        let rendered = KanataBehaviorRenderer.render(mapping)
        XCTAssertTrue(rendered.contains("180"))
        XCTAssertTrue(rendered.contains("250"))
        XCTAssertFalse(rendered.contains("$tap-timeout"))
    }

    // MARK: - Simple action rendering (no behavior)

    func testRender_NoBehavior_ReturnsKanataOutput() {
        let mapping = KeyMapping(input: "caps", action: .keystroke(key: "esc"))
        let rendered = KanataBehaviorRenderer.render(mapping)
        XCTAssertEqual(rendered, "esc")
    }

    func testRender_NoBehavior_Hyper() {
        let mapping = KeyMapping(input: "caps", action: .hyper)
        let rendered = KanataBehaviorRenderer.render(mapping)
        XCTAssertTrue(rendered.contains("multi lctl lmet lalt lsft"))
    }

    func testRender_NoBehavior_RawKanata() {
        let mapping = KeyMapping(input: "x", action: .rawKanata("(layer-switch nav)"))
        let rendered = KanataBehaviorRenderer.render(mapping)
        XCTAssertEqual(rendered, "(layer-switch nav)")
    }
}
