import ArgumentParser
import Foundation
import KeyPathAppKit

extension KeyPathTool {
    struct TCP: AsyncParsableCommand {
        static let configuration = CommandConfiguration(
            abstract: "Query running Kanata via TCP",
            subcommands: [
                TCPStatus.self,
                Layers.self,
                Reload.self,
                HrmStats.self,
            ]
        )

        struct TCPStatus: AsyncParsableCommand {
            static let configuration = CommandConfiguration(
                commandName: "status",
                abstract: "Check Kanata TCP server status"
            )

            mutating func run() async throws {
                let facade = await MainActor.run { CLIFacade() }
                let healthy = await facade.tcpCheckHealth()
                if healthy {
                    print("Kanata TCP server is healthy.")
                    do {
                        let layers = try await facade.tcpGetLayers()
                        print("  Layers: \(layers.joined(separator: ", "))")
                    } catch {
                        print("  (Could not fetch layers: \(error))")
                    }
                } else {
                    print("Kanata TCP server is not responding.")
                    throw ExitCode.failure
                }
            }
        }

        struct Layers: AsyncParsableCommand {
            static let configuration = CommandConfiguration(
                abstract: "List available Kanata layers"
            )

            mutating func run() async throws {
                let facade = await MainActor.run { CLIFacade() }
                let layers = try await facade.tcpGetLayers()
                print("Layers:")
                for (i, layer) in layers.enumerated() {
                    print("  \(i): \(layer)")
                }
            }
        }

        struct Reload: AsyncParsableCommand {
            static let configuration = CommandConfiguration(
                abstract: "Hot-reload Kanata configuration"
            )

            mutating func run() async throws {
                let facade = await MainActor.run { CLIFacade() }
                print("Reloading Kanata configuration...")
                let success = await facade.tcpReload()
                if success {
                    print("Configuration reloaded successfully.")
                } else {
                    print("Reload failed.")
                    throw ExitCode.failure
                }
            }
        }

        struct HrmStats: AsyncParsableCommand {
            static let configuration = CommandConfiguration(
                commandName: "hrm-stats",
                abstract: "Show home row mod timing statistics"
            )

            @Flag(help: "Reset statistics after displaying")
            var reset: Bool = false

            mutating func run() async throws {
                let facade = await MainActor.run { CLIFacade() }
                let stats = try await facade.tcpGetHrmStats()
                print("HRM Statistics:")
                print("  Total decisions: \(stats.totalDecisions)")
                print("  Tap: \(stats.tapCount)")
                print("  Hold: \(stats.holdCount)")
                if stats.totalDecisions > 0 {
                    let tapPct = Double(stats.tapCount) / Double(stats.totalDecisions) * 100
                    print("  Tap rate: \(String(format: "%.1f", tapPct))%")
                }

                if reset {
                    try await facade.tcpResetHrmStats()
                    print("Statistics reset.")
                }
            }
        }
    }
}
