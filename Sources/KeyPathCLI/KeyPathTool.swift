import ArgumentParser
import Foundation
import KeyPathAppKit

@main
struct KeyPathTool: AsyncParsableCommand {
    static let configuration = CommandConfiguration(
        commandName: "keypath",
        abstract: "KeyPath keyboard configuration CLI",
        version: "0.1.0",
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
