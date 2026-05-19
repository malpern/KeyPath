import ArgumentParser

struct Pack: AsyncParsableCommand {
    static let configuration = CommandConfiguration(
        commandName: "pack",
        abstract: "Manage keyboard packs",
        subcommands: [
            PackList.self,
            PackShow.self,
            PackInstall.self,
            PackUninstall.self,
        ]
    )
}
