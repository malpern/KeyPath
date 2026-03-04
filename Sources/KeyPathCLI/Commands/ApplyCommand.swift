import ArgumentParser
import Foundation
import KeyPathAppKit

extension KeyPathTool {
    struct Apply: AsyncParsableCommand {
        static let configuration = CommandConfiguration(
            abstract: "Regenerate config, validate, and reload Kanata"
        )

        @Flag(help: "Print the current config file contents without regenerating or reloading")
        var show: Bool = false

        mutating func run() async throws {
            let facade = await MainActor.run { CLIFacade() }

            if show {
                let config = await facade.currentConfig()
                if config.isEmpty {
                    print("No configuration generated yet. Add rules and run 'keypath apply' first.")
                    throw ExitCode.failure
                }
                print(config)
            } else {
                print("Applying configuration...")
                let result = try await facade.applyConfiguration()
                print("Collections: \(result.collectionsCount) (\(result.enabledCount) enabled)")
                print("Custom rules: \(result.customRulesCount)")
                if result.reloadSuccess {
                    print("Kanata reloaded successfully.")
                } else {
                    print("Config was written but Kanata reload failed.")
                    print("Run 'keypath tcp reload' once Kanata is running.")
                    throw ExitCode.failure
                }
            }
        }
    }
}
