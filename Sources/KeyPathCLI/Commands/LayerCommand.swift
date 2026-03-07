import ArgumentParser
import Foundation
import KeyPathAppKit

extension KeyPathTool {
    struct Layer: AsyncParsableCommand {
        static let configuration = CommandConfiguration(
            abstract: "List or switch Kanata layers",
            subcommands: [
                List.self,
                Switch.self,
            ],
            defaultSubcommand: List.self
        )

        struct List: AsyncParsableCommand {
            static let configuration = CommandConfiguration(
                abstract: "List available layers"
            )

            @Flag(help: "Output as JSON")
            var json: Bool = false

            mutating func run() async throws {
                let facade = await MainActor.run { CLIFacade() }
                let layers: [String]
                do {
                    layers = try await facade.tcpGetLayers()
                } catch {
                    printErr("Could not connect to Kanata (is it running?)")
                    throw ExitCode.failure
                }

                if json {
                    let encoder = JSONEncoder()
                    encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
                    let data = try encoder.encode(layers)
                    print(String(data: data, encoding: .utf8) ?? "")
                } else {
                    if layers.isEmpty {
                        print("No layers found.")
                    } else {
                        print("Layers:")
                        for layer in layers {
                            print("  \(layer)")
                        }
                    }
                }
            }
        }

        struct Switch: AsyncParsableCommand {
            static let configuration = CommandConfiguration(
                abstract: "Switch to a layer by name"
            )

            @Argument(help: "Layer name (e.g., base, nav, vim)")
            var name: String

            mutating func run() async throws {
                let facade = await MainActor.run { CLIFacade() }
                let success = await facade.tcpChangeLayer(name)
                if success {
                    print("Switched to layer '\(name)'")
                } else {
                    printErr("Failed to switch to layer '\(name)'")
                    printErr("Check that the layer exists and Kanata is running.")
                    throw ExitCode.failure
                }
            }
        }
    }
}
