import ArgumentParser
import Foundation
import KeyPathAppKit

struct LayerDelete: AsyncParsableCommand {
    static let configuration = CommandConfiguration(
        commandName: "delete",
        abstract: "Delete a layer and all its collections"
    )

    @OptionGroup var globals: GlobalOptions

    @Argument(help: "Layer name to delete")
    var name: String

    mutating func run() async throws {
        let ctx = globals.outputContext
        let facade = await MainActor.run { CLIFacade() }

        let removed = try await facade.deleteLayer(name: name)
        if removed == 0 {
            let error = CLIError.notFound("Layer", query: name, listCommand: "keypath layer list")
            CLIOutput.writeError(error, context: ctx)
            throw error.code.exitCode
        }

        CLIOutput.write(["deleted": name, "collectionsRemoved": "\(removed)"], context: ctx) {
            "Deleted layer '\(name)' (\(removed) collection\(removed == 1 ? "" : "s") removed)"
        }
    }
}
