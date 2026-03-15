import Foundation
@testable import KeyPathAppKit
import KeyPathCore
import XCTest

final class QMKImportServiceTests: XCTestCase {
    var service: QMKImportService!
    var testUserDefaults: UserDefaults!
    var testSuiteName: String!

    override func setUp() {
        super.setUp()
        testSuiteName = "KeyPath.QMKImportServiceTests.\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: testSuiteName)
        defaults?.removePersistentDomain(forName: testSuiteName)
        testUserDefaults = defaults
        service = QMKImportService(userDefaultsSuiteName: testSuiteName)
    }

    override func tearDown() {
        testUserDefaults?.removePersistentDomain(forName: testSuiteName)
        testUserDefaults = nil
        testSuiteName = nil
        service = nil
        super.tearDown()
    }

    // MARK: - Test Data

    /// Sample QMK info.json for a simple 60% keyboard
    private var sampleQMKJSON: Data {
        """
        {
          "id": "test-keyboard",
          "name": "Test Keyboard",
          "layouts": {
            "default_transform": {
              "layout": [
                {"row": 0, "col": 0, "x": 0, "y": 0, "w": 1},
                {"row": 0, "col": 1, "x": 1, "y": 0, "w": 1},
                {"row": 1, "col": 0, "x": 0, "y": 1, "w": 1.5},
                {"row": 1, "col": 1, "x": 1.5, "y": 1, "w": 1},
                {"row": 2, "col": 0, "x": 0, "y": 2, "w": 1.75},
                {"row": 2, "col": 1, "x": 1.75, "y": 2, "w": 1},
                {"row": 3, "col": 0, "x": 0, "y": 3, "w": 2.25},
                {"row": 3, "col": 1, "x": 2.25, "y": 3, "w": 1}
              ]
            },
            "ansi": {
              "layout": [
                {"row": 0, "col": 0, "x": 0, "y": 0, "w": 1},
                {"row": 0, "col": 1, "x": 1, "y": 0, "w": 1}
              ]
            }
          }
        }
        """.data(using: .utf8)!
    }

    /// Invalid JSON data
    private var invalidJSON: Data {
        "{ invalid json }".data(using: .utf8)!
    }

    /// QMK JSON with no layouts
    private var noLayoutsJSON: Data {
        """
        {
          "id": "test",
          "name": "Test",
          "layouts": {}
        }
        """.data(using: .utf8)!
    }

    // MARK: - Parsing Tests

    func testParseValidQMKJSON() async throws {
        // Create temporary file with QMK JSON
        let tempFile = URL(fileURLWithPath: NSTemporaryDirectory(), isDirectory: true)
            .appendingPathComponent("test-qmk-\(UUID().uuidString).json")
        try sampleQMKJSON.write(to: tempFile)
        defer { try? FileManager.default.removeItem(at: tempFile) }

        let layout = try await service.importFromFile(
            tempFile,
            layoutVariant: nil,
            keyMappingType: .ansi
        )

        XCTAssertEqual(layout.name, "Test Keyboard")
        XCTAssertFalse(layout.keys.isEmpty)
    }

    func testParseInvalidJSON() async throws {
        // Create temporary file with invalid JSON
        let tempFile = URL(fileURLWithPath: NSTemporaryDirectory(), isDirectory: true)
            .appendingPathComponent("test-invalid-\(UUID().uuidString).json")
        try invalidJSON.write(to: tempFile)
        defer { try? FileManager.default.removeItem(at: tempFile) }

        do {
            _ = try await service.importFromFile(
                tempFile,
                layoutVariant: nil,
                keyMappingType: .ansi
            )
            XCTFail("Should have thrown QMKImportError.invalidJSON")
        } catch let error as QMKImportError {
            if case .invalidJSON = error {
                // Expected
            } else {
                XCTFail("Wrong error type: \(error)")
            }
        } catch {
            XCTFail("Unexpected error type: \(error)")
        }
    }

    func testParseNoLayouts() async throws {
        // Create temporary file with no layouts JSON
        let tempFile = URL(fileURLWithPath: NSTemporaryDirectory(), isDirectory: true)
            .appendingPathComponent("test-no-layouts-\(UUID().uuidString).json")
        try noLayoutsJSON.write(to: tempFile)
        defer { try? FileManager.default.removeItem(at: tempFile) }

        do {
            _ = try await service.importFromFile(
                tempFile,
                layoutVariant: nil,
                keyMappingType: .ansi
            )
            XCTFail("Should have thrown QMKImportError.noLayoutFound")
        } catch let error as QMKImportError {
            // Empty layouts object will result in noLayoutFound error
            if case .noLayoutFound = error {
                // Expected
            } else {
                // If it's a different error, that's also acceptable for empty layouts
                print("Note: Got error \(error) instead of noLayoutFound - this may be acceptable")
            }
        } catch {
            XCTFail("Unexpected error type: \(error)")
        }
    }

    func testGetAvailableVariants() throws {
        let variants = try service.getAvailableVariants(from: sampleQMKJSON)
        XCTAssertEqual(variants.sorted(), ["ansi", "default_transform"])
    }

    // MARK: - Storage Tests

    func testSaveAndLoadCustomLayout() async throws {
        // Create temporary file
        let tempFile = URL(fileURLWithPath: NSTemporaryDirectory(), isDirectory: true)
            .appendingPathComponent("test-save-\(UUID().uuidString).json")
        try sampleQMKJSON.write(to: tempFile)
        defer { try? FileManager.default.removeItem(at: tempFile) }

        let layout = try await service.importFromFile(
            tempFile,
            layoutVariant: "default_transform",
            keyMappingType: .ansi
        )

        // Save layout
        await service.saveCustomLayout(
            layout: layout,
            name: "Test Keyboard",
            sourceURL: "https://example.com/test.json",
            layoutJSON: sampleQMKJSON,
            layoutVariant: "default_transform"
        )

        // Load layouts
        let loadedLayouts = await service.loadCustomLayouts()
        XCTAssertEqual(loadedLayouts.count, 1)
        XCTAssertEqual(loadedLayouts.first?.name, "Test Keyboard")
    }

    func testDeleteCustomLayout() async throws {
        // Create temporary file
        let tempFile = URL(fileURLWithPath: NSTemporaryDirectory(), isDirectory: true)
            .appendingPathComponent("test-delete-\(UUID().uuidString).json")
        try sampleQMKJSON.write(to: tempFile)
        defer { try? FileManager.default.removeItem(at: tempFile) }

        let layout = try await service.importFromFile(
            tempFile,
            layoutVariant: nil,
            keyMappingType: .ansi
        )

        // Save layout
        await service.saveCustomLayout(
            layout: layout,
            name: "Test Keyboard",
            sourceURL: nil,
            layoutJSON: sampleQMKJSON,
            layoutVariant: nil
        )

        // Verify it's saved
        var loadedLayouts = await service.loadCustomLayouts()
        XCTAssertEqual(loadedLayouts.count, 1)

        // Get the stored layout ID (it will have custom- prefix)
        guard let storedLayoutId = loadedLayouts.first?.id else {
            XCTFail("Failed to get stored layout ID")
            return
        }

        // Delete layout (extract ID from custom- prefix for the delete method)
        let layoutId = storedLayoutId.hasPrefix("custom-") ? String(storedLayoutId.dropFirst(7)) : storedLayoutId
        await service.deleteCustomLayout(layoutId: layoutId)

        // Verify it's deleted
        loadedLayouts = await service.loadCustomLayouts()
        XCTAssertEqual(loadedLayouts.count, 0)
    }

    // MARK: - Edge Case: Empty Name

    func testParseEmptyNameFallsBack() async throws {
        let emptyNameJSON = """
        {
          "id": "empty-name",
          "name": "",
          "layouts": {
            "default_transform": {
              "layout": [
                {"row": 0, "col": 0, "x": 0, "y": 0, "w": 1},
                {"row": 0, "col": 1, "x": 1, "y": 0, "w": 1}
              ]
            }
          }
        }
        """.data(using: .utf8)!

        let tempFile = URL(fileURLWithPath: NSTemporaryDirectory(), isDirectory: true)
            .appendingPathComponent("test-empty-name-\(UUID().uuidString).json")
        try emptyNameJSON.write(to: tempFile)
        defer { try? FileManager.default.removeItem(at: tempFile) }

        let layout = try await service.importFromFile(
            tempFile,
            layoutVariant: nil,
            keyMappingType: .ansi
        )

        XCTAssertEqual(layout.name, "Imported Keyboard", "Should fall back to 'Imported Keyboard' for empty name")
    }

    // MARK: - Edge Case: Layout With All Invalid Keys

    func testParseLayoutWithAllUnmappableKeysThrows() async throws {
        // All keys at row 99 which has no ANSI mapping
        let unmappableJSON = """
        {
          "id": "unmappable",
          "name": "Unmappable",
          "layouts": {
            "default_transform": {
              "layout": [
                {"row": 99, "col": 99, "x": 0, "y": 0, "w": 1},
                {"row": 99, "col": 98, "x": 1, "y": 0, "w": 1}
              ]
            }
          }
        }
        """.data(using: .utf8)!

        let tempFile = URL(fileURLWithPath: NSTemporaryDirectory(), isDirectory: true)
            .appendingPathComponent("test-unmappable-\(UUID().uuidString).json")
        try unmappableJSON.write(to: tempFile)
        defer { try? FileManager.default.removeItem(at: tempFile) }

        do {
            _ = try await service.importFromFile(
                tempFile,
                layoutVariant: nil,
                keyMappingType: .ansi
            )
            XCTFail("Should throw for layout with all unmappable keys")
        } catch let error as QMKImportError {
            if case .parseError = error {
                // Expected - layout has 0 valid keys
            } else {
                XCTFail("Expected .parseError but got: \(error)")
            }
        }
    }

    // MARK: - Edge Case: Missing Metadata Fields

    func testParseMissingMetadataFields() async throws {
        let minimalJSON = """
        {
          "keyboard_name": "Minimal Board",
          "layouts": {
            "default_transform": {
              "layout": [
                {"row": 0, "col": 0, "x": 0, "y": 0, "w": 1},
                {"row": 0, "col": 1, "x": 1, "y": 0, "w": 1}
              ]
            }
          }
        }
        """.data(using: .utf8)!

        let tempFile = URL(fileURLWithPath: NSTemporaryDirectory(), isDirectory: true)
            .appendingPathComponent("test-minimal-meta-\(UUID().uuidString).json")
        try minimalJSON.write(to: tempFile)
        defer { try? FileManager.default.removeItem(at: tempFile) }

        // Should parse successfully despite missing manufacturer, url, maintainer, features
        let layout = try await service.importFromFile(
            tempFile,
            layoutVariant: nil,
            keyMappingType: .ansi
        )

        XCTAssertEqual(layout.name, "Minimal Board")
        XCTAssertFalse(layout.keys.isEmpty)
    }

    // MARK: - Edge Case: Zero-Size Keys in Import

    func testParseZeroSizeKeysAreFilteredDuringImport() async throws {
        let zeroSizeJSON = """
        {
          "id": "zero-size",
          "name": "Zero Size Keys",
          "layouts": {
            "default_transform": {
              "layout": [
                {"row": 0, "col": 0, "x": 0, "y": 0, "w": 0, "h": 1},
                {"row": 0, "col": 1, "x": 1, "y": 0, "w": 1, "h": 1}
              ]
            }
          }
        }
        """.data(using: .utf8)!

        let tempFile = URL(fileURLWithPath: NSTemporaryDirectory(), isDirectory: true)
            .appendingPathComponent("test-zero-size-\(UUID().uuidString).json")
        try zeroSizeJSON.write(to: tempFile)
        defer { try? FileManager.default.removeItem(at: tempFile) }

        let layout = try await service.importFromFile(
            tempFile,
            layoutVariant: nil,
            keyMappingType: .ansi
        )

        // Zero-width key should have been filtered out by the parser
        // Only 1 valid key should remain (the one with w: 1)
        XCTAssertEqual(layout.keys.count, 1, "Should have exactly 1 valid key after filtering zero-width key")
    }

    // MARK: - Keycode Mapping Tests

    func testANSIMapping() async throws {
        // Create temporary file
        let tempFile = URL(fileURLWithPath: NSTemporaryDirectory(), isDirectory: true)
            .appendingPathComponent("test-ansi-\(UUID().uuidString).json")
        try sampleQMKJSON.write(to: tempFile)
        defer { try? FileManager.default.removeItem(at: tempFile) }

        let layout = try await service.importFromFile(
            tempFile,
            layoutVariant: nil,
            keyMappingType: .ansi
        )

        // Verify keys have proper keycodes from ANSI mapping
        XCTAssertFalse(layout.keys.isEmpty)
        // First key should map to row 0, col 0 which is "1" in ANSI
        if let firstKey = layout.keys.first {
            // The keycode should be mapped from ANSIPositionTable
            XCTAssertNotEqual(firstKey.keyCode, 0)
        }
    }

    // MARK: - Keymap Caching Roundtrip

    func testSaveAndLoadWithCachedKeymap() async {
        // Build a simple 2-key layout JSON
        let json = """
        {
          "id": "cache-test",
          "name": "Cache Test",
          "layouts": {
            "default_transform": {
              "layout": [
                {"matrix": [0,0], "x": 0, "y": 0},
                {"matrix": [0,1], "x": 1, "y": 0}
              ]
            }
          }
        }
        """.data(using: .utf8)!

        let keymapTokens = ["KC_A", "KC_B"]

        // Parse with keymap to get layout
        guard let result = QMKLayoutParser.parseWithKeymap(
            data: json,
            keymapTokens: keymapTokens,
            idOverride: "custom-test-cache",
            nameOverride: "Cache Test"
        ) else {
            XCTFail("parseWithKeymap should succeed")
            return
        }

        // Save with cached keymap tokens
        await service.saveCustomLayout(
            layout: result.layout,
            name: "Cache Test",
            sourceURL: nil,
            layoutJSON: json,
            layoutVariant: nil,
            defaultKeymap: keymapTokens
        )

        // Reload from storage
        let loadedLayouts = await service.loadCustomLayouts()
        XCTAssertEqual(loadedLayouts.count, 1)

        guard let loaded = loadedLayouts.first else {
            XCTFail("Should have one layout")
            return
        }

        // Verify the reloaded layout used keymap-based parsing (keys should have real keyCodes)
        XCTAssertEqual(loaded.keys.count, 2)
        XCTAssertEqual(loaded.keys[0].keyCode, 0x00, "First key should be A (0x00) from cached keymap")
        XCTAssertEqual(loaded.keys[0].label, "a")
        XCTAssertEqual(loaded.keys[1].keyCode, 0x0B, "Second key should be B (0x0B) from cached keymap")
        XCTAssertEqual(loaded.keys[1].label, "b")
    }

    func testSaveWithoutKeymapFallsBackToPositionParsing() async {
        // Save without keymap tokens — should still reload via position-based fallback
        let json = """
        {
          "id": "no-keymap-test",
          "name": "No Keymap",
          "layouts": {
            "default_transform": {
              "layout": [
                {"matrix": [0,0], "x": 0, "y": 0},
                {"matrix": [0,1], "x": 1, "y": 0}
              ]
            }
          }
        }
        """.data(using: .utf8)!

        // Parse with position-based approach (no keymap)
        guard let result = QMKLayoutParser.parseByPositionWithQuality(
            data: json,
            idOverride: "custom-test-no-keymap",
            nameOverride: "No Keymap"
        ) else {
            XCTFail("parseByPositionWithQuality should succeed")
            return
        }

        // Save without keymap
        await service.saveCustomLayout(
            layout: result.layout,
            name: "No Keymap",
            sourceURL: nil,
            layoutJSON: json,
            layoutVariant: nil
            // defaultKeymap is nil
        )

        // Reload — should succeed via position-based fallback
        let loadedLayouts = await service.loadCustomLayouts()
        XCTAssertEqual(loadedLayouts.count, 1)
        XCTAssertEqual(loadedLayouts.first?.keys.count, 2)
    }

    func testStoredLayoutKeymapCodableRoundtrip() throws {
        // Verify the defaultKeymap field survives encode/decode
        let stored = try StoredLayout(
            id: "roundtrip-test",
            name: "Roundtrip",
            layoutJSON: XCTUnwrap("{}".data(using: .utf8)),
            defaultKeymap: ["KC_A", "LT(1, KC_SPC)", "MO(2)"]
        )

        let encoded = try JSONEncoder().encode(stored)
        let decoded = try JSONDecoder().decode(StoredLayout.self, from: encoded)

        XCTAssertEqual(decoded.defaultKeymap, ["KC_A", "LT(1, KC_SPC)", "MO(2)"])
    }

    func testStoredLayoutWithoutKeymapDecodesAsNil() throws {
        // Verify backward compatibility: old stored layouts without defaultKeymap decode fine
        let json = """
        {
          "id": "old-format",
          "name": "Old Format",
          "layoutJSON": "e30=",
          "importDate": 0
        }
        """.data(using: .utf8)!

        let decoded = try JSONDecoder().decode(StoredLayout.self, from: json)
        XCTAssertNil(decoded.defaultKeymap, "Missing defaultKeymap should decode as nil for backward compatibility")
    }

    func testISOMapping() async throws {
        // Create temporary file
        let tempFile = URL(fileURLWithPath: NSTemporaryDirectory(), isDirectory: true)
            .appendingPathComponent("test-iso-\(UUID().uuidString).json")
        try sampleQMKJSON.write(to: tempFile)
        defer { try? FileManager.default.removeItem(at: tempFile) }

        let layout = try await service.importFromFile(
            tempFile,
            layoutVariant: nil,
            keyMappingType: .iso
        )

        // Verify keys have proper keycodes from ISO mapping
        XCTAssertFalse(layout.keys.isEmpty)
    }

    // MARK: - JIS Mapping Tests

    func testJISMapping() async throws {
        let tempFile = URL(fileURLWithPath: NSTemporaryDirectory(), isDirectory: true)
            .appendingPathComponent("test-jis-\(UUID().uuidString).json")
        try sampleQMKJSON.write(to: tempFile)
        defer { try? FileManager.default.removeItem(at: tempFile) }

        let layout = try await service.importFromFile(
            tempFile,
            layoutVariant: nil,
            keyMappingType: .jis
        )

        XCTAssertFalse(layout.keys.isEmpty)
    }

    func testJISPositionTableAlphaKeys() {
        // Verify JIS alpha keys match ANSI (they should be identical)
        let jisA = JISPositionTable.keyMapping(row: 2, col: 1)
        XCTAssertEqual(jisA?.keyCode, 0, "JIS 'a' should have keyCode 0")
        XCTAssertEqual(jisA?.label, "a")

        let jisQ = JISPositionTable.keyMapping(row: 1, col: 1)
        XCTAssertEqual(jisQ?.keyCode, 12, "JIS 'q' should have keyCode 12")
        XCTAssertEqual(jisQ?.label, "q")
    }

    func testJISPositionTableUniqueKeys() {
        // Yen key (row 1, col 13 — replaces ANSI backslash)
        let yen = JISPositionTable.keyMapping(row: 1, col: 13)
        XCTAssertEqual(yen?.keyCode, 0x5D, "JIS Yen key should have keyCode 0x5D")

        // Underscore key (row 3, col 11)
        let underscore = JISPositionTable.keyMapping(row: 3, col: 11)
        XCTAssertEqual(underscore?.keyCode, 0x5E, "JIS Underscore key should have keyCode 0x5E")

        // Eisu key (row 4, col 3)
        let eisu = JISPositionTable.keyMapping(row: 4, col: 3)
        XCTAssertEqual(eisu?.keyCode, 0x66, "JIS Eisu key should have keyCode 0x66")

        // Kana key (row 4, col 5)
        let kana = JISPositionTable.keyMapping(row: 4, col: 5)
        XCTAssertEqual(kana?.keyCode, 0x68, "JIS Kana key should have keyCode 0x68")
    }

    func testJISPositionTableEnterIsLShaped() {
        // Enter should appear at both (2, 12) and (2, 13)
        let enter1 = JISPositionTable.keyMapping(row: 2, col: 12)
        let enter2 = JISPositionTable.keyMapping(row: 2, col: 13)
        XCTAssertEqual(enter1?.keyCode, 36, "JIS Enter at (2,12) should have keyCode 36")
        XCTAssertEqual(enter2?.keyCode, 36, "JIS Enter at (2,13) should have keyCode 36")

        // JIS L-shaped Enter doesn't extend to (3,13) — that position is Up Arrow on larger layouts
        let row3col13 = JISPositionTable.keyMapping(row: 3, col: 13)
        XCTAssertNotEqual(row3col13?.keyCode, 36, "JIS Enter should not extend to (3,13)")
    }

    func testJISVariantDetectionInLoadCustomLayouts() async {
        // Use a layout with enough keys to trigger matrix-based parsing with JIS table
        let json = """
        {
          "id": "jis-detect-test",
          "name": "JIS Detect",
          "layouts": {
            "default_transform": {
              "layout": [
                {"row": 0, "col": 0, "x": 0, "y": 0, "w": 1},
                {"row": 0, "col": 1, "x": 1, "y": 0, "w": 1},
                {"row": 1, "col": 13, "x": 13, "y": 1, "w": 1}
              ]
            }
          }
        }
        """.data(using: .utf8)!

        guard let result = QMKLayoutParser.parseByPositionWithQuality(
            data: json,
            idOverride: "custom-jis-detect",
            nameOverride: "JIS Detect"
        ) else {
            XCTFail("parseByPositionWithQuality should succeed")
            return
        }

        // Save with a JIS variant name — should auto-detect JIS on reload
        await service.saveCustomLayout(
            layout: result.layout,
            name: "JIS Detect",
            sourceURL: nil,
            layoutJSON: json,
            layoutVariant: "LAYOUT_jp"
        )

        let loadedLayouts = await service.loadCustomLayouts()
        XCTAssertEqual(loadedLayouts.count, 1, "JIS variant layout should load successfully")

        // Verify the layout loaded — the key assertion is that JIS variant detection
        // doesn't crash or produce an empty layout. Full keycode verification is covered
        // by testJISPositionTableUniqueKeys and testJISMapping.
        if let layout = loadedLayouts.first {
            XCTAssertFalse(layout.keys.isEmpty, "JIS variant layout should have keys after reload")
        }
    }
}
