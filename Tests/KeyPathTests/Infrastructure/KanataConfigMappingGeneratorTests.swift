@testable import KeyPathAppKit
import KeyPathCore
import XCTest

/// Tests for KanataConfiguration's mapping generator functions — the pure functions
/// that turn collection configs (HRM, layer toggles, chords, auto-shift, tap-hold pickers)
/// into concrete KeyMapping arrays consumed by the config renderer.
final class KanataConfigMappingGeneratorTests: XCTestCase {

    // MARK: - generateHomeRowModsMappings

    func testHRM_DefaultConfig_ProducesMappingsForAllEnabledKeys() {
        let config = HomeRowModsConfig()
        let mappings = KanataConfiguration.generateHomeRowModsMappings(from: config)

        XCTAssertFalse(mappings.isEmpty)
        let inputs = Set(mappings.map(\.input))
        for key in config.enabledKeys {
            XCTAssertTrue(inputs.contains(key), "Missing mapping for enabled key: \(key)")
        }
    }

    func testHRM_DefaultConfig_AllMappingsHaveDualRoleBehavior() {
        let config = HomeRowModsConfig()
        let mappings = KanataConfiguration.generateHomeRowModsMappings(from: config)

        for mapping in mappings {
            guard case .dualRole = mapping.behavior else {
                XCTFail("HRM mapping for '\(mapping.input)' should have dualRole behavior")
                continue
            }
        }
    }

    func testHRM_DefaultConfig_TapActionIsLetterItself() {
        let config = HomeRowModsConfig()
        let mappings = KanataConfiguration.generateHomeRowModsMappings(from: config)

        for mapping in mappings {
            if case let .dualRole(dr) = mapping.behavior {
                XCTAssertEqual(dr.tapAction, .keystroke(key: mapping.input),
                               "Tap action for '\(mapping.input)' should be the key itself")
            }
        }
    }

    func testHRM_ModifierMode_HoldActionIsModifier() {
        var config = HomeRowModsConfig()
        config.holdMode = .modifiers
        config.enabledKeys = Set(["a", "s", "d", "f"])
        config.modifierAssignments = ["a": "lctl", "s": "lalt", "d": "lsft", "f": "lmet"]

        let mappings = KanataConfiguration.generateHomeRowModsMappings(from: config)

        let aMapping = mappings.first(where: { $0.input == "a" })
        if case let .dualRole(dr) = aMapping?.behavior {
            XCTAssertEqual(dr.holdAction, .keystroke(key: "lctl"))
        } else {
            XCTFail("Expected dualRole for 'a'")
        }

        let fMapping = mappings.first(where: { $0.input == "f" })
        if case let .dualRole(dr) = fMapping?.behavior {
            XCTAssertEqual(dr.holdAction, .keystroke(key: "lmet"))
        } else {
            XCTFail("Expected dualRole for 'f'")
        }
    }

    func testHRM_CustomTiming_AppliesOffsets() {
        var config = HomeRowModsConfig()
        config.enabledKeys = Set(["a"])
        config.modifierAssignments = ["a": "lctl"]
        config.timing.tapWindow = 200
        config.timing.holdDelay = 200
        config.timing.tapOffsets = ["a": 20]
        config.timing.holdOffsets = ["a": -10]

        let mappings = KanataConfiguration.generateHomeRowModsMappings(from: config)
        let mapping = mappings.first!

        if case let .dualRole(dr) = mapping.behavior {
            XCTAssertEqual(dr.tapTimeout, 220) // 200 + 20
            XCTAssertEqual(dr.holdTimeout, 190) // 200 + (-10)
        } else {
            XCTFail("Expected dualRole behavior")
        }
    }

    func testHRM_OppositeHandPress_SetsFlag() {
        var config = HomeRowModsConfig()
        config.enabledKeys = Set(["a"])
        config.modifierAssignments = ["a": "lctl"]
        config.oppositeHandActivation = true
        config.oppositeHandMode = .press

        let mappings = KanataConfiguration.generateHomeRowModsMappings(from: config)
        if case let .dualRole(dr) = mappings.first?.behavior {
            XCTAssertTrue(dr.useOppositeHand)
            XCTAssertFalse(dr.useOppositeHandRelease)
            XCTAssertFalse(dr.activateHoldOnOtherKey)
        } else {
            XCTFail("Expected dualRole behavior")
        }
    }

    func testHRM_OppositeHandRelease_SetsFlag() {
        var config = HomeRowModsConfig()
        config.enabledKeys = Set(["a"])
        config.modifierAssignments = ["a": "lctl"]
        config.oppositeHandActivation = true
        config.oppositeHandMode = .release

        let mappings = KanataConfiguration.generateHomeRowModsMappings(from: config)
        if case let .dualRole(dr) = mappings.first?.behavior {
            XCTAssertFalse(dr.useOppositeHand)
            XCTAssertTrue(dr.useOppositeHandRelease)
        } else {
            XCTFail("Expected dualRole behavior")
        }
    }

    func testHRM_QuickTap_SetsFlag() {
        var config = HomeRowModsConfig()
        config.enabledKeys = Set(["a"])
        config.modifierAssignments = ["a": "lctl"]
        config.timing.quickTapEnabled = true
        config.timing.quickTapTermMs = 50

        let mappings = KanataConfiguration.generateHomeRowModsMappings(from: config)
        if case let .dualRole(dr) = mappings.first?.behavior {
            XCTAssertTrue(dr.quickTap)
            XCTAssertEqual(dr.tapTimeout, config.timing.tapWindow + 50)
        } else {
            XCTFail("Expected dualRole behavior")
        }
    }

    func testHRM_EmptyEnabledKeys_ProducesNoMappings() {
        var config = HomeRowModsConfig()
        config.enabledKeys = []

        let mappings = KanataConfiguration.generateHomeRowModsMappings(from: config)
        XCTAssertTrue(mappings.isEmpty)
    }

    // MARK: - generateHomeRowLayerTogglesMappings

    func testLayerToggles_ProducesDualRoleMappings() {
        let config = HomeRowLayerTogglesConfig(
            enabledKeys: Set(["f", "j"]),
            layerAssignments: ["f": "nav", "j": "sym"],
            keySelection: .custom,
            toggleMode: .whileHeld,
            oppositeHandMode: .press
        )

        let mappings = KanataConfiguration.generateHomeRowLayerTogglesMappings(from: config)
        XCTAssertEqual(mappings.count, 2)

        let fMapping = mappings.first(where: { $0.input == "f" })
        XCTAssertNotNil(fMapping)
        if case let .dualRole(dr) = fMapping?.behavior {
            XCTAssertEqual(dr.tapAction, .keystroke(key: "f"))
            XCTAssertEqual(dr.holdAction.kanataOutput, "(layer-while-held nav)")
        } else {
            XCTFail("Expected dualRole for 'f'")
        }
    }

    func testLayerToggles_EmptyKeys_ProducesNoMappings() {
        let config = HomeRowLayerTogglesConfig(
            enabledKeys: [],
            layerAssignments: [:],
            keySelection: .custom,
            toggleMode: .whileHeld,
            oppositeHandMode: .press
        )
        let mappings = KanataConfiguration.generateHomeRowLayerTogglesMappings(from: config)
        XCTAssertTrue(mappings.isEmpty)
    }

    // MARK: - generateChordGroupsMappings

    func testChordGroups_ProducesChordExprMappings() {
        let group = ChordGroup(
            id: UUID(),
            name: "kp-jk",
            timeout: 200,
            chords: [
                ChordDefinition(id: UUID(), keys: ["j", "k"], action: .keystroke(key: "esc"))
            ]
        )
        let config = ChordGroupsConfig(groups: [group])
        let mappings = KanataConfiguration.generateChordGroupsMappings(from: config)

        XCTAssertFalse(mappings.isEmpty)
        let inputs = Set(mappings.map(\.input))
        XCTAssertTrue(inputs.contains("j"))
        XCTAssertTrue(inputs.contains("k"))

        let jMapping = mappings.first(where: { $0.input == "j" })
        XCTAssertEqual(jMapping?.action, .rawKanata("(chord kp-jk j)"))
    }

    func testChordGroups_EmptyGroups_ProducesNoMappings() {
        let config = ChordGroupsConfig(groups: [])
        let mappings = KanataConfiguration.generateChordGroupsMappings(from: config)
        XCTAssertTrue(mappings.isEmpty)
    }

    // MARK: - generateAutoShiftSymbolsMappings

    func testAutoShift_ProducesTapHoldMappings() {
        var config = AutoShiftSymbolsConfig()
        config.enabledKeys = Set(["min", "eql"])
        config.timeoutMs = 180

        let mappings = KanataConfiguration.generateAutoShiftSymbolsMappings(from: config)
        XCTAssertEqual(mappings.count, 2)

        let minMapping = mappings.first(where: { $0.input == "min" })
        if case let .dualRole(dr) = minMapping?.behavior {
            XCTAssertEqual(dr.tapTimeout, 180)
            XCTAssertEqual(dr.holdTimeout, 180)
            XCTAssertEqual(dr.tapAction, .keystroke(key: "min"))
            XCTAssertEqual(dr.holdAction, .keystroke(key: "S-min"))
        } else {
            XCTFail("Expected dualRole behavior for auto-shift")
        }
    }

    func testAutoShift_EmptyEnabledKeys_ProducesNoMappings() {
        var config = AutoShiftSymbolsConfig()
        config.enabledKeys = []
        let mappings = KanataConfiguration.generateAutoShiftSymbolsMappings(from: config)
        XCTAssertTrue(mappings.isEmpty)
    }

    // MARK: - generateTapHoldPickerMappings

    func testTapHoldPicker_ProducesDualRoleMapping() {
        let config = TapHoldPickerConfig(
            inputKey: "caps",
            tapOptions: [SingleKeyPreset(output: "esc", label: "Escape", description: "")],
            holdOptions: [SingleKeyPreset(output: "C-S-M-A-", label: "Hyper", description: "")],
            selectedTapOutput: "esc",
            selectedHoldOutput: "C-S-M-A-"
        )
        var collection = RuleCollection(
            name: "Caps",
            summary: "",
            category: .custom,
            mappings: []
        )
        collection.configuration = .tapHoldPicker(config)

        let mappings = KanataConfiguration.generateTapHoldPickerMappings(from: collection)
        XCTAssertEqual(mappings.count, 1)
        XCTAssertEqual(mappings[0].input, "caps")

        if case let .dualRole(dr) = mappings[0].behavior {
            XCTAssertEqual(dr.tapAction, .keystroke(key: "esc"))
            XCTAssertTrue(dr.activateHoldOnOtherKey)
        } else {
            XCTFail("Expected dualRole behavior")
        }
    }

    func testTapHoldPicker_NonPickerConfig_ReturnsEmpty() {
        let collection = RuleCollection(
            name: "Not a picker",
            summary: "",
            category: .custom,
            mappings: [KeyMapping(input: "a", action: .keystroke(key: "b"), description: "")]
        )
        let mappings = KanataConfiguration.generateTapHoldPickerMappings(from: collection)
        XCTAssertTrue(mappings.isEmpty)
    }

    // MARK: - generateLauncherGridMappings (hold mode)

    func testLauncherGrid_HoldMode_ProducesDirectMappings() {
        var config = LauncherGridConfig()
        config.hyperTriggerMode = .hold
        config.mappings = [
            LauncherMapping(key: "a", action: .launchApp(name: "Safari", bundleId: "com.apple.Safari"), isEnabled: true),
            LauncherMapping(key: "b", action: .openURL("https://github.com"), isEnabled: true),
        ]

        let mappings = KanataConfiguration.generateLauncherGridMappings(from: config)
        XCTAssertEqual(mappings.count, 2)
        XCTAssertEqual(mappings[0].input, "a")
        XCTAssertTrue(mappings[0].action.kanataOutput.contains("launch:com.apple.Safari"))
    }

    func testLauncherGrid_TapMode_WrapsWithLayerSwitch() {
        var config = LauncherGridConfig()
        config.hyperTriggerMode = .tap
        config.mappings = [
            LauncherMapping(key: "a", action: .launchApp(name: "Safari", bundleId: "com.apple.Safari"), isEnabled: true),
        ]

        let mappings = KanataConfiguration.generateLauncherGridMappings(from: config)
        // Tap mode adds (multi action (push-msg "layer:base"))
        let aMapping = mappings.first(where: { $0.input == "a" })
        XCTAssertNotNil(aMapping)
        XCTAssertTrue(aMapping!.action.kanataOutput.contains("layer:base"))
    }

    func testLauncherGrid_TapMode_AddsEscapeKey() {
        var config = LauncherGridConfig()
        config.hyperTriggerMode = .tap
        config.mappings = [
            LauncherMapping(key: "a", action: .launchApp(name: "X", bundleId: "com.test"), isEnabled: true),
        ]

        let mappings = KanataConfiguration.generateLauncherGridMappings(from: config)
        let escMapping = mappings.first(where: { $0.input == "esc" })
        XCTAssertNotNil(escMapping, "Tap mode should add Escape key for exiting")
    }

    func testLauncherGrid_DisabledMappings_Excluded() {
        var config = LauncherGridConfig()
        config.hyperTriggerMode = .hold
        config.mappings = [
            LauncherMapping(key: "a", action: .launchApp(name: "X", bundleId: "com.test"), isEnabled: true),
            LauncherMapping(key: "b", action: .launchApp(name: "Y", bundleId: "com.test"), isEnabled: false),
        ]

        let mappings = KanataConfiguration.generateLauncherGridMappings(from: config)
        XCTAssertEqual(mappings.count, 1)
        XCTAssertEqual(mappings[0].input, "a")
    }
}
