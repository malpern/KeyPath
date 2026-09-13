import ArgumentParser

public struct Help: AsyncParsableCommand {
    public init() {}
    public static let configuration = CommandConfiguration(
        commandName: "help-topics",
        abstract: "Extended help and API discovery",
        subcommands: [
            HelpSchemas.self,
            HelpExamples.self,
        ]
    )
}
