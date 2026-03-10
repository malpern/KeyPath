import ArgumentParser
import Foundation
import KeyPathAppKit

extension KeyPathCLI {
    struct Apply: AsyncParsableCommand {
        static let configuration = CommandConfiguration(
            abstract: "Regenerate config and reload Kanata"
        )

        mutating func run() async throws {
            let facade = await MainActor.run { CLIFacade() }

            print("Applying configuration...")
            let result = try await facade.applyConfiguration()
            print("Collections: \(result.collectionsCount) (\(result.enabledCount) enabled)")
            print("Custom rules: \(result.customRulesCount)")
            if result.reloadSuccess {
                print("Kanata reloaded successfully.")
            } else {
                printErr("Config was written but Kanata reload failed.")
                printErr("Run 'keypath tcp reload' once Kanata is running.")
                throw ExitCode.failure
            }
        }
    }
}
