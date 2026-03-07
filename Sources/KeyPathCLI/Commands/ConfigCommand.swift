import ArgumentParser
import Foundation
import KeyPathAppKit

extension KeyPathTool {
    struct Config: AsyncParsableCommand {
        static let configuration = CommandConfiguration(
            abstract: "Inspect and manage Kanata configuration",
            subcommands: [
                Show.self,
                Path.self,
                Check.self,
            ]
        )

        struct Show: AsyncParsableCommand {
            static let configuration = CommandConfiguration(
                abstract: "Print current generated .kbd configuration"
            )

            mutating func run() async throws {
                let facade = await MainActor.run { CLIFacade() }
                let config = await facade.currentConfig()
                print(config)
            }
        }

        struct Path: AsyncParsableCommand {
            static let configuration = CommandConfiguration(
                abstract: "Print the configuration file path"
            )

            mutating func run() async throws {
                let path = await MainActor.run { CLIFacade().configPath() }
                print(path)
            }
        }

        struct Check: AsyncParsableCommand {
            static let configuration = CommandConfiguration(
                abstract: "Validate configuration using kanata --check"
            )

            @Flag(help: "Output as JSON")
            var json: Bool = false

            mutating func run() async throws {
                let facade = CLIFacade()
                let result = await facade.validateConfig()

                if json {
                    let encoder = JSONEncoder()
                    encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
                    let data = try encoder.encode(result)
                    print(String(data: data, encoding: .utf8) ?? "")
                } else if result.isValid {
                    print("Configuration is valid.")
                } else {
                    printErr("Configuration validation failed:")
                    for error in result.errors {
                        printErr("  - \(error)")
                    }
                }

                if !result.isValid {
                    throw ExitCode.failure
                }
            }
        }
    }
}
