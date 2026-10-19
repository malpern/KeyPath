import ArgumentParser
import Foundation
@_exported import KeyPathCLIHelp
import KeyPathCLISupport

public struct KeyPathCLI: AsyncParsableCommand {
    public init() {}

    public static let configuration = CommandConfiguration(
        commandName: "keypath",
        abstract: "KeyPath keyboard remapping — configure, query, control, simulate",
        discussion: "keypath status|start|stop|restart, doctor, setup and uninstall ask the running KeyPath.app (launching it when needed). macOS permission switches still need a person; setup opens the right pane and waits.",
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
            Doctor.self,
            Setup.self,
            Uninstall.self,
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
