import ArgumentParser

struct Service: AsyncParsableCommand {
    static let configuration = CommandConfiguration(
        commandName: "service",
        abstract: "Reload configuration or read logs; manage the runtime in KeyPath.app",
        subcommands: [
            ServiceReload.self,
            ServiceLogs.self,
        ]
    )
}
