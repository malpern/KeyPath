import ArgumentParser

struct Config: AsyncParsableCommand {
    static let configuration = CommandConfiguration(
        commandName: "config",
        abstract: "Inspect and manage Kanata configuration",
        subcommands: [
            ConfigShow.self,
            ConfigPath.self,
            ConfigCheck.self,
            ConfigApply.self,
            ConfigBackup.self,
            ConfigRestore.self,
        ]
    )
}
