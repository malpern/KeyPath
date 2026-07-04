@testable import KeyPathAppKit
@testable import KeyPathCore
@preconcurrency import XCTest

final class LayerKeyMapperPrebuildTests: XCTestCase {
    /// These tests exercise the simulator-disabled fallback path. The flag is
    /// injected per-instance instead of flipping the UserDefaults-backed global
    /// FeatureFlags value, which leaked into other test classes running in the
    /// same process and caused the #896 flake in RemapEndToEndTests.
    private func makeMapper() -> LayerKeyMapper {
        LayerKeyMapper(simulatorEnabled: { false })
    }

    // MARK: - Cache Key Format

    func testPrebuildStoresCompositeKeysMatchingGetMapping() async throws {
        let mapper = makeMapper()
        let configPath = try createTempConfig("(defcfg)(defsrc)(deflayer base)")

        await mapper.prebuildAllLayers(
            ["nav", "launcher"],
            configPath: configPath,
            layout: .macBookUS
        )

        let cacheKeys = await mapper.cache.keys.sorted()

        XCTAssertTrue(cacheKeys.contains("nav|default"), "Should store nav|default")
        XCTAssertTrue(cacheKeys.contains("nav|neovim-scope-approved"), "Should store nav|neovim-scope-approved")
        XCTAssertTrue(cacheKeys.contains("nav|neovim-scope-fallback"), "Should store nav|neovim-scope-fallback")
        XCTAssertTrue(cacheKeys.contains("launcher|default"), "Should store launcher|default")
        XCTAssertTrue(cacheKeys.contains("launcher|neovim-scope-approved"), "Should store launcher|neovim-scope-approved")
        XCTAssertTrue(cacheKeys.contains("launcher|neovim-scope-fallback"), "Should store launcher|neovim-scope-fallback")

        for key in cacheKeys {
            XCTAssertTrue(key.contains("|"), "Cache key '\(key)' must use composite format (layer|suffix)")
        }
    }

    func testPrebuildCacheHitsOnGetMapping() async throws {
        let mapper = makeMapper()
        let configPath = try createTempConfig("(defcfg)(defsrc)(deflayer base)")

        await mapper.prebuildAllLayers(
            ["nav"],
            configPath: configPath,
            layout: .macBookUS
        )

        let prebuiltCount = await mapper.cache.count

        let (mapping, _) = try await mapper.getMapping(
            for: "nav",
            configPath: configPath,
            layout: .macBookUS,
            cacheKeySuffix: "neovim-scope-fallback"
        )

        let postGetCount = await mapper.cache.count
        XCTAssertEqual(prebuiltCount, postGetCount, "getMapping should hit cache, not add a new entry")
        XCTAssertFalse(mapping.isEmpty, "Mapping should contain fallback keys")
    }

    func testPrebuildNormalizesLayerNamesToLowercase() async throws {
        let mapper = makeMapper()
        let configPath = try createTempConfig("(defcfg)(defsrc)(deflayer base)")

        await mapper.prebuildAllLayers(
            ["Nav", "LAUNCHER"],
            configPath: configPath,
            layout: .macBookUS
        )

        let cacheKeys = await mapper.cache.keys.sorted()
        XCTAssertTrue(cacheKeys.contains("nav|neovim-scope-fallback"))
        XCTAssertTrue(cacheKeys.contains("launcher|neovim-scope-fallback"))
        XCTAssertFalse(cacheKeys.contains { $0.hasPrefix("Nav|") || $0.hasPrefix("LAUNCHER|") },
                       "Keys should be lowercased")
    }

    // MARK: - Neovim Scope Variants

    func testPrebuildSkipsApprovedVariantWhenNoNeovimCollection() async throws {
        let mapper = makeMapper()
        let configPath = try createTempConfig("(defcfg)(defsrc)(deflayer base)")

        await mapper.prebuildAllLayers(
            ["nav"],
            configPath: configPath,
            layout: .macBookUS,
            allEnabledCollections: []
        )

        let cacheKeys = await mapper.cache.keys.sorted()
        XCTAssertTrue(cacheKeys.contains("nav|neovim-scope-fallback"),
                      "Fallback variant should always be built")
        XCTAssertTrue(cacheKeys.contains("nav|default"),
                      "Default variant should always be built")
        // Without neovim collection, approved variant is still built in fallback mode
        // (simulator disabled uses same fallback mapping for all variants)
    }

    // MARK: - Cache Invalidation

    func testInvalidateCacheClearsPrebuiltEntries() async throws {
        let mapper = makeMapper()
        let configPath = try createTempConfig("(defcfg)(defsrc)(deflayer base)")

        await mapper.prebuildAllLayers(
            ["nav"],
            configPath: configPath,
            layout: .macBookUS
        )

        let countBefore = await mapper.cache.count
        XCTAssertGreaterThan(countBefore, 0)

        await mapper.invalidateCache()

        let countAfter = await mapper.cache.count
        XCTAssertEqual(countAfter, 0, "invalidateCache should clear all prebuilt entries")
    }

    // MARK: - Helpers

    private func createTempConfig(_ content: String) throws -> String {
        let tempDir = URL(fileURLWithPath: NSTemporaryDirectory(), isDirectory: true)
        let configPath = tempDir.appendingPathComponent("test-prebuild-\(UUID().uuidString).kbd").path
        try content.write(toFile: configPath, atomically: true, encoding: .utf8)
        addTeardownBlock { try? FileManager.default.removeItem(atPath: configPath) }
        return configPath
    }
}
