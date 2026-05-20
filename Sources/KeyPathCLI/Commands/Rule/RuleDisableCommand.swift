import ArgumentParser
import Foundation
import KeyPathAppKit

struct RuleDisable: AsyncParsableCommand {
    static let configuration = CommandConfiguration(
        commandName: "disable",
        abstract: "Disable a custom rule"
    )

    @OptionGroup var globals: GlobalOptions

    @Argument(help: "Input key of the rule to disable")
    var input: String

    @Flag(help: "Regenerate config and reload Kanata after saving")
    var apply: Bool = false

    mutating func run() async throws {
        let ctx = globals.outputContext
        let facade = await MainActor.run { CLIFacade() }

        guard let title = try await facade.disableRule(input: input) else {
            let error = CLIError.notFound("Rule", query: input, listCommand: "keypath rule list")
            CLIOutput.writeError(error, context: ctx)
            throw error.code.exitCode
        }

        CLIOutput.write(["disabled": input, "title": title], context: ctx) {
            "Disabled '\(title)' (\(input))"
        }

        try await applyConfigurationOrHint(facade: facade, apply: apply, context: ctx)
    }
}
