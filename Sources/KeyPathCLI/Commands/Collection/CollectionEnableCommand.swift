import ArgumentParser
import Foundation
import KeyPathAppKit

struct CollectionEnable: AsyncParsableCommand {
    static let configuration = CommandConfiguration(
        commandName: "enable",
        abstract: "Enable a rule collection"
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
            guard let name = try await facade.enableCollection(nameOrId: nameOrId) else {
                let candidates = await facade.loadRuleCollections().map(\.name)
                let suggestions = FuzzyMatch.suggestions(for: nameOrId, from: candidates)
                let error = CLIError.notFound("Collection", query: nameOrId, listCommand: "keypath collection list", suggestions: suggestions)
                CLIOutput.writeError(error, context: ctx)
                throw error.code.exitCode
            }
            CLIOutput.write(["enabled": name], context: ctx) {
                "Enabled '\(name)'"
            }
        } catch let managed as PackManagedCollectionError {
            let error = CLIError.conflict(
                managed.description,
                hint: "Run 'keypath pack uninstall \(managed.packName.lowercased().replacingOccurrences(of: " ", with: "-"))' to release this collection"
            )
            CLIOutput.writeError(error, context: ctx)
            throw error.code.exitCode
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
