@testable import KeyPathAppKit
import XCTest

final class CustomRuleModelTests: XCTestCase {
    // MARK: - displayTitle

    func testDisplayTitle_WithTitle_ReturnsTitle() {
        let rule = CustomRule(title: "My Rule", input: "caps", action: .keystroke(key: "esc"))
        XCTAssertEqual(rule.displayTitle, "My Rule")
    }

    func testDisplayTitle_EmptyTitle_ReturnsInputArrowOutput() {
        let rule = CustomRule(title: "", input: "caps", action: .keystroke(key: "esc"))
        XCTAssertEqual(rule.displayTitle, "caps → esc")
    }

    func testDisplayTitle_WhitespaceTitle_ReturnsInputArrowOutput() {
        let rule = CustomRule(title: "   ", input: "a", action: .keystroke(key: "b"))
        XCTAssertEqual(rule.displayTitle, "a → b")
    }

    // MARK: - summaryText

    func testSummaryText_WithNotes_ReturnsNotes() {
        let rule = CustomRule(input: "a", action: .keystroke(key: "b"), notes: "Custom note")
        XCTAssertEqual(rule.summaryText, "Custom note")
    }

    func testSummaryText_EmptyNotes_ReturnsFallback() {
        let rule = CustomRule(input: "caps", action: .keystroke(key: "esc"), notes: "")
        XCTAssertTrue(rule.summaryText.contains("Maps"))
        XCTAssertTrue(rule.summaryText.contains("caps"))
    }

    func testSummaryText_NilNotes_ReturnsFallback() {
        let rule = CustomRule(input: "x", action: .keystroke(key: "y"))
        XCTAssertTrue(rule.summaryText.contains("Maps"))
    }

    // MARK: - asKeyMapping

    func testAsKeyMapping_CopiesFields() {
        let id = UUID()
        let rule = CustomRule(
            id: id,
            input: "a",
            action: .keystroke(key: "b"),
            shiftedOutput: "B",
            behavior: .dualRole(DualRoleBehavior.homeRowMod(letter: "a", modifier: "lctl"))
        )

        let mapping = rule.asKeyMapping()
        XCTAssertEqual(mapping.id, id)
        XCTAssertEqual(mapping.input, "a")
        XCTAssertEqual(mapping.action, .keystroke(key: "b"))
        XCTAssertEqual(mapping.shiftedOutput, "B")
        XCTAssertNotNil(mapping.behavior)
    }

    // MARK: - asRuleCollection

    func testAsRuleCollection_CreatesMatchingCollection() {
        let rule = CustomRule(
            title: "Caps Remap",
            input: "caps",
            action: .keystroke(key: "esc"),
            isEnabled: true
        )

        let collection = rule.asRuleCollection()
        XCTAssertEqual(collection.id, rule.id)
        XCTAssertEqual(collection.name, "Caps Remap")
        XCTAssertTrue(collection.isEnabled)
        XCTAssertEqual(collection.category, .custom)
        XCTAssertEqual(collection.mappings.count, 1)
    }

    // MARK: - Sequence extensions

    func testEnabledMappings_FiltersDisabled() {
        var enabled = CustomRule(input: "a", action: .keystroke(key: "b"))
        enabled.isEnabled = true
        var disabled = CustomRule(input: "c", action: .keystroke(key: "d"))
        disabled.isEnabled = false

        let mappings = [enabled, disabled].enabledMappings()
        XCTAssertEqual(mappings.count, 1)
        XCTAssertEqual(mappings[0].input, "a")
    }

    func testAsRuleCollections_MapsAll() {
        let rules = [
            CustomRule(input: "a", action: .keystroke(key: "b")),
            CustomRule(input: "c", action: .keystroke(key: "d")),
        ]
        let collections = rules.asRuleCollections()
        XCTAssertEqual(collections.count, 2)
    }

    // MARK: - Codable round-trip

    func testCodable_RoundTrip_SimpleRule() throws {
        let original = CustomRule(
            title: "Test",
            input: "caps",
            action: .keystroke(key: "esc"),
            isEnabled: true,
            notes: "A note"
        )

        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        let data = try encoder.encode(original)

        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        let decoded = try decoder.decode(CustomRule.self, from: data)

        XCTAssertEqual(decoded.id, original.id)
        XCTAssertEqual(decoded.input, "caps")
        XCTAssertEqual(decoded.action, .keystroke(key: "esc"))
        XCTAssertEqual(decoded.title, "Test")
        XCTAssertEqual(decoded.notes, "A note")
        XCTAssertTrue(decoded.isEnabled)
    }

    func testCodable_LegacyWithoutTargetLayer_DefaultsToBase() throws {
        let json = """
        {
            "id": "11111111-1111-1111-1111-111111111111",
            "title": "Test",
            "input": "caps",
            "action": {"keystroke":{"key":"esc"}},
            "isEnabled": true,
            "createdAt": 0
        }
        """
        let decoder = JSONDecoder()
        let rule = try decoder.decode(CustomRule.self, from: json.data(using: .utf8)!)
        XCTAssertEqual(rule.targetLayer, .base)
    }

    func testCodable_WithTargetLayer() throws {
        let original = CustomRule(
            input: "h",
            action: .keystroke(key: "left"),
            targetLayer: .navigation
        )

        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        let data = try encoder.encode(original)

        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        let decoded = try decoder.decode(CustomRule.self, from: data)
        XCTAssertEqual(decoded.targetLayer, .navigation)
    }

    func testCodable_WithPackSource() throws {
        var original = CustomRule(input: "a", action: .keystroke(key: "b"))
        original.packSource = "com.keypath.pack.test"

        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        let data = try encoder.encode(original)

        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        let decoded = try decoder.decode(CustomRule.self, from: data)
        XCTAssertEqual(decoded.packSource, "com.keypath.pack.test")
    }

    func testCodable_WithDeviceOverrides() throws {
        let override = DeviceKeyOverride(deviceHash: "0x1234ABCD", output: .keystroke(key: "x"))
        var original = CustomRule(input: "a", action: .keystroke(key: "b"))
        original.deviceOverrides = [override]

        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        let data = try encoder.encode(original)

        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        let decoded = try decoder.decode(CustomRule.self, from: data)
        XCTAssertEqual(decoded.deviceOverrides?.count, 1)
        XCTAssertEqual(decoded.deviceOverrides?[0].deviceHash, "0x1234ABCD")
    }

    // MARK: - Equality

    func testEquality_SameID_SameDate_Equal() {
        let id = UUID()
        let date = Date(timeIntervalSince1970: 1_700_000_000)
        let a = CustomRule(id: id, input: "a", action: .keystroke(key: "b"), createdAt: date)
        let b = CustomRule(id: id, input: "a", action: .keystroke(key: "b"), createdAt: date)
        XCTAssertEqual(a, b)
    }

    func testEquality_DifferentID_NotEqual() {
        let a = CustomRule(input: "a", action: .keystroke(key: "b"))
        let b = CustomRule(input: "a", action: .keystroke(key: "b"))
        XCTAssertNotEqual(a, b)
    }

    // MARK: - Init defaults

    func testInit_Defaults() {
        let rule = CustomRule(input: "x", action: .keystroke(key: "y"))
        XCTAssertTrue(rule.isEnabled)
        XCTAssertEqual(rule.title, "")
        XCTAssertNil(rule.notes)
        XCTAssertNil(rule.behavior)
        XCTAssertEqual(rule.targetLayer, .base)
        XCTAssertNil(rule.deviceOverrides)
        XCTAssertNil(rule.packSource)
        XCTAssertNil(rule.shiftedOutput)
    }
}
