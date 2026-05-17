import ArgumentParser

struct Export: AsyncParsableCommand {
    static let configuration = CommandConfiguration(
        commandName: "export",
        abstract: "Export collections as portable JSON",
        subcommands: [
            ExportCollection.self,
            ExportAll.self,
        ]
    )
}
