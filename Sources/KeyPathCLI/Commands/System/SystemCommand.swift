import ArgumentParser

struct System: AsyncParsableCommand {
    static let configuration = CommandConfiguration(
        commandName: "system",
        abstract: "Inspect local permission and configuration diagnostics",
        subcommands: [
            SystemInspect.self,
        ]
    )
}
