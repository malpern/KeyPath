import ArgumentParser
import Foundation
import KeyPathAppKit

struct RuleList: AsyncParsableCommand {
    static let configuration = CommandConfiguration(
        commandName: "list",
        abstract: "List all custom key remappings"
    )

    @OptionGroup var globals: GlobalOptions

    mutating func run() async throws {
        let ctx = globals.outputContext
        let facade = await MainActor.run { CLIFacade() }
        let rules = await facade.loadCustomRules()

        CLIOutput.write(rules, context: ctx) {
            if rules.isEmpty {
                return "No custom rules."
            }
            var lines = ["Custom Rules:", String(repeating: "-", count: 50)]
            for rule in rules {
                var desc = "  \(rule.input) → \(rule.output)"
                if let behavior = rule.behavior {
                    desc += " (\(behavior))"
                }
                lines.append(desc)
            }
            return lines.joined(separator: "\n")
        }
    }
}
