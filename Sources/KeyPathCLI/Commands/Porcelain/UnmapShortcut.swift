import ArgumentParser
import Foundation
import KeyPathAppKit

struct UnmapShortcut: AsyncParsableCommand {
    static let configuration = CommandConfiguration(
        commandName: "unmap",
        abstract: "Remove a key mapping and apply (shortcut for 'rule remove --apply')",
        shouldDisplay: false
    )

    @OptionGroup var globals: GlobalOptions

    @Argument(help: "Input key to unmap")
    var input: String

    mutating func run() async throws {
        var cmd = RuleRemove()
        cmd.globals = globals
        cmd.input = input
        cmd.apply = true
        try await cmd.run()
    }
}
