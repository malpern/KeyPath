import ArgumentParser
import Foundation
import KeyPathAppKit

struct RestartShortcut: AsyncParsableCommand {
    static let configuration = CommandConfiguration(
        commandName: "restart",
        abstract: "Restart remapping (shortcut for 'service restart')",
        shouldDisplay: false
    )

    @OptionGroup var globals: GlobalOptions

    mutating func run() async throws {
        var cmd = ServiceRestart()
        cmd.globals = globals
        try await cmd.run()
    }
}
