import ArgumentParser
import Foundation
@_exported import KeyPathCLIHelp
import KeyPathCLISupport

public struct KeyPathCLI: AsyncParsableCommand {
    public init() {}

    public static let configuration = CommandConfiguration(
        commandName: "keypath",
        abstract: "KeyPath keyboard remapping — configure, query, control, simulate",
        discussion: "keypath status|start|stop|restart ask the running KeyPath.app (start launches it). Installing and repairing stay in KeyPath.app, where macOS permission prompts can be answered.",
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
            StatusShortcut.self,
            StartShortcut.self,
            StopShortcut.self,
            RestartShortcut.self,
            RemapShortcut.self,
            LogsShortcut.self,
            UnmapShortcut.self,
        ]
    )
}
