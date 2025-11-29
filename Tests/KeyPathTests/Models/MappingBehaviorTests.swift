import Foundation
import Testing
@testable import KeyPathAppKit

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
            stateOverrides: ["hold": 250],
            activateHoldOnOtherKey: true,
            quickTap: true
        )

        let data = try JSONEncoder().encode(behavior)
        let decoded = try JSONDecoder().decode(DualRoleBehavior.self, from: data)

        #expect(decoded.tapAction == "a")
        #expect(decoded.holdAction == "lctl")
        #expect(decoded.tapTimeout == 180)
        #expect(decoded.holdTimeout == 220)
        #expect(decoded.stateOverrides?["hold"] == 250)
        #expect(decoded.activateHoldOnOtherKey == true)
        #expect(decoded.quickTap == true)
    }

    @Test("DualRoleBehavior defaults")
    func dualRoleDefaults() {
        let behavior = DualRoleBehavior(tapAction: "j", holdAction: "lsft")

        #expect(behavior.tapTimeout == 200)
        #expect(behavior.holdTimeout == 200)
        #expect(behavior.stateOverrides == nil)
        #expect(behavior.activateHoldOnOtherKey == false)
        #expect(behavior.quickTap == false)
    }

    @Test("homeRowMod factory")
    func homeRowModFactory() {
        let hrm = DualRoleBehavior.homeRowMod(letter: "f", modifier: "lmet")

        #expect(hrm.tapAction == "f")
        #expect(hrm.holdAction == "lmet")
        #expect(hrm.activateHoldOnOtherKey == true)
        #expect(hrm.quickTap == true)
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
        let behavior = MappingBehavior.tapDance(
            TapDanceBehavior.twoStep(singleTap: "x", doubleTap: "y")
        )

        let data = try JSONEncoder().encode(behavior)
        let decoded = try JSONDecoder().decode(MappingBehavior.self, from: data)

        if case let .tapDance(td) = decoded {
            #expect(td.steps.count == 2)
        } else {
            Issue.record("Expected tapDance case")
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
        let data = legacyJSON.data(using: .utf8)!
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
}

