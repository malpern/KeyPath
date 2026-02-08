import Foundation
@testable import KeyPathAppKit
import Testing

@Suite("MappingBehavior")
struct MappingBehaviorTests {
    // MARK: - DualRoleBehavior

    @Test("DualRoleBehavior encodes and decodes")
    func dualRoleRoundTrip() throws {
        let behavior = DualRoleBehavior(
            tapAction: "a",
            holdAction: "lctl",
            tapTimeout: 180,
            holdTimeout: 220,
            activateHoldOnOtherKey: true,
            quickTap: true
        )

        let data = try JSONEncoder().encode(behavior)
        let decoded = try JSONDecoder().decode(DualRoleBehavior.self, from: data)

        #expect(decoded.tapAction == "a")
        #expect(decoded.holdAction == "lctl")
        #expect(decoded.tapTimeout == 180)
        #expect(decoded.holdTimeout == 220)
        #expect(decoded.activateHoldOnOtherKey == true)
        #expect(decoded.quickTap == true)
    }

    @Test("DualRoleBehavior defaults")
    func dualRoleDefaults() {
        let behavior = DualRoleBehavior(tapAction: "j", holdAction: "lsft")

        #expect(behavior.tapTimeout == 200)
        #expect(behavior.holdTimeout == 200)
        #expect(behavior.activateHoldOnOtherKey == false)
        #expect(behavior.quickTap == false)
    }

    @Test("homeRowMod factory")
    func homeRowModFactory() {
        let hrm = DualRoleBehavior.homeRowMod(letter: "f", modifier: "lmet")

        #expect(hrm.tapAction == "f")
        #expect(hrm.holdAction == "lmet")
        #expect(hrm.activateHoldOnOtherKey == true)
        #expect(hrm.quickTap == false) // Only activateHoldOnOtherKey is set for home-row mods
    }

    // MARK: - TapDanceBehavior

    @Test("TapDanceBehavior encodes and decodes")
    func tapDanceRoundTrip() throws {
        let behavior = TapDanceBehavior(
            windowMs: 180,
            steps: [
                TapDanceStep(label: "Single tap", action: "esc"),
                TapDanceStep(label: "Double tap", action: "caps")
            ]
        )

        let data = try JSONEncoder().encode(behavior)
        let decoded = try JSONDecoder().decode(TapDanceBehavior.self, from: data)

        #expect(decoded.windowMs == 180)
        #expect(decoded.steps.count == 2)
        #expect(decoded.steps[0].action == "esc")
        #expect(decoded.steps[1].action == "caps")
    }

    @Test("twoStep factory")
    func twoStepFactory() {
        let td = TapDanceBehavior.twoStep(singleTap: "a", doubleTap: "b", windowMs: 150)

        #expect(td.windowMs == 150)
        #expect(td.steps.count == 2)
        #expect(td.steps[0].action == "a")
        #expect(td.steps[1].action == "b")
    }

    // MARK: - MacroBehavior

    @Test("MacroBehavior text expansion outputs")
    func macroTextOutputs() {
        let macro = MacroBehavior(text: "hi")
        #expect(macro.effectiveOutputs == ["h", "i"])
        #expect(macro.isValid == true)
    }

    @Test("MacroBehavior key sequence outputs")
    func macroKeyOutputs() {
        let macro = MacroBehavior(outputs: ["M-c", "v"], source: .keys)
        #expect(macro.effectiveOutputs == ["M-c", "v"])
        #expect(macro.isValid == true)
    }

    @Test("MacroBehavior invalid when empty")
    func macroInvalidEmpty() {
        let macro = MacroBehavior(outputs: [], text: "")
        #expect(macro.isValid == false)
    }

    @Test("MacroBehavior invalid when text contains unsupported characters")
    func macroInvalidUnsupportedText() {
        let macro = MacroBehavior(text: "hi\u{00E9}")
        #expect(macro.isValid == false)
        #expect(macro.validationErrors.first?.contains("Unsupported character") == true)
    }

    // MARK: - MappingBehavior enum

    @Test("MappingBehavior dualRole case round-trips")
    func mappingBehaviorDualRole() throws {
        let behavior = MappingBehavior.dualRole(
            DualRoleBehavior(tapAction: "s", holdAction: "lalt")
        )

        let data = try JSONEncoder().encode(behavior)
        let decoded = try JSONDecoder().decode(MappingBehavior.self, from: data)

        if case let .dualRole(dr) = decoded {
            #expect(dr.tapAction == "s")
            #expect(dr.holdAction == "lalt")
        } else {
            Issue.record("Expected dualRole case")
        }
    }

    @Test("MappingBehavior tapDance case round-trips")
    func mappingBehaviorTapDance() throws {
        let behavior = MappingBehavior.tapOrTapDance(.tapDance(
            TapDanceBehavior.twoStep(singleTap: "x", doubleTap: "y")
        ))

        let data = try JSONEncoder().encode(behavior)
        let decoded = try JSONDecoder().decode(MappingBehavior.self, from: data)

        if case let .tapOrTapDance(tapBehavior) = decoded,
           case let .tapDance(td) = tapBehavior
        {
            #expect(td.steps.count == 2)
        } else {
            Issue.record("Expected tapDance case")
        }
    }

    @Test("MappingBehavior macro case round-trips")
    func mappingBehaviorMacro() throws {
        let behavior = MappingBehavior.macro(MacroBehavior(text: "hi"))

        let data = try JSONEncoder().encode(behavior)
        let decoded = try JSONDecoder().decode(MappingBehavior.self, from: data)

        if case let .macro(macro) = decoded {
            #expect(macro.text == "hi")
        } else {
            Issue.record("Expected macro case")
        }
    }

    @Test("MappingBehavior decodes legacy tapDance key")
    func mappingBehaviorLegacyTapDanceDecode() throws {
        let legacyJSON = """
        {
            "tapDance": {
                "windowMs": 180,
                "steps": [
                    { "label": "Single tap", "action": "esc" },
                    { "label": "Double tap", "action": "caps" }
                ]
            }
        }
        """

        let data = try #require(legacyJSON.data(using: .utf8))
        let decoded = try JSONDecoder().decode(MappingBehavior.self, from: data)

        if case let .tapOrTapDance(tapBehavior) = decoded,
           case let .tapDance(td) = tapBehavior
        {
            #expect(td.steps.count == 2)
        } else {
            Issue.record("Expected tapDance case from legacy decode")
        }
    }

    // MARK: - KeyMapping integration

    @Test("KeyMapping with nil behavior decodes from legacy JSON")
    func keyMappingLegacyDecode() throws {
        let legacyJSON = """
        {
            "id": "11111111-1111-1111-1111-111111111111",
            "input": "caps",
            "output": "esc"
        }
        """
        let data = try #require(legacyJSON.data(using: .utf8))
        let mapping = try JSONDecoder().decode(KeyMapping.self, from: data)

        #expect(mapping.input == "caps")
        #expect(mapping.output == "esc")
        #expect(mapping.behavior == nil)
    }

    @Test("KeyMapping with dualRole behavior round-trips")
    func keyMappingWithBehavior() throws {
        let mapping = KeyMapping(
            input: "a",
            output: "a",
            behavior: .dualRole(DualRoleBehavior.homeRowMod(letter: "a", modifier: "lctl"))
        )

        let data = try JSONEncoder().encode(mapping)
        let decoded = try JSONDecoder().decode(KeyMapping.self, from: data)

        #expect(decoded.input == "a")
        #expect(decoded.behavior != nil)

        if case let .dualRole(dr) = decoded.behavior {
            #expect(dr.holdAction == "lctl")
        } else {
            Issue.record("Expected dualRole behavior")
        }
    }

    // MARK: - CustomRule integration

    @Test("CustomRule with behavior round-trips")
    func customRuleWithBehavior() throws {
        let rule = CustomRule(
            title: "Home Row A",
            input: "a",
            output: "a",
            behavior: .dualRole(DualRoleBehavior.homeRowMod(letter: "a", modifier: "lctl"))
        )

        let data = try JSONEncoder().encode(rule)
        let decoded = try JSONDecoder().decode(CustomRule.self, from: data)

        #expect(decoded.title == "Home Row A")
        #expect(decoded.behavior != nil)

        if case let .dualRole(dr) = decoded.behavior {
            #expect(dr.tapAction == "a")
            #expect(dr.holdAction == "lctl")
        } else {
            Issue.record("Expected dualRole behavior")
        }
    }

    @Test("CustomRule.asKeyMapping passes behavior through")
    func customRuleAsKeyMapping() {
        let behavior = MappingBehavior.dualRole(
            DualRoleBehavior(tapAction: "s", holdAction: "lalt")
        )
        let rule = CustomRule(
            input: "s",
            output: "s",
            behavior: behavior
        )

        let mapping = rule.asKeyMapping()

        #expect(mapping.input == "s")
        #expect(mapping.behavior == behavior)
    }

    @Test("CustomRule without behavior decodes from legacy JSON")
    func customRuleLegacyDecode() throws {
        let legacyJSON = """
        {
            "id": "22222222-2222-2222-2222-222222222222",
            "title": "Test",
            "input": "caps",
            "output": "esc",
            "isEnabled": true,
            "createdAt": 0
        }
        """
        let data = try #require(legacyJSON.data(using: .utf8))
        let rule = try JSONDecoder().decode(CustomRule.self, from: data)

        #expect(rule.input == "caps")
        #expect(rule.output == "esc")
        #expect(rule.behavior == nil)
    }

    // MARK: - Validation

    @Test("DualRoleBehavior.isValid returns true for valid config")
    func dualRoleValidation() {
        let valid = DualRoleBehavior(tapAction: "a", holdAction: "lctl")
        #expect(valid.isValid == true)
    }

    @Test("DualRoleBehavior.isValid returns false when tapAction mutated to empty")
    func dualRoleInvalidTapAction() {
        var behavior = DualRoleBehavior(tapAction: "a", holdAction: "lctl")
        behavior.tapAction = ""
        #expect(behavior.isValid == false)
    }

    @Test("TapDanceBehavior.isValid returns true for valid config")
    func tapDanceValidation() {
        let valid = TapDanceBehavior.twoStep(singleTap: "a", doubleTap: "b")
        #expect(valid.isValid == true)
    }

    @Test("TapDanceBehavior.isValid returns false for empty steps")
    func tapDanceEmptySteps() {
        // Create valid then mutate to avoid assert
        var behavior = TapDanceBehavior.twoStep(singleTap: "a", doubleTap: "b")
        behavior.steps = []
        #expect(behavior.isValid == false)
    }

    @Test("TapDanceBehavior.isValid returns false when all actions empty")
    func tapDanceEmptyActions() {
        var behavior = TapDanceBehavior.twoStep(singleTap: "a", doubleTap: "b")
        behavior.steps = [TapDanceStep(label: "Single", action: "")]
        #expect(behavior.isValid == false)
    }

    // MARK: - ChordBehavior

    @Test("ChordBehavior encodes and decodes")
    func chordRoundTrip() throws {
        let behavior = ChordBehavior(
            keys: ["j", "k"],
            output: "esc",
            timeout: 250,
            description: "Navigation escape"
        )

        let data = try JSONEncoder().encode(behavior)
        let decoded = try JSONDecoder().decode(ChordBehavior.self, from: data)

        #expect(decoded.keys == ["j", "k"])
        #expect(decoded.output == "esc")
        #expect(decoded.timeout == 250)
        #expect(decoded.description == "Navigation escape")
    }

    @Test("ChordBehavior defaults")
    func chordDefaults() {
        let behavior = ChordBehavior(keys: ["s", "d"], output: "enter")

        #expect(behavior.timeout == 200)
        #expect(behavior.description == nil)
    }

    @Test("ChordBehavior.twoKey factory")
    func chordTwoKeyFactory() {
        let chord = ChordBehavior.twoKey("j", "k", output: "esc", description: "Quick escape")

        #expect(chord.keys == ["j", "k"])
        #expect(chord.output == "esc")
        #expect(chord.timeout == 200) // default
        #expect(chord.description == "Quick escape")
    }

    @Test("ChordBehavior.threeKey factory")
    func chordThreeKeyFactory() {
        let chord = ChordBehavior.threeKey("s", "d", "f", output: "C-x", description: "Cut")

        #expect(chord.keys == ["s", "d", "f"])
        #expect(chord.output == "C-x")
        #expect(chord.timeout == 200) // default
        #expect(chord.description == "Cut")
    }

    @Test("ChordBehavior.isValid returns true for valid config")
    func chordValidation() {
        let valid = ChordBehavior(keys: ["j", "k"], output: "esc")
        #expect(valid.isValid == true)
    }

    @Test("ChordBehavior.isValid returns false when keys mutated to single")
    func chordInvalidSingleKey() {
        var behavior = ChordBehavior(keys: ["j", "k"], output: "esc")
        behavior.keys = ["j"]
        #expect(behavior.isValid == false)
    }

    @Test("ChordBehavior.isValid returns false when output mutated to empty")
    func chordInvalidEmptyOutput() {
        var behavior = ChordBehavior(keys: ["j", "k"], output: "esc")
        behavior.output = ""
        #expect(behavior.isValid == false)
    }

    @Test("ChordBehavior.groupName generates consistent name")
    func chordGroupName() {
        let chord1 = ChordBehavior(keys: ["j", "k"], output: "esc")
        let chord2 = ChordBehavior(keys: ["k", "j"], output: "esc") // reversed order

        // Group names should be same regardless of key order (sorted)
        #expect(chord1.groupName == chord2.groupName)
        #expect(chord1.groupName == "kp-chord-j-k")
    }

    @Test("ChordBehavior timeout clamped to minimum 50ms")
    func chordTimeoutClamped() {
        let chord = ChordBehavior(keys: ["a", "b"], output: "x", timeout: 10)
        #expect(chord.timeout == 50) // clamped to 50
    }

    @Test("MappingBehavior chord case round-trips")
    func mappingBehaviorChord() throws {
        let behavior = MappingBehavior.chord(
            ChordBehavior(keys: ["j", "k"], output: "esc", timeout: 200)
        )

        let data = try JSONEncoder().encode(behavior)
        let decoded = try JSONDecoder().decode(MappingBehavior.self, from: data)

        if case let .chord(ch) = decoded {
            #expect(ch.keys == ["j", "k"])
            #expect(ch.output == "esc")
        } else {
            Issue.record("Expected chord case")
        }
    }

    @Test("KeyMapping with chord behavior round-trips")
    func keyMappingWithChordBehavior() throws {
        let mapping = KeyMapping(
            input: "j",
            output: "_", // placeholder - chord doesn't use individual output
            behavior: .chord(ChordBehavior.twoKey("j", "k", output: "esc"))
        )

        let data = try JSONEncoder().encode(mapping)
        let decoded = try JSONDecoder().decode(KeyMapping.self, from: data)

        #expect(decoded.input == "j")
        #expect(decoded.behavior != nil)

        if case let .chord(ch) = decoded.behavior {
            #expect(ch.keys == ["j", "k"])
            #expect(ch.output == "esc")
        } else {
            Issue.record("Expected chord behavior")
        }
    }

    @Test("CustomRule with chord behavior round-trips")
    func customRuleWithChordBehavior() throws {
        let rule = CustomRule(
            title: "J+K Escape",
            input: "j",
            output: "_",
            behavior: .chord(ChordBehavior.twoKey("j", "k", output: "esc"))
        )

        let data = try JSONEncoder().encode(rule)
        let decoded = try JSONDecoder().decode(CustomRule.self, from: data)

        #expect(decoded.title == "J+K Escape")
        #expect(decoded.behavior != nil)

        if case let .chord(ch) = decoded.behavior {
            #expect(ch.keys == ["j", "k"])
            #expect(ch.output == "esc")
        } else {
            Issue.record("Expected chord behavior")
        }
    }
}
