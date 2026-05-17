import Foundation
@testable import KeyPathAppKit
import Testing

/// Golden-file tests that assert exact rendered output for all behavior types.
/// These serve as a regression safety net during the Action model unification.
/// If any test here breaks, the refactor changed observable config output.
@Suite("Behavior rendering golden outputs")
struct BehaviorRenderingGoldenTests {
    // MARK: - Simple mappings (no behavior)

    @Test("Simple keystroke")
    func simpleKeystroke() {
        let mapping = KeyMapping(input: "caps", action: .keystroke(key: "esc"))
        #expect(KanataBehaviorRenderer.render(mapping) == "esc")
    }

    @Test("Simple rawKanata passthrough")
    func simpleRawKanata() {
        let mapping = KeyMapping(input: "f1", action: .rawKanata("(push-msg \"system:mission-control\")"))
        #expect(KanataBehaviorRenderer.render(mapping) == "(push-msg \"system:mission-control\")")
    }

    @Test("Simple launchApp action")
    func simpleLaunchApp() {
        let mapping = KeyMapping(input: "f2", action: .launchApp(name: "Safari", bundleId: "com.apple.Safari"))
        #expect(KanataBehaviorRenderer.render(mapping) == "(push-msg \"launch:com.apple.Safari\")")
    }

    // MARK: - Dual role (all variants)

    @Test("Basic tap-hold with default timeouts")
    func dualRoleBasic() {
        let mapping = KeyMapping(
            input: "a",
            action: .keystroke(key: "a"),
            behavior: .dualRole(DualRoleBehavior(tapAction: .keystroke(key: "a"), holdAction: .keystroke(key: "lctl")))
        )
        #expect(KanataBehaviorRenderer.render(mapping) == "(tap-hold $tap-timeout $hold-timeout a lctl)")
    }

    @Test("Tap-hold with custom timeouts")
    func dualRoleCustomTimeouts() {
        let mapping = KeyMapping(
            input: "a",
            action: .keystroke(key: "a"),
            behavior: .dualRole(DualRoleBehavior(tapAction: .keystroke(key: "a"), holdAction: .keystroke(key: "lsft"), tapTimeout: 150, holdTimeout: 300))
        )
        #expect(KanataBehaviorRenderer.render(mapping) == "(tap-hold 150 300 a lsft)")
    }

    @Test("Tap-hold-press (activateHoldOnOtherKey)")
    func dualRoleTapHoldPress() {
        let mapping = KeyMapping(
            input: "a",
            action: .keystroke(key: "a"),
            behavior: .dualRole(DualRoleBehavior(
                tapAction: .keystroke(key: "a"), holdAction: .keystroke(key: "lctl"),
                activateHoldOnOtherKey: true
            ))
        )
        #expect(KanataBehaviorRenderer.render(mapping) == "(tap-hold-press $tap-timeout $hold-timeout a lctl)")
    }

    @Test("Tap-hold-release (quickTap)")
    func dualRoleTapHoldRelease() {
        let mapping = KeyMapping(
            input: "a",
            action: .keystroke(key: "a"),
            behavior: .dualRole(DualRoleBehavior(
                tapAction: .keystroke(key: "a"), holdAction: .keystroke(key: "lctl"),
                quickTap: true
            ))
        )
        #expect(KanataBehaviorRenderer.render(mapping) == "(tap-hold-release $tap-timeout $hold-timeout a lctl)")
    }

    @Test("Tap-hold-release-keys (customTapKeys)")
    func dualRoleReleaseKeys() {
        let mapping = KeyMapping(
            input: "a",
            action: .keystroke(key: "a"),
            behavior: .dualRole(DualRoleBehavior(
                tapAction: .keystroke(key: "a"), holdAction: .keystroke(key: "lctl"),
                customTapKeys: ["j", "k", "l"]
            ))
        )
        #expect(KanataBehaviorRenderer.render(mapping) == "(tap-hold-release-keys $tap-timeout $hold-timeout a lctl (j k l))")
    }

    @Test("Tap-hold-opposite-hand")
    func dualRoleOppositeHand() {
        let mapping = KeyMapping(
            input: "a",
            action: .keystroke(key: "a"),
            behavior: .dualRole(DualRoleBehavior(
                tapAction: .keystroke(key: "a"), holdAction: .keystroke(key: "lctl"),
                useOppositeHand: true
            ))
        )
        #expect(KanataBehaviorRenderer.render(mapping) == "(tap-hold-opposite-hand $hold-timeout a lctl)")
    }

    @Test("Tap-hold-opposite-hand-release")
    func dualRoleOppositeHandRelease() {
        let mapping = KeyMapping(
            input: "a",
            action: .keystroke(key: "a"),
            behavior: .dualRole(DualRoleBehavior(
                tapAction: .keystroke(key: "a"), holdAction: .keystroke(key: "lctl"),
                useOppositeHandRelease: true
            ))
        )
        #expect(KanataBehaviorRenderer.render(mapping) == "(tap-hold-opposite-hand-release $hold-timeout a lctl)")
    }

    @Test("Tap-hold-release-order")
    func dualRoleReleaseOrder() {
        let mapping = KeyMapping(
            input: "a",
            action: .keystroke(key: "a"),
            behavior: .dualRole(DualRoleBehavior(
                tapAction: .keystroke(key: "a"), holdAction: .keystroke(key: "lctl"),
                useReleaseOrder: true
            ))
        )
        #expect(KanataBehaviorRenderer.render(mapping) == "(tap-hold-release-order $tap-timeout a lctl)")
    }

    @Test("Tap-hold with require-prior-idle override")
    func dualRoleWithPriorIdle() {
        let mapping = KeyMapping(
            input: "a",
            action: .keystroke(key: "a"),
            behavior: .dualRole(DualRoleBehavior(
                tapAction: .keystroke(key: "a"), holdAction: .keystroke(key: "lctl"),
                activateHoldOnOtherKey: true,
                requirePriorIdleOverrideMs: 150
            ))
        )
        #expect(KanataBehaviorRenderer.render(mapping) == "(tap-hold-press $tap-timeout $hold-timeout a lctl (require-prior-idle 150))")
    }

    @Test("Dual-role with hyper hold action")
    func dualRoleHyperHold() {
        let mapping = KeyMapping(
            input: "caps",
            action: .keystroke(key: "caps"),
            behavior: .dualRole(DualRoleBehavior(tapAction: .keystroke(key: "esc"), holdAction: .hyper))
        )
        #expect(KanataBehaviorRenderer.render(mapping) == "(tap-hold $tap-timeout $hold-timeout esc (multi lctl lmet lalt lsft))")
    }

    @Test("Dual-role with meh hold action")
    func dualRoleMehHold() {
        let mapping = KeyMapping(
            input: "caps",
            action: .keystroke(key: "caps"),
            behavior: .dualRole(DualRoleBehavior(tapAction: .keystroke(key: "esc"), holdAction: .meh))
        )
        #expect(KanataBehaviorRenderer.render(mapping) == "(tap-hold $tap-timeout $hold-timeout esc (multi lctl lalt lsft))")
    }

    @Test("Dual-role with multi-key hold action")
    func dualRoleMultiKeyHold() {
        let mapping = KeyMapping(
            input: "z",
            action: .keystroke(key: "z"),
            behavior: .dualRole(DualRoleBehavior(tapAction: .keystroke(key: "z"), holdAction: KanataBehaviorRenderer.parseActionString("lctl lalt")))
        )
        #expect(KanataBehaviorRenderer.render(mapping) == "(tap-hold $tap-timeout $hold-timeout z (multi lctl lalt))")
    }

    @Test("Dual-role with S-expression hold action")
    func dualRoleSExpressionHold() {
        let mapping = KeyMapping(
            input: "spc",
            action: .keystroke(key: "spc"),
            behavior: .dualRole(DualRoleBehavior(tapAction: .keystroke(key: "spc"), holdAction: .rawKanata("(layer-while-held nav)")))
        )
        #expect(KanataBehaviorRenderer.render(mapping) == "(tap-hold $tap-timeout $hold-timeout spc (layer-while-held nav))")
    }

    // MARK: - Tap dance

    @Test("Two-step tap-dance")
    func tapDanceTwoStep() {
        let mapping = KeyMapping(
            input: "a",
            action: .keystroke(key: "a"),
            behavior: .tapOrTapDance(.tapDance(TapDanceBehavior(
                windowMs: 200,
                steps: [
                    TapDanceStep(label: "Single", action: .keystroke(key: "a")),
                    TapDanceStep(label: "Double", action: .keystroke(key: "lctl")),
                ]
            )))
        )
        #expect(KanataBehaviorRenderer.render(mapping) == "(tap-dance 200 (a lctl))")
    }

    @Test("Tap-dance with custom window")
    func tapDanceCustomWindow() {
        let mapping = KeyMapping(
            input: "a",
            action: .keystroke(key: "a"),
            behavior: .tapOrTapDance(.tapDance(TapDanceBehavior(
                windowMs: 300,
                steps: [
                    TapDanceStep(label: "1", action: .keystroke(key: "a")),
                    TapDanceStep(label: "2", action: .keystroke(key: "b")),
                    TapDanceStep(label: "3", action: .keystroke(key: "c")),
                ]
            )))
        )
        #expect(KanataBehaviorRenderer.render(mapping) == "(tap-dance 300 (a b c))")
    }

    @Test("Empty tap-dance returns passthrough")
    func tapDanceEmpty() {
        let mapping = KeyMapping(
            input: "a",
            action: .keystroke(key: "a"),
            behavior: .tapOrTapDance(.tapDance(TapDanceBehavior(windowMs: 200, steps: [])))
        )
        #expect(KanataBehaviorRenderer.render(mapping) == "_")
    }

    @Test("Tap behavior renders simple output")
    func tapBehavior() {
        let mapping = KeyMapping(
            input: "a",
            action: .keystroke(key: "esc"),
            behavior: .tapOrTapDance(.tap)
        )
        #expect(KanataBehaviorRenderer.render(mapping) == "esc")
    }

    // MARK: - Macro

    @Test("Macro with key sequence")
    func macroKeys() {
        let mapping = KeyMapping(
            input: "f1",
            action: .keystroke(key: "f1"),
            behavior: .macro(MacroBehavior(outputs: ["h", "i"], source: .keys))
        )
        #expect(KanataBehaviorRenderer.render(mapping) == "(macro h i)")
    }

    @Test("Macro with text")
    func macroText() {
        let mapping = KeyMapping(
            input: "f1",
            action: .keystroke(key: "f1"),
            behavior: .macro(MacroBehavior(outputs: [], text: "hi", source: .text))
        )
        #expect(KanataBehaviorRenderer.render(mapping) == "(macro h i)")
    }

    @Test("Empty macro returns passthrough")
    func macroEmpty() {
        let mapping = KeyMapping(
            input: "f1",
            action: .keystroke(key: "f1"),
            behavior: .macro(MacroBehavior(outputs: [], source: .keys))
        )
        #expect(KanataBehaviorRenderer.render(mapping) == "_")
    }

    // MARK: - Chord

    @Test("Chord renders alias reference")
    func chordAlias() {
        let mapping = KeyMapping(
            input: "j",
            action: .keystroke(key: "j"),
            behavior: .chord(ChordBehavior(keys: ["j", "k"], output: .keystroke(key: "esc"), timeout: 200))
        )
        let result = KanataBehaviorRenderer.render(mapping)
        #expect(result == "@kp-chord-j-k")
    }

    @Test("Chord definition renders full defchords block")
    func chordDefinition() {
        let chord = ChordBehavior(keys: ["j", "k"], output: .keystroke(key: "esc"), timeout: 200)
        let result = KanataBehaviorRenderer.renderChordDefinition(chord)
        #expect(result == "(defchords kp-chord-j-k 200\n  (j k) esc\n)")
    }

    @Test("Chord definition with multi-key output")
    func chordDefinitionMultiKey() {
        let chord = ChordBehavior(keys: ["a", "s"], output: KanataBehaviorRenderer.parseActionString("lctl lalt"), timeout: 150)
        let result = KanataBehaviorRenderer.renderChordDefinition(chord)
        #expect(result == "(defchords kp-chord-a-s 150\n  (a s) (multi lctl lalt)\n)")
    }

    // MARK: - Combined: hyper in linked layer context

    @Test("Hyper hold with linked nav layer — full output")
    func hyperWithNavLayer() {
        let mapping = KeyMapping(
            input: "caps",
            action: .keystroke(key: "caps"),
            behavior: .dualRole(DualRoleBehavior(tapAction: .keystroke(key: "esc"), holdAction: .hyper))
        )
        let layerInfos = [HyperLinkedLayerInfo(layerName: "nav", triggerMode: .hold)]
        let result = KanataBehaviorRenderer.render(mapping, hyperLinkedLayerInfos: layerInfos)
        #expect(result == "(tap-hold $tap-timeout $hold-timeout esc (multi lctl lmet lalt lsft (layer-while-held nav) (on-press-fakekey kp-layer-nav-enter tap) (on-release-fakekey kp-layer-nav-exit tap)))")
    }
}
