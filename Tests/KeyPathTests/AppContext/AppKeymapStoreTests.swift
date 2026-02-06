@testable import KeyPathAppKit
@preconcurrency import XCTest

final class AppKeymapStoreTests: XCTestCase {
    private var tempDirectory: URL!
    private var store: AppKeymapStore!

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

    // MARK: - Load Tests

    func testLoadReturnsEmptyWhenFileMissing() async {
        let loaded = await store.loadKeymaps()
        XCTAssertTrue(loaded.isEmpty)
    }

    func testLoadGracefullyHandlesCorruptData() async throws {
        let url = tempDirectory.appendingPathComponent("AppKeymaps.json")
        try "not-json".write(to: url, atomically: true, encoding: .utf8)

        // Recreate store to pick up the corrupt file
        store = AppKeymapStore.testStore(at: url)
        await store.invalidateCache()

        let loaded = await store.loadKeymaps()
        XCTAssertTrue(loaded.isEmpty)
    }

    // MARK: - Save/Load Round Trip

    func testSaveAndLoadRoundTrip() async throws {
        let keymaps = [
            AppKeymap(
                bundleIdentifier: "com.apple.Safari",
                displayName: "Safari",
                overrides: [
                    AppKeyOverride(inputKey: "j", outputAction: "down"),
                    AppKeyOverride(inputKey: "k", outputAction: "up")
                ]
            ),
            AppKeymap(
                bundleIdentifier: "com.microsoft.VSCode",
                displayName: "VS Code",
                overrides: [
                    AppKeyOverride(inputKey: "h", outputAction: "left")
                ]
            )
        ]

        try await store.saveKeymaps(keymaps)
        await store.invalidateCache()
        let loaded = await store.loadKeymaps()

        XCTAssertEqual(loaded.count, 2)
        XCTAssertEqual(loaded[0].mapping.bundleIdentifier, "com.apple.Safari")
        XCTAssertEqual(loaded[0].overrides.count, 2)
        XCTAssertEqual(loaded[1].mapping.bundleIdentifier, "com.microsoft.VSCode")
    }

    // MARK: - Upsert Tests

    func testUpsertKeymap_AddsNewKeymap() async throws {
        let keymap = AppKeymap(
            bundleIdentifier: "com.apple.Safari",
            displayName: "Safari",
            overrides: []
        )

        try await store.upsertKeymap(keymap)
        let loaded = await store.loadKeymaps()

        XCTAssertEqual(loaded.count, 1)
        XCTAssertEqual(loaded[0].mapping.bundleIdentifier, "com.apple.Safari")
    }

    func testUpsertKeymap_UpdatesExistingKeymap() async throws {
        // Add initial keymap
        let initial = AppKeymap(
            bundleIdentifier: "com.apple.Safari",
            displayName: "Safari",
            overrides: [AppKeyOverride(inputKey: "j", outputAction: "down")]
        )
        try await store.upsertKeymap(initial)

        // Update with new overrides
        let updated = AppKeymap(
            bundleIdentifier: "com.apple.Safari",
            displayName: "Safari Updated",
            overrides: [
                AppKeyOverride(inputKey: "j", outputAction: "down"),
                AppKeyOverride(inputKey: "k", outputAction: "up")
            ]
        )
        try await store.upsertKeymap(updated)

        let loaded = await store.loadKeymaps()

        XCTAssertEqual(loaded.count, 1) // Still only one keymap
        XCTAssertEqual(loaded[0].overrides.count, 2) // But with updated overrides
    }

    func testUpsertKeymap_HandlesVirtualKeyNameCollision() async throws {
        // Add first Safari keymap
        let safari1 = AppKeymap(
            bundleIdentifier: "com.apple.Safari",
            displayName: "Safari",
            overrides: []
        )
        try await store.upsertKeymap(safari1)

        // Add second app with same display name but different bundle ID
        let safari2 = AppKeymap(
            bundleIdentifier: "com.example.Safari",
            displayName: "Safari",
            overrides: []
        )
        try await store.upsertKeymap(safari2)

        let loaded = await store.loadKeymaps()

        XCTAssertEqual(loaded.count, 2)

        // Virtual key names should be different
        let vkNames = Set(loaded.map(\.mapping.virtualKeyName))
        XCTAssertEqual(vkNames.count, 2, "Virtual key names should be unique")
    }

    // MARK: - Remove Tests

    func testRemoveKeymap_RemovesExistingKeymap() async throws {
        let keymap = AppKeymap(
            bundleIdentifier: "com.apple.Safari",
            displayName: "Safari",
            overrides: []
        )
        try await store.upsertKeymap(keymap)

        try await store.removeKeymap(bundleIdentifier: "com.apple.Safari")
        let loaded = await store.loadKeymaps()

        XCTAssertTrue(loaded.isEmpty)
    }

    func testRemoveKeymap_NoOpForMissingKeymap() async throws {
        // Should not throw
        try await store.removeKeymap(bundleIdentifier: "com.nonexistent.App")
        let loaded = await store.loadKeymaps()
        XCTAssertTrue(loaded.isEmpty)
    }

    // MARK: - Query Tests

    func testGetKeymap_ReturnsCorrectKeymap() async throws {
        let keymap = AppKeymap(
            bundleIdentifier: "com.apple.Safari",
            displayName: "Safari",
            overrides: []
        )
        try await store.upsertKeymap(keymap)

        let found = await store.getKeymap(bundleIdentifier: "com.apple.Safari")
        XCTAssertNotNil(found)
        XCTAssertEqual(found?.mapping.displayName, "Safari")
    }

    func testGetKeymap_ReturnsNilForMissingKeymap() async {
        let found = await store.getKeymap(bundleIdentifier: "com.nonexistent.App")
        XCTAssertNil(found)
    }

    func testGetEnabledKeymaps_FiltersDisabled() async throws {
        let enabledKeymap = AppKeymap(
            bundleIdentifier: "com.apple.Safari",
            displayName: "Safari",
            overrides: []
        )

        let disabledMapping = AppKeyMapping(
            bundleIdentifier: "com.microsoft.VSCode",
            displayName: "VS Code",
            isEnabled: false
        )
        let disabledKeymap = AppKeymap(
            mapping: disabledMapping,
            overrides: []
        )

        try await store.saveKeymaps([enabledKeymap, disabledKeymap])

        let enabled = await store.getEnabledKeymaps()

        XCTAssertEqual(enabled.count, 1)
        XCTAssertEqual(enabled[0].mapping.bundleIdentifier, "com.apple.Safari")
    }

    func testGetBundleToVKMapping_ReturnsCorrectMapping() async throws {
        let keymaps = [
            AppKeymap(
                bundleIdentifier: "com.apple.Safari",
                displayName: "Safari",
                overrides: []
            ),
            AppKeymap(
                bundleIdentifier: "com.microsoft.VSCode",
                displayName: "VS Code",
                overrides: []
            )
        ]
        try await store.saveKeymaps(keymaps)

        let mapping = await store.getBundleToVKMapping()

        XCTAssertEqual(mapping.count, 2)
        XCTAssertEqual(mapping["com.apple.Safari"], "vk_safari")
        XCTAssertEqual(mapping["com.microsoft.VSCode"], "vk_vs_code")
    }

    // MARK: - Cache Tests

    func testCacheIsUsed() async throws {
        let keymap = AppKeymap(
            bundleIdentifier: "com.apple.Safari",
            displayName: "Safari",
            overrides: []
        )
        try await store.saveKeymaps([keymap])

        // First load populates cache
        let loaded1 = await store.loadKeymaps()
        XCTAssertEqual(loaded1.count, 1)

        // Delete file behind the store's back
        try FileManager.default.removeItem(at: tempDirectory.appendingPathComponent("AppKeymaps.json"))

        // Second load should still return cached data
        let loaded2 = await store.loadKeymaps()
        XCTAssertEqual(loaded2.count, 1)
    }

    func testInvalidateCacheForcesReload() async throws {
        let keymap = AppKeymap(
            bundleIdentifier: "com.apple.Safari",
            displayName: "Safari",
            overrides: []
        )
        try await store.saveKeymaps([keymap])

        // First load populates cache
        _ = await store.loadKeymaps()

        // Delete file behind the store's back
        try FileManager.default.removeItem(at: tempDirectory.appendingPathComponent("AppKeymaps.json"))

        // Invalidate cache
        await store.invalidateCache()

        // Now load should see empty (file is gone)
        let loaded = await store.loadKeymaps()
        XCTAssertTrue(loaded.isEmpty)
    }
}
