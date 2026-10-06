import ArgumentParser
import Foundation
@_exported import KeyPathCLIHelp
import KeyPathCLISupport

public struct KeyPathCLI: AsyncParsableCommand {
    public init() {}

    public static let configuration = CommandConfiguration(
        commandName: "keypath",
        abstract: "KeyPath keyboard remapping — configure, query, simulate",
        discussion: "Open KeyPath.app to start or stop remapping and check the live session. Runtime lifecycle and system installation commands are unavailable in this driverless CLI.",
        version: CLIVersion.current,
        subcommands: [
            // Plumbing (noun-verb)
            Rule.self,
            Collection.self,
            Layer.self,
            Pack.self,
            Service.self,
            Config.self,
            System.self,
            Export.self,
            Import.self,
            Simulate.self,
            Help.self,
            Completions.self,
            // Porcelain shortcuts (hidden from --help)
            RemapShortcut.self,
            LogsShortcut.self,
            UnmapShortcut.self,
        ]
    )
}
