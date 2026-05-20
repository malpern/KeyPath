import ArgumentParser
import Foundation
import KeyPathAppKit

struct RuleShow: AsyncParsableCommand {
    static let configuration = CommandConfiguration(
        commandName: "show",
        abstract: "Show details of a custom rule"
    )

    @OptionGroup var globals: GlobalOptions

    @Argument(help: "Input key to show mapping for")
    var input: String

    mutating func run() async throws {
        let ctx = globals.outputContext
        let facade = RulesFacade()

        guard let rule = await facade.showRule(input: input) else {
            let error = CLIError.notFound("Rule", query: input, listCommand: "keypath rule list")
            CLIOutput.writeError(error, context: ctx)
            throw error.code.exitCode
        }

        CLIOutput.write(rule, context: ctx) {
            var lines = [
                "Input: \(rule.input)",
                "Action: \(rule.action.displayName)",
                "Layer: \(rule.targetLayer)",
                "Enabled: \(rule.isEnabled)",
            ]
            if let behavior = rule.behavior {
                lines.append("Behavior: \(behavior.cliSchemaName)")
            }
            if let shifted = rule.shiftedOutput {
                lines.append("Shifted: \(shifted)")
            }
            if let title = rule.title {
                lines.append("Title: \(title)")
            }
            if let notes = rule.notes {
                lines.append("Notes: \(notes)")
            }
            if let overrides = rule.deviceOverrides, !overrides.isEmpty {
                lines.append("Device overrides: \(overrides.count)")
                for override_ in overrides {
                    lines.append("  \(override_.deviceHash) → \(override_.action.displayName)")
                }
            }
            return lines.joined(separator: "\n")
        }
    }
}
