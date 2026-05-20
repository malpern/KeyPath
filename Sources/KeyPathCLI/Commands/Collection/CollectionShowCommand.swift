import ArgumentParser
import Foundation
import KeyPathAppKit

struct CollectionShow: AsyncParsableCommand {
    static let configuration = CommandConfiguration(
        commandName: "show",
        abstract: "Show details of a rule collection"
    )

    @OptionGroup var globals: GlobalOptions

    @Argument(help: "Collection name or ID")
    var nameOrId: String

    mutating func run() async throws {
        let ctx = globals.outputContext
        let facade = await MainActor.run { CLIFacade() }

        let collection: CLIRuleCollection
        do {
            guard let found = try await facade.showCollection(nameOrId: nameOrId) else {
                let candidates = await facade.loadRuleCollections().map(\.name)
                let suggestions = FuzzyMatch.suggestions(for: nameOrId, from: candidates)
                let error = CLIError.notFound("Collection", query: nameOrId, listCommand: "keypath collection list", suggestions: suggestions)
                CLIOutput.writeError(error, context: ctx)
                throw error.code.exitCode
            }
            collection = found
        } catch let ambiguous as AmbiguousCollectionMatch {
            let error = CLIError.ambiguous(
                ambiguous.description,
                matches: ambiguous.matches.map { "\($0.name) (id: \($0.id))" }
            )
            CLIOutput.writeError(error, context: ctx)
            throw error.code.exitCode
        }

        CLIOutput.write(collection, context: ctx) {
            """
            Name: \(collection.name)
            ID: \(collection.id)
            Enabled: \(collection.isEnabled)
            Mappings: \(collection.mappingCount)
            Summary: \(collection.summary)
            """
        }
    }
}
