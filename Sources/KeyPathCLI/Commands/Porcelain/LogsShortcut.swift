import ArgumentParser
import Foundation
import KeyPathAppKit

struct LogsShortcut: AsyncParsableCommand {
    static let configuration = CommandConfiguration(
        commandName: "logs",
        abstract: "Show service logs (shortcut for 'service logs')",
        shouldDisplay: false
    )

    @OptionGroup var globals: GlobalOptions

    @Option(help: "Number of lines to show (default: 50)")
    var lines: Int = 50

    mutating func run() async throws {
        var cmd = ServiceLogs()
        cmd.globals = globals
        cmd.lines = lines
        try await cmd.run()
    }
}
