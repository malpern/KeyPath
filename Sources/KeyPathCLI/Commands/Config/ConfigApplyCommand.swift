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
        let dryRun = globals.dryRun
        let spinner = CLISpinner(context: ctx)
        spinner.start(dryRun ? "Previewing configuration..." : "Applying configuration...")

        let facade = ConfigFacade()
        let result = try await facade.applyConfiguration(dryRun: dryRun)

        if result.dryRun == true {
            spinner.succeed("Configuration previewed")
        } else if result.reloadSuccess {
            spinner.succeed("Configuration applied")
        } else {
            spinner.fail("Config written but Kanata reload failed")
        }

        CLIOutput.write(result, context: ctx) {
            let nc = ctx.noColor
            var lines = [
                "Collections: \(result.collectionsCount) (\(result.enabledCount) enabled)",
                "Custom rules: \(result.customRulesCount)",
            ]
            if let changeset = result.changeset {
                if !changeset.enabledCollections.isEmpty {
                    lines.append(ANSIColor.dim("  Enabled: \(changeset.enabledCollections.joined(separator: ", "))", noColor: nc))
                }
                if !changeset.customRules.isEmpty {
                    lines.append(ANSIColor.dim("  Rules: \(changeset.customRules.joined(separator: ", "))", noColor: nc))
                }
            }
            if result.dryRun == true {
                lines.append(ANSIColor.yellow("Dry run: config validated; no files written and Kanata was not reloaded.", noColor: nc))
            } else if result.reloadSuccess {
                lines.append(ANSIColor.green("Kanata reloaded successfully.", noColor: nc))
            } else {
                lines.append(ANSIColor.red("Config was written but Kanata reload failed.", noColor: nc))
                lines.append("Run 'keypath service reload' once Kanata is running.")
            }
            return lines.joined(separator: "\n")
        }

        if result.dryRun != true, !result.reloadSuccess {
            throw CLIExitCode.serviceUnreachable.exitCode
        }
    }
}
