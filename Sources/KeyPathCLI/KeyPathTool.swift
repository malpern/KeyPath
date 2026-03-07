import ArgumentParser
import Foundation
import KeyPathAppKit

@main
struct KeyPathTool: AsyncParsableCommand {
    static let configuration = CommandConfiguration(
        commandName: "keypath",
        abstract: "KeyPath keyboard configuration CLI",
        version: CLIVersion.current,
        subcommands: [
            Status.self,
            Remap.self,
            Rules.self,
            Apply.self,
            Config.self,
            TCP.self,
            Install.self,
            Repair.self,
            Uninstall.self,
            Inspect.self,
        ]
    )
}
