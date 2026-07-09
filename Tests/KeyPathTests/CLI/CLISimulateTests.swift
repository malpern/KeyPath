@testable import KeyPathAppKit
import KeyPathRulesCore
@preconcurrency import XCTest

final class MockSimulatorProvider: CLISimulatorProvider, @unchecked Sendable {
    var result: CLISimulationResult
    var lastTaps: [CLISimulatorKeyTap] = []
    var lastRawContent: String?
    var lastConfigPath: String = ""
    var shouldThrow: Error?

    init(result: CLISimulationResult = CLISimulationResult(events: [], finalLayer: "base", durationMs: 0)) {
        self.result = result
    }

    func simulate(taps: [CLISimulatorKeyTap], configPath: String) async throws -> CLISimulationResult {
        lastTaps = taps
        lastConfigPath = configPath
        if let error = shouldThrow { throw error }
        return result
    }

    func simulateRaw(simContent: String, configPath: String) async throws -> CLISimulationResult {
        lastRawContent = simContent
        lastConfigPath = configPath
        if let error = shouldThrow { throw error }
        return result
    }
}

@MainActor
final class CLISimulateTests: XCTestCase {
    private let facade = SimulatorFacade()

    // MARK: - Basic Simulation

    func testSimulateSimpleKey() async throws {
        let mock = MockSimulatorProvider(result: CLISimulationResult(
            events: [
                CLISimEvent(type: "input", timeMs: 0, action: "press", key: "a"),
                CLISimEvent(type: "output", timeMs: 0, action: "press", key: "a"),
                CLISimEvent(type: "input", timeMs: 200, action: "release", key: "a"),
                CLISimEvent(type: "output", timeMs: 200, action: "release", key: "a"),
            ],
            finalLayer: "base",
            durationMs: 200
        ))

        let result = try await facade.simulate(
            keys: [CLISimulatorKeyTap(key: "a")],
            configPath: "/fake/config.kbd",
            simulatorProvider: mock
        )

        XCTAssertEqual(result.finalLayer, "base")
        XCTAssertEqual(result.durationMs, 200)
        XCTAssertEqual(result.events.count, 4)
        XCTAssertEqual(result.events.filter { $0.type == "output" }.count, 2)
    }

    // MARK: - Layer Change

    func testSimulateLayerChange() async throws {
        let mock = MockSimulatorProvider(result: CLISimulationResult(
            events: [
                CLISimEvent(type: "input", timeMs: 0, action: "press", key: "caps"),
                CLISimEvent(type: "layer", timeMs: 0, key: "base -> nav"),
                CLISimEvent(type: "input", timeMs: 400, action: "release", key: "caps"),
                CLISimEvent(type: "layer", timeMs: 400, key: "nav -> base"),
            ],
            finalLayer: "base",
            durationMs: 400
        ))

        let result = try await facade.simulate(
            keys: [CLISimulatorKeyTap(key: "caps", delayMs: 400, isHold: true)],
            configPath: "/fake/config.kbd",
            simulatorProvider: mock
        )

        let layerEvents = result.events.filter { $0.type == "layer" }
        XCTAssertEqual(layerEvents.count, 2)
        XCTAssertEqual(layerEvents.first?.key, "base -> nav")
    }

    // MARK: - Tap-Hold Dual Role

    func testSimulateTapHold() async throws {
        let mock = MockSimulatorProvider(result: CLISimulationResult(
            events: [
                CLISimEvent(type: "input", timeMs: 0, action: "press", key: "caps"),
                CLISimEvent(type: "output", timeMs: 0, action: "press", key: "esc"),
                CLISimEvent(type: "output", timeMs: 0, action: "release", key: "esc"),
                CLISimEvent(type: "input", timeMs: 200, action: "release", key: "caps"),
            ],
            finalLayer: "base",
            durationMs: 200
        ))

        let result = try await facade.simulate(
            keys: [CLISimulatorKeyTap(key: "caps")],
            configPath: "/fake/config.kbd",
            simulatorProvider: mock
        )

        let outputs = result.events.filter { $0.type == "output" }
        XCTAssertEqual(outputs.count, 2)
        XCTAssertEqual(outputs.first?.key, "esc")
    }

    // MARK: - Error Handling

    func testSimulateErrorPropagates() async {
        let mock = MockSimulatorProvider()
        mock.shouldThrow = SimulatorError.simulatorNotFound

        do {
            _ = try await facade.simulate(
                keys: [CLISimulatorKeyTap(key: "a")],
                configPath: "/fake/config.kbd",
                simulatorProvider: mock
            )
            XCTFail("Expected error")
        } catch is SimulatorError {
            // Expected
        } catch {
            XCTFail("Wrong error type: \(error)")
        }
    }

    // MARK: - Key Tap Conversion

    func testKeyTapsPassedToProvider() async throws {
        let mock = MockSimulatorProvider()

        _ = try await facade.simulate(
            keys: [
                CLISimulatorKeyTap(key: "caps", delayMs: 200),
                CLISimulatorKeyTap(key: "a", delayMs: 100),
            ],
            configPath: "/my/config.kbd",
            simulatorProvider: mock
        )

        XCTAssertEqual(mock.lastTaps.count, 2)
        XCTAssertEqual(mock.lastTaps[0].key, "caps")
        XCTAssertEqual(mock.lastTaps[0].delayMs, 200)
        XCTAssertEqual(mock.lastTaps[1].key, "a")
        XCTAssertEqual(mock.lastTaps[1].delayMs, 100)
        XCTAssertEqual(mock.lastConfigPath, "/my/config.kbd")
    }

    func testRawSimulationPassedToProvider() async throws {
        let mock = MockSimulatorProvider(result: CLISimulationResult(
            events: [
                CLISimEvent(type: "output", timeMs: 100, action: "press", key: "lmet"),
            ],
            finalLayer: "base",
            durationMs: 200
        ))
        let raw = "d:f t:100 d:j t:50 u:j t:50 u:f"

        let result = try await facade.simulateRaw(
            simContent: raw,
            configPath: "/my/config.kbd",
            simulatorProvider: mock
        )

        XCTAssertEqual(mock.lastRawContent, raw)
        XCTAssertEqual(mock.lastConfigPath, "/my/config.kbd")
        XCTAssertEqual(result.events.first?.key, "lmet")
    }

    // MARK: - Result Structure

    func testResultEncodesAsJSON() async throws {
        let mock = MockSimulatorProvider(result: CLISimulationResult(
            events: [
                CLISimEvent(type: "output", timeMs: 10, action: "press", key: "lctl"),
                CLISimEvent(type: "unicode", timeMs: 20, key: "a"),
            ],
            finalLayer: "nav",
            durationMs: 30
        ))

        let result = try await facade.simulate(
            keys: [CLISimulatorKeyTap(key: "a")],
            configPath: "/fake/config.kbd",
            simulatorProvider: mock
        )

        let data = try JSONEncoder().encode(result)
        let decoded = try JSONDecoder().decode(CLISimulationResult.self, from: data)

        XCTAssertEqual(decoded.finalLayer, "nav")
        XCTAssertEqual(decoded.durationMs, 30)
        XCTAssertEqual(decoded.events.count, 2)
        XCTAssertEqual(decoded.events[0].type, "output")
        XCTAssertEqual(decoded.events[0].key, "lctl")
        XCTAssertEqual(decoded.events[1].type, "unicode")
        XCTAssertEqual(decoded.events[1].key, "a")
    }

    // MARK: - Empty Simulation

    func testSimulateEmptyKeysReturnsEmpty() async throws {
        let mock = MockSimulatorProvider()

        let result = try await facade.simulate(
            keys: [],
            configPath: "/fake/config.kbd",
            simulatorProvider: mock
        )

        XCTAssertTrue(result.events.isEmpty)
        XCTAssertEqual(result.finalLayer, "base")
        XCTAssertEqual(result.durationMs, 0)
    }
}

// MARK: - Real Simulator Integration Tests

/// End-to-end tests that run the actual kanata-simulator binary.
/// Skipped automatically if the binary isn't found (e.g., CI without a built app).
@MainActor
final class CLISimulateIntegrationTests: XCTestCase {
    private let facade = SimulatorFacade()

    private func requireSimulatorPath() throws -> String {
        let which = Process()
        which.executableURL = URL(fileURLWithPath: "/usr/bin/which")
        which.arguments = ["kanata-simulator"]
        let pipe = Pipe()
        which.standardOutput = pipe
        try? which.run()
        which.waitUntilExit()
        if which.terminationStatus == 0 {
            let path = String(data: pipe.fileHandleForReading.readDataToEndOfFile(), encoding: .utf8)?
                .trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
            if !path.isEmpty { return path }
        }

        let candidates = [
            "/opt/homebrew/bin/kanata-simulator",
            "/Applications/KeyPath.app/Contents/Library/KeyPath/kanata-simulator",
            URL(fileURLWithPath: #filePath)
                .deletingLastPathComponent()
                .deletingLastPathComponent()
                .deletingLastPathComponent()
                .deletingLastPathComponent()
                .appendingPathComponent("build/kanata-simulator").path,
        ]
        if let path = candidates.first(where: { FileManager.default.fileExists(atPath: $0) }) {
            return path
        }
        throw XCTSkip("kanata-simulator binary not found — skipping integration test")
    }

    private func createTempConfig(_ content: String) throws -> String {
        let path = URL(fileURLWithPath: NSTemporaryDirectory())
            .appendingPathComponent("keypath-cli-sim-test-\(UUID().uuidString).kbd").path
        try content.write(toFile: path, atomically: true, encoding: .utf8)
        return path
    }

    private func runOrSkipOnVersionMismatch(
        _ block: () async throws -> CLISimulationResult
    ) async throws -> CLISimulationResult {
        do {
            return try await block()
        } catch let error as SimulatorError {
            if case let .processFailedWithCode(_, msg) = error, msg.contains("Unknown defcfg option") || msg.contains("unexpected argument") {
                throw XCTSkip("kanata-simulator too old for current config format")
            }
            throw error
        }
    }

    func testRealSimulateSimpleRemap() async throws {
        let simulatorPath = try requireSimulatorPath()

        let mapping = KeyMapping(input: "a", action: .keystroke(key: "b"))
        let collections = [RuleCollection].collection(named: "Test A->B", mappings: [mapping])
        let config = KanataConfiguration.generateFromCollections(collections)
        let configPath = try createTempConfig(config)
        defer { try? FileManager.default.removeItem(atPath: configPath) }

        let provider = RealSimulatorTestProvider(simulatorPath: simulatorPath)
        let result = try await runOrSkipOnVersionMismatch {
            try await facade.simulate(
                keys: [CLISimulatorKeyTap(key: "a")],
                configPath: configPath,
                simulatorProvider: provider
            )
        }

        let outputs = result.events.filter { $0.type == "output" }
        XCTAssertFalse(outputs.isEmpty, "Should have output events")
        XCTAssertTrue(outputs.contains { $0.key == "b" }, "Pressing 'a' should output 'b'")
    }

    func testRealSimulateTapHold() async throws {
        let simulatorPath = try requireSimulatorPath()

        let behavior = MappingBehavior.dualRole(DualRoleBehavior(
            tapAction: .keystroke(key: "esc"),
            holdAction: .keystroke(key: "lctl"),
            tapTimeout: 200,
            holdTimeout: 200,
            activateHoldOnOtherKey: true
        ))
        let mapping = KeyMapping(
            input: "caps",
            action: .keystroke(key: "lctl"),
            behavior: behavior
        )
        let collections = [RuleCollection].collection(named: "Test Tap-Hold", mappings: [mapping])
        let config = KanataConfiguration.generateFromCollections(collections)
        let configPath = try createTempConfig(config)
        defer { try? FileManager.default.removeItem(atPath: configPath) }

        let provider = RealSimulatorTestProvider(simulatorPath: simulatorPath)

        let tapResult = try await runOrSkipOnVersionMismatch {
            try await facade.simulate(
                keys: [CLISimulatorKeyTap(key: "caps", delayMs: 50)],
                configPath: configPath,
                simulatorProvider: provider
            )
        }

        XCTAssertFalse(tapResult.events.isEmpty, "Simulation should produce events")
        XCTAssertTrue(tapResult.events.contains { $0.type == "input" }, "Should have input events")
    }

    func testRealSimulateMultipleKeys() async throws {
        let simulatorPath = try requireSimulatorPath()

        let mappings = [
            KeyMapping(input: "a", action: .keystroke(key: "b")),
            KeyMapping(input: "1", action: .keystroke(key: "2")),
        ]
        let collections = [RuleCollection].collection(named: "Test Multi", mappings: mappings)
        let config = KanataConfiguration.generateFromCollections(collections)
        let configPath = try createTempConfig(config)
        defer { try? FileManager.default.removeItem(atPath: configPath) }

        let provider = RealSimulatorTestProvider(simulatorPath: simulatorPath)
        let result = try await runOrSkipOnVersionMismatch {
            try await facade.simulate(
                keys: [
                    CLISimulatorKeyTap(key: "a"),
                    CLISimulatorKeyTap(key: "1"),
                ],
                configPath: configPath,
                simulatorProvider: provider
            )
        }

        let outputs = result.events.filter { $0.type == "output" }
        XCTAssertTrue(outputs.contains { $0.key == "b" }, "Key 'a' should produce 'b'")
        XCTAssertTrue(outputs.contains { $0.key == "2" }, "Key '1' should produce '2'")
        XCTAssertTrue(result.durationMs > 0)
    }

    func testRealSimulateRawHomeRowModsOppositeHandChord() async throws {
        let simulatorPath = try requireSimulatorPath()

        let config = HomeRowModsConfig(
            enabledKeys: ["f", "j"],
            modifierAssignments: ["f": "lmet", "j": "rmet"],
            holdMode: .modifiers,
            timing: TimingConfig(tapWindow: 200, holdDelay: 150, requirePriorIdleMs: 0),
            oppositeHandMode: .press
        )
        let collection = RuleCollection(
            name: "Home Row Mods",
            summary: "Tap for letters, hold for modifiers",
            category: .productivity,
            mappings: [],
            isEnabled: true,
            configuration: .homeRowMods(config)
        )
        let renderedConfig = KanataConfiguration.generateFromCollections([collection])
        let configPath = try createTempConfig(renderedConfig)
        defer { try? FileManager.default.removeItem(atPath: configPath) }

        let provider = RealSimulatorTestProvider(simulatorPath: simulatorPath)
        let result = try await runOrSkipOnVersionMismatch {
            try await facade.simulateRaw(
                simContent: "d:f t:100 d:j t:50 u:j t:50 u:f",
                configPath: configPath,
                simulatorProvider: provider
            )
        }

        let activatedLeftCommand = result.events.contains { event in
            event.type == "output" && event.action == "press" && event.key == "lmet"
        }
        XCTAssertTrue(activatedLeftCommand, "Overlapping f+j HRM simulation should activate f's left-command hold action")
    }
}

/// Provider that uses the real SimulatorService with a specific binary path.
private final class RealSimulatorTestProvider: CLISimulatorProvider, @unchecked Sendable {
    private let simulatorPath: String

    init(simulatorPath: String) {
        self.simulatorPath = simulatorPath
    }

    func simulate(taps: [CLISimulatorKeyTap], configPath: String) async throws -> CLISimulationResult {
        let service = SimulatorService(simulatorPath: simulatorPath)
        let internalTaps = taps.map {
            SimulatorKeyTap(kanataKey: $0.key, displayLabel: $0.key, delayAfterMs: $0.delayMs, isHold: $0.isHold)
        }
        let result = try await service.simulate(taps: internalTaps, configPath: configPath)
        return cliSimulationResult(from: result)
    }

    func simulateRaw(simContent: String, configPath: String) async throws -> CLISimulationResult {
        let service = SimulatorService(simulatorPath: simulatorPath)
        let result = try await service.simulateRaw(simContent: simContent, configPath: configPath)
        return cliSimulationResult(from: result)
    }

    private func cliSimulationResult(from result: SimulationResult) -> CLISimulationResult {
        let events = result.events.map { event -> CLISimEvent in
            switch event {
            case let .input(t, action, key):
                CLISimEvent(type: "input", timeMs: t, action: action.rawValue, key: key)
            case let .output(t, action, key):
                CLISimEvent(type: "output", timeMs: t, action: action.rawValue, key: key)
            case let .layer(t, from, to):
                CLISimEvent(type: "layer", timeMs: t, key: "\(from) -> \(to)")
            case let .unicode(t, char):
                CLISimEvent(type: "unicode", timeMs: t, key: char)
            case let .mouse(t, action, data):
                CLISimEvent(type: "mouse", timeMs: t, action: action.rawValue, key: data)
            }
        }
        return CLISimulationResult(events: events, finalLayer: result.finalLayer ?? "base", durationMs: result.durationMs)
    }
}
