import ArgumentParser
import Foundation
import KeyPathAppKit

struct CollectionDelete: AsyncParsableCommand {
    static let configuration = CommandConfiguration(
        commandName: "delete",
        abstract: "Delete a rule collection"
    )

    @OptionGroup var globals: GlobalOptions

    @Argument(help: "Collection name or ID to delete")
    var nameOrId: String

    @Flag(help: "Skip confirmation (required for non-interactive)")
    var force: Bool = false

    mutating func run() async throws {
        let ctx = globals.outputContext
        let facade = await MainActor.run { CLIFacade() }

        do {
            let deleted = try await facade.deleteCollection(nameOrId: nameOrId)
            if !deleted {
                let error = CLIError.notFound("Collection", query: nameOrId, listCommand: "keypath collection list")
                CLIOutput.writeError(error, context: ctx)
                throw error.code.exitCode
            }

            CLIOutput.write(["deleted": nameOrId], context: ctx) {
                "Deleted collection: \(nameOrId)"
            }
        } catch let error as AmbiguousCollectionMatch {
            let cliError = CLIError.ambiguous(error.description, matches: error.matches.map { "\($0.name) (\($0.id))" })
            CLIOutput.writeError(cliError, context: ctx)
            throw CLIExitCode.conflict.exitCode
        }
    }
}
