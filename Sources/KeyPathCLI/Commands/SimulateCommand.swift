import ArgumentParser
import Foundation
import KeyPathAppKit

struct Simulate: AsyncParsableCommand {
    static let configuration = CommandConfiguration(
        commandName: "simulate",
        abstract: "Simulate a key sequence and show what Kanata would output",
        discussion: "Pass keys as space-separated arguments. Append ':hold' to simulate a long press. Use --raw or --sim-file for overlapping press/release timelines."
    )

    @OptionGroup var globals: GlobalOptions

    @Argument(help: "Key sequence as space-separated keys (e.g., 'caps a' or 'caps:hold a')")
    var keys: [String] = []

    @Option(name: .customLong("config"), help: "Path to kanata config file (default: active config)")
    var configPath: String?

    @Option(name: .customLong("delay"), help: "Default delay between keys in ms (default: 200)")
    var delayMs: UInt64 = 200

    @Option(name: .customLong("raw"), help: "Raw kanata simulator timeline, e.g. 'd:f t:100 d:j t:50 u:j t:50 u:f'")
    var rawSimulation: String?

    @Option(name: .customLong("sim-file"), help: "Path to a raw kanata simulator timeline file")
    var simulationFile: String?

    func validate() throws {
        let rawModes = [rawSimulation != nil, simulationFile != nil].filter { $0 }.count
        if rawModes > 1 {
            throw ValidationError("Use only one of --raw or --sim-file")
        }
        if rawModes > 0, !keys.isEmpty {
            throw ValidationError("Pass either key arguments or a raw simulation timeline, not both")
        }
        if rawModes == 0, keys.isEmpty {
            throw ValidationError("Pass at least one key, --raw, or --sim-file")
        }
    }

    mutating func run() async throws {
        let ctx = globals.outputContext
        let facade = SimulatorFacade()

        let rawContent = try loadRawSimulationContent()
        let taps = keys.map { key -> CLISimulatorKeyTap in
            let parts = key.split(separator: ":", maxSplits: 1)
            let keyName = String(parts[0])
            let isHold = parts.count > 1 && parts[1] == "hold"
            let holdDelay: UInt64 = isHold ? 400 : delayMs
            return CLISimulatorKeyTap(key: keyName, delayMs: holdDelay, isHold: isHold)
        }

        if globals.dryRun {
            let simContent = rawContent ?? taps.map { tap in
                "d:\(tap.key) t:\(tap.delayMs) u:\(tap.key)"
            }.joined(separator: " ")
            let keyCount = rawContent.map(Self.rawEventCount) ?? taps.count

            let preview = CLISimulateDryRun(
                keyCount: keyCount,
                simContent: simContent,
                configPath: configPath ?? "(active config)"
            )

            CLIOutput.write(preview, context: ctx) {
                Self.dryRunDescription(rawContent: rawContent, keyCount: keyCount, simContent: simContent)
            }
            return
        }

        do {
            let result = if let rawContent {
                try await facade.simulateRaw(
                    simContent: rawContent,
                    configPath: configPath
                )
            } else {
                try await facade.simulate(
                    keys: taps,
                    configPath: configPath
                )
            }

            CLIOutput.write(result, context: ctx) {
                formatHumanOutput(result)
            }
        } catch {
            let cliError = CLIError.validation(
                "Simulation failed: \(error.localizedDescription)",
                hint: "Ensure the kanata-simulator binary is bundled and config is valid"
            )
            CLIOutput.writeError(cliError, context: ctx)
            throw cliError.code.exitCode
        }
    }

    private func formatHumanOutput(_ result: CLISimulationResult) -> String {
        var lines: [String] = []
        let outputs = result.events.filter { $0.type == "output" || $0.type == "layer" }
        if outputs.isEmpty {
            lines.append("No output events (keys may have been absorbed)")
        } else {
            for event in outputs {
                let time = String(format: "%4dms", event.timeMs)
                switch event.type {
                case "output":
                    lines.append("\(time)  \(event.action ?? "") \(event.key ?? "")")
                case "layer":
                    lines.append("\(time)  layer \(event.key ?? "")")
                default:
                    break
                }
            }
        }
        lines.append("Final layer: \(result.finalLayer) | Duration: \(result.durationMs)ms")
        return lines.joined(separator: "\n")
    }

    private func loadRawSimulationContent() throws -> String? {
        if let rawSimulation {
            return Self.normalizedRawSimulationContent(rawSimulation)
        }
        guard let simulationFile else { return nil }
        do {
            let content = try String(contentsOfFile: simulationFile, encoding: .utf8)
            return Self.normalizedRawSimulationContent(content)
        } catch {
            throw ValidationError("Could not read --sim-file '\(simulationFile)': \(error.localizedDescription)")
        }
    }

    static func dryRunDescription(rawContent: String?, keyCount: Int, simContent: String) -> String {
        if rawContent != nil {
            return "Would simulate raw timeline (\(keyCount) event(s)): \(simContent)"
        }
        return "Would simulate \(keyCount) key(s): \(simContent)"
    }

    static func rawEventCount(in simContent: String) -> Int {
        simContent
            .split(whereSeparator: \.isWhitespace)
            .filter { token in
                token.hasPrefix("d:") || token.hasPrefix("u:")
            }
            .count
    }

    static func normalizedRawSimulationContent(_ content: String) -> String {
        content.trimmingCharacters(in: .whitespacesAndNewlines)
    }
}

struct CLISimulateDryRun: Codable, Sendable {
    let keyCount: Int
    let simContent: String
    let configPath: String
}
