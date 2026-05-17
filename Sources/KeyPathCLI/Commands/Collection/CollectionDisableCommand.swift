import ArgumentParser
import Foundation
import KeyPathAppKit

struct CollectionDisable: AsyncParsableCommand {
    static let configuration = CommandConfiguration(
        commandName: "disable",
        abstract: "Disable a rule collection"
    )

    @OptionGroup var globals: GlobalOptions

    @Argument(help: "Collection name or ID")
    var nameOrId: String

    @Flag(help: "Regenerate config and reload Kanata after saving")
    var apply: Bool = false

    mutating func run() async throws {
        let ctx = globals.outputContext
        let facade = await MainActor.run { CLIFacade() }

        do {
            guard let name = try await facade.disableCollection(nameOrId: nameOrId) else {
                let error = CLIError.notFound("Collection", query: nameOrId, listCommand: "keypath collection list")
                CLIOutput.writeError(error, context: ctx)
                throw error.code.exitCode
            }
            CLIOutput.write(["disabled": name], context: ctx) {
                "Disabled '\(name)'"
            }
        } catch let ambiguous as AmbiguousCollectionMatch {
            let error = CLIError.ambiguous(
                ambiguous.description,
                matches: ambiguous.matches.map { "\($0.name) (id: \($0.id))" }
            )
            CLIOutput.writeError(error, context: ctx)
            throw error.code.exitCode
        }

        try await applyConfigurationOrHint(facade: facade, apply: apply, context: ctx)
    }
}
