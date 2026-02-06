@testable import KeyPathAppKit
@preconcurrency import XCTest

final class AppKeyMappingTests: XCTestCase {
    // MARK: - Virtual Key Name Generation

    func testGenerateVirtualKeyName_SimpleAppName() {
        let vkName = AppKeyMapping.generateVirtualKeyName(
            displayName: "Safari",
            bundleIdentifier: "com.apple.Safari"
        )
        XCTAssertEqual(vkName, "vk_safari")
    }

    func testGenerateVirtualKeyName_AppNameWithSpaces() {
        let vkName = AppKeyMapping.generateVirtualKeyName(
            displayName: "VS Code",
            bundleIdentifier: "com.microsoft.VSCode"
        )
        XCTAssertEqual(vkName, "vk_vs_code")
    }

    func testGenerateVirtualKeyName_AppNameWithHyphens() {
        let vkName = AppKeyMapping.generateVirtualKeyName(
            displayName: "Fantastical-2",
            bundleIdentifier: "com.flexibits.fantastical2"
        )
        XCTAssertEqual(vkName, "vk_fantastical_2")
    }

    func testGenerateVirtualKeyName_AppNameWithNumbers() {
        let vkName = AppKeyMapping.generateVirtualKeyName(
            displayName: "1Password",
            bundleIdentifier: "com.1password.1password"
        )
        // Starts with number, should get "app_" prefix
        XCTAssertEqual(vkName, "vk_app_1password")
    }

    func testGenerateVirtualKeyName_EmptyDisplayName_UseBundleIDFallback() {
        let vkName = AppKeyMapping.generateVirtualKeyName(
            displayName: "",
            bundleIdentifier: "com.apple.Safari"
        )
        XCTAssertEqual(vkName, "vk_safari")
    }

    func testGenerateVirtualKeyName_SpecialCharsOnly_UsesHash() {
        let vkName = AppKeyMapping.generateVirtualKeyName(
            displayName: "!!!",
            bundleIdentifier: "com.example.SpecialApp"
        )
        // Should fall back to hash-based name
        XCTAssertTrue(vkName.hasPrefix("vk_app_"))
        XCTAssertTrue(vkName.count > 8) // Has hash suffix
    }

    func testGenerateVirtualKeyName_UnicodeCharacters() {
        let vkName = AppKeyMapping.generateVirtualKeyName(
            displayName: "日本語App",
            bundleIdentifier: "com.example.JapaneseApp"
        )
        // Unicode letters should be filtered out, leaving "app"
        XCTAssertEqual(vkName, "vk_app")
    }

    // MARK: - Unique Virtual Key Name Generation

    func testGenerateUniqueVirtualKeyName_AddsHashSuffix() {
        let baseName = AppKeyMapping.generateVirtualKeyName(
            displayName: "Safari",
            bundleIdentifier: "com.apple.Safari"
        )
        let uniqueName = AppKeyMapping.generateUniqueVirtualKeyName(
            displayName: "Safari",
            bundleIdentifier: "com.apple.Safari"
        )

        XCTAssertTrue(uniqueName.hasPrefix(baseName))
        XCTAssertTrue(uniqueName.count > baseName.count)
        XCTAssertTrue(uniqueName.contains("_"))
    }

    func testGenerateUniqueVirtualKeyName_IsDeterministic() {
        let name1 = AppKeyMapping.generateUniqueVirtualKeyName(
            displayName: "Safari",
            bundleIdentifier: "com.apple.Safari"
        )
        let name2 = AppKeyMapping.generateUniqueVirtualKeyName(
            displayName: "Safari",
            bundleIdentifier: "com.apple.Safari"
        )

        // Same input should always produce same output (deterministic hash)
        XCTAssertEqual(name1, name2)
    }

    func testGenerateUniqueVirtualKeyName_DifferentBundleIDsProduceDifferentNames() {
        let name1 = AppKeyMapping.generateUniqueVirtualKeyName(
            displayName: "Safari",
            bundleIdentifier: "com.apple.Safari"
        )
        let name2 = AppKeyMapping.generateUniqueVirtualKeyName(
            displayName: "Safari",
            bundleIdentifier: "com.example.Safari"
        )

        XCTAssertNotEqual(name1, name2)
    }

    // MARK: - AppKeyMapping Initialization

    func testAppKeyMapping_DefaultsAreCorrect() {
        let mapping = AppKeyMapping(
            bundleIdentifier: "com.apple.Safari",
            displayName: "Safari"
        )

        XCTAssertEqual(mapping.bundleIdentifier, "com.apple.Safari")
        XCTAssertEqual(mapping.displayName, "Safari")
        XCTAssertEqual(mapping.virtualKeyName, "vk_safari")
        XCTAssertTrue(mapping.isEnabled)
        XCTAssertNotNil(mapping.id)
    }

    func testAppKeyMapping_CustomVirtualKeyName() {
        let mapping = AppKeyMapping(
            bundleIdentifier: "com.apple.Safari",
            displayName: "Safari",
            virtualKeyName: "vk_custom_name"
        )

        XCTAssertEqual(mapping.virtualKeyName, "vk_custom_name")
    }

    // MARK: - AppKeyOverride

    func testAppKeyOverride_Initialization() {
        let override = AppKeyOverride(
            inputKey: "j",
            outputAction: "down",
            description: "Vim-style down"
        )

        XCTAssertEqual(override.inputKey, "j")
        XCTAssertEqual(override.outputAction, "down")
        XCTAssertEqual(override.description, "Vim-style down")
    }

    // MARK: - AppKeymap

    func testAppKeymap_ConvenienceInitializer() {
        let keymap = AppKeymap(
            bundleIdentifier: "com.apple.Safari",
            displayName: "Safari",
            overrides: [
                AppKeyOverride(inputKey: "j", outputAction: "down"),
                AppKeyOverride(inputKey: "k", outputAction: "up")
            ]
        )

        XCTAssertEqual(keymap.mapping.bundleIdentifier, "com.apple.Safari")
        XCTAssertEqual(keymap.mapping.displayName, "Safari")
        XCTAssertEqual(keymap.overrides.count, 2)
    }

    // MARK: - Codable

    func testAppKeymap_CodableRoundTrip() throws {
        let original = AppKeymap(
            bundleIdentifier: "com.apple.Safari",
            displayName: "Safari",
            overrides: [
                AppKeyOverride(inputKey: "j", outputAction: "down"),
                AppKeyOverride(inputKey: "k", outputAction: "up")
            ]
        )

        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        let data = try encoder.encode(original)

        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        let decoded = try decoder.decode(AppKeymap.self, from: data)

        XCTAssertEqual(decoded.mapping.bundleIdentifier, original.mapping.bundleIdentifier)
        XCTAssertEqual(decoded.mapping.displayName, original.mapping.displayName)
        XCTAssertEqual(decoded.mapping.virtualKeyName, original.mapping.virtualKeyName)
        XCTAssertEqual(decoded.overrides.count, original.overrides.count)
    }
}
