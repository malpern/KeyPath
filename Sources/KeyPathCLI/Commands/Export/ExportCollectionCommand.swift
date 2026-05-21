import ArgumentParser
import Foundation
import KeyPathAppKit

struct ExportCollection: AsyncParsableCommand {
    static let configuration = CommandConfiguration(
        commandName: "collection",
        abstract: "Export a single collection as JSON"
    )

    @OptionGroup var globals: GlobalOptions

    @Argument(help: "Collection name or ID to export")
    var nameOrId: String

    @Option(help: "Output file path (default: stdout)")
    var output: String?

    mutating func run() async throws {
        let ctx = globals.outputContext
        let facade = CollectionsFacade()

        do {
            guard let exported = try await facade.exportCollection(nameOrId: nameOrId) else {
                let error = CLIError.notFound("Collection", query: nameOrId, listCommand: "keypath collection list")
                CLIOutput.writeError(error, context: ctx)
                throw error.code.exitCode
            }

            let encoder = JSONEncoder()
            encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
            encoder.dateEncodingStrategy = .iso8601
            let data = try encoder.encode(exported)
            let json = String(data: data, encoding: .utf8)!

            if let outputPath = output {
                let url = URL(fileURLWithPath: (outputPath as NSString).expandingTildeInPath)
                try data.write(to: url)
                CLIOutput.write(["exported": nameOrId, "path": url.path], context: ctx) {
                    "Exported '\(exported.name)' to \(url.path)"
                }
            } else {
                CLIOutput.writeRaw(json)
            }
        } catch let error as AmbiguousCollectionMatch {
            let cliError = CLIError.ambiguous(error.description, matches: error.matches.map { "\($0.name) (\($0.id))" })
            CLIOutput.writeError(cliError, context: ctx)
            throw CLIExitCode.conflict.exitCode
        }
    }
}
