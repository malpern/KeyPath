import Foundation
@testable import KeyPathAppKit
import KeyPathRulesCore
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

    // MARK: - Structured Action Round-Trip

    @Test("parseActionString reconstructs launchApp from kanata output")
    func roundTripLaunchApp() {
        let original = KeyAction.launchApp(name: "com.apple.Safari", bundleId: "com.apple.Safari")
        let parsed = KanataBehaviorRenderer.parseActionString(original.kanataOutput)
        #expect(parsed.kanataOutput == original.kanataOutput)
        if case .launchApp = parsed {} else {
            Issue.record("Expected .launchApp, got \(parsed)")
        }
    }

    @Test("parseActionString reconstructs openURL from kanata output")
    func roundTripOpenURL() {
        let original = KeyAction.openURL("https://example.com/path?q=1")
        let parsed = KanataBehaviorRenderer.parseActionString(original.kanataOutput)
        #expect(parsed.kanataOutput == original.kanataOutput)
        if case .openURL = parsed {} else {
            Issue.record("Expected .openURL, got \(parsed)")
        }
    }

    @Test("parseActionString reconstructs windowAction from kanata output")
    func roundTripWindowAction() {
        let original = KeyAction.windowAction(position: "left-half")
        let parsed = KanataBehaviorRenderer.parseActionString(original.kanataOutput)
        #expect(parsed.kanataOutput == original.kanataOutput)
        if case .windowAction = parsed {} else {
            Issue.record("Expected .windowAction, got \(parsed)")
        }
    }

    @Test("parseActionString reconstructs systemAction from kanata output")
    func roundTripSystemAction() {
        let original = KeyAction.systemAction(id: "mission-control")
        let parsed = KanataBehaviorRenderer.parseActionString(original.kanataOutput)
        #expect(parsed.kanataOutput == original.kanataOutput)
        if case .systemAction = parsed {} else {
            Issue.record("Expected .systemAction, got \(parsed)")
        }
    }

    @Test("parseActionString reconstructs notify from kanata output")
    func roundTripNotify() {
        let original = KeyAction.notify(title: "Hello", body: "World", sound: true)
        let parsed = KanataBehaviorRenderer.parseActionString(original.kanataOutput)
        #expect(parsed.kanataOutput == original.kanataOutput)
        if case .notify = parsed {} else {
            Issue.record("Expected .notify, got \(parsed)")
        }
    }

    @Test("parseActionString reconstructs fakeKey from kanata output")
    func roundTripFakeKey() {
        let original = KeyAction.fakeKey(name: "kp-layer-vim-enter", action: .tap)
        let parsed = KanataBehaviorRenderer.parseActionString(original.kanataOutput)
        #expect(parsed.kanataOutput == original.kanataOutput)
        if case .fakeKey = parsed {} else {
            Issue.record("Expected .fakeKey, got \(parsed)")
        }
    }

    @Test("parseActionString reconstructs activateLayer from kanata output")
    func roundTripActivateLayer() {
        let original = KeyAction.activateLayer(name: "vim")
        let parsed = KanataBehaviorRenderer.parseActionString(original.kanataOutput)
        #expect(parsed.kanataOutput == original.kanataOutput)
        if case .activateLayer = parsed {} else {
            Issue.record("Expected .activateLayer, got \(parsed)")
        }
    }

    @Test("parseActionString reconstructs hyper from S-expression")
    func roundTripHyperSexpr() {
        let parsed = KanataBehaviorRenderer.parseActionString("(multi lctl lmet lalt lsft)")
        if case .hyper = parsed {} else {
            Issue.record("Expected .hyper, got \(parsed)")
        }
    }

    @Test("parseActionString reconstructs meh from S-expression")
    func roundTripMehSexpr() {
        let parsed = KanataBehaviorRenderer.parseActionString("(multi lctl lalt lsft)")
        if case .meh = parsed {} else {
            Issue.record("Expected .meh, got \(parsed)")
        }
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
