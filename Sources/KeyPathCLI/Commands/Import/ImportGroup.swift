import ArgumentParser

struct Import: AsyncParsableCommand {
    static let configuration = CommandConfiguration(
        commandName: "import",
        abstract: "Import rules from files or external formats",
        subcommands: [
            ImportCollection.self,
            ImportKarabiner.self,
        ]
    )
}
