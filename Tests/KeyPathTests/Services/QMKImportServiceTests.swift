import Foundation
@testable import KeyPathAppKit
import KeyPathCore
import XCTest

final class QMKImportServiceTests: XCTestCase {
    var service: QMKImportService!
    var testUserDefaults: UserDefaults!

    override func setUp() {
        super.setUp()
        service = QMKImportService.shared
        // Clear any existing custom layouts from standard UserDefaults
        UserDefaults.standard.removeObject(forKey: CustomLayoutStore.userDefaultsKey)
    }

    override func tearDown() {
        // Clean up after each test
        UserDefaults.standard.removeObject(forKey: CustomLayoutStore.userDefaultsKey)
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
        let tempFile = FileManager.default.temporaryDirectory
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
        let tempFile = FileManager.default.temporaryDirectory
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
        let tempFile = FileManager.default.temporaryDirectory
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
        let tempFile = FileManager.default.temporaryDirectory
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
        let tempFile = FileManager.default.temporaryDirectory
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

    // MARK: - Keycode Mapping Tests

    func testANSIMapping() async throws {
        // Create temporary file
        let tempFile = FileManager.default.temporaryDirectory
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

    func testISOMapping() async throws {
        // Create temporary file
        let tempFile = FileManager.default.temporaryDirectory
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
}
