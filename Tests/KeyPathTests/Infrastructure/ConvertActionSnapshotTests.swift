import Foundation
@testable import KeyPathAppKit
import Testing

/// Snapshot tests for KanataBehaviorRenderer.convertAction behavior.
/// These tests exercise convertAction through the public render() API using
/// DualRoleBehavior mappings where tapAction/holdAction pass through convertAction.
///
/// Purpose: lock down exact output for every input pattern so the Phase 2
/// refactor (convertAction → KeyAction → kanataOutput) can't silently diverge.
@Suite("convertAction snapshots")
struct ConvertActionSnapshotTests {
    // MARK: - Single key passthrough

    @Test("Single lowercase key passes through convertToKanataKey")
    func singleKey() {
        let result = renderHold("a")
        #expect(result.contains(" a)"))
    }

    @Test("Single key with kanata name")
    func singleKanataKey() {
        let result = renderHold("lctl")
        #expect(result.contains(" lctl)"))
    }

    @Test("Key name normalization (escape → esc)")
    func keyNameNormalization() {
        let result = renderHold("escape")
        #expect(result.contains(" esc)"))
    }

    @Test("Key name normalization (command → lmet)")
    func commandNormalization() {
        let result = renderHold("command")
        #expect(result.contains(" lmet)"))
    }

    @Test("Key name normalization (backspace → bspc)")
    func backspaceNormalization() {
        let result = renderHold("backspace")
        #expect(result.contains(" bspc)"))
    }

    // MARK: - Hyper keyword

    @Test("hyper keyword without linked layers")
    func hyperNoLayers() {
        let result = renderHold("hyper")
        #expect(result.contains("(multi lctl lmet lalt lsft)"))
    }

    @Test("hyper is case-insensitive")
    func hyperCaseInsensitive() {
        let resultUpper = renderHold("HYPER")
        let resultMixed = renderHold("Hyper")
        #expect(resultUpper.contains("(multi lctl lmet lalt lsft)"))
        #expect(resultMixed.contains("(multi lctl lmet lalt lsft)"))
    }

    @Test("hyper with hold-mode linked layer")
    func hyperWithHoldLayer() {
        let result = renderHold("hyper", hyperLinkedLayerInfos: [
            HyperLinkedLayerInfo(layerName: "nav", triggerMode: .hold),
        ])
        #expect(result.contains("(multi lctl lmet lalt lsft (layer-while-held nav)"))
        #expect(result.contains("(on-press-fakekey kp-layer-nav-enter tap)"))
        #expect(result.contains("(on-release-fakekey kp-layer-nav-exit tap)"))
    }

    @Test("hyper with tap-mode linked layer")
    func hyperWithTapLayer() {
        let result = renderHold("hyper", hyperLinkedLayerInfos: [
            HyperLinkedLayerInfo(layerName: "symbols", triggerMode: .tap),
        ])
        #expect(result.contains("(multi lctl lmet lalt lsft"))
        #expect(result.contains("(on-press-fakekey kp-layer-symbols-enter tap)"))
        #expect(result.contains("(one-shot-press 5000 (layer-while-held symbols))"))
    }

    // MARK: - Meh keyword

    @Test("meh keyword")
    func mehKeyword() {
        let result = renderHold("meh")
        #expect(result.contains("(multi lctl lalt lsft)"))
    }

    @Test("meh is case-insensitive")
    func mehCaseInsensitive() {
        let result = renderHold("MEH")
        #expect(result.contains("(multi lctl lalt lsft)"))
    }

    // MARK: - Multi-key (space-separated)

    @Test("Space-separated keys produce multi expression")
    func multiKey() {
        let result = renderHold("lctl lalt del")
        #expect(result.contains("(multi lctl lalt del)"))
    }

    @Test("Two keys produce multi expression")
    func twoKeys() {
        let result = renderHold("lmet spc")
        #expect(result.contains("(multi lmet spc)"))
    }

    // MARK: - S-expression passthrough

    @Test("S-expression passes through unchanged")
    func sExpression() {
        let result = renderHold("(layer-while-held nav)")
        #expect(result.contains("(layer-while-held nav)"))
    }

    @Test("Nested S-expression passes through")
    func nestedSExpression() {
        let result = renderHold("(multi lctl (layer-toggle symbols))")
        #expect(result.contains("(multi lctl (layer-toggle symbols))"))
    }

    // MARK: - Tap action (goes through same convertAction)

    @Test("Tap action also converted")
    func tapAction() {
        let mapping = KeyMapping(
            input: "a",
            action: .keystroke(key: "a"),
            behavior: .dualRole(DualRoleBehavior(
                tapAction: KanataBehaviorRenderer.parseActionString("escape"),
                holdAction: .keystroke(key: "lctl")
            ))
        )
        let result = KanataBehaviorRenderer.render(mapping)
        #expect(result == "(tap-hold $tap-timeout $hold-timeout esc lctl)")
    }

    @Test("Tap and hold both use hyper")
    func tapAndHoldHyper() {
        let mapping = KeyMapping(
            input: "caps",
            action: .keystroke(key: "caps"),
            behavior: .dualRole(DualRoleBehavior(
                tapAction: .keystroke(key: "esc"),
                holdAction: .hyper
            ))
        )
        let result = KanataBehaviorRenderer.render(mapping)
        #expect(result == "(tap-hold $tap-timeout $hold-timeout esc (multi lctl lmet lalt lsft))")
    }

    // MARK: - Tap-dance (convertAction applied to each step)

    @Test("Tap-dance steps go through convertAction")
    func tapDanceSteps() {
        let mapping = KeyMapping(
            input: "a",
            action: .keystroke(key: "a"),
            behavior: .tapOrTapDance(.tapDance(TapDanceBehavior(
                windowMs: 200,
                steps: [
                    TapDanceStep(label: "Single", action: .keystroke(key: "a")),
                    TapDanceStep(label: "Double", action: KanataBehaviorRenderer.parseActionString("escape")),
                    TapDanceStep(label: "Triple", action: .hyper),
                ]
            )))
        )
        let result = KanataBehaviorRenderer.render(mapping)
        #expect(result == "(tap-dance 200 (a esc (multi lctl lmet lalt lsft)))")
    }

    // MARK: - Chord output (convertAction applied)

    @Test("Chord output goes through convertAction")
    func chordOutput() {
        let chord = ChordBehavior(keys: ["j", "k"], output: KanataBehaviorRenderer.parseActionString("escape"), timeout: 200)
        let result = KanataBehaviorRenderer.renderChordDefinition(chord)
        #expect(result.contains(" esc"))
    }

    @Test("Chord output with hyper keyword")
    func chordHyperOutput() {
        let chord = ChordBehavior(keys: ["j", "k"], output: .hyper, timeout: 200)
        let result = KanataBehaviorRenderer.renderChordDefinition(chord)
        #expect(result.contains("(multi lctl lmet lalt lsft)"))
    }

    // MARK: - Edge cases

    @Test("Whitespace-only action treated as empty after trim")
    func whitespaceAction() {
        let result = renderHold("  a  ")
        #expect(result.contains(" a)"))
    }

    @Test("Modified key prefix preserved")
    func modifiedKey() {
        let result = renderHold("M-c")
        #expect(result.contains(" M-c)"))
    }

    // MARK: - Helpers

    private func renderHold(
        _ holdAction: String,
        hyperLinkedLayerInfos: [HyperLinkedLayerInfo] = []
    ) -> String {
        let mapping = KeyMapping(
            input: "x",
            action: .keystroke(key: "x"),
            behavior: .dualRole(DualRoleBehavior(
                tapAction: .keystroke(key: "x"),
                holdAction: KanataBehaviorRenderer.parseActionString(holdAction)
            ))
        )
        return KanataBehaviorRenderer.render(mapping, hyperLinkedLayerInfos: hyperLinkedLayerInfos)
    }
}
