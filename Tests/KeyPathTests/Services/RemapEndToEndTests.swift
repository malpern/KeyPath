@testable import KeyPathAppKit
@testable import KeyPathCore
@preconcurrency import XCTest

/// End-to-end integration test: create a rule collection with a 1→2 remap,
/// generate the kanata config, run it through the simulator, and verify
/// that pressing key 1 outputs key 2.
final class RemapEndToEndTests: XCTestCase {
    private lazy var simulatorPath: String? = Self.resolveSimulatorPath()

    // MARK: - End-to-End: RuleCollection → Config → Simulator → Verify

    func testRuleCollectionRemapOneToTwo() async throws {
        let simulatorPath = try requireSimulatorPath()

        // 1. Create a rule collection with a 1→2 mapping
        let mapping = KeyMapping(input: "1", output: "2")
        let collections = [RuleCollection].collection(
            named: "Test 1→2",
            mappings: [mapping]
        )

        // 2. Generate kanata config from the rule collection
        let config = KanataConfiguration.generateFromCollections(collections)
        XCTAssertTrue(config.contains("(defsrc"), "Generated config must have defsrc")
        XCTAssertTrue(config.contains("(deflayer"), "Generated config must have deflayer")

        // 3. Write config to temp file
        let configPath = try createTempConfig(config, name: "test-e2e-remap-1-to-2.kbd")
        defer { try? FileManager.default.removeItem(atPath: configPath) }

        // 4. Run through simulator and get key mapping
        let simulatorService = SimulatorService.forTesting(simulatorPath: simulatorPath)
        let mapper = LayerKeyMapper(simulatorService: simulatorService)
        let layerMapping = try await mapper.getMapping(
            for: "base",
            configPath: configPath,
            layout: .macBookUS
        )

        // 5. Verify: key 1 (keycode 18) outputs key 2
        let key1Info = layerMapping[18]
        XCTAssertNotNil(key1Info, "Key 1 (keycode 18) must be present in the layer mapping")
        XCTAssertEqual(key1Info?.outputKey, "2", "Pressing key 1 must output key 2")
        XCTAssertEqual(key1Info?.displayLabel, "2", "Display label for key 1 must show 2")
    }

    func testRuleCollectionRemapRoundTrip() async throws {
        let simulatorPath = try requireSimulatorPath()

        // Create multiple remaps and verify all of them
        let mappings = [
            KeyMapping(input: "a", output: "b"),
            KeyMapping(input: "1", output: "2"),
            KeyMapping(input: "q", output: "w"),
        ]
        let collections = [RuleCollection].collection(
            named: "Test Multi-Remap",
            mappings: mappings
        )

        let config = KanataConfiguration.generateFromCollections(collections)
        let configPath = try createTempConfig(config, name: "test-e2e-multi-remap.kbd")
        defer { try? FileManager.default.removeItem(atPath: configPath) }

        let simulatorService = SimulatorService.forTesting(simulatorPath: simulatorPath)
        let mapper = LayerKeyMapper(simulatorService: simulatorService)
        let layerMapping = try await mapper.getMapping(
            for: "base",
            configPath: configPath,
            layout: .macBookUS
        )

        // a→b (keycode 0)
        let keyA = layerMapping[0]
        XCTAssertNotNil(keyA, "Key a must be in the mapping")
        XCTAssertEqual(keyA?.outputKey, "b", "Key a must output b")

        // 1→2 (keycode 18)
        let key1 = layerMapping[18]
        XCTAssertNotNil(key1, "Key 1 must be in the mapping")
        XCTAssertEqual(key1?.outputKey, "2", "Key 1 must output 2")

        // q→w (keycode 12)
        let keyQ = layerMapping[12]
        XCTAssertNotNil(keyQ, "Key q must be in the mapping")
        XCTAssertEqual(keyQ?.outputKey, "w", "Key q must output w")
    }

    // MARK: - Helpers

    private func createTempConfig(_ content: String, name: String) throws -> String {
        let tempDir = URL(fileURLWithPath: NSTemporaryDirectory(), isDirectory: true)
        let configPath = tempDir.appendingPathComponent(name).path
        try content.write(toFile: configPath, atomically: true, encoding: .utf8)
        return configPath
    }

    private func requireSimulatorPath() throws -> String {
        if let simulatorPath {
            return simulatorPath
        }
        let candidates = Self.simulatorCandidatePaths.joined(separator: ", ")
        throw XCTSkip(
            "Simulator binary not found. Set KEYPATH_SIMULATOR_PATH or build via Scripts/build-kanata-simulator.sh. Tried: \(candidates)"
        )
    }

    private static var simulatorCandidatePaths: [String] {
        let cwd = FileManager.default.currentDirectoryPath
        return [
            "/Applications/KeyPath.app/Contents/Library/KeyPath/kanata-simulator",
            "\(cwd)/dist/KeyPath.app/Contents/Library/KeyPath/kanata-simulator",
            "\(cwd)/build/kanata-simulator",
        ]
    }

    private static func resolveSimulatorPath() -> String? {
        let fileManager = FileManager.default
        if let env = ProcessInfo.processInfo.environment["KEYPATH_SIMULATOR_PATH"],
           !env.isEmpty,
           fileManager.fileExists(atPath: env)
        {
            return env
        }
        return simulatorCandidatePaths.first { fileManager.fileExists(atPath: $0) }
    }
}
