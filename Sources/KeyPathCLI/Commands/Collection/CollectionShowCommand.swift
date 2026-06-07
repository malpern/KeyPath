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

    @Flag(name: .customLong("full"), help: "Show full collection model including display configuration")
    var full: Bool = false

    mutating func run() async throws {
        let ctx = globals.outputContext
        let facade = CollectionsFacade()

        if full {
            try await showFullCollection(ctx: ctx, facade: facade)
            return
        }

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

    private func showFullCollection(ctx: OutputContext, facade: CollectionsFacade) async throws {
        let collection: CLIRuleCollectionDetail
        do {
            guard let found = try await facade.showCollectionDetail(nameOrId: nameOrId) else {
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
            Style: \(collection.displayStyle)
            Mappings: \(collection.mappingCount)
            Target layer: \(collection.targetLayer)
            Configuration: \(collection.displayStyle)
            Summary: \(collection.summary)
            """
        }
    }
}
