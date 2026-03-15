@testable import KeyPathAppKit
@preconcurrency import XCTest

// MARK: - Mock Label Provider

/// Mock that returns whatever labels it's given — including for modifier keyCodes.
/// The real UCKeyTranslateLabelProvider filters modifiers out; the mock does not,
/// which lets us verify that SystemKeyLabelProvider's refresh() handles filtering.
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
    /// Restore the shared provider to its default state after each test
    /// that mutates it, even if assertions fail.
    @MainActor
    private func withRestoredProvider(_ body: (SystemKeyLabelProvider) -> Void) {
        let provider = SystemKeyLabelProvider.shared
        addTeardownBlock { @MainActor in
            provider.labelProvider = UCKeyTranslateLabelProvider()
            provider.refresh()
        }
        body(provider)
    }

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
    func testSystemKeymapFindReturnsNil() {
        // find() returns nil for system — use resolve() from @MainActor UI code
        XCTAssertNil(LogicalKeymap.find(id: LogicalKeymap.systemId))
    }

    @MainActor
    func testSystemKeymapResolveReturnsDynamicKeymap() {
        let keymap = LogicalKeymap.resolve(id: LogicalKeymap.systemId)
        XCTAssertEqual(keymap.id, LogicalKeymap.systemId)
        XCTAssertEqual(keymap.name, "System")
    }

    @MainActor
    func testSystemKeymapDefaultId() {
        // QWERTY remains the default — System is opt-in for QMK/international users
        XCTAssertEqual(LogicalKeymap.defaultId, LogicalKeymap.qwertyUSId)
    }

    @MainActor
    func testStaticKeymapsStillResolve() {
        XCTAssertNotNil(LogicalKeymap.find(id: "qwerty-us"))
        XCTAssertNotNil(LogicalKeymap.find(id: "colemak"))
        XCTAssertNotNil(LogicalKeymap.find(id: "azerty"))
        XCTAssertNotNil(LogicalKeymap.find(id: "qwertz"))
        XCTAssertNotNil(LogicalKeymap.find(id: "dvorak"))
    }

    @MainActor
    func testProviderRefreshWithMock() {
        withRestoredProvider { provider in
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
        }
    }

    @MainActor
    func testModifierKeysExcludedFromLabels() {
        // Inject a mock that WOULD return labels for modifier keyCodes.
        // Verify that after refresh(), those keyCodes are still present
        // because SystemKeyLabelProvider stores whatever the provider returns.
        // The actual exclusion happens in UCKeyTranslateLabelProvider (production),
        // which skips modifier keyCodes entirely so they return empty strings.
        // Here we verify the production provider's exclusion list is correct.
        let modifierKeyCodes: [UInt16] = [54, 55, 56, 57, 58, 59, 60, 61, 62, 63]

        // The production provider should return no labels for modifier keyCodes
        let productionProvider = UCKeyTranslateLabelProvider()
        let results = productionProvider.labels(for: modifierKeyCodes)

        for keyCode in modifierKeyCodes {
            XCTAssertNil(results[keyCode], "Modifier keyCode \(keyCode) should not have labels from UCKeyTranslate")
        }
    }

    @MainActor
    func testEmptyResultsFallThrough() {
        withRestoredProvider { provider in
            provider.labelProvider = MockKeyLabelProvider(mockLabels: [:])
            provider.refresh()

            XCTAssertTrue(provider.currentLabels.isEmpty)
            XCTAssertTrue(provider.currentShiftLabels.isEmpty)

            let keymap = LogicalKeymap.system
            XCTAssertEqual(keymap.id, LogicalKeymap.systemId)
            XCTAssertTrue(keymap.coreLabels.isEmpty)
        }
    }

    @MainActor
    func testSystemKeymapPutsAllLabelsInCore() {
        withRestoredProvider { provider in
            let mock = MockKeyLabelProvider(mockLabels: [
                0: (base: "A", shifted: "A"),
                18: (base: "1", shifted: "!"),
                50: (base: "`", shifted: "~")
            ])

            provider.labelProvider = mock
            provider.refresh()

            let keymap = LogicalKeymap.system
            XCTAssertTrue(keymap.extraLabels.isEmpty, "System keymap should have no extra labels")
            XCTAssertEqual(keymap.coreLabels.count, 3, "All labels should be in coreLabels")
        }
    }
}
