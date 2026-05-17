import ArgumentParser
import Foundation
import KeyPathAppKit

struct CollectionCreate: AsyncParsableCommand {
    static let configuration = CommandConfiguration(
        commandName: "create",
        abstract: "Create a new rule collection"
    )

    @OptionGroup var globals: GlobalOptions

    @Argument(help: "Name for the new collection")
    var name: String

    @Option(help: "Category (custom, productivity, navigation, layers, accessibility, experimental)")
    var category: String?

    @Option(help: "Short description of the collection")
    var summary: String?

    mutating func run() async throws {
        let ctx = globals.outputContext
        let facade = await MainActor.run { CLIFacade() }

        if globals.dryRun {
            let preview = ["name": name, "category": category ?? "custom", "summary": summary ?? ""]
            CLIOutput.write(preview, context: ctx) {
                "Would create collection: \(name)"
            }
            return
        }

        let collection = try await facade.createCollection(name: name, category: category, summary: summary)
        CLIOutput.write(collection, context: ctx) {
            "Created collection: \(collection.name) (id: \(collection.id))"
        }
    }
}
