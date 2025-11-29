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
        #expect(result == "(tap-hold 200 200 a lctl)")
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
        #expect(result == "(tap-hold-press 200 200 f lmet)")
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
        #expect(result == "(tap-hold-release 200 200 j rsft)")
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
        #expect(result == "(tap-hold-press 200 200 d lsft)")
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
        #expect(result == "(tap-hold-press 200 200 a lctl)")
    }

    // MARK: - Tap Dance

    @Test("Two-step tap-dance renders correctly")
    func twoStepTapDance() {
        let mapping = KeyMapping(
            input: "caps",
            output: "esc",
            behavior: .tapDance(TapDanceBehavior.twoStep(
                singleTap: "esc",
                doubleTap: "caps"
            ))
        )
        let result = KanataBehaviorRenderer.render(mapping)
        #expect(result == "(tap-dance 200 (esc caps))")
    }

    @Test("Tap-dance with custom window")
    func tapDanceCustomWindow() {
        let mapping = KeyMapping(
            input: "spc",
            output: "spc",
            behavior: .tapDance(TapDanceBehavior(
                windowMs: 150,
                steps: [
                    TapDanceStep(label: "Single", action: "spc"),
                    TapDanceStep(label: "Double", action: "ret"),
                    TapDanceStep(label: "Triple", action: "tab")
                ]
            ))
        )
        let result = KanataBehaviorRenderer.render(mapping)
        #expect(result == "(tap-dance 150 (spc ret tab))")
    }

    @Test("Empty tap-dance returns passthrough")
    func emptyTapDance() {
        let mapping = KeyMapping(
            input: "x",
            output: "x",
            behavior: .tapDance(TapDanceBehavior(windowMs: 200, steps: []))
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
        #expect(result == "(tap-hold 200 200 esc lmet)")
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

        #expect(result == "(tap-hold-press 200 200 a lctl)")
    }

    @Test("CustomRule with tapDance behavior renders correctly")
    func customRuleTapDanceIntegration() {
        let rule = CustomRule(
            title: "Caps Escape/CapsLock",
            input: "caps",
            output: "esc",
            behavior: .tapDance(TapDanceBehavior.twoStep(singleTap: "esc", doubleTap: "caps"))
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
}
