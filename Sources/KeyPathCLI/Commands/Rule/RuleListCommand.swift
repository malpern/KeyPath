import ArgumentParser
import Foundation
import KeyPathAppKit

struct RuleList: AsyncParsableCommand {
    static let configuration = CommandConfiguration(
        commandName: "list",
        abstract: "List all custom key remappings"
    )

    @OptionGroup var globals: GlobalOptions

    @Flag(name: .customLong("enabled-only"), help: "Only show enabled rules")
    var enabledOnly: Bool = false

    mutating func run() async throws {
        let ctx = globals.outputContext
        let facade = RulesFacade()
        let rules = await facade.listRules(enabledOnly: enabledOnly)

        CLIOutput.write(rules, context: ctx) {
            if rules.isEmpty {
                return enabledOnly ? "No enabled rules." : "No custom rules."
            }
            let nc = ctx.noColor
            var lines = [ANSIColor.bold("Custom Rules:", noColor: nc), String(repeating: "-", count: 50)]
            for rule in rules {
                var desc = "  \(rule.input) → \(rule.action.displayName)"
                if let behavior = rule.behavior {
                    desc += " (\(behavior.cliSchemaName))"
                }
                if !rule.isEnabled {
                    desc += " \(ANSIColor.dim("[disabled]", noColor: nc))"
                }
                if rule.targetLayer != "base" {
                    desc += " \(ANSIColor.dim("[layer: \(rule.targetLayer)]", noColor: nc))"
                }
                lines.append(desc)
            }
            return lines.joined(separator: "\n")
        }
    }
}
