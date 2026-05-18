import ArgumentParser
import Foundation
import KeyPathAppKit

struct Simulate: AsyncParsableCommand {
    static let configuration = CommandConfiguration(
        commandName: "simulate",
        abstract: "Simulate a key sequence and show what Kanata would output"
    )

    @OptionGroup var globals: GlobalOptions

    @Argument(help: "Key sequence as space-separated keys (e.g., 'caps a' or 'caps:hold a')")
    var keys: [String]

    @Option(name: .customLong("config"), help: "Path to kanata config file (default: active config)")
    var configPath: String?

    @Option(name: .customLong("delay"), help: "Default delay between keys in ms (default: 200)")
    var delayMs: UInt64 = 200

    mutating func run() async throws {
        let ctx = globals.outputContext
        let facade = await MainActor.run { CLIFacade() }

        let taps = keys.map { key -> CLISimulatorKeyTap in
            let parts = key.split(separator: ":", maxSplits: 1)
            let keyName = String(parts[0])
            let isHold = parts.count > 1 && parts[1] == "hold"
            let holdDelay: UInt64 = isHold ? 400 : delayMs
            return CLISimulatorKeyTap(key: keyName, delayMs: holdDelay, isHold: isHold)
        }

        if globals.dryRun {
            let simContent = taps.map { tap in
                "d:\(tap.key) t:\(tap.delayMs) u:\(tap.key)"
            }.joined(separator: " ")

            let preview = CLISimulateDryRun(
                keyCount: taps.count,
                simContent: simContent,
                configPath: configPath ?? "(active config)"
            )

            CLIOutput.write(preview, context: ctx) {
                "Would simulate \(taps.count) key(s): \(simContent)"
            }
            return
        }

        do {
            let result = try await facade.simulate(
                keys: taps,
                configPath: configPath
            )

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
}

struct CLISimulateDryRun: Codable, Sendable {
    let keyCount: Int
    let simContent: String
    let configPath: String
}
