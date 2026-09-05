import ArgumentParser
import Foundation
import KeyPathAppKit

struct RuleEnable: AsyncParsableCommand {
    static let configuration = CommandConfiguration(
        commandName: "enable",
        abstract: "Enable a custom rule"
    )

    @OptionGroup var globals: GlobalOptions

    @Argument(help: "Input key of the rule to enable")
    var input: String

    @Flag(help: "Regenerate config and reload Kanata after saving")
    var apply: Bool = false

    mutating func run() async throws {
        let command = self
        try await CLIConfigurationOperation.run { operation in
            try await command.run(operation: operation)
        }
    }

    private func run(operation: CLIConfigurationOperation) async throws {
        let ctx = globals.outputContext
        let facade = operation.rules

        guard let title = try await facade.enableRule(input: input) else {
            let error = CLIError.notFound("Rule", query: input, listCommand: "keypath rule list")
            CLIOutput.writeError(error, context: ctx)
            throw error.code.exitCode
        }

        CLIOutput.write(["enabled": input, "title": title], context: ctx) {
            "Enabled '\(title)' (\(input))"
        }

        try await applyConfigurationOrHint(apply: apply, context: ctx, facade: operation.config)
    }
}
