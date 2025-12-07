@preconcurrency import XCTest

@testable import KeyPathAppKit

final class LayerKeyMapperTests: XCTestCase {
    /// Path to the real simulator binary in the installed app
    private let simulatorPath = "/Applications/KeyPath.app/Contents/Library/KeyPath/kanata-simulator"

    /// Check if simulator is available for integration tests
    private var simulatorAvailable: Bool {
        FileManager.default.fileExists(atPath: simulatorPath)
    }

    // MARK: - Simulator-based Tests

    func testSimpleRemap() async throws {
        try XCTSkipUnless(simulatorAvailable, "Simulator binary not found at \(simulatorPath)")

        // Config with a simple remap: 1 -> 2
        let config = """
        (defcfg process-unmapped-keys yes)
        (defsrc 1)
        (deflayer base 2)
        """

        let configPath = try createTempConfig(config, name: "test-sim-remap.kbd")
        defer { try? FileManager.default.removeItem(atPath: configPath) }

        let simulatorService = SimulatorService.forTesting(simulatorPath: simulatorPath)
        let mapper = LayerKeyMapper(simulatorService: simulatorService)
        let mapping: [UInt16: LayerKeyInfo]
        do {
            mapping = try await mapper.getMapping(for: "base", configPath: configPath)
        } catch SimulatorError.keyMappingModeUnavailable {
            throw XCTSkip("Installed simulator does not support --key-mapping mode")
        }

        // Should have mapping for key 1 (keycode 18)
        let key1Mapping = mapping[18]
        XCTAssertNotNil(key1Mapping, "Should have mapping for key 1")
        XCTAssertEqual(key1Mapping?.displayLabel, "2", "Key 1 should display as 2")
        XCTAssertEqual(key1Mapping?.outputKey, "2", "Output key should be 2")
    }

    func testTapHoldAlias() async throws {
        try XCTSkipUnless(simulatorAvailable, "Simulator binary not found at \(simulatorPath)")

        // Config with alias (tap-hold) - simulator needed to resolve this
        // Note: tap-hold with 200ms timeout may not resolve with a quick 50ms tap
        // This test verifies the key is present in the mapping, not the specific output
        let config = """
        (defcfg process-unmapped-keys yes)
        (defalias myesc (tap-hold 200 200 esc lctl))
        (defsrc caps)
        (deflayer base @myesc)
        """

        let configPath = try createTempConfig(config, name: "test-sim-alias.kbd")
        defer { try? FileManager.default.removeItem(atPath: configPath) }

        let simulatorService = SimulatorService.forTesting(simulatorPath: simulatorPath)
        let mapper = LayerKeyMapper(simulatorService: simulatorService)
        let mapping: [UInt16: LayerKeyInfo]
        do {
            mapping = try await mapper.getMapping(for: "base", configPath: configPath)
        } catch SimulatorError.keyMappingModeUnavailable {
            throw XCTSkip("Installed simulator does not support --key-mapping mode")
        }

        // Caps Lock (keycode 57) should have some mapping
        // With tap-hold, a 50ms tap may not produce output (waits for timeout)
        // so we just verify the key is tracked
        let capsMapping = mapping[57]
        XCTAssertNotNil(capsMapping, "Should have mapping for caps lock")
        // The display label may be the original key if tap-hold didn't resolve
        // This is expected behavior - complex behaviors need longer simulation times
    }

    func testMultipleRemaps() async throws {
        try XCTSkipUnless(simulatorAvailable, "Simulator binary not found at \(simulatorPath)")

        let config = """
        (defcfg process-unmapped-keys yes)
        (defsrc 1 a)
        (deflayer base 2 b)
        """

        let configPath = try createTempConfig(config, name: "test-multi-remap.kbd")
        defer { try? FileManager.default.removeItem(atPath: configPath) }

        let simulatorService = SimulatorService.forTesting(simulatorPath: simulatorPath)
        let mapper = LayerKeyMapper(simulatorService: simulatorService)
        let mapping: [UInt16: LayerKeyInfo]
        do {
            mapping = try await mapper.getMapping(for: "base", configPath: configPath)
        } catch SimulatorError.keyMappingModeUnavailable {
            throw XCTSkip("Installed simulator does not support --key-mapping mode")
        }

        // Check 1->2 mapping (keycode 18)
        let key1Mapping = mapping[18]
        XCTAssertNotNil(key1Mapping, "Should have mapping for key 1")
        XCTAssertEqual(key1Mapping?.displayLabel, "2", "Key 1 should display as 2")

        // Check a->b mapping (keycode 0)
        let keyAMapping = mapping[0]
        XCTAssertNotNil(keyAMapping, "Should have mapping for key a")
        XCTAssertEqual(keyAMapping?.displayLabel, "B", "Key a should display as B")
    }

    func testUnchangedKeyNotRemapped() async throws {
        try XCTSkipUnless(simulatorAvailable, "Simulator binary not found at \(simulatorPath)")

        // Config where key maps to itself (a->a)
        let config = """
        (defcfg process-unmapped-keys yes)
        (defsrc a b)
        (deflayer base a c)
        """

        let configPath = try createTempConfig(config, name: "test-same.kbd")
        defer { try? FileManager.default.removeItem(atPath: configPath) }

        let simulatorService = SimulatorService.forTesting(simulatorPath: simulatorPath)
        let mapper = LayerKeyMapper(simulatorService: simulatorService)
        let mapping: [UInt16: LayerKeyInfo]
        do {
            mapping = try await mapper.getMapping(for: "base", configPath: configPath)
        } catch SimulatorError.keyMappingModeUnavailable {
            throw XCTSkip("Installed simulator does not support --key-mapping mode")
        }

        // Key a (keycode 0) should NOT be marked as remapped since it maps to itself
        let keyAMapping = mapping[0]
        if let keyAMapping {
            // If it exists, output should be same as input
            XCTAssertEqual(keyAMapping.outputKey?.lowercased(), "a", "Key a maps to itself")
        }

        // Key b (keycode 11) should be remapped to c
        let keyBMapping = mapping[11]
        XCTAssertNotNil(keyBMapping, "Should have mapping for key b")
        XCTAssertEqual(keyBMapping?.displayLabel, "C", "Key b should display as C")
    }

    // MARK: - Helpers

    private func createTempConfig(_ content: String, name: String) throws -> String {
        let tempDir = FileManager.default.temporaryDirectory
        let configPath = tempDir.appendingPathComponent(name).path
        try content.write(toFile: configPath, atomically: true, encoding: .utf8)
        return configPath
    }
}
