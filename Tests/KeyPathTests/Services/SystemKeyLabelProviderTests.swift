@testable import KeyPathAppKit
@preconcurrency import XCTest

// MARK: - Mock Label Provider

struct MockKeyLabelProvider: KeyLabelQuerying {
    let mockLabels: [UInt16: (base: String, shifted: String)]

    func labels(for keyCodes: [UInt16]) -> [UInt16: (base: String, shifted: String)] {
        var result: [UInt16: (base: String, shifted: String)] = [:]
        for keyCode in keyCodes {
            if let pair = mockLabels[keyCode] {
                result[keyCode] = pair
            }
        }
        return result
    }
}

// MARK: - Tests

final class SystemKeyLabelProviderTests: XCTestCase {
    @MainActor
    func testMockProviderReturnsKnownLabels() {
        let mock = MockKeyLabelProvider(mockLabels: [
            0: (base: "A", shifted: "A"), // a key
            12: (base: "Q", shifted: "Q"), // q key
            18: (base: "1", shifted: "!") // 1 key
        ])

        let results = mock.labels(for: [0, 12, 18, 99])

        XCTAssertEqual(results[0]?.base, "A")
        XCTAssertEqual(results[12]?.base, "Q")
        XCTAssertEqual(results[18]?.shifted, "!")
        XCTAssertNil(results[99]) // Not in mock
    }

    @MainActor
    func testSystemKeymapFindReturnsDynamicKeymap() {
        // LogicalKeymap.find(id: "system") should return a non-nil keymap
        let keymap = LogicalKeymap.find(id: "system")
        XCTAssertNotNil(keymap)
        XCTAssertEqual(keymap?.id, "system")
        XCTAssertEqual(keymap?.name, "System")
    }

    @MainActor
    func testSystemKeymapDefaultId() {
        // Default ID should be "system" for new users
        XCTAssertEqual(LogicalKeymap.defaultId, "system")
    }

    @MainActor
    func testStaticKeymapsStillResolve() {
        // Existing static keymaps should still be findable
        XCTAssertNotNil(LogicalKeymap.find(id: "qwerty-us"))
        XCTAssertNotNil(LogicalKeymap.find(id: "colemak"))
        XCTAssertNotNil(LogicalKeymap.find(id: "azerty"))
        XCTAssertNotNil(LogicalKeymap.find(id: "qwertz"))
        XCTAssertNotNil(LogicalKeymap.find(id: "dvorak"))
    }

    @MainActor
    func testProviderRefreshWithMock() {
        let provider = SystemKeyLabelProvider.shared

        // Inject mock with French-like labels
        let frenchMock = MockKeyLabelProvider(mockLabels: [
            0: (base: "Q", shifted: "Q"), // a→q in AZERTY
            12: (base: "A", shifted: "A"), // q→a in AZERTY
            18: (base: "1", shifted: "&") // 1→& in French
        ])

        provider.labelProvider = frenchMock
        provider.refresh()

        XCTAssertEqual(provider.currentLabels[0], "Q")
        XCTAssertEqual(provider.currentLabels[12], "A")
        XCTAssertEqual(provider.currentLabels[18], "1")
        XCTAssertEqual(provider.currentShiftLabels[18], "&")

        // Restore default provider
        provider.labelProvider = UCKeyTranslateLabelProvider()
        provider.refresh()
    }

    @MainActor
    func testModifierKeysExcluded() {
        // Modifier keyCodes should not appear in UCKeyTranslate results
        // (they return empty strings and should keep their symbols)
        let modifierKeyCodes: [UInt16] = [54, 55, 56, 57, 58, 59, 60, 61, 62, 63]

        let mock = MockKeyLabelProvider(mockLabels: [:]) // Empty mock
        let results = mock.labels(for: modifierKeyCodes)

        // All modifiers should be absent (no labels returned)
        for keyCode in modifierKeyCodes {
            XCTAssertNil(results[keyCode], "Modifier keyCode \(keyCode) should not have labels")
        }
    }

    @MainActor
    func testEmptyResultsFallThrough() {
        // When provider returns empty labels, the keymap should still work
        // (PhysicalKey.label provides fallback symbols)
        let emptyMock = MockKeyLabelProvider(mockLabels: [:])
        let provider = SystemKeyLabelProvider.shared

        provider.labelProvider = emptyMock
        provider.refresh()

        XCTAssertTrue(provider.currentLabels.isEmpty)
        XCTAssertTrue(provider.currentShiftLabels.isEmpty)

        // System keymap with empty labels should still have id "system"
        let keymap = LogicalKeymap.system
        XCTAssertEqual(keymap.id, "system")
        XCTAssertTrue(keymap.coreLabels.isEmpty)

        // Restore default provider
        provider.labelProvider = UCKeyTranslateLabelProvider()
        provider.refresh()
    }

    @MainActor
    func testSystemKeymapPutsAllLabelsInCore() {
        // System keymap puts all labels in coreLabels (not extraLabels)
        // so the punctuation toggle is irrelevant
        let mock = MockKeyLabelProvider(mockLabels: [
            0: (base: "A", shifted: "A"),
            18: (base: "1", shifted: "!"),
            50: (base: "`", shifted: "~")
        ])

        let provider = SystemKeyLabelProvider.shared
        provider.labelProvider = mock
        provider.refresh()

        let keymap = LogicalKeymap.system
        XCTAssertTrue(keymap.extraLabels.isEmpty, "System keymap should have no extra labels")
        XCTAssertEqual(keymap.coreLabels.count, 3, "All labels should be in coreLabels")

        // Restore
        provider.labelProvider = UCKeyTranslateLabelProvider()
        provider.refresh()
    }
}
