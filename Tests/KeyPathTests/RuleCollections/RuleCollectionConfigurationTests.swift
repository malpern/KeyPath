import Foundation
@testable import KeyPathAppKit
import XCTest

final class RuleCollectionConfigurationTests: XCTestCase {
    // MARK: - Display Style Tests

    func testDisplayStyleForList() {
        let config = RuleCollectionConfiguration.list
        XCTAssertEqual(config.displayStyle, .list)
    }

    func testDisplayStyleForTable() {
        let config = RuleCollectionConfiguration.table
        XCTAssertEqual(config.displayStyle, .table)
    }

    func testDisplayStyleForSingleKeyPicker() {
        let config = RuleCollectionConfiguration.singleKeyPicker(
            SingleKeyPickerConfig(inputKey: "caps", presetOptions: [])
        )
        XCTAssertEqual(config.displayStyle, .singleKeyPicker)
    }

    func testDisplayStyleForHomeRowMods() {
        let config = RuleCollectionConfiguration.homeRowMods(HomeRowModsConfig())
        XCTAssertEqual(config.displayStyle, .homeRowMods)
    }

    func testDisplayStyleForTapHoldPicker() {
        let config = RuleCollectionConfiguration.tapHoldPicker(
            TapHoldPickerConfig(inputKey: "caps", tapOptions: [], holdOptions: [])
        )
        XCTAssertEqual(config.displayStyle, .tapHoldPicker)
    }

    func testDisplayStyleForLayerPresetPicker() {
        let config = RuleCollectionConfiguration.layerPresetPicker(
            LayerPresetPickerConfig(presets: [])
        )
        XCTAssertEqual(config.displayStyle, .layerPresetPicker)
    }

    // MARK: - Convenience Accessor Tests

    func testSingleKeyPickerConfigAccessor() {
        let pickerConfig = SingleKeyPickerConfig(inputKey: "caps", presetOptions: [], selectedOutput: "esc")
        let config = RuleCollectionConfiguration.singleKeyPicker(pickerConfig)

        XCTAssertNotNil(config.singleKeyPickerConfig)
        XCTAssertEqual(config.singleKeyPickerConfig?.inputKey, "caps")
        XCTAssertEqual(config.singleKeyPickerConfig?.selectedOutput, "esc")

        // Should return nil for other types
        XCTAssertNil(RuleCollectionConfiguration.list.singleKeyPickerConfig)
        XCTAssertNil(RuleCollectionConfiguration.table.singleKeyPickerConfig)
    }

    func testTapHoldPickerConfigAccessor() {
        let pickerConfig = TapHoldPickerConfig(
            inputKey: "caps",
            tapOptions: [],
            holdOptions: [],
            selectedTapOutput: "esc",
            selectedHoldOutput: "hyper"
        )
        let config = RuleCollectionConfiguration.tapHoldPicker(pickerConfig)

        XCTAssertNotNil(config.tapHoldPickerConfig)
        XCTAssertEqual(config.tapHoldPickerConfig?.inputKey, "caps")
        XCTAssertEqual(config.tapHoldPickerConfig?.selectedTapOutput, "esc")
        XCTAssertEqual(config.tapHoldPickerConfig?.selectedHoldOutput, "hyper")

        // Should return nil for other types
        XCTAssertNil(RuleCollectionConfiguration.list.tapHoldPickerConfig)
    }

    func testHomeRowModsConfigAccessor() {
        let hrmConfig = HomeRowModsConfig()
        let config = RuleCollectionConfiguration.homeRowMods(hrmConfig)

        XCTAssertNotNil(config.homeRowModsConfig)

        // Should return nil for other types
        XCTAssertNil(RuleCollectionConfiguration.list.homeRowModsConfig)
    }

    func testLayerPresetPickerConfigAccessor() {
        let preset = LayerPreset(id: "test", label: "Test", description: "Test preset", mappings: [])
        let pickerConfig = LayerPresetPickerConfig(presets: [preset], selectedPresetId: "test")
        let config = RuleCollectionConfiguration.layerPresetPicker(pickerConfig)

        XCTAssertNotNil(config.layerPresetPickerConfig)
        XCTAssertEqual(config.layerPresetPickerConfig?.presets.count, 1)
        XCTAssertEqual(config.layerPresetPickerConfig?.selectedPresetId, "test")

        // Should return nil for other types
        XCTAssertNil(RuleCollectionConfiguration.list.layerPresetPickerConfig)
    }

    // MARK: - Mutating Helper Tests

    func testUpdateSelectedOutput() {
        var config = RuleCollectionConfiguration.singleKeyPicker(
            SingleKeyPickerConfig(inputKey: "caps", presetOptions: [], selectedOutput: nil)
        )

        config.updateSelectedOutput("esc")
        XCTAssertEqual(config.singleKeyPickerConfig?.selectedOutput, "esc")

        config.updateSelectedOutput("ctrl")
        XCTAssertEqual(config.singleKeyPickerConfig?.selectedOutput, "ctrl")

        // Should be no-op for wrong config type
        var listConfig = RuleCollectionConfiguration.list
        listConfig.updateSelectedOutput("esc")
        XCTAssertEqual(listConfig.displayStyle, .list)
    }

    func testUpdateSelectedTapOutput() {
        var config = RuleCollectionConfiguration.tapHoldPicker(
            TapHoldPickerConfig(inputKey: "caps", tapOptions: [], holdOptions: [])
        )

        config.updateSelectedTapOutput("esc")
        XCTAssertEqual(config.tapHoldPickerConfig?.selectedTapOutput, "esc")

        // Should be no-op for wrong config type
        var listConfig = RuleCollectionConfiguration.list
        listConfig.updateSelectedTapOutput("esc")
        XCTAssertEqual(listConfig.displayStyle, .list)
    }

    func testUpdateSelectedHoldOutput() {
        var config = RuleCollectionConfiguration.tapHoldPicker(
            TapHoldPickerConfig(inputKey: "caps", tapOptions: [], holdOptions: [])
        )

        config.updateSelectedHoldOutput("hyper")
        XCTAssertEqual(config.tapHoldPickerConfig?.selectedHoldOutput, "hyper")

        // Should be no-op for wrong config type
        var listConfig = RuleCollectionConfiguration.list
        listConfig.updateSelectedHoldOutput("hyper")
        XCTAssertEqual(listConfig.displayStyle, .list)
    }

    func testUpdateHomeRowModsConfig() {
        var config = RuleCollectionConfiguration.homeRowMods(HomeRowModsConfig())

        var newConfig = HomeRowModsConfig()
        newConfig.enabledKeys = ["a", "s", "d", "f"]
        config.updateHomeRowModsConfig(newConfig)

        XCTAssertEqual(config.homeRowModsConfig?.enabledKeys, ["a", "s", "d", "f"])

        // Should be no-op for wrong config type
        var listConfig = RuleCollectionConfiguration.list
        listConfig.updateHomeRowModsConfig(newConfig)
        XCTAssertEqual(listConfig.displayStyle, .list)
    }

    func testUpdateSelectedPreset() {
        let preset1 = LayerPreset(id: "preset1", label: "Preset 1", description: "", mappings: [])
        let preset2 = LayerPreset(id: "preset2", label: "Preset 2", description: "", mappings: [])
        var config = RuleCollectionConfiguration.layerPresetPicker(
            LayerPresetPickerConfig(presets: [preset1, preset2], selectedPresetId: nil)
        )

        config.updateSelectedPreset("preset2")
        XCTAssertEqual(config.layerPresetPickerConfig?.selectedPresetId, "preset2")

        // Should be no-op for wrong config type
        var listConfig = RuleCollectionConfiguration.list
        listConfig.updateSelectedPreset("preset1")
        XCTAssertEqual(listConfig.displayStyle, .list)
    }

    // MARK: - Codable Tests

    func testEncodingAndDecodingList() throws {
        let original = RuleCollectionConfiguration.list
        let data = try JSONEncoder().encode(original)
        let decoded = try JSONDecoder().decode(RuleCollectionConfiguration.self, from: data)

        XCTAssertEqual(original, decoded)
    }

    func testEncodingAndDecodingTable() throws {
        let original = RuleCollectionConfiguration.table
        let data = try JSONEncoder().encode(original)
        let decoded = try JSONDecoder().decode(RuleCollectionConfiguration.self, from: data)

        XCTAssertEqual(original, decoded)
    }

    func testEncodingAndDecodingSingleKeyPicker() throws {
        let preset = SingleKeyPreset(output: "esc", label: "Escape", description: "Escape key")
        let original = RuleCollectionConfiguration.singleKeyPicker(
            SingleKeyPickerConfig(inputKey: "caps", presetOptions: [preset], selectedOutput: "esc")
        )
        let data = try JSONEncoder().encode(original)
        let decoded = try JSONDecoder().decode(RuleCollectionConfiguration.self, from: data)

        XCTAssertEqual(original, decoded)
        XCTAssertEqual(decoded.singleKeyPickerConfig?.inputKey, "caps")
        XCTAssertEqual(decoded.singleKeyPickerConfig?.selectedOutput, "esc")
    }

    func testEncodingAndDecodingTapHoldPicker() throws {
        let tapPreset = SingleKeyPreset(output: "esc", label: "Escape", description: "Escape key")
        let holdPreset = SingleKeyPreset(output: "hyper", label: "Hyper", description: "Hyper modifier")
        let original = RuleCollectionConfiguration.tapHoldPicker(
            TapHoldPickerConfig(
                inputKey: "caps",
                tapOptions: [tapPreset],
                holdOptions: [holdPreset],
                selectedTapOutput: "esc",
                selectedHoldOutput: "hyper"
            )
        )
        let data = try JSONEncoder().encode(original)
        let decoded = try JSONDecoder().decode(RuleCollectionConfiguration.self, from: data)

        XCTAssertEqual(original, decoded)
        XCTAssertEqual(decoded.tapHoldPickerConfig?.selectedTapOutput, "esc")
        XCTAssertEqual(decoded.tapHoldPickerConfig?.selectedHoldOutput, "hyper")
    }

    func testEncodingAndDecodingLayerPresetPicker() throws {
        let mapping = KeyMapping(input: "a", action: .keystroke(key: "1"))
        let preset = LayerPreset(id: "standard", label: "Standard", description: "Standard layout", mappings: [mapping])
        let original = RuleCollectionConfiguration.layerPresetPicker(
            LayerPresetPickerConfig(presets: [preset], selectedPresetId: "standard")
        )
        let data = try JSONEncoder().encode(original)
        let decoded = try JSONDecoder().decode(RuleCollectionConfiguration.self, from: data)

        XCTAssertEqual(original, decoded)
        XCTAssertEqual(decoded.layerPresetPickerConfig?.selectedPresetId, "standard")
    }

    // MARK: - LayerPresetPickerConfig Computed Properties

    func testSelectedPresetComputedProperty() {
        let preset1 = LayerPreset(id: "preset1", label: "Preset 1", description: "", mappings: [])
        let preset2 = LayerPreset(id: "preset2", label: "Preset 2", description: "", mappings: [])
        let config = LayerPresetPickerConfig(presets: [preset1, preset2], selectedPresetId: "preset2")

        XCTAssertNotNil(config.selectedPreset)
        XCTAssertEqual(config.selectedPreset?.id, "preset2")
        XCTAssertEqual(config.selectedPreset?.label, "Preset 2")
    }

    func testSelectedPresetReturnsNilWhenNoMatch() {
        let preset = LayerPreset(id: "preset1", label: "Preset 1", description: "", mappings: [])
        let config = LayerPresetPickerConfig(presets: [preset], selectedPresetId: "nonexistent")

        XCTAssertNil(config.selectedPreset)
    }

    func testSelectedMappingsReturnsCorrectMappings() {
        let mapping1 = KeyMapping(input: "a", action: .keystroke(key: "1"))
        let mapping2 = KeyMapping(input: "b", action: .keystroke(key: "2"))
        let preset = LayerPreset(id: "preset1", label: "Preset 1", description: "", mappings: [mapping1, mapping2])
        let config = LayerPresetPickerConfig(presets: [preset], selectedPresetId: "preset1")

        XCTAssertEqual(config.selectedMappings.count, 2)
        XCTAssertEqual(config.selectedMappings[0].input, "a")
        XCTAssertEqual(config.selectedMappings[1].action.outputString, "2")
    }

    func testSelectedMappingsReturnsEmptyWhenNoPresetSelected() {
        let mapping = KeyMapping(input: "a", action: .keystroke(key: "1"))
        let preset = LayerPreset(id: "preset1", label: "Preset 1", description: "", mappings: [mapping])
        let config = LayerPresetPickerConfig(presets: [preset], selectedPresetId: nil)

        XCTAssertTrue(config.selectedMappings.isEmpty)
    }

    // MARK: - KeyAction Tests (replaces LauncherTarget)

    func testKeyActionAppDisplayName() {
        let action = KeyAction.launchApp(name: "Safari", bundleId: "com.apple.Safari")
        XCTAssertEqual(action.displayName, "Safari")
        XCTAssertTrue(action.isLaunchApp)
        XCTAssertFalse(action.isOpenURL)
        XCTAssertFalse(action.isOpenFolder)
        XCTAssertFalse(action.isRunScript)
    }

    func testKeyActionURLDisplayName() {
        let action = KeyAction.openURL("github.com")
        XCTAssertEqual(action.displayName, "github.com")
        XCTAssertFalse(action.isLaunchApp)
        XCTAssertTrue(action.isOpenURL)
        XCTAssertFalse(action.isOpenFolder)
        XCTAssertFalse(action.isRunScript)
    }

    func testKeyActionURLDisplayNameStripsScheme() {
        let action = KeyAction.openURL("https://github.com/openai")
        XCTAssertEqual(action.displayName, "github.com")
    }

    func testKeyActionFolderDisplayName() {
        // With custom name
        let actionWithName = KeyAction.openFolder(path: "~/Downloads", name: "Downloads")
        XCTAssertEqual(actionWithName.displayName, "Downloads")
        XCTAssertFalse(actionWithName.isLaunchApp)
        XCTAssertFalse(actionWithName.isOpenURL)
        XCTAssertTrue(actionWithName.isOpenFolder)
        XCTAssertFalse(actionWithName.isRunScript)

        // Without custom name - should derive from path
        let actionNoName = KeyAction.openFolder(path: "~/Documents", name: nil)
        XCTAssertEqual(actionNoName.displayName, "Folder")
    }

    func testKeyActionScriptDisplayName() {
        // With custom name
        let actionWithName = KeyAction.runScript(path: "~/Scripts/backup.sh", name: "Backup")
        XCTAssertEqual(actionWithName.displayName, "Backup")
        XCTAssertFalse(actionWithName.isLaunchApp)
        XCTAssertFalse(actionWithName.isOpenURL)
        XCTAssertFalse(actionWithName.isOpenFolder)
        XCTAssertTrue(actionWithName.isRunScript)

        // Without custom name - should derive from path (without extension)
        let actionNoName = KeyAction.runScript(path: "~/Scripts/backup.sh", name: nil)
        XCTAssertEqual(actionNoName.displayName, "backup")
    }

    func testKeyActionKanataOutputForApp() {
        let action = KeyAction.launchApp(name: "Safari", bundleId: "com.apple.Safari")
        XCTAssertEqual(action.kanataOutput, "(push-msg \"launch:com.apple.Safari\")")
    }

    func testKeyActionKanataOutputForURL() {
        let action = KeyAction.openURL("github.com")
        XCTAssertEqual(action.kanataOutput, "(push-msg \"open:github.com\")")
    }

    func testKeyActionKanataOutputForFolder() {
        let action = KeyAction.openFolder(path: "~/Downloads", name: nil)
        XCTAssertEqual(action.kanataOutput, "(push-msg \"folder:~/Downloads\")")
    }

    func testKeyActionKanataOutputForScript() {
        let action = KeyAction.runScript(path: "~/Scripts/backup.sh", name: nil)
        XCTAssertEqual(action.kanataOutput, "(push-msg \"script:~/Scripts/backup.sh\")")
    }

    func testKeyActionEncodingAndDecodingFolder() throws {
        let original = KeyAction.openFolder(path: "~/Documents", name: "My Docs")
        let data = try JSONEncoder().encode(original)
        let decoded = try JSONDecoder().decode(KeyAction.self, from: data)

        XCTAssertEqual(original, decoded)
        if case let .openFolder(path, name) = decoded {
            XCTAssertEqual(path, "~/Documents")
            XCTAssertEqual(name, "My Docs")
        } else {
            XCTFail("Expected openFolder action")
        }
    }

    func testKeyActionEncodingAndDecodingScript() throws {
        let original = KeyAction.runScript(path: "~/Scripts/test.sh", name: "Test Script")
        let data = try JSONEncoder().encode(original)
        let decoded = try JSONDecoder().decode(KeyAction.self, from: data)

        XCTAssertEqual(original, decoded)
        if case let .runScript(path, name) = decoded {
            XCTAssertEqual(path, "~/Scripts/test.sh")
            XCTAssertEqual(name, "Test Script")
        } else {
            XCTFail("Expected runScript action")
        }
    }

    func testLauncherMappingWithFolderAction() {
        let mapping = LauncherMapping(
            key: "f5",
            action: .openFolder(path: "~/Downloads", name: "Downloads"),
            isEnabled: true
        )

        XCTAssertEqual(mapping.key, "f5")
        XCTAssertTrue(mapping.action.isOpenFolder)
        XCTAssertTrue(mapping.isEnabled)
    }

    func testLauncherMappingWithScriptAction() {
        let mapping = LauncherMapping(
            key: "f9",
            action: .runScript(path: "~/Scripts/backup.sh", name: "Backup"),
            isEnabled: true
        )

        XCTAssertEqual(mapping.key, "f9")
        XCTAssertTrue(mapping.action.isRunScript)
        XCTAssertTrue(mapping.isEnabled)
    }

    func testLauncherGridConfigDefaultMappingsIncludeAppsAndURLs() {
        let config = LauncherGridConfig.defaultConfig
        let appMappings = config.mappings.filter(\.action.isLaunchApp)
        let urlMappings = config.mappings.filter(\.action.isOpenURL)
        let folderMappings = config.mappings.filter(\.action.isOpenFolder)

        XCTAssertFalse(appMappings.isEmpty, "Default config should include app mappings")
        XCTAssertFalse(urlMappings.isEmpty, "Default config should include URL mappings")
        XCTAssertTrue(folderMappings.isEmpty, "Default config should not include folder mappings")

        // Spot-check a known default
        let safariMapping = appMappings.first { $0.key == "s" }
        XCTAssertNotNil(safariMapping)
        if case let .launchApp(name, bundleId) = safariMapping?.action {
            XCTAssertEqual(name, "Safari")
            XCTAssertEqual(bundleId, "com.apple.Safari")
        }
    }

    // MARK: - LauncherGridConfig Codable Tests

    func testLauncherGridConfigEncodingWithFoldersAndScripts() throws {
        var config = LauncherGridConfig(activationMode: .holdHyper, mappings: [], hasSeenWelcome: true)
        config.mappings = [
            LauncherMapping(key: "a", action: .launchApp(name: "Safari", bundleId: nil)),
            LauncherMapping(key: "1", action: .openURL("github.com")),
            LauncherMapping(key: "f5", action: .openFolder(path: "~/Downloads", name: "Downloads")),
            LauncherMapping(key: "f9", action: .runScript(path: "~/test.sh", name: "Test"))
        ]

        let data = try JSONEncoder().encode(config)
        let decoded = try JSONDecoder().decode(LauncherGridConfig.self, from: data)

        XCTAssertEqual(decoded.mappings.count, 4)
        XCTAssertTrue(decoded.mappings[2].action.isOpenFolder)
        XCTAssertTrue(decoded.mappings[3].action.isRunScript)
    }
}
