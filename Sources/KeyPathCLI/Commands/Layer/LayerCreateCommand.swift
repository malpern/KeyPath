import ArgumentParser
import Foundation
import KeyPathAppKit

struct LayerCreate: AsyncParsableCommand {
    static let configuration = CommandConfiguration(
        commandName: "create",
        abstract: "Create a new layer (with an empty collection targeting it)"
    )

    @OptionGroup var globals: GlobalOptions

    @Argument(help: "Name for the new layer")
    var name: String

    mutating func run() async throws {
        let ctx = globals.outputContext
        let facade = await MainActor.run { CLIFacade() }

        let collection = try await facade.createLayer(name: name)
        CLIOutput.write(collection, context: ctx) {
            "Created layer '\(name)' (collection: \(collection.name))"
        }
    }
}
