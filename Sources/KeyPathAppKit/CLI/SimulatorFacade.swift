import Foundation
import KeyPathCore

public struct SimulatorFacade: Sendable {
    public init() {}

    public func simulate(
        keys: [CLISimulatorKeyTap],
        configPath: String?,
        simulatorProvider: CLISimulatorProvider? = nil
    ) async throws -> CLISimulationResult {
        let config: String = if let configPath {
            configPath
        } else {
            await MainActor.run { ConfigurationService().configurationPath }
        }

        let provider = simulatorProvider ?? RealSimulatorProvider()
        return try await provider.simulate(taps: keys, configPath: config)
    }

    public func simulateRaw(
        simContent: String,
        configPath: String?,
        simulatorProvider: CLISimulatorProvider? = nil
    ) async throws -> CLISimulationResult {
        let config: String = if let configPath {
            configPath
        } else {
            await MainActor.run { ConfigurationService().configurationPath }
        }

        let provider = simulatorProvider ?? RealSimulatorProvider()
        return try await provider.simulateRaw(simContent: simContent, configPath: config)
    }

    public func validateKey(_ key: String) -> String? {
        guard CustomRuleValidator.isValidKey(key) else { return nil }
        return CustomRuleValidator.normalizeKey(key)
    }
}

// MARK: - Simulator Types

public struct CLISimulatorKeyTap: Sendable {
    public let key: String
    public let delayMs: UInt64
    public let isHold: Bool

    public init(key: String, delayMs: UInt64 = 200, isHold: Bool = false) {
        self.key = key
        self.delayMs = delayMs
        self.isHold = isHold
    }
}

public struct CLISimulationResult: Codable, Sendable {
    public let events: [CLISimEvent]
    public let finalLayer: String
    public let durationMs: UInt64
}

public struct CLISimEvent: Codable, Sendable {
    public let type: String
    public let timeMs: UInt64
    public let action: String?
    public let key: String?

    public init(type: String, timeMs: UInt64, action: String? = nil, key: String? = nil) {
        self.type = type
        self.timeMs = timeMs
        self.action = action
        self.key = key
    }
}

public protocol CLISimulatorProvider: Sendable {
    func simulate(taps: [CLISimulatorKeyTap], configPath: String) async throws -> CLISimulationResult
    func simulateRaw(simContent: String, configPath: String) async throws -> CLISimulationResult
}

struct RealSimulatorProvider: CLISimulatorProvider {
    func simulate(taps: [CLISimulatorKeyTap], configPath: String) async throws -> CLISimulationResult {
        let service = SimulatorService()
        let internalTaps = taps.map {
            SimulatorKeyTap(kanataKey: $0.key, displayLabel: $0.key, delayAfterMs: $0.delayMs, isHold: $0.isHold)
        }
        let result = try await service.simulate(taps: internalTaps, configPath: configPath)
        return cliSimulationResult(from: result)
    }

    func simulateRaw(simContent: String, configPath: String) async throws -> CLISimulationResult {
        let service = SimulatorService()
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
