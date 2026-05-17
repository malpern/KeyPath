import ArgumentParser
import Foundation
import KeyPathAppKit

struct StartShortcut: AsyncParsableCommand {
    static let configuration = CommandConfiguration(
        commandName: "start",
        abstract: "Start the Kanata service (shortcut for 'service start')",
        shouldDisplay: false
    )

    @OptionGroup var globals: GlobalOptions

    mutating func run() async throws {
        var cmd = ServiceStart()
        cmd.globals = globals
        try await cmd.run()
    }
}
