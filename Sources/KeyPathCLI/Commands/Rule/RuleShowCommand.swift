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
        let facade = await MainActor.run { CLIFacade() }
        let rules = await facade.loadCustomRules()

        guard let rule = rules.first(where: { $0.input == input }) else {
            let error = CLIError.notFound("Rule", query: input, listCommand: "keypath rule list")
            CLIOutput.writeError(error, context: ctx)
            throw error.code.exitCode
        }

        CLIOutput.write(rule, context: ctx) {
            var lines = [
                "Input: \(rule.input)",
                "Output: \(rule.output)",
            ]
            if let behavior = rule.behavior {
                lines.append("Behavior: \(behavior)")
            }
            return lines.joined(separator: "\n")
        }
    }
}
