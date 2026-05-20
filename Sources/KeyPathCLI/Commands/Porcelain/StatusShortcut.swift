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

    mutating func run() async throws {
        var cmd = ServiceStatus()
        cmd.globals = globals
        try await cmd.run()
    }
}
