@testable import KeyPathAppKit
import XCTest

// MARK: - Key Translator Tests

final class KarabinerKeyTranslatorTests: XCTestCase {
    func testBasicKeyTranslation() {
        XCTAssertEqual(KarabinerKeyTranslator.toKanata("a"), "a")
        XCTAssertEqual(KarabinerKeyTranslator.toKanata("z"), "z")
        XCTAssertEqual(KarabinerKeyTranslator.toKanata("1"), "1")
        XCTAssertEqual(KarabinerKeyTranslator.toKanata("0"), "0")
    }

    func testSpecialKeyTranslation() {
        XCTAssertEqual(KarabinerKeyTranslator.toKanata("return_or_enter"), "ret")
        XCTAssertEqual(KarabinerKeyTranslator.toKanata("escape"), "esc")
        XCTAssertEqual(KarabinerKeyTranslator.toKanata("delete_or_backspace"), "bspc")
        XCTAssertEqual(KarabinerKeyTranslator.toKanata("spacebar"), "spc")
        XCTAssertEqual(KarabinerKeyTranslator.toKanata("tab"), "tab")
        XCTAssertEqual(KarabinerKeyTranslator.toKanata("caps_lock"), "caps")
    }

    func testArrowKeys() {
        XCTAssertEqual(KarabinerKeyTranslator.toKanata("up_arrow"), "up")
        XCTAssertEqual(KarabinerKeyTranslator.toKanata("down_arrow"), "down")
        XCTAssertEqual(KarabinerKeyTranslator.toKanata("left_arrow"), "left")
        XCTAssertEqual(KarabinerKeyTranslator.toKanata("right_arrow"), "right")
    }

    func testModifierTranslation() {
        XCTAssertEqual(KarabinerKeyTranslator.modifierToKanata("left_command"), "lmet")
        XCTAssertEqual(KarabinerKeyTranslator.modifierToKanata("left_shift"), "lsft")
        XCTAssertEqual(KarabinerKeyTranslator.modifierToKanata("left_control"), "lctl")
        XCTAssertEqual(KarabinerKeyTranslator.modifierToKanata("left_option"), "lalt")
        XCTAssertEqual(KarabinerKeyTranslator.modifierToKanata("command"), "lmet")
    }

    func testSymbolKeys() {
        XCTAssertEqual(KarabinerKeyTranslator.toKanata("grave_accent_and_tilde"), "grv")
        XCTAssertEqual(KarabinerKeyTranslator.toKanata("semicolon"), "scln")
        XCTAssertEqual(KarabinerKeyTranslator.toKanata("quote"), "apo")
        XCTAssertEqual(KarabinerKeyTranslator.toKanata("open_bracket"), "lbrc")
        XCTAssertEqual(KarabinerKeyTranslator.toKanata("close_bracket"), "rbrc")
    }

    func testConsumerKeyTranslation() {
        XCTAssertEqual(KarabinerKeyTranslator.consumerKeyToKanata("volume_increment"), "volu")
        XCTAssertEqual(KarabinerKeyTranslator.consumerKeyToKanata("volume_decrement"), "vold")
        XCTAssertEqual(KarabinerKeyTranslator.consumerKeyToKanata("mute"), "mute")
        XCTAssertEqual(KarabinerKeyTranslator.consumerKeyToKanata("play_or_pause"), "pp")
    }

    func testUnknownKeyReturnsNil() {
        XCTAssertNil(KarabinerKeyTranslator.toKanata("nonexistent_key"))
        XCTAssertNil(KarabinerKeyTranslator.consumerKeyToKanata("nonexistent_consumer_key"))
        XCTAssertNil(KarabinerKeyTranslator.modifierToKanata("nonexistent_modifier"))
    }

    func testKanataExpressionWithModifiers() {
        XCTAssertEqual(
            KarabinerKeyTranslator.toKanataExpression(keyCode: "a", modifiers: ["left_command"]),
            "M-a"
        )
        XCTAssertEqual(
            KarabinerKeyTranslator.toKanataExpression(keyCode: "c", modifiers: ["left_command", "left_shift"]),
            "M-S-c"
        )
        XCTAssertEqual(
            KarabinerKeyTranslator.toKanataExpression(keyCode: "a", modifiers: []),
            "a"
        )
    }

    func testKanataExpressionWithUnknownKey() {
        XCTAssertNil(KarabinerKeyTranslator.toKanataExpression(keyCode: "nonexistent"))
    }

    func testFunctionKeys() {
        XCTAssertEqual(KarabinerKeyTranslator.toKanata("f1"), "f1")
        XCTAssertEqual(KarabinerKeyTranslator.toKanata("f12"), "f12")
        XCTAssertEqual(KarabinerKeyTranslator.toKanata("f20"), "f20")
    }
}

// MARK: - Converter Service Tests

final class KarabinerConverterServiceTests: XCTestCase {
    let service = KarabinerConverterService()

    // MARK: - JSON Parsing

    func testEmptyJSONThrows() async {
        let data = "{}".data(using: .utf8)!
        do {
            _ = try await service.convert(data: data, profileIndex: nil)
            XCTFail("Should throw for missing profiles")
        } catch let error as KarabinerImportError {
            if case .invalidJSON = error {
                // Expected - profiles key missing
            } else if case .noProfiles = error {
                // Also acceptable
            } else {
                XCTFail("Unexpected error type: \(error)")
            }
        } catch {
            // Acceptable - decoding error
        }
    }

    func testEmptyProfilesThrows() async {
        let json = """
        { "profiles": [] }
        """
        let data = json.data(using: .utf8)!
        do {
            _ = try await service.convert(data: data, profileIndex: nil)
            XCTFail("Should throw for empty profiles")
        } catch let error as KarabinerImportError {
            if case .noProfiles = error {} else {
                XCTFail("Expected noProfiles, got \(error)")
            }
        } catch {
            XCTFail("Unexpected error: \(error)")
        }
    }

    func testProfileIndexOutOfRange() async {
        let json = """
        { "profiles": [{ "name": "Default", "simple_modifications": [] }] }
        """
        let data = json.data(using: .utf8)!
        do {
            _ = try await service.convert(data: data, profileIndex: 5)
            XCTFail("Should throw for out-of-range index")
        } catch let error as KarabinerImportError {
            if case .profileIndexOutOfRange = error {} else {
                XCTFail("Expected profileIndexOutOfRange, got \(error)")
            }
        } catch {
            XCTFail("Unexpected error: \(error)")
        }
    }

    func testGetProfiles() throws {
        let json = """
        {
            "profiles": [
                { "name": "Default", "selected": true },
                { "name": "Gaming", "selected": false }
            ]
        }
        """
        let data = json.data(using: .utf8)!
        let profiles = try service.getProfiles(from: data)
        XCTAssertEqual(profiles.count, 2)
        XCTAssertEqual(profiles[0].name, "Default")
        XCTAssertTrue(profiles[0].isSelected)
        XCTAssertEqual(profiles[1].name, "Gaming")
        XCTAssertFalse(profiles[1].isSelected)
    }

    // MARK: - Simple Modifications

    func testSimpleModificationConversion() async throws {
        let json = """
        {
            "profiles": [{
                "name": "Default",
                "simple_modifications": [
                    {
                        "from": { "key_code": "caps_lock" },
                        "to": [{ "key_code": "escape" }]
                    }
                ]
            }]
        }
        """
        let data = json.data(using: .utf8)!
        let result = try await service.convert(data: data, profileIndex: 0)

        XCTAssertEqual(result.collections.count, 1)
        XCTAssertEqual(result.collections[0].name, "Karabiner Simple Remaps")
        XCTAssertEqual(result.collections[0].mappings.count, 1)
        XCTAssertEqual(result.collections[0].mappings[0].input, "caps")
        XCTAssertEqual(result.collections[0].mappings[0].output, "esc")
    }

    func testMultipleSimpleModifications() async throws {
        let json = """
        {
            "profiles": [{
                "name": "Default",
                "simple_modifications": [
                    {
                        "from": { "key_code": "caps_lock" },
                        "to": [{ "key_code": "escape" }]
                    },
                    {
                        "from": { "key_code": "escape" },
                        "to": [{ "key_code": "caps_lock" }]
                    }
                ]
            }]
        }
        """
        let data = json.data(using: .utf8)!
        let result = try await service.convert(data: data, profileIndex: 0)

        XCTAssertEqual(result.collections.count, 1)
        XCTAssertEqual(result.collections[0].mappings.count, 2)
    }

    // MARK: - Complex Modifications - Simple Remap

    func testComplexSimpleRemap() async throws {
        let json = """
        {
            "profiles": [{
                "name": "Default",
                "complex_modifications": {
                    "rules": [{
                        "description": "Vim arrows",
                        "manipulators": [{
                            "type": "basic",
                            "from": {
                                "key_code": "h",
                                "modifiers": { "mandatory": ["left_command"] }
                            },
                            "to": [{ "key_code": "left_arrow" }]
                        }]
                    }]
                }
            }]
        }
        """
        let data = json.data(using: .utf8)!
        let result = try await service.convert(data: data, profileIndex: 0)

        XCTAssertEqual(result.collections.count, 1)
        XCTAssertEqual(result.collections[0].name, "Vim arrows")
        XCTAssertEqual(result.collections[0].mappings.count, 1)
        XCTAssertEqual(result.collections[0].mappings[0].input, "M-h")
        XCTAssertEqual(result.collections[0].mappings[0].output, "left")
    }

    // MARK: - Dual Role

    func testDualRoleConversion() async throws {
        let json = """
        {
            "profiles": [{
                "name": "Default",
                "complex_modifications": {
                    "rules": [{
                        "description": "Caps Lock dual role",
                        "manipulators": [{
                            "type": "basic",
                            "from": { "key_code": "caps_lock" },
                            "to": [{ "key_code": "left_control" }],
                            "to_if_alone": [{ "key_code": "escape" }]
                        }]
                    }]
                }
            }]
        }
        """
        let data = json.data(using: .utf8)!
        let result = try await service.convert(data: data, profileIndex: 0)

        XCTAssertEqual(result.collections.count, 1)
        let mapping = result.collections[0].mappings[0]
        XCTAssertEqual(mapping.input, "caps")

        if case let .dualRole(behavior) = mapping.behavior {
            XCTAssertEqual(behavior.tapAction, "esc")
            XCTAssertEqual(behavior.holdAction, "lctl")
        } else {
            XCTFail("Expected dual role behavior")
        }
    }

    // MARK: - Chord (Simultaneous)

    func testChordConversion() async throws {
        let json = """
        {
            "profiles": [{
                "name": "Default",
                "complex_modifications": {
                    "rules": [{
                        "description": "JK to Escape",
                        "manipulators": [{
                            "type": "basic",
                            "from": {
                                "key_code": "j",
                                "simultaneous": [{ "key_code": "k" }]
                            },
                            "to": [{ "key_code": "escape" }]
                        }]
                    }]
                }
            }]
        }
        """
        let data = json.data(using: .utf8)!
        let result = try await service.convert(data: data, profileIndex: 0)

        XCTAssertEqual(result.collections.count, 1)
        let mapping = result.collections[0].mappings[0]

        if case let .chord(behavior) = mapping.behavior {
            XCTAssertTrue(behavior.keys.contains("j"))
            XCTAssertTrue(behavior.keys.contains("k"))
            XCTAssertEqual(behavior.output, "esc")
        } else {
            XCTFail("Expected chord behavior")
        }
    }

    // MARK: - Macro (Multi-key To)

    func testMacroConversion() async throws {
        let json = """
        {
            "profiles": [{
                "name": "Default",
                "complex_modifications": {
                    "rules": [{
                        "description": "Copy-Paste macro",
                        "manipulators": [{
                            "type": "basic",
                            "from": {
                                "key_code": "v",
                                "modifiers": { "mandatory": ["left_command", "left_shift"] }
                            },
                            "to": [
                                { "key_code": "c", "modifiers": ["left_command"] },
                                { "key_code": "v", "modifiers": ["left_command"] }
                            ]
                        }]
                    }]
                }
            }]
        }
        """
        let data = json.data(using: .utf8)!
        let result = try await service.convert(data: data, profileIndex: 0)

        XCTAssertEqual(result.collections.count, 1)
        let mapping = result.collections[0].mappings[0]

        if case let .macro(behavior) = mapping.behavior {
            XCTAssertEqual(behavior.outputs.count, 2)
            XCTAssertEqual(behavior.outputs[0], "M-c")
            XCTAssertEqual(behavior.outputs[1], "M-v")
        } else {
            XCTFail("Expected macro behavior")
        }
    }

    // MARK: - Shell Command

    func testShellCommandAppLaunch() async throws {
        let json = """
        {
            "profiles": [{
                "name": "Default",
                "complex_modifications": {
                    "rules": [{
                        "description": "Launch Safari",
                        "manipulators": [{
                            "type": "basic",
                            "from": {
                                "key_code": "s",
                                "modifiers": { "mandatory": ["left_command", "left_shift"] }
                            },
                            "to": [{ "shell_command": "open -a Safari" }]
                        }]
                    }]
                }
            }]
        }
        """
        let data = json.data(using: .utf8)!
        let result = try await service.convert(data: data, profileIndex: 0)

        XCTAssertEqual(result.launcherMappings.count, 1)
        if case let .app(name, _) = result.launcherMappings[0].target {
            XCTAssertEqual(name, "Safari")
        } else {
            XCTFail("Expected app launcher target")
        }
    }

    func testShellCommandURLOpen() async throws {
        let json = """
        {
            "profiles": [{
                "name": "Default",
                "complex_modifications": {
                    "rules": [{
                        "description": "Open Google",
                        "manipulators": [{
                            "type": "basic",
                            "from": {
                                "key_code": "g",
                                "modifiers": { "mandatory": ["left_command", "left_shift"] }
                            },
                            "to": [{ "shell_command": "open https://google.com" }]
                        }]
                    }]
                }
            }]
        }
        """
        let data = json.data(using: .utf8)!
        let result = try await service.convert(data: data, profileIndex: 0)

        XCTAssertEqual(result.launcherMappings.count, 1)
        if case let .url(urlString) = result.launcherMappings[0].target {
            XCTAssertEqual(urlString, "https://google.com")
        } else {
            XCTFail("Expected URL launcher target")
        }
    }

    // MARK: - App-Specific Rules

    func testAppSpecificRule() async throws {
        let json = """
        {
            "profiles": [{
                "name": "Default",
                "complex_modifications": {
                    "rules": [{
                        "description": "Chrome shortcuts",
                        "manipulators": [{
                            "type": "basic",
                            "from": { "key_code": "j" },
                            "to": [{ "key_code": "down_arrow" }],
                            "conditions": [{
                                "type": "frontmost_application_if",
                                "bundle_identifiers": ["^com\\\\.google\\\\.Chrome$"]
                            }]
                        }]
                    }]
                }
            }]
        }
        """
        let data = json.data(using: .utf8)!
        let result = try await service.convert(data: data, profileIndex: 0)

        XCTAssertFalse(result.appKeymaps.isEmpty, "Should have app keymaps")
        let keymap = result.appKeymaps[0]
        XCTAssertEqual(keymap.mapping.bundleIdentifier, "com.google.Chrome")
        XCTAssertEqual(keymap.overrides.count, 1)
        XCTAssertEqual(keymap.overrides[0].inputKey, "j")
        XCTAssertEqual(keymap.overrides[0].outputAction, "down")
    }

    // MARK: - Skipped Rules

    func testMouseKeySkipped() async throws {
        let json = """
        {
            "profiles": [{
                "name": "Default",
                "complex_modifications": {
                    "rules": [{
                        "description": "Mouse keys",
                        "manipulators": [{
                            "type": "basic",
                            "from": { "key_code": "j" },
                            "to": [{ "mouse_key": { "y": 1536 } }]
                        }]
                    }]
                }
            }]
        }
        """
        let data = json.data(using: .utf8)!
        let result = try await service.convert(data: data, profileIndex: 0)

        XCTAssertTrue(result.collections.isEmpty || result.collections[0].mappings.isEmpty)
        XCTAssertFalse(result.skippedRules.isEmpty)
        XCTAssertTrue(result.skippedRules[0].reason.contains("Mouse"))
    }

    func testUnknownKeySkipped() async throws {
        let json = """
        {
            "profiles": [{
                "name": "Default",
                "simple_modifications": [{
                    "from": { "key_code": "totally_fake_key" },
                    "to": [{ "key_code": "escape" }]
                }]
            }]
        }
        """
        let data = json.data(using: .utf8)!
        let result = try await service.convert(data: data, profileIndex: 0)

        XCTAssertFalse(result.skippedRules.isEmpty)
        XCTAssertTrue(result.skippedRules[0].reason.contains("Unknown"))
    }

    // MARK: - Disabled Rules

    func testDisabledRulesSkipped() async throws {
        let json = """
        {
            "profiles": [{
                "name": "Default",
                "complex_modifications": {
                    "rules": [{
                        "description": "Disabled rule",
                        "enabled": false,
                        "manipulators": [{
                            "type": "basic",
                            "from": { "key_code": "a" },
                            "to": [{ "key_code": "b" }]
                        }]
                    }]
                }
            }]
        }
        """
        let data = json.data(using: .utf8)!
        let result = try await service.convert(data: data, profileIndex: 0)

        XCTAssertTrue(result.collections.isEmpty)
    }

    // MARK: - Profile Selection

    func testSelectedProfileUsedByDefault() async throws {
        let json = """
        {
            "profiles": [
                {
                    "name": "First",
                    "selected": false,
                    "simple_modifications": [{
                        "from": { "key_code": "a" },
                        "to": [{ "key_code": "b" }]
                    }]
                },
                {
                    "name": "Second",
                    "selected": true,
                    "simple_modifications": [{
                        "from": { "key_code": "c" },
                        "to": [{ "key_code": "d" }]
                    }]
                }
            ]
        }
        """
        let data = json.data(using: .utf8)!
        let result = try await service.convert(data: data, profileIndex: nil)

        XCTAssertEqual(result.profileName, "Second")
        XCTAssertEqual(result.collections[0].mappings[0].input, "c")
    }

    // MARK: - Consumer Key Codes

    func testConsumerKeySimpleModification() async throws {
        let json = """
        {
            "profiles": [{
                "name": "Default",
                "simple_modifications": [{
                    "from": { "consumer_key_code": "volume_increment" },
                    "to": [{ "consumer_key_code": "volume_decrement" }]
                }]
            }]
        }
        """
        let data = json.data(using: .utf8)!
        let result = try await service.convert(data: data, profileIndex: 0)

        XCTAssertEqual(result.collections.count, 1)
        XCTAssertEqual(result.collections[0].mappings[0].input, "volu")
        XCTAssertEqual(result.collections[0].mappings[0].output, "vold")
    }

    // MARK: - Metadata

    func testImportedCollectionMetadata() async throws {
        let json = """
        {
            "profiles": [{
                "name": "Default",
                "simple_modifications": [{
                    "from": { "key_code": "caps_lock" },
                    "to": [{ "key_code": "escape" }]
                }]
            }]
        }
        """
        let data = json.data(using: .utf8)!
        let result = try await service.convert(data: data, profileIndex: 0)

        let collection = result.collections[0]
        XCTAssertEqual(collection.category, .custom)
        XCTAssertTrue(collection.tags.contains("karabiner"))
        XCTAssertTrue(collection.tags.contains("imported"))
        XCTAssertEqual(collection.icon, "arrow.right.arrow.left")
    }

    // MARK: - File Too Large

    func testFileTooLargeThrows() async {
        let data = Data(repeating: 0, count: 11 * 1024 * 1024)
        do {
            _ = try await service.convert(data: data, profileIndex: nil)
            XCTFail("Should throw for oversized file")
        } catch let error as KarabinerImportError {
            if case .fileTooLarge = error {} else {
                XCTFail("Expected fileTooLarge, got \(error)")
            }
        } catch {
            XCTFail("Unexpected error: \(error)")
        }
    }
}

// MARK: - Variable Value Tests

final class KarabinerVariableValueTests: XCTestCase {
    func testIsOn() {
        XCTAssertTrue(KarabinerVariableValue.int(1).isOn)
        XCTAssertFalse(KarabinerVariableValue.int(0).isOn)
        XCTAssertTrue(KarabinerVariableValue.bool(true).isOn)
        XCTAssertFalse(KarabinerVariableValue.bool(false).isOn)
        XCTAssertTrue(KarabinerVariableValue.string("active").isOn)
        XCTAssertFalse(KarabinerVariableValue.string("").isOn)
        XCTAssertFalse(KarabinerVariableValue.string("0").isOn)
    }

    func testDecoding() throws {
        let intJSON = "1".data(using: .utf8)!
        let intVal = try JSONDecoder().decode(KarabinerVariableValue.self, from: intJSON)
        XCTAssertEqual(intVal, .int(1))

        let strJSON = "\"hello\"".data(using: .utf8)!
        let strVal = try JSONDecoder().decode(KarabinerVariableValue.self, from: strJSON)
        XCTAssertEqual(strVal, .string("hello"))
    }
}
