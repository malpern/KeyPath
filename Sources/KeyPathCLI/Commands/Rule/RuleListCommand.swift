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
        let facade = await MainActor.run { CLIFacade() }
        let rules = await facade.listRules(enabledOnly: enabledOnly)

        CLIOutput.write(rules, context: ctx) {
            if rules.isEmpty {
                return enabledOnly ? "No enabled rules." : "No custom rules."
            }
            var lines = ["Custom Rules:", String(repeating: "-", count: 50)]
            for rule in rules {
                var desc = "  \(rule.input) → \(rule.action.displayName)"
                if let behavior = rule.behavior {
                    desc += " (\(behavior.cliSchemaName))"
                }
                if !rule.isEnabled {
                    desc += " [disabled]"
                }
                if rule.targetLayer != "base" {
                    desc += " [layer: \(rule.targetLayer)]"
                }
                lines.append(desc)
            }
            return lines.joined(separator: "\n")
        }
    }
}
