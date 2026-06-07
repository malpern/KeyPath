@testable import KeyPathAppKit
import KeyPathCore
import XCTest

final class TapHoldIdleLabelTests: XCTestCase {
    @MainActor
    func testUpdateTapHoldIdleLabelsFromEnabledCollection() {
        let vm = KeyboardVisualizationViewModel()
        let config = TapHoldPickerConfig(
            inputKey: "caps",
            tapOptions: [SingleKeyPreset(output: "esc", label: "Escape", description: "Remap to Escape")],
            holdOptions: [SingleKeyPreset(output: "C-S-M-A-", label: "Hyper", description: "All modifiers")],
            selectedTapOutput: "esc"
        )
        let collection = RuleCollection(
            id: UUID(),
            name: "Test Caps",
            summary: "",
            category: .productivity,
            mappings: [],
            isEnabled: true,
            isSystemDefault: false,
            configuration: .tapHoldPicker(config)
        )

        vm.updateTapHoldIdleLabels(from: [collection])

        let capsKeyCode: UInt16 = 57
        XCTAssertNotNil(vm.tapHoldIdleLabels[capsKeyCode], "Should have idle label for capslock")
    }

    @MainActor
    func testDisabledCollectionDoesNotPopulateLabels() {
        let vm = KeyboardVisualizationViewModel()
        let config = TapHoldPickerConfig(
            inputKey: "caps",
            tapOptions: [SingleKeyPreset(output: "esc", label: "Escape", description: "Remap to Escape")],
            holdOptions: [SingleKeyPreset(output: "C-S-M-A-", label: "Hyper", description: "All modifiers")],
            selectedTapOutput: "esc"
        )
        let collection = RuleCollection(
            id: UUID(),
            name: "Test Caps",
            summary: "",
            category: .productivity,
            mappings: [],
            isEnabled: false,
            isSystemDefault: false,
            configuration: .tapHoldPicker(config)
        )

        vm.updateTapHoldIdleLabels(from: [collection])

        XCTAssertTrue(vm.tapHoldIdleLabels.isEmpty, "Disabled collection should not produce idle labels")
    }

    @MainActor
    func testNonTapHoldCollectionIsIgnored() {
        let vm = KeyboardVisualizationViewModel()
        let collection = RuleCollection(
            id: UUID(),
            name: "Simple Remap",
            summary: "",
            category: .productivity,
            mappings: [],
            isEnabled: true,
            isSystemDefault: false,
            configuration: .list
        )

        vm.updateTapHoldIdleLabels(from: [collection])

        XCTAssertTrue(vm.tapHoldIdleLabels.isEmpty, "Non-tapHoldPicker config should not produce idle labels")
    }

    @MainActor
    func testNoSelectedTapOutputFallsBackToFirstOption() {
        let vm = KeyboardVisualizationViewModel()
        let config = TapHoldPickerConfig(
            inputKey: "caps",
            tapOptions: [SingleKeyPreset(output: "esc", label: "Escape", description: "Remap to Escape")],
            holdOptions: [SingleKeyPreset(output: "C-S-M-A-", label: "Hyper", description: "All modifiers")],
            selectedTapOutput: nil
        )
        let collection = RuleCollection(
            id: UUID(),
            name: "Test Caps",
            summary: "",
            category: .productivity,
            mappings: [],
            isEnabled: true,
            isSystemDefault: false,
            configuration: .tapHoldPicker(config)
        )

        vm.updateTapHoldIdleLabels(from: [collection])

        let capsKeyCode: UInt16 = 57
        XCTAssertNotNil(vm.tapHoldIdleLabels[capsKeyCode], "Should fallback to first tap option")
    }

    @MainActor
    func testMultipleCollectionsPopulateMultipleLabels() {
        let vm = KeyboardVisualizationViewModel()
        let capsConfig = TapHoldPickerConfig(
            inputKey: "caps",
            tapOptions: [SingleKeyPreset(output: "esc", label: "Escape", description: "Remap to Escape")],
            holdOptions: [],
            selectedTapOutput: "esc"
        )
        let tabConfig = TapHoldPickerConfig(
            inputKey: "tab",
            tapOptions: [SingleKeyPreset(output: "tab", label: "Tab", description: "Tab key")],
            holdOptions: [],
            selectedTapOutput: "tab"
        )
        let collections = [
            RuleCollection(
                id: UUID(), name: "Caps", summary: "", category: .productivity,
                mappings: [], isEnabled: true, isSystemDefault: false,
                configuration: .tapHoldPicker(capsConfig)
            ),
            RuleCollection(
                id: UUID(), name: "Tab", summary: "", category: .productivity,
                mappings: [], isEnabled: true, isSystemDefault: false,
                configuration: .tapHoldPicker(tabConfig)
            ),
        ]

        vm.updateTapHoldIdleLabels(from: collections)

        XCTAssertEqual(vm.tapHoldIdleLabels.count, 2, "Should have labels for both caps and tab")
    }

    @MainActor
    func testHomeRowModsPopulateIdleTapLabels() {
        let vm = KeyboardVisualizationViewModel()
        let config = HomeRowModsConfig(
            enabledKeys: ["a", "s", ";"],
            modifierAssignments: ["a": "lsft", "s": "lctl", ";": "rsft"]
        )
        let collection = RuleCollection(
            id: RuleCollectionIdentifier.homeRowMods,
            name: "Home Row Mods",
            summary: "",
            category: .productivity,
            mappings: [],
            isEnabled: true,
            isSystemDefault: true,
            configuration: .homeRowMods(config)
        )

        vm.updateTapHoldIdleLabels(from: [collection])

        XCTAssertEqual(vm.tapHoldIdleLabels[0], "A")
        XCTAssertEqual(vm.tapHoldIdleLabels[1], "S")
        XCTAssertEqual(vm.tapHoldIdleLabels[41], ";")
    }

    @MainActor
    func testDisabledHomeRowModsDoNotPopulateIdleTapLabels() {
        let vm = KeyboardVisualizationViewModel()
        let collection = RuleCollection(
            id: RuleCollectionIdentifier.homeRowMods,
            name: "Home Row Mods",
            summary: "",
            category: .productivity,
            mappings: [],
            isEnabled: false,
            isSystemDefault: true,
            configuration: .homeRowMods(HomeRowModsConfig())
        )

        vm.updateTapHoldIdleLabels(from: [collection])

        XCTAssertTrue(vm.tapHoldIdleLabels.isEmpty)
    }

    // MARK: - kanataNameToKeyCode mapping

    func testKanataNameToKeyCodeMapsCommonKeys() {
        XCTAssertEqual(KeyboardVisualizationViewModel.kanataNameToKeyCode("caps"), 57)
        XCTAssertEqual(KeyboardVisualizationViewModel.kanataNameToKeyCode("capslock"), 57)
        XCTAssertEqual(KeyboardVisualizationViewModel.kanataNameToKeyCode("tab"), 48)
        XCTAssertEqual(KeyboardVisualizationViewModel.kanataNameToKeyCode("space"), 49)
        XCTAssertEqual(KeyboardVisualizationViewModel.kanataNameToKeyCode("spc"), 49)
        XCTAssertEqual(KeyboardVisualizationViewModel.kanataNameToKeyCode("esc"), 53)
        XCTAssertEqual(KeyboardVisualizationViewModel.kanataNameToKeyCode("escape"), 53)
        XCTAssertEqual(KeyboardVisualizationViewModel.kanataNameToKeyCode("enter"), 36)
        XCTAssertEqual(KeyboardVisualizationViewModel.kanataNameToKeyCode("ret"), 36)
        XCTAssertEqual(KeyboardVisualizationViewModel.kanataNameToKeyCode(";"), 41)
        XCTAssertEqual(KeyboardVisualizationViewModel.kanataNameToKeyCode("scln"), 41)
    }

    func testKanataNameToKeyCodeIsCaseInsensitive() {
        XCTAssertEqual(
            KeyboardVisualizationViewModel.kanataNameToKeyCode("CAPS"),
            KeyboardVisualizationViewModel.kanataNameToKeyCode("caps")
        )
        XCTAssertEqual(
            KeyboardVisualizationViewModel.kanataNameToKeyCode("Tab"),
            KeyboardVisualizationViewModel.kanataNameToKeyCode("tab")
        )
    }

    // MARK: - tapHoldOutputDisplayLabel

    @MainActor
    func testTapHoldOutputDisplayLabelForEsc() {
        let label = KeyboardVisualizationViewModel.tapHoldOutputDisplayLabel("esc")
        XCTAssertNotNil(label)
    }

    @MainActor
    func testTapHoldOutputDisplayLabelForUnknownKey() {
        let label = KeyboardVisualizationViewModel.tapHoldOutputDisplayLabel("zzz_nonexistent")
        _ = label
    }
}
