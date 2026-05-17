import ArgumentParser
import Foundation
import KeyPathAppKit

struct ConfigApply: AsyncParsableCommand {
    static let configuration = CommandConfiguration(
        commandName: "apply",
        abstract: "Regenerate config and reload Kanata"
    )

    @OptionGroup var globals: GlobalOptions

    mutating func run() async throws {
        let ctx = globals.outputContext
        CLIOutput.progress("Applying configuration...", context: ctx)

        let facade = await MainActor.run { CLIFacade() }
        let result = try await facade.applyConfiguration()

        CLIOutput.write(result, context: ctx) {
            var lines = [
                "Collections: \(result.collectionsCount) (\(result.enabledCount) enabled)",
                "Custom rules: \(result.customRulesCount)",
            ]
            if result.reloadSuccess {
                lines.append("Kanata reloaded successfully.")
            } else {
                lines.append("Config was written but Kanata reload failed.")
                lines.append("Run 'keypath service reload' once Kanata is running.")
            }
            return lines.joined(separator: "\n")
        }

        if !result.reloadSuccess {
            throw CLIExitCode.serviceUnreachable.exitCode
        }
    }
}
