import ArgumentParser
import Foundation
import KeyPathAppKit

struct RuleRemove: AsyncParsableCommand {
    static let configuration = CommandConfiguration(
        commandName: "remove",
        abstract: "Remove a key remapping"
    )

    @OptionGroup var globals: GlobalOptions

    @Argument(help: "Input key to remove mapping for")
    var input: String

    @Flag(help: "Regenerate config and reload Kanata after saving")
    var apply: Bool = false

    mutating func run() async throws {
        let ctx = globals.outputContext
        let facade = await MainActor.run { CLIFacade() }

        let removed = try await facade.removeRemap(input: input)
        if !removed {
            let error = CLIError.notFound("Rule", query: input, listCommand: "keypath rule list")
            CLIOutput.writeError(error, context: ctx)
            throw error.code.exitCode
        }

        CLIOutput.write(["removed": input], context: ctx) {
            "Removed mapping for '\(input)'"
        }

        try await applyConfigurationOrHint(facade: facade, apply: apply, context: ctx)
    }
}
