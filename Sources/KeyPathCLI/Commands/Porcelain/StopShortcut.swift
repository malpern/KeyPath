import ArgumentParser
import Foundation
import KeyPathAppKit

struct StopShortcut: AsyncParsableCommand {
    static let configuration = CommandConfiguration(
        commandName: "stop",
        abstract: "Stop the Kanata service (shortcut for 'service stop')",
        shouldDisplay: false
    )

    @OptionGroup var globals: GlobalOptions

    mutating func run() async throws {
        var cmd = ServiceStop()
        cmd.globals = globals
        try await cmd.run()
    }
}
