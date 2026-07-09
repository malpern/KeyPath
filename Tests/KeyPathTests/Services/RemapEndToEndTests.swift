@testable import KeyPathAppKit
@testable import KeyPathCore
import KeyPathRulesCore
@preconcurrency import XCTest

/// End-to-end integration test: create a rule collection with a 1→2 remap,
/// generate the kanata config, run it through the simulator, and verify
/// that pressing key 1 outputs key 2.
///
/// Hermeticity (#896): the simulator feature flag is injected as a constant
/// (`simulatorEnabled: { true }` via `SimulatorService.forTesting` and the
/// `LayerKeyMapper` initializer), so this suite never depends on the
/// UserDefaults-backed `FeatureFlags.simulatorAndVirtualKeysEnabled` that other
/// test classes mutate. The simulator binary is resolved with CI's
/// `KEYPATH_BUNDLED_SIMULATOR_OVERRIDE` taking precedence over local candidate
/// paths, so on the self-hosted runner the tests exercise the freshly built,
/// engine-pinned binary instead of stale leftovers in the persistent workspace
/// (the failure class previously diagnosed in #891).
final class RemapEndToEndTests: XCTestCase {
    private lazy var simulatorPath: String? = Self.resolveSimulatorPath()

    // MARK: - End-to-End: RuleCollection → Config → Simulator → Verify

    func testRuleCollectionRemapOneToTwo() async throws {
        let simulatorPath = try requireSimulatorPath()

        // 1. Create a rule collection with a 1→2 mapping
        let mapping = KeyMapping(input: "1", action: .keystroke(key: "2"))
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
        try await preflightSimulator(simulatorService, configPath: configPath, simulatorPath: simulatorPath)
        let mapper = LayerKeyMapper(simulatorService: simulatorService, simulatorEnabled: { true })
        let (layerMapping, report) = try await mapper.getMapping(
            for: "base",
            configPath: configPath,
            layout: .macBookUS
        )
        let diag = diagnostics(simulatorPath: simulatorPath, report: report)

        // 5. Verify: key 1 (keycode 18) outputs key 2
        let key1Info = layerMapping[18]
        XCTAssertNotNil(key1Info, "Key 1 (keycode 18) must be present in the layer mapping — \(diag)")
        XCTAssertEqual(key1Info?.outputKey, "2", "Pressing key 1 must output key 2 — \(diag)")
        XCTAssertEqual(key1Info?.displayLabel, "2", "Display label for key 1 must show 2 — \(diag)")
    }

    func testRuleCollectionRemapRoundTrip() async throws {
        let simulatorPath = try requireSimulatorPath()

        // Create multiple remaps and verify all of them
        let mappings = [
            KeyMapping(input: "a", action: .keystroke(key: "b")),
            KeyMapping(input: "1", action: .keystroke(key: "2")),
            KeyMapping(input: "q", action: .keystroke(key: "w"))
        ]
        let collections = [RuleCollection].collection(
            named: "Test Multi-Remap",
            mappings: mappings
        )

        let config = KanataConfiguration.generateFromCollections(collections)
        let configPath = try createTempConfig(config, name: "test-e2e-multi-remap.kbd")
        defer { try? FileManager.default.removeItem(atPath: configPath) }

        let simulatorService = SimulatorService.forTesting(simulatorPath: simulatorPath)
        try await preflightSimulator(simulatorService, configPath: configPath, simulatorPath: simulatorPath)
        let mapper = LayerKeyMapper(simulatorService: simulatorService, simulatorEnabled: { true })
        let (layerMapping, report) = try await mapper.getMapping(
            for: "base",
            configPath: configPath,
            layout: .macBookUS
        )
        let diag = diagnostics(simulatorPath: simulatorPath, report: report)

        // a→b (keycode 0)
        let keyA = layerMapping[0]
        XCTAssertNotNil(keyA, "Key a must be in the mapping — \(diag)")
        XCTAssertEqual(keyA?.outputKey, "b", "Key a must output b — \(diag)")

        // 1→2 (keycode 18)
        let key1 = layerMapping[18]
        XCTAssertNotNil(key1, "Key 1 must be in the mapping — \(diag)")
        XCTAssertEqual(key1?.outputKey, "2", "Key 1 must output 2 — \(diag)")

        // q→w (keycode 12)
        let keyQ = layerMapping[12]
        XCTAssertNotNil(keyQ, "Key q must be in the mapping — \(diag)")
        XCTAssertEqual(keyQ?.outputKey, "w", "Key q must output w — \(diag)")
    }

    // MARK: - Helpers

    /// Run one direct simulation before the real assertions so a broken simulator
    /// binary or unparseable config fails loudly with the underlying error instead
    /// of silently degrading into nil-output fallback mapping entries (#896).
    private func preflightSimulator(
        _ service: SimulatorService,
        configPath: String,
        simulatorPath: String
    ) async throws {
        do {
            _ = try await service.simulateRaw(
                simContent: "d:1 t:50 u:1 t:250",
                configPath: configPath
            )
        } catch {
            XCTFail("Simulator preflight failed (binary: \(simulatorPath)): \(error)")
            throw error
        }
    }

    private func diagnostics(simulatorPath: String, report: SimulationReport?) -> String {
        let failed = report?.failedKeys.map(\.kanataName).joined(separator: ",") ?? "none"
        return "[simulator: \(simulatorPath), failedSimKeys: \(failed)]"
    }

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
        let sourceFile = URL(fileURLWithPath: #filePath)
        let projectRoot = sourceFile
            .deletingLastPathComponent() // Services/
            .deletingLastPathComponent() // KeyPathTests/
            .deletingLastPathComponent() // Tests/
            .deletingLastPathComponent() // KeyPath project root
            .path
        return [
            "/Applications/KeyPath.app/Contents/Library/KeyPath/kanata-simulator",
            "\(projectRoot)/build/kanata-simulator",
            "\(cwd)/dist/KeyPath.app/Contents/Library/KeyPath/kanata-simulator",
            "\(cwd)/build/kanata-simulator"
        ]
    }

    private static func resolveSimulatorPath() -> String? {
        let fileManager = FileManager.default
        // Explicit env overrides win. KEYPATH_SIMULATOR_PATH is the test-specific
        // override; KEYPATH_BUNDLED_SIMULATOR_OVERRIDE is what CI exports to point
        // at the freshly built, engine-pinned simulator. Honoring it here keeps the
        // test off stale binaries left in the runner's persistent workspace or an
        // old installed KeyPath.app (#896, same failure class as #891).
        for envKey in ["KEYPATH_SIMULATOR_PATH", "KEYPATH_BUNDLED_SIMULATOR_OVERRIDE"] {
            if let env = ProcessInfo.processInfo.environment[envKey],
               !env.isEmpty,
               fileManager.fileExists(atPath: env)
            {
                return env
            }
        }
        return simulatorCandidatePaths.first { fileManager.fileExists(atPath: $0) }
    }
}
