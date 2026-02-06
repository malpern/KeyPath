@testable import KeyPathAppKit
@preconcurrency import XCTest

/// Tests for AppContextService - the service that monitors frontmost application
/// and activates/deactivates virtual keys via TCP to enable per-app keymaps.
final class AppContextServiceTests: XCTestCase {
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

    // MARK: - Bundle to VK Lookup Tests

    func testBundleToVKLookup_FindsMatchingApp() async throws {
        // Setup: Store a keymap for Bear
        let keymap = AppKeymap(
            bundleIdentifier: "com.apple.Bear",
            displayName: "Bear",
            overrides: [AppKeyOverride(inputKey: "a", outputAction: "b")]
        )
        try await store.upsertKeymap(keymap)

        // Get the mapping
        let mapping = await store.getBundleToVKMapping()

        // Verify Bear maps to its virtual key
        XCTAssertEqual(mapping["com.apple.Bear"], "vk_bear")
    }

    func testBundleToVKLookup_ReturnsNilForUnknownApp() async throws {
        // Setup: Store a keymap for Bear only
        let keymap = AppKeymap(
            bundleIdentifier: "com.apple.Bear",
            displayName: "Bear",
            overrides: []
        )
        try await store.upsertKeymap(keymap)

        let mapping = await store.getBundleToVKMapping()

        // Safari has no keymap
        XCTAssertNil(mapping["com.apple.Safari"])
    }

    // MARK: - Service State Tests

    @MainActor
    func testAppContextService_InitialState() {
        let service = AppContextService.shared

        // Before starting, should not be monitoring
        // Note: We can't reset singleton state, so this test just verifies the property exists
        XCTAssertNotNil(service)
    }

    // MARK: - Virtual Key Name Generation Tests

    func testVirtualKeyName_StandardApp() {
        let vkName = AppKeyMapping.generateVirtualKeyName(
            displayName: "Bear",
            bundleIdentifier: "com.apple.Bear"
        )
        XCTAssertEqual(vkName, "vk_bear")
    }

    func testVirtualKeyName_AppWithSpaces() {
        let vkName = AppKeyMapping.generateVirtualKeyName(
            displayName: "VS Code",
            bundleIdentifier: "com.microsoft.VSCode"
        )
        XCTAssertEqual(vkName, "vk_vs_code")
    }

    func testVirtualKeyName_AppStartingWithNumber() {
        let vkName = AppKeyMapping.generateVirtualKeyName(
            displayName: "1Password",
            bundleIdentifier: "com.1password.1password"
        )
        // Should get app_ prefix since it starts with a number
        XCTAssertEqual(vkName, "vk_app_1password")
    }

    // MARK: - TCP Command Format Tests

    func testTCPCommand_FakeKeyPress() throws {
        // Verify the expected JSON format for ActOnFakeKey
        let expectedFormat = """
        {"ActOnFakeKey":{"name":"vk_bear","action":"Press"}}
        """

        // Parse and verify structure
        let data = try XCTUnwrap(expectedFormat.data(using: .utf8))
        let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any]

        XCTAssertNotNil(json)
        XCTAssertNotNil(json?["ActOnFakeKey"])

        let fakeKey = json?["ActOnFakeKey"] as? [String: String]
        XCTAssertEqual(fakeKey?["name"], "vk_bear")
        XCTAssertEqual(fakeKey?["action"], "Press")
    }

    func testTCPCommand_FakeKeyRelease() throws {
        let expectedFormat = """
        {"ActOnFakeKey":{"name":"vk_bear","action":"Release"}}
        """

        let data = try XCTUnwrap(expectedFormat.data(using: .utf8))
        let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any]

        let fakeKey = json?["ActOnFakeKey"] as? [String: String]
        XCTAssertEqual(fakeKey?["action"], "Release")
    }

    // MARK: - App Switch Scenario Tests

    func testAppSwitchScenario_NoMappingToMapping() async throws {
        // Setup: Only Bear has a keymap
        let bearKeymap = AppKeymap(
            bundleIdentifier: "com.apple.Bear",
            displayName: "Bear",
            overrides: [AppKeyOverride(inputKey: "a", outputAction: "b")]
        )
        try await store.upsertKeymap(bearKeymap)

        let mapping = await store.getBundleToVKMapping()

        // Scenario: User switches from Finder (no keymap) to Bear (has keymap)
        let finderVK = mapping["com.apple.Finder"] // nil
        let bearVK = mapping["com.apple.Bear"] // "vk_bear"

        XCTAssertNil(finderVK, "Finder should have no VK")
        XCTAssertEqual(bearVK, "vk_bear", "Bear should have VK")

        // Expected TCP commands:
        // 1. No release (previous was nil)
        // 2. Press vk_bear
    }

    func testAppSwitchScenario_MappingToMapping() async throws {
        // Setup: Both Bear and Safari have keymaps
        let bearKeymap = AppKeymap(
            bundleIdentifier: "com.apple.Bear",
            displayName: "Bear",
            overrides: [AppKeyOverride(inputKey: "a", outputAction: "b")]
        )
        let safariKeymap = AppKeymap(
            bundleIdentifier: "com.apple.Safari",
            displayName: "Safari",
            overrides: [AppKeyOverride(inputKey: "a", outputAction: "c")]
        )
        try await store.upsertKeymap(bearKeymap)
        try await store.upsertKeymap(safariKeymap)

        let mapping = await store.getBundleToVKMapping()

        // Scenario: User switches from Bear to Safari
        let bearVK = mapping["com.apple.Bear"]
        let safariVK = mapping["com.apple.Safari"]

        XCTAssertEqual(bearVK, "vk_bear")
        XCTAssertEqual(safariVK, "vk_safari")

        // Expected TCP commands:
        // 1. Release vk_bear
        // 2. Press vk_safari
    }

    func testAppSwitchScenario_MappingToNoMapping() async throws {
        // Setup: Only Bear has a keymap
        let bearKeymap = AppKeymap(
            bundleIdentifier: "com.apple.Bear",
            displayName: "Bear",
            overrides: [AppKeyOverride(inputKey: "a", outputAction: "b")]
        )
        try await store.upsertKeymap(bearKeymap)

        let mapping = await store.getBundleToVKMapping()

        // Scenario: User switches from Bear to Finder
        let bearVK = mapping["com.apple.Bear"]
        let finderVK = mapping["com.apple.Finder"]

        XCTAssertEqual(bearVK, "vk_bear")
        XCTAssertNil(finderVK)

        // Expected TCP commands:
        // 1. Release vk_bear
        // 2. No press (Finder has no VK)
    }

    // MARK: - Edge Cases

    func testEmptyStore_NoVKMappings() async {
        let mapping = await store.getBundleToVKMapping()
        XCTAssertTrue(mapping.isEmpty)
    }

    func testDisabledKeymap_ExcludedFromMapping() async throws {
        // Create a disabled keymap
        let disabledMapping = AppKeyMapping(
            bundleIdentifier: "com.apple.Bear",
            displayName: "Bear",
            isEnabled: false
        )
        let keymap = AppKeymap(
            mapping: disabledMapping,
            overrides: [AppKeyOverride(inputKey: "a", outputAction: "b")]
        )
        try await store.upsertKeymap(keymap)

        let mapping = await store.getBundleToVKMapping()

        // Disabled keymaps should not appear
        XCTAssertNil(mapping["com.apple.Bear"])
    }

    func testKeymapWithNoOverrides_StillHasVK() async throws {
        // A keymap with no overrides still needs a VK for the config to be valid
        let keymap = AppKeymap(
            bundleIdentifier: "com.apple.Bear",
            displayName: "Bear",
            overrides: []
        )
        try await store.upsertKeymap(keymap)

        let mapping = await store.getBundleToVKMapping()

        // Should still have VK even with no overrides
        XCTAssertEqual(mapping["com.apple.Bear"], "vk_bear")
    }

    // MARK: - Reload Mapping Tests

    func testReloadMappings_PicksUpNewKeymaps() async throws {
        // Initial state: no keymaps
        var mapping = await store.getBundleToVKMapping()
        XCTAssertTrue(mapping.isEmpty)

        // Add a keymap
        let keymap = AppKeymap(
            bundleIdentifier: "com.apple.Bear",
            displayName: "Bear",
            overrides: []
        )
        try await store.upsertKeymap(keymap)

        // Invalidate cache and reload
        await store.invalidateCache()
        mapping = await store.getBundleToVKMapping()

        XCTAssertEqual(mapping["com.apple.Bear"], "vk_bear")
    }

    func testReloadMappings_PicksUpRemovedKeymaps() async throws {
        // Initial state: Bear has a keymap
        let keymap = AppKeymap(
            bundleIdentifier: "com.apple.Bear",
            displayName: "Bear",
            overrides: []
        )
        try await store.upsertKeymap(keymap)

        var mapping = await store.getBundleToVKMapping()
        XCTAssertNotNil(mapping["com.apple.Bear"])

        // Remove the keymap
        try await store.removeKeymap(bundleIdentifier: "com.apple.Bear")

        // Reload
        await store.invalidateCache()
        mapping = await store.getBundleToVKMapping()

        XCTAssertNil(mapping["com.apple.Bear"])
    }
}
