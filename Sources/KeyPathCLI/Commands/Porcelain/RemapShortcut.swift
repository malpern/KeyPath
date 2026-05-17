import ArgumentParser
import Foundation
import KeyPathAppKit

struct RemapShortcut: AsyncParsableCommand {
    static let configuration = CommandConfiguration(
        commandName: "remap",
        abstract: "Create or modify a key remapping (shortcut for 'rule add')",
        shouldDisplay: false
    )

    @OptionGroup var globals: GlobalOptions

    @Argument(help: "Input key to remap (e.g., caps, lalt)")
    var input: String

    @Argument(help: "Output key for simple remap (e.g., esc, lctl)")
    var output: String?

    @Option(help: "Key to emit on tap (for tap-hold)")
    var tap: String?

    @Option(help: "Key to emit on hold (for tap-hold)")
    var hold: String?

    @Option(help: "Tap-hold timeout in milliseconds (default: 200)")
    var timeout: Int = 200

    @Flag(help: "Regenerate config and reload Kanata after saving")
    var apply: Bool = false

    func validate() throws {
        if (tap != nil) != (hold != nil) {
            throw ValidationError("--tap and --hold must be used together")
        }
    }

    mutating func run() async throws {
        var cmd = RuleAdd()
        cmd.globals = globals
        cmd.input = input
        cmd.output = output
        cmd.tap = tap
        cmd.hold = hold
        cmd.timeout = timeout
        cmd.apply = apply
        try await cmd.run()
    }
}
