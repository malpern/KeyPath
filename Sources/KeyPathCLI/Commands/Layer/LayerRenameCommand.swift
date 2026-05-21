import ArgumentParser
import Foundation
import KeyPathAppKit

struct LayerRename: AsyncParsableCommand {
    static let configuration = CommandConfiguration(
        commandName: "rename",
        abstract: "Rename a layer (updates all collections targeting it)"
    )

    @OptionGroup var globals: GlobalOptions

    @Argument(help: "Current layer name")
    var name: String

    @Argument(help: "New layer name")
    var newName: String

    mutating func run() async throws {
        let ctx = globals.outputContext
        let facade = CollectionsFacade()

        let updated = try await facade.renameLayer(oldName: name, newName: newName)
        if updated == 0 {
            let error = CLIError.notFound("Layer", query: name, listCommand: "keypath layer list")
            CLIOutput.writeError(error, context: ctx)
            throw error.code.exitCode
        }

        CLIOutput.write(["oldName": name, "newName": newName, "collectionsUpdated": "\(updated)"], context: ctx) {
            "Renamed layer '\(name)' → '\(newName)' (\(updated) collection\(updated == 1 ? "" : "s") updated)"
        }
    }
}
