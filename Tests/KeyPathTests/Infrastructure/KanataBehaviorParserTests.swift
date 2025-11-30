import Foundation
@testable import KeyPathAppKit
import Testing

@Suite("KanataBehaviorParser")
struct KanataBehaviorParserTests {
    // MARK: - Simple Keys (no behavior)

    @Test("Simple key returns nil")
    func simpleKey() {
        let result = KanataBehaviorParser.parse("esc")
        #expect(result == nil)
    }

    @Test("Simple key with modifier returns nil")
    func simpleKeyWithModifier() {
        let result = KanataBehaviorParser.parse("M-c")
        #expect(result == nil)
    }

    // MARK: - Tap-Hold Parsing

    @Test("Basic tap-hold parses correctly")
    func basicTapHold() {
        let result = KanataBehaviorParser.parse("(tap-hold 200 200 a lctl)")

        guard case let .dualRole(dr) = result else {
            Issue.record("Expected dualRole")
            return
        }

        #expect(dr.tapAction == "a")
        #expect(dr.holdAction == "lctl")
        #expect(dr.tapTimeout == 200)
        #expect(dr.holdTimeout == 200)
        #expect(dr.activateHoldOnOtherKey == false)
        #expect(dr.quickTap == false)
    }

    @Test("tap-hold with custom timeouts")
    func tapHoldCustomTimeouts() {
        let result = KanataBehaviorParser.parse("(tap-hold 180 250 s lalt)")

        guard case let .dualRole(dr) = result else {
            Issue.record("Expected dualRole")
            return
        }

        #expect(dr.tapTimeout == 180)
        #expect(dr.holdTimeout == 250)
    }

    @Test("tap-hold-press sets activateHoldOnOtherKey flag")
    func tapHoldPress() {
        let result = KanataBehaviorParser.parse("(tap-hold-press 200 200 f lmet)")

        guard case let .dualRole(dr) = result else {
            Issue.record("Expected dualRole")
            return
        }

        #expect(dr.tapAction == "f")
        #expect(dr.holdAction == "lmet")
        #expect(dr.activateHoldOnOtherKey == true)
        #expect(dr.quickTap == false)
    }

    @Test("tap-hold-release sets quickTap flag")
    func tapHoldRelease() {
        let result = KanataBehaviorParser.parse("(tap-hold-release 200 200 j rsft)")

        guard case let .dualRole(dr) = result else {
            Issue.record("Expected dualRole")
            return
        }

        #expect(dr.tapAction == "j")
        #expect(dr.holdAction == "rsft")
        #expect(dr.activateHoldOnOtherKey == false)
        #expect(dr.quickTap == true)
    }

    @Test("tap-hold-release-keys parses custom tap keys")
    func tapHoldReleaseKeys() {
        let result = KanataBehaviorParser.parse("(tap-hold-release-keys 200 200 a lctl (s d f))")

        guard case let .dualRole(dr) = result else {
            Issue.record("Expected dualRole")
            return
        }

        #expect(dr.tapAction == "a")
        #expect(dr.holdAction == "lctl")
        #expect(dr.activateHoldOnOtherKey == false)
        #expect(dr.quickTap == false)
        #expect(dr.customTapKeys == ["s", "d", "f"])
    }

    @Test("Custom tap keys round-trips through render and parse")
    func customTapKeysRoundTrip() {
        let original = DualRoleBehavior(
            tapAction: "a",
            holdAction: "lctl",
            customTapKeys: ["s", "d", "f"]
        )
        let mapping = KeyMapping(input: "a", output: "a", behavior: .dualRole(original))
        let rendered = KanataBehaviorRenderer.render(mapping)
        let parsed = KanataBehaviorParser.parse(rendered)

        guard case let .dualRole(dr) = parsed else {
            Issue.record("Expected dualRole after round-trip")
            return
        }

        #expect(dr.tapAction == original.tapAction)
        #expect(dr.holdAction == original.holdAction)
        #expect(dr.customTapKeys == original.customTapKeys)
    }

    // MARK: - Tap-Dance Parsing

    @Test("Two-step tap-dance parses correctly")
    func twoStepTapDance() {
        let result = KanataBehaviorParser.parse("(tap-dance 200 (esc caps))")

        guard case let .tapDance(td) = result else {
            Issue.record("Expected tapDance")
            return
        }

        #expect(td.windowMs == 200)
        #expect(td.steps.count == 2)
        #expect(td.steps[0].action == "esc")
        #expect(td.steps[0].label == "Single Tap")
        #expect(td.steps[1].action == "caps")
        #expect(td.steps[1].label == "Double Tap")
    }

    @Test("Tap-dance with custom window")
    func tapDanceCustomWindow() {
        let result = KanataBehaviorParser.parse("(tap-dance 150 (spc ret tab))")

        guard case let .tapDance(td) = result else {
            Issue.record("Expected tapDance")
            return
        }

        #expect(td.windowMs == 150)
        #expect(td.steps.count == 3)
        #expect(td.steps[2].action == "tab")
        #expect(td.steps[2].label == "Triple Tap")
    }

    // MARK: - Round-Trip Tests

    @Test("Dual-role round-trips through render and parse")
    func dualRoleRoundTrip() {
        let original = DualRoleBehavior(
            tapAction: "a",
            holdAction: "lctl",
            tapTimeout: 180,
            holdTimeout: 220
        )
        let mapping = KeyMapping(input: "a", output: "a", behavior: .dualRole(original))
        let rendered = KanataBehaviorRenderer.render(mapping)
        let parsed = KanataBehaviorParser.parse(rendered)

        guard case let .dualRole(dr) = parsed else {
            Issue.record("Expected dualRole after round-trip")
            return
        }

        #expect(dr.tapAction == original.tapAction)
        #expect(dr.holdAction == original.holdAction)
        #expect(dr.tapTimeout == original.tapTimeout)
        #expect(dr.holdTimeout == original.holdTimeout)
    }

    @Test("Tap-dance round-trips through render and parse")
    func tapDanceRoundTrip() {
        let original = TapDanceBehavior.twoStep(singleTap: "esc", doubleTap: "caps", windowMs: 180)
        let mapping = KeyMapping(input: "caps", output: "esc", behavior: .tapDance(original))
        let rendered = KanataBehaviorRenderer.render(mapping)
        let parsed = KanataBehaviorParser.parse(rendered)

        guard case let .tapDance(td) = parsed else {
            Issue.record("Expected tapDance after round-trip")
            return
        }

        #expect(td.windowMs == original.windowMs)
        #expect(td.steps.count == original.steps.count)
        #expect(td.steps[0].action == original.steps[0].action)
        #expect(td.steps[1].action == original.steps[1].action)
    }

    // MARK: - Edge Cases

    @Test("Malformed input returns nil")
    func malformedInput() {
        #expect(KanataBehaviorParser.parse("(tap-hold)") == nil)
        #expect(KanataBehaviorParser.parse("(tap-hold 200)") == nil)
        #expect(KanataBehaviorParser.parse("(tap-dance)") == nil)
        #expect(KanataBehaviorParser.parse("(unknown 1 2 3)") == nil)
        #expect(KanataBehaviorParser.parse("") == nil)
    }

    // MARK: - Multi-Key Actions

    @Test("tap-hold with multi hold action parses correctly")
    func tapHoldWithMultiHold() {
        let result = KanataBehaviorParser.parse("(tap-hold 200 200 esc (multi lctl lmet lalt lsft))")

        guard case let .dualRole(dr) = result else {
            Issue.record("Expected dualRole")
            return
        }

        #expect(dr.tapAction == "esc")
        #expect(dr.holdAction == "(multi lctl lmet lalt lsft)")
        #expect(dr.tapTimeout == 200)
        #expect(dr.holdTimeout == 200)
    }

    @Test("tap-dance with multi action parses correctly")
    func tapDanceWithMulti() {
        let result = KanataBehaviorParser.parse("(tap-dance 200 (esc (multi lctl lmet lalt lsft)))")

        guard case let .tapDance(td) = result else {
            Issue.record("Expected tapDance")
            return
        }

        #expect(td.windowMs == 200)
        #expect(td.steps.count == 2)
        #expect(td.steps[0].action == "esc")
        #expect(td.steps[1].action == "(multi lctl lmet lalt lsft)")
    }

    @Test("Hyper round-trips through render and parse")
    func hyperRoundTrip() {
        // Render hyper
        let original = DualRoleBehavior(
            tapAction: "esc",
            holdAction: "hyper"
        )
        let mapping = KeyMapping(input: "caps", output: "caps", behavior: .dualRole(original))
        let rendered = KanataBehaviorRenderer.render(mapping)

        // Verify it expanded
        #expect(rendered == "(tap-hold 200 200 esc (multi lctl lmet lalt lsft))")

        // Parse it back
        let parsed = KanataBehaviorParser.parse(rendered)

        guard case let .dualRole(dr) = parsed else {
            Issue.record("Expected dualRole after round-trip")
            return
        }

        // Hold action is stored as the expanded form
        #expect(dr.tapAction == "esc")
        #expect(dr.holdAction == "(multi lctl lmet lalt lsft)")
    }
}
