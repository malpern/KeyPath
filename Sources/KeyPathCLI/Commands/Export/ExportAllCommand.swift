import ArgumentParser
import Foundation
import KeyPathAppKit

struct ExportAll: AsyncParsableCommand {
    static let configuration = CommandConfiguration(
        commandName: "all",
        abstract: "Export all collections as JSON"
    )

    @OptionGroup var globals: GlobalOptions

    @Option(help: "Output file path (default: stdout)")
    var output: String?

    mutating func run() async throws {
        let ctx = globals.outputContext
        let facade = await MainActor.run { CLIFacade() }

        let exported = await facade.exportAllCollections()

        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        encoder.dateEncodingStrategy = .iso8601
        let data = try encoder.encode(exported)
        let json = String(data: data, encoding: .utf8)!

        if let outputPath = output {
            let url = URL(fileURLWithPath: (outputPath as NSString).expandingTildeInPath)
            try data.write(to: url)
            CLIOutput.write(["count": "\(exported.count)", "path": url.path], context: ctx) {
                "Exported \(exported.count) collection\(exported.count == 1 ? "" : "s") to \(url.path)"
            }
        } else {
            CLIOutput.writeRaw(json)
        }
    }
}
