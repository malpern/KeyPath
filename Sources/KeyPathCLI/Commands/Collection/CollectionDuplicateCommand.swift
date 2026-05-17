import ArgumentParser
import Foundation
import KeyPathAppKit

struct CollectionDuplicate: AsyncParsableCommand {
    static let configuration = CommandConfiguration(
        commandName: "duplicate",
        abstract: "Duplicate a rule collection"
    )

    @OptionGroup var globals: GlobalOptions

    @Argument(help: "Collection name or ID to duplicate")
    var nameOrId: String

    @Option(help: "Name for the duplicate (default: '<name> (Copy)')")
    var name: String?

    mutating func run() async throws {
        let ctx = globals.outputContext
        let facade = await MainActor.run { CLIFacade() }

        do {
            guard let collection = try await facade.duplicateCollection(nameOrId: nameOrId, newName: name) else {
                let error = CLIError.notFound("Collection", query: nameOrId, listCommand: "keypath collection list")
                CLIOutput.writeError(error, context: ctx)
                throw error.code.exitCode
            }

            CLIOutput.write(collection, context: ctx) {
                "Duplicated as: \(collection.name) (id: \(collection.id))"
            }
        } catch let error as AmbiguousCollectionMatch {
            let cliError = CLIError.ambiguous(error.description, matches: error.matches.map { "\($0.name) (\($0.id))" })
            CLIOutput.writeError(cliError, context: ctx)
            throw CLIExitCode.conflict.exitCode
        }
    }
}
