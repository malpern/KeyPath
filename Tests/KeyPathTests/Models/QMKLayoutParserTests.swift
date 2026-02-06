@testable import KeyPathAppKit
import Testing

/// Tests for QMK layout JSON parsing
struct QMKLayoutParserTests {
    // MARK: - Sample JSON Data

    /// Minimal valid QMK layout JSON for testing
    static let minimalJSON = """
    {
      "id": "test-keyboard",
      "name": "Test Keyboard",
      "layouts": {
        "default_transform": {
          "layout": [
            { "row": 0, "col": 0, "x": 0, "y": 0 },
            { "row": 0, "col": 1, "x": 1, "y": 0 },
            { "row": 1, "col": 0, "x": 0, "y": 1, "w": 1.5 },
            { "row": 1, "col": 1, "x": 1.5, "y": 1, "h": 2 }
          ]
        }
      }
    }
    """.data(using: .utf8)!

    /// QMK layout with rotated keys (like thumb clusters)
    static let rotatedKeysJSON = """
    {
      "id": "rotated-test",
      "name": "Rotated Test",
      "layouts": {
        "default_transform": {
          "layout": [
            { "row": 0, "col": 0, "x": 0, "y": 0 },
            { "row": 0, "col": 1, "x": 1, "y": 0.5, "r": 15, "rx": 0, "ry": 1 },
            { "row": 0, "col": 2, "x": 2, "y": 0.5, "r": -15, "rx": 3, "ry": 1 }
          ]
        }
      }
    }
    """.data(using: .utf8)!

    // MARK: - Key Mapping Helper

    /// Simple key mapping that returns (keyCode, label) based on row/col
    static func simpleKeyMapping(row: Int, col: Int) -> (keyCode: UInt16, label: String)? {
        // Map (row, col) to a unique keyCode and label
        let keyCode = UInt16(row * 10 + col)
        let label = "\(row),\(col)"
        return (keyCode, label)
    }

    // MARK: - Basic Parsing Tests

    @Test func parseMinimalJSON() {
        let layout = QMKLayoutParser.parse(
            data: Self.minimalJSON,
            keyMapping: Self.simpleKeyMapping
        )

        #expect(layout != nil, "Should successfully parse minimal JSON")
        #expect(layout?.id == "test-keyboard")
        #expect(layout?.name == "Test Keyboard")
        #expect(layout?.keys.count == 4, "Should have 4 keys")
    }

    @Test func parseKeyPositions() throws {
        let layout = try #require(QMKLayoutParser.parse(
            data: Self.minimalJSON,
            keyMapping: Self.simpleKeyMapping
        ))

        // Find key at (0, 0)
        let key00 = layout.keys.first { $0.label == "0,0" }
        #expect(key00 != nil)
        #expect(key00?.x == 0)
        #expect(key00?.y == 0)

        // Find key at (0, 1)
        let key01 = layout.keys.first { $0.label == "0,1" }
        #expect(key01 != nil)
        #expect(key01?.x == 1)
        #expect(key01?.y == 0)
    }

    @Test func parseKeySizes() throws {
        let layout = try #require(QMKLayoutParser.parse(
            data: Self.minimalJSON,
            keyMapping: Self.simpleKeyMapping
        ))

        // Default size keys
        let normalKey = layout.keys.first { $0.label == "0,0" }
        #expect(normalKey?.width == 1.0, "Default width should be 1.0")
        #expect(normalKey?.height == 1.0, "Default height should be 1.0")

        // Wide key (1.5u)
        let wideKey = layout.keys.first { $0.label == "1,0" }
        #expect(wideKey?.width == 1.5, "Should parse custom width")
        #expect(wideKey?.height == 1.0, "Height should default to 1.0")

        // Tall key (2u)
        let tallKey = layout.keys.first { $0.label == "1,1" }
        #expect(tallKey?.width == 1.0, "Width should default to 1.0")
        #expect(tallKey?.height == 2.0, "Should parse custom height")
    }

    @Test func parseRotation() throws {
        let layout = try #require(QMKLayoutParser.parse(
            data: Self.rotatedKeysJSON,
            keyMapping: Self.simpleKeyMapping
        ))

        // Non-rotated key
        let normalKey = layout.keys.first { $0.label == "0,0" }
        #expect(normalKey?.rotation == 0.0, "Default rotation should be 0")

        // Positively rotated key
        let rotatedPos = layout.keys.first { $0.label == "0,1" }
        #expect(rotatedPos?.rotation == 15.0, "Should parse positive rotation")

        // Negatively rotated key
        let rotatedNeg = layout.keys.first { $0.label == "0,2" }
        #expect(rotatedNeg?.rotation == -15.0, "Should parse negative rotation")
    }

    // MARK: - Override Tests

    @Test func parseWithIdOverride() {
        let layout = QMKLayoutParser.parse(
            data: Self.minimalJSON,
            keyMapping: Self.simpleKeyMapping,
            idOverride: "custom-id"
        )

        #expect(layout?.id == "custom-id", "Should use overridden ID")
        #expect(layout?.name == "Test Keyboard", "Name should remain from JSON")
    }

    @Test func parseWithNameOverride() {
        let layout = QMKLayoutParser.parse(
            data: Self.minimalJSON,
            keyMapping: Self.simpleKeyMapping,
            nameOverride: "Custom Name"
        )

        #expect(layout?.id == "test-keyboard", "ID should remain from JSON")
        #expect(layout?.name == "Custom Name", "Should use overridden name")
    }

    @Test func parseWithBothOverrides() {
        let layout = QMKLayoutParser.parse(
            data: Self.minimalJSON,
            keyMapping: Self.simpleKeyMapping,
            idOverride: "new-id",
            nameOverride: "New Name"
        )

        #expect(layout?.id == "new-id")
        #expect(layout?.name == "New Name")
    }

    // MARK: - Key Filtering Tests

    @Test func unmappedKeysAreSkipped() throws {
        /// Key mapping that only maps row 0
        func partialMapping(row: Int, col: Int) -> (keyCode: UInt16, label: String)? {
            guard row == 0 else { return nil }
            return (UInt16(col), "col\(col)")
        }

        let layout = try #require(QMKLayoutParser.parse(
            data: Self.minimalJSON,
            keyMapping: partialMapping
        ))

        #expect(layout.keys.count == 2, "Should only have 2 keys from row 0")
        #expect(layout.keys.allSatisfy { $0.label.hasPrefix("col") })
    }

    // MARK: - Dimension Computation Tests

    @Test func computedDimensions() throws {
        let layout = try #require(QMKLayoutParser.parse(
            data: Self.minimalJSON,
            keyMapping: Self.simpleKeyMapping
        ))

        // Total width should be x + width of rightmost key
        // Key at (1.5, 1) has width 1.0, so totalWidth = 1.5 + 1.0 = 2.5
        #expect(layout.totalWidth == 2.5, "Should compute total width from keys")

        // Total height should be y + height of bottommost key
        // Key at (1.5, 1) has height 2, so totalHeight = 1 + 2 = 3
        #expect(layout.totalHeight == 3.0, "Should compute total height from keys")
    }

    // MARK: - Error Handling Tests

    @Test func invalidJSONReturnsNil() {
        let invalidJSON = "{ invalid json }".data(using: .utf8)!
        let layout = QMKLayoutParser.parse(
            data: invalidJSON,
            keyMapping: Self.simpleKeyMapping
        )

        #expect(layout == nil, "Should return nil for invalid JSON")
    }

    @Test func emptyLayoutsReturnsNil() {
        let emptyLayouts = """
        {
          "id": "empty",
          "name": "Empty",
          "layouts": {}
        }
        """.data(using: .utf8)!

        let layout = QMKLayoutParser.parse(
            data: emptyLayouts,
            keyMapping: Self.simpleKeyMapping
        )

        #expect(layout == nil, "Should return nil when no layouts defined")
    }

    // MARK: - Bundle Loading Tests

    @Test func loadKinesis360FromBundle() {
        // This tests the actual production JSON file
        let layout = PhysicalLayout.kinesisAdvantage360

        #expect(layout.id == "kinesis-360")
        #expect(layout.name == "Kinesis Advantage 360")
        #expect(layout.keys.count > 50, "Should have at least 50 keys")

        // Verify some specific keys exist
        let hasRotatedKeys = layout.keys.contains { $0.rotation != 0 }
        #expect(hasRotatedKeys, "Should have rotated thumb cluster keys")

        let hasTallKeys = layout.keys.contains { $0.height > 1.0 }
        #expect(hasTallKeys, "Should have tall keys (2u)")
    }

    // MARK: - JSON keyCode/label Tests (Tier 1 format)

    @Test func parseJSONWithEmbeddedKeyCodeAndLabel() {
        // JSON with embedded keyCode and label (Tier 1 format)
        let jsonWithKeyCode = """
        {
          "id": "tier1-keyboard",
          "name": "Tier 1 Keyboard",
          "layouts": {
            "default_transform": {
              "layout": [
                { "row": 0, "col": 0, "x": 0, "y": 0, "keyCode": 18, "label": "1" },
                { "row": 0, "col": 1, "x": 1, "y": 0, "keyCode": 0, "label": "a" },
                { "row": 0, "col": 2, "x": 2, "y": 0, "keyCode": 115, "label": "Home" }
              ]
            }
          }
        }
        """.data(using: .utf8)!

        /// Pass a keyMapping function that returns nil - JSON should provide the mappings
        func nilMapping(_: Int, _: Int) -> (keyCode: UInt16, label: String)? {
            nil
        }

        let layout = QMKLayoutParser.parse(
            data: jsonWithKeyCode,
            keyMapping: nilMapping
        )

        #expect(layout != nil, "Should parse JSON with embedded keyCode/label")
        #expect(layout?.keys.count == 3, "Should have 3 keys")

        // Verify keys have correct keyCode and label from JSON
        let key1 = layout?.keys.first { $0.keyCode == 18 }
        #expect(key1 != nil, "Should find key with keyCode 18")
        #expect(key1?.label == "1", "Label should come from JSON")

        let keyA = layout?.keys.first { $0.keyCode == 0 }
        #expect(keyA != nil, "Should find key with keyCode 0")
        #expect(keyA?.label == "a", "Label should come from JSON")

        let keyHome = layout?.keys.first { $0.keyCode == 115 }
        #expect(keyHome != nil, "Should find key with keyCode 115 (Home)")
        #expect(keyHome?.label == "Home", "Label should come from JSON")
    }

    @Test func parseJSONWithMixedKeyCodeAndFallback() {
        // JSON where some keys have embedded keyCode/label, others don't
        let mixedJSON = """
        {
          "id": "mixed-keyboard",
          "name": "Mixed Keyboard",
          "layouts": {
            "default_transform": {
              "layout": [
                { "row": 0, "col": 0, "x": 0, "y": 0, "keyCode": 18, "label": "1" },
                { "row": 0, "col": 1, "x": 1, "y": 0 }
              ]
            }
          }
        }
        """.data(using: .utf8)!

        /// Provide fallback mapping for keys without embedded keyCode/label
        func fallbackMapping(row: Int, col: Int) -> (keyCode: UInt16, label: String)? {
            if row == 0, col == 1 {
                return (19, "2")
            }
            return nil
        }

        let layout = QMKLayoutParser.parse(
            data: mixedJSON,
            keyMapping: fallbackMapping
        )

        #expect(layout != nil, "Should parse mixed JSON")
        #expect(layout?.keys.count == 2, "Should have 2 keys")

        // First key from JSON
        let key1 = layout?.keys.first { $0.keyCode == 18 }
        #expect(key1?.label == "1", "Should use JSON label")

        // Second key from fallback
        let key2 = layout?.keys.first { $0.keyCode == 19 }
        #expect(key2?.label == "2", "Should use fallback label")
    }
}
