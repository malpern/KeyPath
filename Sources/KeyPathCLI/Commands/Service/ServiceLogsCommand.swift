import ArgumentParser
import Foundation
import KeyPathAppKit

struct ServiceLogs: AsyncParsableCommand {
    static let configuration = CommandConfiguration(
        commandName: "logs",
        abstract: "Show recent Kanata service logs"
    )

    @OptionGroup var globals: GlobalOptions

    @Option(help: "Number of lines to show (default: 50)")
    var lines: Int = 50

    mutating func run() async throws {
        let ctx = globals.outputContext
        let facade = CLIFacade()

        let logLines = facade.serviceLogs(lines: lines)
        if logLines.isEmpty {
            CLIOutput.write(["lines": [String]()], context: ctx) {
                "No log entries found. Log file: ~/Library/Logs/KeyPath/keypath-debug.log"
            }
        } else {
            CLIOutput.write(["lines": logLines], context: ctx) {
                logLines.joined(separator: "\n")
            }
        }
    }
}
