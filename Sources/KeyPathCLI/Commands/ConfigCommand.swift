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
                abstract: "Check that a generated configuration file exists on disk"
            )

            mutating func run() async throws {
                let facade = await MainActor.run { CLIFacade() }
                let config = await facade.currentConfig()
                if config.isEmpty {
                    print("No configuration generated yet. Run 'keypath apply' first.")
                    throw ExitCode.failure
                }
                print("Configuration exists (\(config.count) characters)")
                print("Note: This checks file presence only. Use 'keypath apply' to validate and reload via Kanata.")
            }
        }
    }
}
