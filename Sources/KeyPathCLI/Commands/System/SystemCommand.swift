import ArgumentParser

struct System: AsyncParsableCommand {
    static let configuration = CommandConfiguration(
        commandName: "system",
        abstract: "Install, repair, or uninstall KeyPath services",
        subcommands: [
            SystemInstall.self,
            SystemRepair.self,
            SystemUninstall.self,
            SystemInspect.self,
        ]
    )
}
