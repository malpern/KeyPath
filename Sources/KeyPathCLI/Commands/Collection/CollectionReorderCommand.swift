import ArgumentParser
import Foundation
import KeyPathAppKit

struct CollectionReorder: AsyncParsableCommand {
    static let configuration = CommandConfiguration(
        commandName: "reorder",
        abstract: "Move a collection to a new position in the list"
    )

    @OptionGroup var globals: GlobalOptions

    @Argument(help: "Collection name or ID to move")
    var nameOrId: String

    @Option(help: "Target position (0-indexed)")
    var position: Int

    mutating func run() async throws {
        let ctx = globals.outputContext
        let facade = CollectionsFacade()

        do {
            let moved = try await facade.reorderCollection(nameOrId: nameOrId, position: position)
            if !moved {
                let candidates = await facade.loadRuleCollections().map(\.name)
                let suggestions = FuzzyMatch.suggestions(for: nameOrId, from: candidates)
                let error = CLIError.notFound("Collection", query: nameOrId, listCommand: "keypath collection list", suggestions: suggestions)
                CLIOutput.writeError(error, context: ctx)
                throw error.code.exitCode
            }

            CLIOutput.write(["moved": nameOrId, "position": "\(position)"], context: ctx) {
                "Moved '\(nameOrId)' to position \(position)"
            }
        } catch let error as AmbiguousCollectionMatch {
            let cliError = CLIError.ambiguous(error.description, matches: error.matches.map { "\($0.name) (\($0.id))" })
            CLIOutput.writeError(cliError, context: ctx)
            throw CLIExitCode.conflict.exitCode
        }
    }
}
