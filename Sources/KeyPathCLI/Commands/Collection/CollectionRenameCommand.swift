import ArgumentParser
import Foundation
import KeyPathAppKit

struct CollectionRename: AsyncParsableCommand {
    static let configuration = CommandConfiguration(
        commandName: "rename",
        abstract: "Rename a rule collection"
    )

    @OptionGroup var globals: GlobalOptions

    @Argument(help: "Collection name or ID to rename")
    var nameOrId: String

    @Argument(help: "New name for the collection")
    var newName: String

    mutating func run() async throws {
        let ctx = globals.outputContext
        let facade = await MainActor.run { CLIFacade() }

        do {
            guard let oldName = try await facade.renameCollection(nameOrId: nameOrId, newName: newName) else {
                let error = CLIError.notFound("Collection", query: nameOrId, listCommand: "keypath collection list")
                CLIOutput.writeError(error, context: ctx)
                throw error.code.exitCode
            }

            CLIOutput.write(["oldName": oldName, "newName": newName], context: ctx) {
                "Renamed '\(oldName)' → '\(newName)'"
            }
        } catch let error as AmbiguousCollectionMatch {
            let cliError = CLIError.ambiguous(error.description, matches: error.matches.map { "\($0.name) (\($0.id))" })
            CLIOutput.writeError(cliError, context: ctx)
            throw CLIExitCode.conflict.exitCode
        }
    }
}
