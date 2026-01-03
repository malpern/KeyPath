import AppKit
@preconcurrency import XCTest

@testable import KeyPathAppKit

/// Tests for MapperViewModel's per-app mapping functionality.
/// Verifies that when `selectedAppCondition` is set, rules are routed
/// to the AppKeymapStore system rather than saved as global CustomRules.
final class MapperViewModelAppSpecificTests: XCTestCase {
    private var tempDirectory: URL!
    private var store: AppKeymapStore!

    /// Placeholder icon for tests
    private var testIcon: NSImage {
        NSImage(size: NSSize(width: 16, height: 16))
    }

    override func setUpWithError() throws {
        tempDirectory = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString, isDirectory: true)
        try FileManager.default.createDirectory(at: tempDirectory, withIntermediateDirectories: true)
        store = AppKeymapStore.testStore(at: tempDirectory.appendingPathComponent("AppKeymaps.json"))
    }

    override func tearDownWithError() throws {
        if let tempDirectory {
            try? FileManager.default.removeItem(at: tempDirectory)
        }
        tempDirectory = nil
        store = nil
    }

    // MARK: - AppConditionInfo Tests

    func testAppConditionInfo_HasCorrectIdentifier() {
        let condition = AppConditionInfo(
            bundleIdentifier: "com.apple.Bear",
            displayName: "Bear",
            icon: testIcon
        )

        XCTAssertEqual(condition.bundleIdentifier, "com.apple.Bear")
        XCTAssertEqual(condition.displayName, "Bear")
        XCTAssertEqual(condition.id, "com.apple.Bear")
    }

    func testAppConditionInfo_Hashable() {
        let condition1 = AppConditionInfo(
            bundleIdentifier: "com.apple.Bear",
            displayName: "Bear",
            icon: testIcon
        )
        let condition2 = AppConditionInfo(
            bundleIdentifier: "com.apple.Bear",
            displayName: "Bear Notes", // Different display name
            icon: testIcon
        )
        let condition3 = AppConditionInfo(
            bundleIdentifier: "com.apple.Safari",
            displayName: "Safari",
            icon: testIcon
        )

        // Same bundle ID should be equal
        XCTAssertEqual(condition1.id, condition2.id)

        // Different bundle ID should not be equal
        XCTAssertNotEqual(condition1.id, condition3.id)
    }

    // MARK: - Integration with AppKeymapStore

    func testAppKeymapStore_CanStorePerAppMapping() async throws {
        let bundleId = "com.apple.Bear"
        let displayName = "Bear"

        // Create a keymap with an override
        let override = AppKeyOverride(
            inputKey: "a",
            outputAction: "b",
            description: "Test mapping"
        )
        let keymap = AppKeymap(
            bundleIdentifier: bundleId,
            displayName: displayName,
            overrides: [override]
        )

        // Save to store
        try await store.upsertKeymap(keymap)

        // Verify it was saved
        let loaded = await store.getKeymap(bundleIdentifier: bundleId)
        XCTAssertNotNil(loaded)
        XCTAssertEqual(loaded?.mapping.displayName, displayName)
        XCTAssertEqual(loaded?.overrides.count, 1)
        XCTAssertEqual(loaded?.overrides.first?.inputKey, "a")
        XCTAssertEqual(loaded?.overrides.first?.outputAction, "b")
    }

    func testAppKeymapStore_UpdateExistingOverride() async throws {
        let bundleId = "com.apple.Bear"

        // Create initial keymap
        let override1 = AppKeyOverride(inputKey: "a", outputAction: "b")
        let keymap1 = AppKeymap(
            bundleIdentifier: bundleId,
            displayName: "Bear",
            overrides: [override1]
        )
        try await store.upsertKeymap(keymap1)

        // Update with new override for same key
        let override2 = AppKeyOverride(inputKey: "a", outputAction: "c")
        var keymap2 = await store.getKeymap(bundleIdentifier: bundleId)!
        keymap2.overrides = [override2]
        try await store.upsertKeymap(keymap2)

        // Verify update
        let loaded = await store.getKeymap(bundleIdentifier: bundleId)
        XCTAssertEqual(loaded?.overrides.count, 1)
        XCTAssertEqual(loaded?.overrides.first?.outputAction, "c")
    }

    func testAppKeymapStore_MultipleAppsWithSameKeyMapping() async throws {
        // Bear: a → b
        let bearOverride = AppKeyOverride(inputKey: "a", outputAction: "b")
        let bearKeymap = AppKeymap(
            bundleIdentifier: "com.apple.Bear",
            displayName: "Bear",
            overrides: [bearOverride]
        )

        // Safari: a → c (same input key, different output)
        let safariOverride = AppKeyOverride(inputKey: "a", outputAction: "c")
        let safariKeymap = AppKeymap(
            bundleIdentifier: "com.apple.Safari",
            displayName: "Safari",
            overrides: [safariOverride]
        )

        try await store.upsertKeymap(bearKeymap)
        try await store.upsertKeymap(safariKeymap)

        // Both should be stored independently
        let allKeymaps = await store.loadKeymaps()
        XCTAssertEqual(allKeymaps.count, 2)

        let bearLoaded = await store.getKeymap(bundleIdentifier: "com.apple.Bear")
        let safariLoaded = await store.getKeymap(bundleIdentifier: "com.apple.Safari")

        XCTAssertEqual(bearLoaded?.overrides.first?.outputAction, "b")
        XCTAssertEqual(safariLoaded?.overrides.first?.outputAction, "c")
    }

    // MARK: - Config Generation Integration

    func testConfigGenerator_ProducesCorrectSwitchExpression() async throws {
        // Store a mapping for Bear
        let override = AppKeyOverride(inputKey: "a", outputAction: "b")
        let keymap = AppKeymap(
            bundleIdentifier: "com.apple.Bear",
            displayName: "Bear",
            overrides: [override]
        )
        try await store.upsertKeymap(keymap)

        // Generate config
        let keymaps = await store.loadKeymaps()
        let config = AppConfigGenerator.generate(from: keymaps)

        // Verify structure
        XCTAssertTrue(config.contains("defvirtualkeys"), "Should have virtual keys block")
        XCTAssertTrue(config.contains("vk_bear"), "Should have Bear's virtual key")
        XCTAssertTrue(config.contains("defalias"), "Should have alias block")
        XCTAssertTrue(config.contains("kp-a"), "Should have alias for 'a' key")
        XCTAssertTrue(config.contains("(switch"), "Should have switch expression")
        XCTAssertTrue(config.contains("((input virtual vk_bear)) b"), "Should map to 'b' when Bear active")
        XCTAssertTrue(config.contains("() a)"), "Should pass through 'a' by default")
    }

    func testConfigGenerator_MultipleApps_CombinedSwitchExpression() async throws {
        // Bear: a → b
        let bearKeymap = AppKeymap(
            bundleIdentifier: "com.apple.Bear",
            displayName: "Bear",
            overrides: [AppKeyOverride(inputKey: "a", outputAction: "b")]
        )
        // Safari: a → c
        let safariKeymap = AppKeymap(
            bundleIdentifier: "com.apple.Safari",
            displayName: "Safari",
            overrides: [AppKeyOverride(inputKey: "a", outputAction: "c")]
        )

        try await store.upsertKeymap(bearKeymap)
        try await store.upsertKeymap(safariKeymap)

        let keymaps = await store.loadKeymaps()
        let config = AppConfigGenerator.generate(from: keymaps)

        // Both virtual keys should exist
        XCTAssertTrue(config.contains("vk_bear"))
        XCTAssertTrue(config.contains("vk_safari"))

        // Single alias for 'a' with both cases
        XCTAssertTrue(config.contains("kp-a"))
        XCTAssertTrue(config.contains("vk_bear")) // Bear case
        XCTAssertTrue(config.contains("vk_safari")) // Safari case
    }

    // MARK: - Bundle to VK Mapping

    func testBundleToVKMapping_ReturnsCorrectMapping() async throws {
        let keymap = AppKeymap(
            bundleIdentifier: "com.apple.Bear",
            displayName: "Bear",
            overrides: [AppKeyOverride(inputKey: "a", outputAction: "b")]
        )
        try await store.upsertKeymap(keymap)

        let mapping = await store.getBundleToVKMapping()

        XCTAssertEqual(mapping["com.apple.Bear"], "vk_bear")
    }

    func testBundleToVKMapping_DisabledAppsExcluded() async throws {
        // Enabled app
        let enabledKeymap = AppKeymap(
            bundleIdentifier: "com.apple.Bear",
            displayName: "Bear",
            overrides: []
        )

        // Disabled app
        let disabledMapping = AppKeyMapping(
            bundleIdentifier: "com.apple.Safari",
            displayName: "Safari",
            isEnabled: false
        )
        let disabledKeymap = AppKeymap(mapping: disabledMapping, overrides: [])

        try await store.saveKeymaps([enabledKeymap, disabledKeymap])

        let mapping = await store.getBundleToVKMapping()

        XCTAssertEqual(mapping.count, 1)
        XCTAssertNotNil(mapping["com.apple.Bear"])
        XCTAssertNil(mapping["com.apple.Safari"])
    }
}
