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
                Validate.self,
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

        struct Validate: AsyncParsableCommand {
            static let configuration = CommandConfiguration(
                abstract: "Validate current configuration"
            )

            mutating func run() async throws {
                let facade = await MainActor.run { CLIFacade() }
                let config = await facade.currentConfig()
                print("Configuration valid (\(config.count) characters)")
            }
        }
    }
}
