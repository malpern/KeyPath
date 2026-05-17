import ArgumentParser

struct Help: AsyncParsableCommand {
    static let configuration = CommandConfiguration(
        commandName: "help-topics",
        abstract: "Extended help and API discovery",
        subcommands: [
            HelpSchemas.self,
        ]
    )
}
