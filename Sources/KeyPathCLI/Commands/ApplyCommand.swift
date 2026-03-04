import ArgumentParser
import Foundation
import KeyPathAppKit

extension KeyPathTool {
    struct Apply: AsyncParsableCommand {
        static let configuration = CommandConfiguration(
            abstract: "Regenerate config, validate, and reload Kanata"
        )

        @Flag(help: "Only regenerate the config file without reloading Kanata (does not invoke Kanata syntax checking)")
        var dryRun: Bool = false

        mutating func run() async throws {
            let facade = await MainActor.run { CLIFacade() }

            if dryRun {
                print("Dry run: regenerating configuration without reload...")
                let config = await facade.currentConfig()
                if config.isEmpty {
                    print("No configuration generated. Add rules first.")
                    throw ExitCode.failure
                }
                print("Configuration regenerated (\(config.count) characters)")
                print("Note: Kanata syntax was not checked. Run without --dry-run to validate via reload.")
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
