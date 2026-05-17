import ArgumentParser
import Foundation
import KeyPathAppKit

struct StatusShortcut: AsyncParsableCommand {
    static let configuration = CommandConfiguration(
        commandName: "status",
        abstract: "Check system status (shortcut for 'service status')",
        shouldDisplay: false
    )

    @OptionGroup var globals: GlobalOptions

    @Option(help: "Timeout in seconds (default: 30)")
    var timeout: Int = 30

    mutating func run() async throws {
        var cmd = ServiceStatus()
        cmd.globals = globals
        cmd.timeout = timeout
        try await cmd.run()
    }
}
