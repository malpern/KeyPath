import ArgumentParser
import Foundation
import KeyPathAppKit

public struct KeyPathCLI: AsyncParsableCommand {
    public init() {}

    public static let configuration = CommandConfiguration(
        commandName: "keypath",
        abstract: "KeyPath keyboard remapping — configure, query, control",
        version: CLIVersion.current,
        subcommands: [
            // Plumbing (noun-verb)
            Rule.self,
            Collection.self,
            Layer.self,
            Service.self,
            Config.self,
            System.self,
            Export.self,
            Import.self,
            Simulate.self,
            Help.self,
            Completions.self,
            // Porcelain shortcuts (hidden from --help)
            StatusShortcut.self,
            RemapShortcut.self,
            StartShortcut.self,
            StopShortcut.self,
            RestartShortcut.self,
            LogsShortcut.self,
            UnmapShortcut.self,
        ]
    )
}
