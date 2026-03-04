import Foundation
@testable import KeyPathAppKit
import Testing

@Suite("KanataBehaviorRenderer")
struct KanataBehaviorRendererTests {
    // MARK: - Simple Output (no behavior)

    @Test("Simple mapping renders output directly")
    func simpleMapping() {
        let mapping = KeyMapping(input: "caps", output: "esc")
        let result = KanataBehaviorRenderer.render(mapping)
        #expect(result == "esc")
    }

    @Test("Simple mapping with modifier prefix")
    func simpleMappingWithModifier() {
        let mapping = KeyMapping(input: "a", output: "M-c")
        let result = KanataBehaviorRenderer.render(mapping)
        #expect(result == "M-c")
    }

    // MARK: - Dual Role (tap-hold)

    @Test("Basic tap-hold renders correctly")
    func basicTapHold() {
        let mapping = KeyMapping(
            input: "a",
            output: "a",
            behavior: .dualRole(DualRoleBehavior(
                tapAction: "a",
                holdAction: "lctl"
            ))
        )
        let result = KanataBehaviorRenderer.render(mapping)
        #expect(result == "(tap-hold $tap-timeout $hold-timeout a lctl)")
    }

    @Test("tap-hold with custom timeouts")
    func tapHoldCustomTimeouts() {
        let mapping = KeyMapping(
            input: "s",
            output: "s",
            behavior: .dualRole(DualRoleBehavior(
                tapAction: "s",
                holdAction: "lalt",
                tapTimeout: 180,
                holdTimeout: 250
            ))
        )
        let result = KanataBehaviorRenderer.render(mapping)
        #expect(result == "(tap-hold 180 250 s lalt)")
    }

    @Test("tap-hold-press variant when activateHoldOnOtherKey is true")
    func tapHoldPress() {
        let mapping = KeyMapping(
            input: "f",
            output: "f",
            behavior: .dualRole(DualRoleBehavior(
                tapAction: "f",
                holdAction: "lmet",
                activateHoldOnOtherKey: true
            ))
        )
        let result = KanataBehaviorRenderer.render(mapping)
        #expect(result == "(tap-hold-press $tap-timeout $hold-timeout f lmet)")
    }

    @Test("tap-hold-release variant when quickTap is true")
    func tapHoldRelease() {
        let mapping = KeyMapping(
            input: "j",
            output: "j",
            behavior: .dualRole(DualRoleBehavior(
                tapAction: "j",
                holdAction: "rsft",
                quickTap: true
            ))
        )
        let result = KanataBehaviorRenderer.render(mapping)
        #expect(result == "(tap-hold-release $tap-timeout $hold-timeout j rsft)")
    }

    @Test("Home row mod factory produces tap-hold-press")
    func homeRowModFactory() {
        let mapping = KeyMapping(
            input: "d",
            output: "d",
            behavior: .dualRole(DualRoleBehavior.homeRowMod(letter: "d", modifier: "lsft"))
        )
        let result = KanataBehaviorRenderer.render(mapping)
        // homeRowMod sets activateHoldOnOtherKey=true, so tap-hold-press
        #expect(result == "(tap-hold-press $tap-timeout $hold-timeout d lsft)")
    }

    @Test("Both flags set: activateHoldOnOtherKey takes precedence")
    func bothFlagsSet() {
        let mapping = KeyMapping(
            input: "a",
            output: "a",
            behavior: .dualRole(DualRoleBehavior(
                tapAction: "a",
                holdAction: "lctl",
                activateHoldOnOtherKey: true,
                quickTap: true
            ))
        )
        let result = KanataBehaviorRenderer.render(mapping)
        // activateHoldOnOtherKey takes precedence over quickTap
        #expect(result == "(tap-hold-press $tap-timeout $hold-timeout a lctl)")
    }

    @Test("Custom tap keys renders tap-hold-release-keys")
    func customTapKeys() {
        let mapping = KeyMapping(
            input: "a",
            output: "a",
            behavior: .dualRole(DualRoleBehavior(
                tapAction: "a",
                holdAction: "lctl",
                customTapKeys: ["s", "d", "f"]
            ))
        )
        let result = KanataBehaviorRenderer.render(mapping)
        #expect(result == "(tap-hold-release-keys $tap-timeout $hold-timeout a lctl (s d f))")
    }

    @Test("Custom tap keys with flags: customTapKeys takes precedence")
    func customTapKeysWithFlags() {
        let mapping = KeyMapping(
            input: "a",
            output: "a",
            behavior: .dualRole(DualRoleBehavior(
                tapAction: "a",
                holdAction: "lctl",
                activateHoldOnOtherKey: true,
                customTapKeys: ["s", "d", "f"]
            ))
        )
        let result = KanataBehaviorRenderer.render(mapping)
        // customTapKeys takes precedence over activateHoldOnOtherKey
        #expect(result == "(tap-hold-release-keys $tap-timeout $hold-timeout a lctl (s d f))")
    }

    // MARK: - Opposite-Hand Activation

    @Test("HRM with opposite-hand ON produces tap-hold-opposite-hand for 'a'")
    func oppositeHandLeftKey() {
        let config = HomeRowModsConfig(
            enabledKeys: ["a"],
            modifierAssignments: ["a": "lsft"],
            holdMode: .modifiers,
            oppositeHandActivation: true
        )
        let mappings = KanataConfiguration.generateHomeRowModsMappings(from: config)
        let rendered = KanataBehaviorRenderer.render(mappings[0])
        // tap-hold-opposite-hand uses single timeout (holdDelay=150)
        // require-prior-idle is a defcfg option, not per-action
        #expect(rendered == "(tap-hold-opposite-hand 150 a lsft)")
    }

    @Test("HRM with opposite-hand ON produces tap-hold-opposite-hand for 'j'")
    func oppositeHandRightKey() {
        let config = HomeRowModsConfig(
            enabledKeys: ["j"],
            modifierAssignments: ["j": "rmet"],
            holdMode: .modifiers,
            oppositeHandActivation: true
        )
        let mappings = KanataConfiguration.generateHomeRowModsMappings(from: config)
        let rendered = KanataBehaviorRenderer.render(mappings[0])
        #expect(rendered == "(tap-hold-opposite-hand 150 j rmet)")
    }

    @Test("HRM with opposite-hand OFF produces tap-hold-press")
    func oppositeHandOff() {
        let config = HomeRowModsConfig(
            enabledKeys: ["a"],
            modifierAssignments: ["a": "lsft"],
            holdMode: .modifiers,
            oppositeHandActivation: false
        )
        let mappings = KanataConfiguration.generateHomeRowModsMappings(from: config)
        let rendered = KanataBehaviorRenderer.render(mappings[0])
        #expect(rendered == "(tap-hold-press $tap-timeout 150 a lsft)")
    }

    @Test("Non-HRM dual-role (caps lock) with activateHoldOnOtherKey still produces tap-hold-press")
    func nonHrmDualRoleStillTapHoldPress() {
        let mapping = KeyMapping(
            input: "caps",
            output: "caps",
            behavior: .dualRole(DualRoleBehavior(
                tapAction: "esc",
                holdAction: "lctl",
                activateHoldOnOtherKey: true,
                customTapKeys: []
            ))
        )
        let result = KanataBehaviorRenderer.render(mapping)
        #expect(result == "(tap-hold-press $tap-timeout $hold-timeout esc lctl)")
    }

    // MARK: - Tap Dance

    @Test("Two-step tap-dance renders correctly")
    func twoStepTapDance() {
        let mapping = KeyMapping(
            input: "caps",
            output: "esc",
            behavior: .tapOrTapDance(.tapDance(TapDanceBehavior.twoStep(
                singleTap: "esc",
                doubleTap: "caps"
            )))
        )
        let result = KanataBehaviorRenderer.render(mapping)
        #expect(result == "(tap-dance 200 (esc caps))")
    }

    @Test("Tap-dance with custom window")
    func tapDanceCustomWindow() {
        let mapping = KeyMapping(
            input: "spc",
            output: "spc",
            behavior: .tapOrTapDance(.tapDance(TapDanceBehavior(
                windowMs: 150,
                steps: [
                    TapDanceStep(label: "Single", action: "spc"),
                    TapDanceStep(label: "Double", action: "ret"),
                    TapDanceStep(label: "Triple", action: "tab")
                ]
            )))
        )
        let result = KanataBehaviorRenderer.render(mapping)
        #expect(result == "(tap-dance 150 (spc ret tab))")
    }

    @Test("Empty tap-dance returns passthrough")
    func emptyTapDance() {
        let mapping = KeyMapping(
            input: "x",
            output: "x",
            behavior: .tapOrTapDance(.tapDance(TapDanceBehavior(windowMs: 200, steps: [])))
        )
        let result = KanataBehaviorRenderer.render(mapping)
        #expect(result == "_")
    }

    // MARK: - Macro

    @Test("Macro text renders correctly")
    func macroTextRendering() {
        let mapping = KeyMapping(
            input: "m",
            output: "m",
            behavior: .macro(MacroBehavior(text: "hi!"))
        )
        let result = KanataBehaviorRenderer.render(mapping)
        #expect(result == "(macro h i S-1)")
    }

    @Test("Macro key sequence renders correctly")
    func macroKeySequenceRendering() {
        let mapping = KeyMapping(
            input: "m",
            output: "m",
            behavior: .macro(MacroBehavior(outputs: ["M-right", "a"], source: .keys))
        )
        let result = KanataBehaviorRenderer.render(mapping)
        #expect(result == "(macro M-right a)")
    }

    @Test("Macro text with unsupported characters renders passthrough")
    func macroTextUnsupportedCharacters() {
        let mapping = KeyMapping(
            input: "m",
            output: "m",
            behavior: .macro(MacroBehavior(text: "hi\u{00E9}"))
        )
        let result = KanataBehaviorRenderer.render(mapping)
        #expect(result == "_")
    }

    // MARK: - Key Conversion Integration

    @Test("Tap-hold with special key names")
    func tapHoldSpecialKeys() {
        let mapping = KeyMapping(
            input: "caps",
            output: "caps",
            behavior: .dualRole(DualRoleBehavior(
                tapAction: "escape",
                holdAction: "command"
            ))
        )
        let result = KanataBehaviorRenderer.render(mapping)
        // "escape" -> "esc", "command" -> "lmet"
        #expect(result == "(tap-hold $tap-timeout $hold-timeout esc lmet)")
    }

    // MARK: - Integration: CustomRule → KeyMapping → Kanata

    @Test("CustomRule with dualRole behavior renders correctly")
    func customRuleIntegration() {
        let rule = CustomRule(
            title: "Home Row A",
            input: "a",
            output: "a",
            behavior: .dualRole(DualRoleBehavior.homeRowMod(letter: "a", modifier: "lctl"))
        )

        let mapping = rule.asKeyMapping()
        let result = KanataBehaviorRenderer.render(mapping)

        #expect(result == "(tap-hold-press $tap-timeout $hold-timeout a lctl)")
    }

    @Test("CustomRule with tapDance behavior renders correctly")
    func customRuleTapDanceIntegration() {
        let rule = CustomRule(
            title: "Caps Escape/CapsLock",
            input: "caps",
            output: "esc",
            behavior: .tapOrTapDance(.tapDance(TapDanceBehavior.twoStep(singleTap: "esc", doubleTap: "caps")))
        )

        let mapping = rule.asKeyMapping()
        let result = KanataBehaviorRenderer.render(mapping)

        #expect(result == "(tap-dance 200 (esc caps))")
    }

    @Test("CustomRule without behavior renders simple output")
    func customRuleSimpleIntegration() {
        let rule = CustomRule(
            input: "caps",
            output: "esc"
        )

        let mapping = rule.asKeyMapping()
        let result = KanataBehaviorRenderer.render(mapping)

        #expect(result == "esc")
    }

    // MARK: - Hyper and Meh Keywords

    @Test("Hyper keyword expands to multi modifier")
    func hyperKeyword() {
        let mapping = KeyMapping(
            input: "caps",
            output: "caps",
            behavior: .dualRole(DualRoleBehavior(
                tapAction: "esc",
                holdAction: "hyper"
            ))
        )
        let result = KanataBehaviorRenderer.render(mapping)
        #expect(result == "(tap-hold $tap-timeout $hold-timeout esc (multi lctl lmet lalt lsft))")
    }

    @Test("Meh keyword expands to multi modifier without Cmd")
    func mehKeyword() {
        let mapping = KeyMapping(
            input: "caps",
            output: "caps",
            behavior: .dualRole(DualRoleBehavior(
                tapAction: "esc",
                holdAction: "meh"
            ))
        )
        let result = KanataBehaviorRenderer.render(mapping)
        #expect(result == "(tap-hold $tap-timeout $hold-timeout esc (multi lctl lalt lsft))")
    }

    @Test("Hyper keyword is case insensitive")
    func hyperCaseInsensitive() {
        let mapping = KeyMapping(
            input: "caps",
            output: "caps",
            behavior: .dualRole(DualRoleBehavior(
                tapAction: "esc",
                holdAction: "HYPER"
            ))
        )
        let result = KanataBehaviorRenderer.render(mapping)
        #expect(result == "(tap-hold $tap-timeout $hold-timeout esc (multi lctl lmet lalt lsft))")
    }

    // MARK: - Multi-key Actions

    @Test("Space-separated keys wrap in multi")
    func multiKeyAction() {
        let mapping = KeyMapping(
            input: "a",
            output: "a",
            behavior: .dualRole(DualRoleBehavior(
                tapAction: "a",
                holdAction: "lctl lmet"
            ))
        )
        let result = KanataBehaviorRenderer.render(mapping)
        #expect(result == "(tap-hold $tap-timeout $hold-timeout a (multi lctl lmet))")
    }

    @Test("Multi-key tap action in tap-dance")
    func multiKeyTapDance() {
        let mapping = KeyMapping(
            input: "x",
            output: "x",
            behavior: .tapOrTapDance(.tapDance(TapDanceBehavior(
                windowMs: 200,
                steps: [
                    TapDanceStep(label: "Single", action: "a"),
                    TapDanceStep(label: "Double", action: "lctl a")
                ]
            )))
        )
        let result = KanataBehaviorRenderer.render(mapping)
        #expect(result == "(tap-dance 200 (a (multi lctl a)))")
    }

    @Test("Hyper in tap-dance step")
    func hyperInTapDance() {
        let mapping = KeyMapping(
            input: "caps",
            output: "caps",
            behavior: .tapOrTapDance(.tapDance(TapDanceBehavior(
                windowMs: 200,
                steps: [
                    TapDanceStep(label: "Single", action: "esc"),
                    TapDanceStep(label: "Double", action: "hyper")
                ]
            )))
        )
        let result = KanataBehaviorRenderer.render(mapping)
        #expect(result == "(tap-dance 200 (esc (multi lctl lmet lalt lsft)))")
    }

    // MARK: - S-Expression Passthrough (Layer Actions)

    @Test("S-expression holdAction passes through unchanged (layer-while-held)")
    func sExpressionLayerWhileHeld() {
        let mapping = KeyMapping(
            input: "a",
            output: "a",
            behavior: .dualRole(DualRoleBehavior(
                tapAction: "a",
                holdAction: "(layer-while-held nav)",
                activateHoldOnOtherKey: true
            ))
        )
        let result = KanataBehaviorRenderer.render(mapping)
        #expect(result == "(tap-hold-press $tap-timeout $hold-timeout a (layer-while-held nav))")
    }

    @Test("S-expression holdAction passes through unchanged (layer-toggle)")
    func sExpressionLayerToggle() {
        let mapping = KeyMapping(
            input: "a",
            output: "a",
            behavior: .dualRole(DualRoleBehavior(
                tapAction: "a",
                holdAction: "(layer-toggle nav)",
                activateHoldOnOtherKey: true
            ))
        )
        let result = KanataBehaviorRenderer.render(mapping)
        #expect(result == "(tap-hold-press $tap-timeout $hold-timeout a (layer-toggle nav))")
    }

    @Test("S-expression holdAction is not mangled into (multi lpar rpar)")
    func sExpressionNotMangled() {
        let mapping = KeyMapping(
            input: "s",
            output: "s",
            behavior: .dualRole(DualRoleBehavior(
                tapAction: "s",
                holdAction: "(layer-while-held sym)",
                activateHoldOnOtherKey: true
            ))
        )
        let result = KanataBehaviorRenderer.render(mapping)
        #expect(!result.contains("lpar"), "S-expression should not be converted to lpar")
        #expect(!result.contains("rpar"), "S-expression should not be converted to rpar")
        #expect(result.contains("(layer-while-held sym)"), "Layer action should be preserved intact")
    }

    @Test("S-expression tapAction passes through unchanged")
    func sExpressionTapAction() {
        let mapping = KeyMapping(
            input: "a",
            output: "a",
            behavior: .dualRole(DualRoleBehavior(
                tapAction: "(one-shot-press 5000 (layer-while-held nav))",
                holdAction: "lctl"
            ))
        )
        let result = KanataBehaviorRenderer.render(mapping)
        #expect(result.contains("(one-shot-press 5000 (layer-while-held nav))"))
    }

    // MARK: - Simple Output S-Expression Passthrough

    @Test("Simple mapping with S-expression output passes through")
    func simpleOutputSExpression() {
        let mapping = KeyMapping(input: "s", output: "(multi XX (push-msg \"layer:base\"))")
        let result = KanataBehaviorRenderer.render(mapping)
        #expect(result == "(multi XX (push-msg \"layer:base\"))")
    }

    // MARK: - Home Row Mods Layers Mode End-to-End

    @Test("Home row mods layers mode generates valid tap-hold with layer action")
    func homeRowModsLayersMode() {
        let config = HomeRowModsConfig(
            enabledKeys: ["a", "s"],
            modifierAssignments: ["a": "lmet", "s": "lalt"],
            layerAssignments: ["a": "nav", "s": "sym"],
            holdMode: .layers,
            layerToggleMode: .whileHeld,
            oppositeHandActivation: false
        )

        let mappings = KanataConfiguration.generateHomeRowModsMappings(from: config)
        #expect(mappings.count == 2)

        let allRendered = mappings.map { KanataBehaviorRenderer.render($0) }

        // Every rendered mapping should use tap-hold-press with layer-while-held
        for rendered in allRendered {
            #expect(rendered.contains("tap-hold-press"), "Should use tap-hold-press for home row mods")
            #expect(rendered.contains("layer-while-held"), "Should use layer-while-held action")
            #expect(!rendered.contains("lpar"), "Should not mangle S-expressions")
            #expect(!rendered.contains("rpar"), "Should not mangle S-expressions")
        }

        // Both layer assignments should appear (order may vary)
        let joined = allRendered.joined(separator: " ")
        #expect(joined.contains("(layer-while-held nav)"))
        #expect(joined.contains("(layer-while-held sym)"))
    }

    @Test("Home row mods layers mode with toggle generates layer-toggle")
    func homeRowModsLayersModeToggle() {
        let config = HomeRowModsConfig(
            enabledKeys: ["a"],
            modifierAssignments: ["a": "lmet"],
            layerAssignments: ["a": "nav"],
            holdMode: .layers,
            layerToggleMode: .toggle,
            oppositeHandActivation: false
        )

        let mappings = KanataConfiguration.generateHomeRowModsMappings(from: config)
        let rendered = KanataBehaviorRenderer.render(mappings[0])
        #expect(rendered.contains("(layer-toggle nav)"))
    }
}
