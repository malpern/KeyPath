@testable import KeyPathAppKit
@preconcurrency import XCTest

@MainActor
final class CLIKarabinerImportTests: XCTestCase {
    private let facade = CLIFacade()
    private var originalCollections: [RuleCollection] = []

    override func setUp() async throws {
        try await super.setUp()
        originalCollections = await RuleCollectionStore.shared.loadCollections()
    }

    override func tearDown() async throws {
        try await RuleCollectionStore.shared.saveCollections(originalCollections)
        try await super.tearDown()
    }

    // MARK: - Simple Modifications

    func testSimpleModificationImport() throws {
        let json = """
        {
            "profiles": [{
                "name": "Default",
                "selected": true,
                "simple_modifications": [
                    {
                        "from": {"key_code": "caps_lock"},
                        "to": [{"key_code": "escape"}]
                    }
                ]
            }]
        }
        """
        let result = try facade.importFromKarabiner(data: Data(json.utf8), collectionName: nil, profileIndex: nil)

        XCTAssertEqual(result.profileName, "Default")
        XCTAssertEqual(result.collections.count, 1)
        XCTAssertEqual(result.collections.first?.name, "Karabiner Simple Remaps")
        XCTAssertEqual(result.collections.first?.mappings.count, 1)
        XCTAssertEqual(result.collections.first?.mappings.first?.input, "caps")
    }

    // MARK: - Complex Modifications

    func testComplexModificationSimpleRemap() throws {
        let json = """
        {
            "profiles": [{
                "name": "Test",
                "selected": true,
                "complex_modifications": {
                    "rules": [{
                        "description": "Tab to Escape",
                        "manipulators": [{
                            "type": "basic",
                            "from": {"key_code": "tab"},
                            "to": [{"key_code": "escape"}]
                        }]
                    }]
                }
            }]
        }
        """
        let result = try facade.importFromKarabiner(data: Data(json.utf8), collectionName: nil, profileIndex: nil)

        XCTAssertEqual(result.collections.count, 1)
        XCTAssertEqual(result.collections.first?.name, "Tab to Escape")
        XCTAssertEqual(result.collections.first?.mappings.first?.input, "tab")
    }

    func testComplexModificationWithModifiers() throws {
        let json = """
        {
            "profiles": [{
                "name": "Test",
                "selected": true,
                "complex_modifications": {
                    "rules": [{
                        "description": "Ctrl-A to Home",
                        "manipulators": [{
                            "type": "basic",
                            "from": {
                                "key_code": "a",
                                "modifiers": {"mandatory": ["left_control"]}
                            },
                            "to": [{"key_code": "home"}]
                        }]
                    }]
                }
            }]
        }
        """
        let result = try facade.importFromKarabiner(data: Data(json.utf8), collectionName: nil, profileIndex: nil)

        XCTAssertEqual(result.collections.count, 1)
        let mapping = result.collections.first?.mappings.first
        XCTAssertEqual(mapping?.input, "C-a")
    }

    // MARK: - Dual Role

    func testDualRoleImport() throws {
        let json = """
        {
            "profiles": [{
                "name": "Test",
                "selected": true,
                "complex_modifications": {
                    "rules": [{
                        "description": "Caps Lock dual role",
                        "manipulators": [{
                            "type": "basic",
                            "from": {"key_code": "caps_lock"},
                            "to": [{"key_code": "left_control"}],
                            "to_if_alone": [{"key_code": "escape"}]
                        }]
                    }]
                }
            }]
        }
        """
        let result = try facade.importFromKarabiner(data: Data(json.utf8), collectionName: nil, profileIndex: nil)

        XCTAssertEqual(result.collections.count, 1)
        let mapping = result.collections.first?.mappings.first
        XCTAssertNotNil(mapping?.behavior)
        if case .dualRole = mapping?.behavior {
            // Expected
        } else {
            XCTFail("Expected dualRole behavior, got \(String(describing: mapping?.behavior))")
        }
    }

    // MARK: - Macro

    func testMacroImport() throws {
        let json = """
        {
            "profiles": [{
                "name": "Test",
                "selected": true,
                "complex_modifications": {
                    "rules": [{
                        "description": "Macro sequence",
                        "manipulators": [{
                            "type": "basic",
                            "from": {
                                "key_code": "f1",
                                "modifiers": {"mandatory": ["left_command"]}
                            },
                            "to": [
                                {"key_code": "h"},
                                {"key_code": "i"}
                            ]
                        }]
                    }]
                }
            }]
        }
        """
        let result = try facade.importFromKarabiner(data: Data(json.utf8), collectionName: nil, profileIndex: nil)

        XCTAssertEqual(result.collections.count, 1)
        let mapping = result.collections.first?.mappings.first
        XCTAssertNotNil(mapping?.behavior)
        if case let .macro(macro) = mapping?.behavior {
            XCTAssertEqual(macro.outputs, ["h", "i"])
        } else {
            XCTFail("Expected macro behavior")
        }
    }

    // MARK: - Skipped Rules

    func testMouseButtonSkipped() throws {
        let json = """
        {
            "profiles": [{
                "name": "Test",
                "selected": true,
                "complex_modifications": {
                    "rules": [{
                        "description": "Mouse remap",
                        "manipulators": [{
                            "type": "basic",
                            "from": {"pointing_button": "button4"},
                            "to": [{"key_code": "escape"}]
                        }]
                    }]
                }
            }]
        }
        """
        let result = try facade.importFromKarabiner(data: Data(json.utf8), collectionName: nil, profileIndex: nil)

        XCTAssertTrue(result.collections.isEmpty || result.collections.allSatisfy { $0.mappings.isEmpty })
        XCTAssertFalse(result.skippedRules.isEmpty)
        XCTAssertTrue(result.skippedRules.first?.reason.contains("Mouse") == true
            || result.skippedRules.first?.reason.contains("mouse") == true)
    }

    // MARK: - Collection Name Override

    func testCollectionNameMergesAll() throws {
        let json = """
        {
            "profiles": [{
                "name": "Test",
                "selected": true,
                "simple_modifications": [
                    {
                        "from": {"key_code": "caps_lock"},
                        "to": [{"key_code": "escape"}]
                    }
                ],
                "complex_modifications": {
                    "rules": [{
                        "description": "Tab remap",
                        "manipulators": [{
                            "type": "basic",
                            "from": {"key_code": "tab"},
                            "to": [{"key_code": "escape"}]
                        }]
                    }]
                }
            }]
        }
        """
        let result = try facade.importFromKarabiner(data: Data(json.utf8), collectionName: "My Merged Rules", profileIndex: nil)

        XCTAssertEqual(result.collections.count, 1)
        XCTAssertEqual(result.collections.first?.name, "My Merged Rules")
        XCTAssertEqual(result.collections.first?.mappings.count, 2)
    }

    // MARK: - Invalid JSON

    func testInvalidJSONThrows() {
        let data = Data("not json".utf8)

        XCTAssertThrowsError(try facade.importFromKarabiner(data: data, collectionName: nil, profileIndex: nil))
    }

    // MARK: - Complex Modifications File Format

    func testComplexModificationsFileFormat() throws {
        let json = """
        {
            "title": "My Custom Rules",
            "rules": [{
                "description": "A to B",
                "manipulators": [{
                    "type": "basic",
                    "from": {"key_code": "a"},
                    "to": [{"key_code": "b"}]
                }]
            }]
        }
        """
        let result = try facade.importFromKarabiner(data: Data(json.utf8), collectionName: nil, profileIndex: nil)

        XCTAssertEqual(result.profileName, "My Custom Rules")
        XCTAssertEqual(result.collections.count, 1)
        XCTAssertEqual(result.collections.first?.mappings.first?.input, "a")
    }

    // MARK: - Profile Selection

    func testProfileSelection() throws {
        let json = """
        {
            "profiles": [
                {
                    "name": "Work",
                    "selected": false,
                    "simple_modifications": [
                        {
                            "from": {"key_code": "caps_lock"},
                            "to": [{"key_code": "escape"}]
                        }
                    ]
                },
                {
                    "name": "Gaming",
                    "selected": false,
                    "simple_modifications": [
                        {
                            "from": {"key_code": "caps_lock"},
                            "to": [{"key_code": "left_control"}]
                        }
                    ]
                }
            ]
        }
        """
        let result = try facade.importFromKarabiner(data: Data(json.utf8), collectionName: nil, profileIndex: 1)

        XCTAssertEqual(result.profileName, "Gaming")
    }

    // MARK: - Persist Import

    func testImportPersistsCollections() async throws {
        let json = """
        {
            "profiles": [{
                "name": "Default",
                "selected": true,
                "simple_modifications": [
                    {
                        "from": {"key_code": "caps_lock"},
                        "to": [{"key_code": "escape"}]
                    }
                ]
            }]
        }
        """
        let importResult = try facade.importFromKarabiner(data: Data(json.utf8), collectionName: "Persisted Karabiner", profileIndex: nil)

        var imported: [CLIRuleCollection] = []
        for exported in importResult.collections {
            let col = try await facade.importCollection(exported, onConflict: .replace)
            imported.append(col)
        }

        XCTAssertEqual(imported.count, 1)
        XCTAssertEqual(imported.first?.name, "Persisted Karabiner")
        XCTAssertEqual(imported.first?.mappingCount, 1)
    }

    // MARK: - Shell Command Warning

    func testShellCommandProducesLauncherWarning() throws {
        let json = """
        {
            "profiles": [{
                "name": "Test",
                "selected": true,
                "complex_modifications": {
                    "rules": [{
                        "description": "Launch Safari",
                        "manipulators": [{
                            "type": "basic",
                            "from": {
                                "key_code": "s",
                                "modifiers": {"mandatory": ["left_command", "left_shift"]}
                            },
                            "to": [{"shell_command": "open -a Safari"}]
                        }]
                    }]
                }
            }]
        }
        """
        let result = try facade.importFromKarabiner(data: Data(json.utf8), collectionName: nil, profileIndex: nil)

        XCTAssertTrue(result.warnings.contains { $0.contains("launcher") })
    }

    // MARK: - Profile Listing

    func testListKarabinerProfiles() throws {
        let json = """
        {
            "profiles": [
                {"name": "Default", "selected": true},
                {"name": "Gaming", "selected": false}
            ]
        }
        """
        let profiles = try facade.listKarabinerProfiles(data: Data(json.utf8))

        XCTAssertEqual(profiles.count, 2)
        XCTAssertEqual(profiles[0].name, "Default")
        XCTAssertTrue(profiles[0].isSelected)
        XCTAssertEqual(profiles[1].name, "Gaming")
        XCTAssertFalse(profiles[1].isSelected)
    }
}
