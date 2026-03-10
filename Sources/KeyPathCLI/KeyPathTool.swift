import ArgumentParser
import Foundation
import KeyPathAppKit

@main
struct KeyPathCLI: AsyncParsableCommand {
    static let configuration = CommandConfiguration(
        commandName: "keypath-cli",
        abstract: "KeyPath keyboard configuration CLI",
        version: CLIVersion.current,
        subcommands: [
            Status.self,
            Remap.self,
            Rules.self,
            Apply.self,
            Config.self,
            TCP.self,
        ]
    )
}
