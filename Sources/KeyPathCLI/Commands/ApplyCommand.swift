import ArgumentParser
import Foundation
import KeyPathAppKit

extension KeyPathTool {
    struct Apply: AsyncParsableCommand {
        static let configuration = CommandConfiguration(
            abstract: "Regenerate config, validate, and reload Kanata"
        )

        @Flag(help: "Only validate, don't write or reload")
        var dryRun: Bool = false

        mutating func run() async throws {
            let facade = await MainActor.run { CLIFacade() }

            if dryRun {
                print("Dry run: validating configuration...")
                let config = await facade.currentConfig()
                print("Configuration valid (\(config.count) characters)")
            } else {
                print("Applying configuration...")
                let result = try await facade.applyConfiguration()
                print("Collections: \(result.collectionsCount) (\(result.enabledCount) enabled)")
                print("Custom rules: \(result.customRulesCount)")
                if result.reloadSuccess {
                    print("Kanata reloaded successfully.")
                } else {
                    print("Kanata reload failed.")
                    throw ExitCode.failure
                }
            }
        }
    }
}
